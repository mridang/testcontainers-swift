/// Low-level Docker Engine API client.
///
/// `DockerClient` communicates with the Docker daemon over a Unix domain socket
/// or a TCP/HTTP connection using `AsyncHTTPClient` from swift-server.
///
/// The public API mirrors the subset of the Docker Engine REST API used by
/// testcontainers-swift.
import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Describes a volume or bind mount to attach to a container.
public struct MountConfig {
    /// The container-side bind path.
    public let hostPath: String
    /// Access mode: `"ro"` for read-only, `"rw"` for read-write.
    public let mode: String

    public init(hostPath: String, mode: String = "rw") {
        self.hostPath = hostPath
        self.mode = mode
    }
}

// MARK: - Free functions (Dart-compatible naming)

/// Returns the effective Docker host from the configuration or environment.
///
/// Resolution order:
/// 1. `tc.host` key in `~/.testcontainers.properties`
/// 2. `DOCKER_HOST` environment variable
///
/// Returns `nil` when neither source is set.
public func dockerHost() -> String? {
    let host = testcontainersConfig.tcHost ?? ProcessInfo.processInfo.environment["DOCKER_HOST"]
    guard let h = host else { return nil }
    return sanitizeDockerHost(h)
}

private func sanitizeDockerHost(_ host: String) -> String {
    guard host.hasPrefix("ssh://") else { return host }
    // Remove trailing path from SSH URLs
    guard var comps = URLComponents(string: host) else { return host }
    if !(comps.path.isEmpty) {
        comps.path = ""
    }
    return comps.string ?? host
}

/// Returns the hostname portion of an SSH-based Docker host URL.
///
/// For example, `ssh://user@myhost.example.com` returns `"myhost.example.com"`.
/// Returns `nil` when `dockerHost()` is not an SSH URL or the host component is empty.
public func dockerHostHostname() -> String? {
    guard let rawHost = dockerHost(), rawHost.hasPrefix("ssh://") else { return nil }
    guard let uri = URLComponents(string: rawHost), !uri.host!.isEmpty else { return nil }
    return URLComponents(string: rawHost)?.host
}

/// Returns `true` when the Docker host is reached via SSH.
public func isSshDockerHost() -> Bool {
    return dockerHostHostname() != nil
}

/// Returns the raw `DOCKER_AUTH_CONFIG` string, or `nil`.
public func dockerAuthConfig() -> String? {
    return testcontainersConfig.dockerAuthConfig
}

// MARK: - DockerClient

/// A thin HTTP client that speaks directly to the Docker Engine API.
///
/// By default, `DockerClient` uses a Unix domain socket. When `DOCKER_HOST`
/// is set to a TCP/HTTP URL, an HTTP client is used instead.
public class DockerClient: @unchecked Sendable {
    private let httpClient: HTTPClient
    private let baseURL: String
    private let _socketPath: String

    /// Creates a `DockerClient` from the environment.
    ///
    /// If `DOCKER_AUTH_CONFIG` is set, the first registry entry is used to
    /// perform an implicit login.
    public init(
        socketPath: String = testcontainersConfig.ryukDockerSocket,
        tcpHost: String? = nil
    ) {
        self._socketPath = socketPath
        if let tcp = tcpHost ?? Self.tcpDockerHost() {
            let normalized =
                tcp
                .replacingOccurrences(of: "tcp://", with: "http://")
                .replacingOccurrences(of: "ssh://", with: "http://")
            self.baseURL = normalized
            self.httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        } else {
            // AsyncHTTPClient requires the Unix socket path in the URL authority
            // (host) component with every '/' percent-encoded as '%2F', e.g.
            // http+unix://%2Fvar%2Frun%2Fdocker.sock
            // Using .urlPathAllowed keeps '/' unencoded → empty host → missingSocketPath.
            // .urlHostAllowed excludes '/' so slashes are encoded correctly.
            let encoded = socketPath.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? socketPath
            self.baseURL = "http+unix://\(encoded)"
            self.httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        }
        // Trigger auth if configured
        if let authConfig = dockerAuthConfig() {
            if let auth = try? parseDockerAuthConfig(authConfig), let first = auth.first {
                Task { try? await self.login(auth: first) }
            }
        }
    }

    /// Creates a `DockerClient` with no real socket connection.
    ///
    /// The socket path is set to a non-existent path so that any method that
    /// tries to make an actual Docker API call will fail immediately. This
    /// constructor exists solely to enable unit tests of pure parsing logic
    /// (e.g. `decodeChunked`, `stripDockerLogHeaders`) without a Docker daemon.
    public static func testOnly() -> DockerClient {
        return DockerClient(socketPath: "/dev/null")
    }

    deinit {
        try? httpClient.syncShutdown()
    }

    private static func tcpDockerHost() -> String? {
        guard let h = ProcessInfo.processInfo.environment["DOCKER_HOST"],
            h.hasPrefix("tcp://") || h.hasPrefix("http://") || h.hasPrefix("https://")
        else { return nil }
        return h
    }

    // MARK: - Connection mode

    /// Returns the effective connection mode for this client.
    public var connectionMode: ConnectionMode {
        if let override = testcontainersConfig.connectionModeOverride { return override }
        let localhosts: Set<String> = ["localhost", "127.0.0.1", "::1"]
        if !insideContainer() || !localhosts.contains(host) {
            return .dockerHost
        }
        if runningContainerId() != nil { return .bridgeIp }
        return .gatewayIp
    }

    /// Returns the host address used to reach containers from the test process.
    public var host: String {
        if let override = testcontainersConfig.tcHostOverride { return override }

        if let sshHost = dockerHostHostname() { return sshHost }

        if let rawHost = dockerHost() {
            if rawHost.hasPrefix("tcp://") || rawHost.hasPrefix("http://") || rawHost.hasPrefix("https://") {
                let uri = URLComponents(string: rawHost)
                let h = uri?.host ?? ""
                if h.isEmpty || (h == "localnpipe" && isWindows()) { return "localhost" }
                return h
            }
        }

        if insideContainer() {
            if let gw = defaultGatewayIp() { return gw }
        }
        return "localhost"
    }

    // MARK: - Private HTTP helpers

    private func url(_ path: String, query: [String: String] = [:]) -> String {
        var components = URLComponents(string: baseURL + path)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url?.absoluteString ?? (baseURL + path)
    }

    private func request(
        method: HTTPMethod,
        path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil,
        rawBody: Data? = nil,
        headers extraHeaders: [String: String] = [:]
    ) async throws -> (statusCode: Int, body: Data) {
        var req = HTTPClientRequest(url: url(path, query: query))
        req.method = method

        req.headers.add(name: "Host", value: "localhost")
        req.headers.add(name: "x-tc-sid", value: sessionId)

        if let body = body {
            let data = try JSONSerialization.data(withJSONObject: body)
            req.headers.add(name: "Content-Type", value: "application/json")
            req.headers.add(name: "Content-Length", value: "\(data.count)")
            req.body = .bytes(ByteBuffer(bytes: data))
        } else if let raw = rawBody {
            req.headers.add(name: "Content-Length", value: "\(raw.count)")
            req.body = .bytes(ByteBuffer(bytes: raw))
        }

        for (k, v) in extraHeaders { req.headers.add(name: k, value: v) }

        let response = try await httpClient.execute(req, timeout: .seconds(30))
        var collected = Data()
        for try await chunk in response.body {
            collected.append(contentsOf: chunk.readableBytesView)
        }
        return (statusCode: Int(response.status.code), body: collected)
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DockerClientError.unexpectedResponse("Expected JSON object")
        }
        return obj
    }

    private func jsonArray(from data: Data) throws -> [[String: Any]] {
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw DockerClientError.unexpectedResponse("Expected JSON array")
        }
        return arr
    }

    // MARK: - toDockerKey

    /// Converts a Swift camelCase or snake_case key to the Docker API's PascalCase convention.
    ///
    /// Known special cases (`privileged`, `auto_remove`, `autoRemove`, `platform`) are
    /// mapped explicitly. All other keys have their first character upper-cased.
    ///
    /// Exposed for unit testing.
    public static func toDockerKey(_ dartKey: String) throws -> String {
        return try _toDockerKey(dartKey)
    }

    private static func _toDockerKey(_ key: String) throws -> String {
        if key.isEmpty {
            throw DockerClientError.unexpectedResponse("Docker key must not be empty")
        }
        switch key {
        case "privileged": return "Privileged"
        case "auto_remove", "autoRemove": return "AutoRemove"
        case "platform": return "Platform"
        default:
            let first = key.prefix(1).uppercased()
            return first + key.dropFirst()
        }
    }

    // MARK: - Container lifecycle

    /// Creates a container and returns its ID.
    public func createContainer(
        image: String,
        command: [String]? = nil,
        env: [String: String] = [:],
        name: String? = nil,
        ports: [Int: Int?] = [:],
        volumes: [String: MountConfig] = [:],
        tmpfs: [String: String]? = nil,
        network: String? = nil,
        networkAliases: [String]? = nil,
        labels: [String: String] = [:],
        kwargs: [String: Any] = [:]
    ) async throws -> String {
        // Extract user-provided labels from kwargs so they don't end up in HostConfig.
        let userLabels = kwargs["labels"] as? [String: String] ?? labels
        var hostConfigKwargs = kwargs
        hostConfigKwargs.removeValue(forKey: "labels")

        var body: [String: Any] = ["Image": image]

        if let cmd = command { body["Cmd"] = cmd }
        body["Env"] = env.map { "\($0.key)=\($0.value)" }
        body["Labels"] = userLabels

        // ExposedPorts
        var exposed: [String: Any] = [:]
        for p in ports.keys { exposed["\(p)/tcp"] = [:] as [String: Any] }
        if !exposed.isEmpty { body["ExposedPorts"] = exposed }

        // HostConfig
        var hostConfig: [String: Any] = [:]
        var portBindings: [String: Any] = [:]
        for (container, hostPort) in ports {
            let binding: [String: String]
            if let h = hostPort {
                binding = ["HostIp": "", "HostPort": "\(h)"]
            } else {
                binding = ["HostIp": "", "HostPort": ""]
            }
            portBindings["\(container)/tcp"] = [binding]
        }
        if !portBindings.isEmpty { hostConfig["PortBindings"] = portBindings }

        if !volumes.isEmpty {
            hostConfig["Binds"] = volumes.map { "\($0.key):\($0.value.hostPath):\($0.value.mode)" }
        }

        if let tmpfsMap = tmpfs, !tmpfsMap.isEmpty {
            hostConfig["Tmpfs"] = tmpfsMap
        }

        if let netName = network {
            hostConfig["NetworkMode"] = netName
        }

        // Apply remaining kwargs (labels already extracted) → converted to Docker PascalCase keys
        for (k, v) in hostConfigKwargs {
            hostConfig[try Self._toDockerKey(k)] = v
        }

        if !hostConfig.isEmpty { body["HostConfig"] = hostConfig }

        // NetworkingConfig
        if let netName = network, let aliases = networkAliases, !aliases.isEmpty {
            body["NetworkingConfig"] = [
                "EndpointsConfig": [
                    netName: ["Aliases": aliases]
                ]
            ]
        } else if let netName = network {
            body["NetworkingConfig"] = [
                "EndpointsConfig": [netName: [:] as [String: Any]]
            ]
        }

        var query: [String: String] = [:]
        if let n = name { query["name"] = n }

        let (statusCode, respBody) = try await request(
            method: .POST,
            path: "/v1.41/containers/create",
            query: query,
            body: body
        )
        guard statusCode == 201 else {
            throw DockerClientError.apiError(statusCode, String(data: respBody, encoding: .utf8) ?? "")
        }
        let json = try jsonObject(from: respBody)
        guard let id = json["Id"] as? String else {
            throw DockerClientError.unexpectedResponse("No Id in create response")
        }
        return id
    }

    /// Starts a container.
    public func startContainer(_ id: String) async throws {
        let (statusCode, body) = try await request(method: .POST, path: "/v1.41/containers/\(id)/start")
        guard statusCode == 204 || statusCode == 304 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
    }

    /// Stops a container.
    public func stopContainer(_ id: String, timeout: Int = 10) async throws {
        let (statusCode, body) = try await request(
            method: .POST,
            path: "/v1.41/containers/\(id)/stop",
            query: ["t": "\(timeout)"]
        )
        guard statusCode == 204 || statusCode == 304 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
    }

    /// Removes a container.
    public func removeContainer(_ id: String, force: Bool = false, removeVolumes: Bool = false) async throws {
        let (statusCode, body) = try await request(
            method: .DELETE,
            path: "/v1.41/containers/\(id)",
            query: ["force": force ? "true" : "false", "v": removeVolumes ? "true" : "false"]
        )
        guard statusCode == 204 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
    }

    /// Removes a Docker image.
    public func removeImage(_ id: String, force: Bool = true, noPrune: Bool = false) async throws {
        let (statusCode, _) = try await request(
            method: .DELETE,
            path: "/v1.41/images/\(id)",
            query: ["force": force ? "true" : "false", "noprune": noPrune ? "true" : "false"]
        )
        guard statusCode == 200 || statusCode == 404 else {
            throw DockerClientError.apiError(statusCode, "removeImage failed")
        }
    }

    /// Pulls a Docker image.
    public func pullImage(_ image: String) async throws {
        let parts = image.split(separator: ":")
        let fromImage = String(parts.first ?? Substring(image))
        let tag = parts.count > 1 ? String(parts.last!) : "latest"
        let (statusCode, _) = try await request(
            method: .POST,
            path: "/v1.41/images/create",
            query: ["fromImage": fromImage, "tag": tag]
        )
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, "pull failed")
        }
    }

    /// Returns the host port mapped to `port` on container `containerId`.
    public func port(_ containerId: String, _ port: Int) async throws -> Int {
        let details = try await containerDetails(containerId)
        let networkSettings = details["NetworkSettings"] as? [String: Any]
        let ports = networkSettings?["Ports"] as? [String: Any]
        let key = "\(port)/tcp"
        if let bindings = ports?[key] as? [[String: String]],
            let first = bindings.first,
            let hostPortStr = first["HostPort"],
            let hostPort = Int(hostPortStr)
        {
            return hostPort
        }
        throw DockerClientError.portNotFound(port)
    }

    /// Lists containers.
    public func containers(all: Bool = false, filters: [String: Any]? = nil) async throws -> [[String: Any]] {
        var query: [String: String] = ["all": all ? "true" : "false"]
        if let f = filters,
            let data = try? JSONSerialization.data(withJSONObject: f),
            let str = String(data: data, encoding: .utf8)
        {
            query["filters"] = str
        }
        let (statusCode, body) = try await request(method: .GET, path: "/v1.41/containers/json", query: query)
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
        return try jsonArray(from: body)
    }

    /// Returns raw container details (`GET /containers/{id}/json`).
    public func containerDetails(_ id: String) async throws -> [String: Any] {
        let (statusCode, body) = try await request(method: .GET, path: "/v1.41/containers/\(id)/json")
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
        return try jsonObject(from: body)
    }

    /// Returns the bridge network IP of a container.
    public func bridgeIp(_ id: String) async throws -> String {
        let details = try await containerDetails(id)
        let networkSettings = details["NetworkSettings"] as? [String: Any]
        let networkMode = (details["HostConfig"] as? [String: Any])?["NetworkMode"] as? String ?? "bridge"
        let networkName = networkMode == "default" ? "bridge" : networkMode
        let networks = networkSettings?["Networks"] as? [String: Any]
        let network = networks?[networkName] as? [String: Any]
        return (network?["IPAddress"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "localhost"
    }

    /// Returns the gateway IP of a container's default network.
    public func gatewayIp(_ id: String) async throws -> String {
        let details = try await containerDetails(id)
        let networkSettings = details["NetworkSettings"] as? [String: Any]
        let networkMode = (details["HostConfig"] as? [String: Any])?["NetworkMode"] as? String ?? "bridge"
        let networkName = networkMode == "default" ? "bridge" : networkMode
        let networks = networkSettings?["Networks"] as? [String: Any]
        let network = networks?[networkName] as? [String: Any]
        return (network?["Gateway"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "localhost"
    }

    /// Authenticates against a Docker registry.
    public func login(auth: DockerAuthInfo) async throws {
        let body: [String: Any] = [
            "serveraddress": auth.registry,
            "username": auth.username,
            "password": auth.password,
        ]
        let (statusCode, respBody) = try await request(method: .POST, path: "/v1.41/auth", body: body)
        guard statusCode == 200 || statusCode == 204 else {
            throw DockerClientError.apiError(statusCode, String(data: respBody, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Network management

    /// Creates a Docker network and returns its ID.
    public func createNetwork(_ name: String, options: [String: Any]? = nil) async throws -> String {
        var body: [String: Any] = [
            "Name": name,
            "Labels": (try? createLabels(image: "")) ?? [:],
        ]
        if let opts = options {
            for (k, v) in opts { body[k] = v }
        }
        let (statusCode, respBody) = try await request(method: .POST, path: "/v1.41/networks/create", body: body)
        guard statusCode == 201 else {
            throw DockerClientError.apiError(statusCode, String(data: respBody, encoding: .utf8) ?? "")
        }
        let json = try jsonObject(from: respBody)
        guard let id = json["Id"] as? String else {
            throw DockerClientError.unexpectedResponse("No Id in createNetwork response")
        }
        return id
    }

    /// Removes a network.
    public func removeNetwork(_ id: String) async throws {
        let (statusCode, body) = try await request(method: .DELETE, path: "/v1.41/networks/\(id)")
        guard statusCode == 204 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
    }

    /// Connects a container to a network.
    public func connectNetwork(_ networkId: String, _ containerId: String, aliases: [String]? = nil) async throws {
        var body: [String: Any] = ["Container": containerId]
        if let a = aliases {
            body["EndpointConfig"] = ["Aliases": a]
        }
        let (statusCode, respBody) = try await request(
            method: .POST,
            path: "/v1.41/networks/\(networkId)/connect",
            body: body
        )
        guard statusCode == 200 || statusCode == 204 else {
            throw DockerClientError.apiError(statusCode, String(data: respBody, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Exec

    /// Runs a command inside a running container and returns (exitCode, output).
    public func execInContainer(_ id: String, command: [String]) async throws -> (exitCode: Int, output: Data) {
        let createBody: [String: Any] = [
            "AttachStdout": true,
            "AttachStderr": true,
            "Cmd": command,
        ]
        let (createStatus, createRespBody) = try await request(
            method: .POST,
            path: "/v1.41/containers/\(id)/exec",
            body: createBody
        )
        guard createStatus == 201 else {
            throw DockerClientError.apiError(createStatus, String(data: createRespBody, encoding: .utf8) ?? "")
        }
        let createJson = try jsonObject(from: createRespBody)
        guard let execId = createJson["Id"] as? String else {
            throw DockerClientError.unexpectedResponse("No exec Id")
        }

        let startBody: [String: Any] = ["Detach": false, "Tty": false]
        let (startStatus, output) = try await request(
            method: .POST,
            path: "/v1.41/exec/\(execId)/start",
            body: startBody
        )
        guard startStatus == 200 else {
            throw DockerClientError.apiError(startStatus, String(data: output, encoding: .utf8) ?? "")
        }

        let (inspectStatus, inspectBody) = try await request(
            method: .GET,
            path: "/v1.41/exec/\(execId)/json"
        )
        guard inspectStatus == 200 else {
            throw DockerClientError.apiError(inspectStatus, String(data: inspectBody, encoding: .utf8) ?? "")
        }
        let inspectJson = try jsonObject(from: inspectBody)
        let exitCode = inspectJson["ExitCode"] as? Int ?? 0

        return (exitCode: exitCode, output: output)
    }

    // MARK: - Inspect

    /// Returns a typed `ContainerInspectInfo` for the given container ID.
    public func containerInspectInfo(_ id: String) async throws -> ContainerInspectInfo {
        let (statusCode, body) = try await request(method: .GET, path: "/v1.41/containers/\(id)/json")
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(ContainerInspectInfo.self, from: body)
    }

    // MARK: - Archive / transfer

    /// Uploads a tar archive to a container path.
    public func putArchive(_ id: String, path: String, tarData: Data) async throws {
        let (statusCode, body) = try await request(
            method: .PUT,
            path: "/v1.41/containers/\(id)/archive",
            query: ["path": path],
            rawBody: tarData,
            headers: ["Content-Type": "application/x-tar"]
        )
        guard statusCode == 200 || statusCode == 204 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
    }

    /// Downloads a tar archive from a container path.
    public func archive(_ id: String, path: String) async throws -> Data {
        let (statusCode, body) = try await request(
            method: .GET,
            path: "/v1.41/containers/\(id)/archive",
            query: ["path": path]
        )
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
        return body
    }

    // MARK: - Wait

    /// Blocks until the container stops and returns its exit code.
    public func waitContainer(_ id: String) async throws -> Int {
        let (statusCode, body) = try await request(method: .POST, path: "/v1.41/containers/\(id)/wait")
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
        let json = try jsonObject(from: body)
        return json["StatusCode"] as? Int ?? 0
    }

    // MARK: - Logs

    /// Returns the stdout and stderr logs of a container as separate byte arrays.
    public func logs(_ id: String) async throws -> (stdout: Data, stderr: Data) {
        let (stdoutStatus, stdoutBody) = try await request(
            method: .GET,
            path: "/v1.41/containers/\(id)/logs",
            query: ["stdout": "true", "stderr": "false"]
        )
        guard stdoutStatus == 200 else {
            throw DockerClientError.apiError(stdoutStatus, String(data: stdoutBody, encoding: .utf8) ?? "")
        }
        let (stderrStatus, stderrBody) = try await request(
            method: .GET,
            path: "/v1.41/containers/\(id)/logs",
            query: ["stdout": "false", "stderr": "true"]
        )
        guard stderrStatus == 200 else {
            throw DockerClientError.apiError(stderrStatus, String(data: stderrBody, encoding: .utf8) ?? "")
        }
        return (stdout: _stripDockerLogHeaders(stdoutBody), stderr: _stripDockerLogHeaders(stderrBody))
    }

    // MARK: - Image operations

    /// Builds a Docker image from a local context directory.
    ///
    /// Returns `(imageId, logs)` where `imageId` is the built image's ID
    /// (or the `tag` string when the ID cannot be parsed) and `logs` is the
    /// streaming build log as a list of JSON objects.
    public func buildImage(
        contextPath: String,
        tag: String? = nil,
        noCache: Bool = false,
        dockerfile: String? = nil
    ) async throws -> (String, [[String: Any]]) {
        let contextURL = URL(fileURLWithPath: contextPath)
        let tarData = try buildTransferTar(.path(contextURL), destination: ".")

        var query: [String: String] = [:]
        if let t = tag { query["t"] = t }
        if noCache { query["nocache"] = "true" }
        if let df = dockerfile { query["dockerfile"] = df }

        let (statusCode, body) = try await request(
            method: .POST,
            path: "/v1.41/build",
            query: query,
            rawBody: tarData,
            headers: ["Content-Type": "application/x-tar"]
        )
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
        var imageId: String?
        var buildLogs: [[String: Any]] = []
        let responseText = String(data: body, encoding: .utf8) ?? ""
        for line in responseText.components(separatedBy: "\n") {
            guard !line.isEmpty else { continue }
            if let lineData = line.data(using: .utf8),
                let parsed = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            {
                buildLogs.append(parsed)
                if let aux = parsed["aux"] as? [String: Any],
                    let idStr = aux["ID"] as? String
                {
                    imageId = idStr
                }
            }
        }
        return (imageId ?? tag ?? "", buildLogs)
    }

    // MARK: - Private log helpers

    /// Removes Docker's 8-byte multiplexed log frame headers from `data`.
    private func _stripDockerLogHeaders(_ data: Data) -> Data {
        var result = Data()
        var pos = 0
        while pos + 8 <= data.count {
            let size =
                Int(data[pos + 4]) << 24
                | Int(data[pos + 5]) << 16
                | Int(data[pos + 6]) << 8
                | Int(data[pos + 7])
            pos += 8
            if pos + size <= data.count {
                result.append(data[pos..<pos + size])
                pos += size
            } else {
                break
            }
        }
        return result.isEmpty ? data : result
    }

    // MARK: - Testable helpers (mirrors Dart's @visibleForTesting)

    /// Exposed for unit testing — strips Docker multiplexed log headers.
    public func stripDockerLogHeaders(_ data: Data) -> Data {
        return _stripDockerLogHeaders(data)
    }

    /// Exposed for unit testing — decodes HTTP chunked-transfer-encoded body.
    public func decodeChunked(_ data: Data) -> Data {
        return _decodeChunked(data)
    }

    private func _decodeChunked(_ data: Data) -> Data {
        var result = Data()
        var pos = 0
        while pos < data.count {
            // Find CRLF
            var lineEnd = -1
            for i in pos..<(data.count - 1) {
                if data[i] == 13 && data[i + 1] == 10 {
                    lineEnd = i
                    break
                }
            }
            guard lineEnd >= 0 else { break }
            let sizeStr = String(data: data[pos..<lineEnd], encoding: .utf8)?.trimmingCharacters(in: .whitespaces) ?? ""
            let size = Int(sizeStr, radix: 16) ?? 0
            if size == 0 { break }
            pos = lineEnd + 2
            if pos + size > data.count { break }
            result.append(data[pos..<pos + size])
            pos += size + 2  // skip trailing CRLF
        }
        return result
    }

    /// Exposed for unit testing — parses a raw HTTP/1.0 response byte buffer.
    public func parseHttpResponse(_ bytes: Data) -> (statusCode: Int, headers: [String: String], body: Data) {
        let raw = String(data: bytes, encoding: .utf8) ?? ""
        guard let headerEnd = raw.range(of: "\r\n\r\n") else {
            return (statusCode: 500, headers: [:], body: bytes)
        }
        let headerSection = String(raw[raw.startIndex..<headerEnd.lowerBound])
        let lines = headerSection.components(separatedBy: "\r\n")
        let statusParts = lines.first?.components(separatedBy: " ") ?? []
        let statusCode = statusParts.count > 1 ? Int(statusParts[1]) ?? 500 : 500

        var responseHeaders: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let idx = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<idx].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
            responseHeaders[key] = value
        }

        let bodyStartOffset = bytes.count - (raw.count - raw.distance(from: raw.startIndex, to: headerEnd.upperBound))
        let bodyBytes = bodyStartOffset <= bytes.count ? bytes[bodyStartOffset...] : Data()
        let bodyData =
            responseHeaders["transfer-encoding"] == "chunked"
            ? _decodeChunked(Data(bodyBytes))
            : Data(bodyBytes)

        return (statusCode: statusCode, headers: responseHeaders, body: bodyData)
    }
}

// MARK: - Errors

/// Errors thrown by `DockerClient`.
public enum DockerClientError: Error, CustomStringConvertible {
    case apiError(Int, String)
    case unexpectedResponse(String)
    case portNotFound(Int)

    public var description: String {
        switch self {
        case .apiError(let code, let body): return "Docker API error \(code): \(body)"
        case .unexpectedResponse(let m): return "Unexpected Docker response: \(m)"
        case .portNotFound(let p): return "Port \(p)/tcp not found in container port mappings"
        }
    }
}
