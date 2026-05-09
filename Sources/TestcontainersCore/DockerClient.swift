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
    /// The host path (or named volume) to mount.
    public let hostPath: String
    /// Access mode: `"ro"` for read-only, `"rw"` for read-write.
    public let mode: String

    public init(hostPath: String, mode: String = "rw") {
        self.hostPath = hostPath
        self.mode = mode
    }
}

/// Returns the `DOCKER_HOST` environment variable value, or `nil`.
public func getDockerHost() -> String? {
    ProcessInfo.processInfo.environment["DOCKER_HOST"]
}

/// Extracts the hostname from a `ssh://user@host` Docker host URL, or `nil`.
public func getDockerHostHostname() -> String? {
    guard let dockerHost = getDockerHost(), dockerHost.hasPrefix("ssh://") else { return nil }
    let withoutScheme = String(dockerHost.dropFirst("ssh://".count))
    // Strip optional user@
    let hostPart = withoutScheme.components(separatedBy: "@").last ?? withoutScheme
    // Strip port if present
    return hostPart.components(separatedBy: ":").first
}

/// Returns `true` when `DOCKER_HOST` starts with `ssh://`.
public func isSshDockerHost() -> Bool {
    getDockerHost()?.hasPrefix("ssh://") ?? false
}

/// Returns the `DOCKER_AUTH_CONFIG` environment variable value, or `nil`.
public func getDockerAuthConfig() -> String? {
    ProcessInfo.processInfo.environment["DOCKER_AUTH_CONFIG"]
}

// MARK: - DockerClient

/// A thin HTTP client that speaks directly to the Docker Engine API.
///
/// By default, `DockerClient` uses a Unix domain socket. When `DOCKER_HOST`
/// is set to a TCP/HTTP URL, an HTTP client is used instead.
public class DockerClient {
    private let httpClient: HTTPClient
    private let baseURL: String
    private let _socketPath: String

    /// Creates a `DockerClient`.
    ///
    /// - Parameters:
    ///   - socketPath: Path to the Docker Unix socket.
    ///   - tcpHost: Optional TCP host (e.g. `"tcp://192.168.99.100:2376"`). When set,
    ///     overrides the Unix socket.
    public init(
        socketPath: String = testcontainersConfig.ryukDockerSocket,
        tcpHost: String? = nil
    ) {
        self._socketPath = socketPath
        if let tcp = tcpHost ?? Self.tcpDockerHost() {
            let normalized = tcp
                .replacingOccurrences(of: "tcp://", with: "http://")
                .replacingOccurrences(of: "ssh://", with: "http://")
            self.baseURL = normalized
            self.httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        } else {
            // Percent-encode the socket path for the unix+http URL scheme
            let encoded = socketPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? socketPath
            self.baseURL = "http+unix://\(encoded)"
            self.httpClient = HTTPClient(eventLoopGroupProvider: .singleton)
        }
    }

    deinit {
        try? httpClient.syncShutdown()
    }

    private static func tcpDockerHost() -> String? {
        guard let h = ProcessInfo.processInfo.environment["DOCKER_HOST"],
              h.hasPrefix("tcp://") || h.hasPrefix("http://")
        else { return nil }
        return h
    }

    // MARK: - Connection mode

    /// Returns the effective connection mode for this client.
    public func connectionMode() -> ConnectionMode {
        if let override = testcontainersConfig.connectionModeOverride { return override }
        if insideContainer() { return .bridgeIp }
        if let dh = getDockerHost(), dh.hasPrefix("ssh://") { return .gatewayIp }
        return .dockerHost
    }

    /// Returns the host address used to reach containers from the test process.
    public func host() -> String {
        if let tcHost = testcontainersConfig.tcHost { return tcHost }
        if let override = testcontainersConfig.tcHostOverride { return override }
        switch connectionMode() {
        case .bridgeIp:
            return "172.17.0.1"  // docker0 default gateway
        case .gatewayIp:
            return defaultGatewayIp() ?? "172.17.0.1"
        case .dockerHost:
            if let dh = getDockerHost(), dh.hasPrefix("ssh://") {
                return getDockerHostHostname() ?? "localhost"
            }
            return "localhost"
        }
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

        if let body = body {
            let data = try JSONSerialization.data(withJSONObject: body)
            req.headers.add(name: "Content-Type", value: "application/json")
            req.headers.add(name: "Content-Length", value: "\(data.count)")
            req.body = .bytes(ByteBuffer(data: data))
        } else if let raw = rawBody {
            req.headers.add(name: "Content-Length", value: "\(raw.count)")
            req.body = .bytes(ByteBuffer(data: raw))
        }

        for (k, v) in extraHeaders { req.headers.add(name: k, value: v) }

        let response = try await httpClient.execute(req, timeout: .seconds(30))
        var collected = Data()
        for try await chunk in response.body {
            collected.append(contentsOf: chunk.readableBytesView)
        }
        return (statusCode: Int(response.status.code), body: collected)
    }

    private func json(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        guard let obj = try json(from: data) as? [String: Any] else {
            throw DockerClientError.unexpectedResponse("Expected JSON object")
        }
        return obj
    }

    private func jsonArray(from data: Data) throws -> [[String: Any]] {
        guard let arr = try json(from: data) as? [[String: Any]] else {
            throw DockerClientError.unexpectedResponse("Expected JSON array")
        }
        return arr
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
        network: String? = nil,
        networkAliases: [String] = [],
        labels: [String: String] = [:],
        kwargs: [String: Any] = [:]
    ) async throws -> String {
        var body: [String: Any] = ["Image": image]

        if let cmd = command { body["Cmd"] = cmd }
        if !env.isEmpty { body["Env"] = env.map { "\($0.key)=\($0.value)" } }
        if !labels.isEmpty { body["Labels"] = labels }

        // ExposedPorts
        if !ports.isEmpty {
            var exposed: [String: Any] = [:]
            for p in ports.keys { exposed["\(p)/tcp"] = [:] as [String: Any] }
            body["ExposedPorts"] = exposed
        }

        // HostConfig
        var hostConfig: [String: Any] = [:]
        if !ports.isEmpty {
            var portBindings: [String: Any] = [:]
            for (container, host) in ports {
                let binding: [String: String]
                if let h = host {
                    binding = ["HostPort": "\(h)"]
                } else {
                    binding = ["HostPort": ""]
                }
                portBindings["\(container)/tcp"] = [binding]
            }
            hostConfig["PortBindings"] = portBindings
        }
        if !volumes.isEmpty {
            // Format: hostPath:containerPath:mode (Docker convention)
            // Key = host path, MountConfig.hostPath = container bind path
            hostConfig["Binds"] = volumes.map { "\($0.key):\($0.value.hostPath):\($0.value.mode)" }
        }
        if let priv = kwargs["privileged"] as? Bool { hostConfig["Privileged"] = priv }
        if let ar = kwargs["autoRemove"] as? Bool { hostConfig["AutoRemove"] = ar }
        if let mem = kwargs["memLimit"] as? Int { hostConfig["Memory"] = mem }
        if let platform = kwargs["platform"] as? String { body["Platform"] = platform }
        if !hostConfig.isEmpty { body["HostConfig"] = hostConfig }

        // NetworkingConfig
        if let netName = network {
            body["NetworkingConfig"] = [
                "EndpointsConfig": [
                    netName: networkAliases.isEmpty ? [:] as [String: Any] : ["Aliases": networkAliases],
                ],
            ]
        }

        var query: [String: String] = [:]
        if let n = name { query["name"] = n }

        let (statusCode, respBody) = try await request(method: .POST, path: "/v1.41/containers/create", query: query, body: body)
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
    public func removeImage(_ id: String, force: Bool = false, noPrune: Bool = false) async throws {
        var query: [String: String] = [:]
        if force { query["force"] = "1" }
        if noPrune { query["noprune"] = "1" }
        let (statusCode, _) = try await request(
            method: .DELETE,
            path: "/v1.41/images/\(id)",
            query: query
        )
        guard statusCode == 200 || statusCode == 204 else {
            throw DockerClientError.apiError(statusCode, "removeImage failed")
        }
    }

    /// Pulls a Docker image.
    public func pullImage(_ image: String) async throws {
        let (statusCode, _) = try await request(
            method: .POST,
            path: "/v1.41/images/create",
            query: ["fromImage": image]
        )
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, "pull failed")
        }
    }

    /// Returns the host port mapped to `port` on container `containerId`.
    public func port(containerId: String, port: Int) async throws -> Int {
        let details = try await getContainerDetails(containerId)
        let networkSettings = details["NetworkSettings"] as? [String: Any]
        let ports = networkSettings?["Ports"] as? [String: Any]
        let key = "\(port)/tcp"
        if let bindings = ports?[key] as? [[String: String]],
           let first = bindings.first,
           let hostPortStr = first["HostPort"],
           let hostPort = Int(hostPortStr) {
            return hostPort
        }
        throw DockerClientError.portNotFound(port)
    }

    /// Returns all containers.
    public func getContainers(all: Bool = false, filters: [String: Any]? = nil) async throws -> [[String: Any]] {
        var query: [String: String] = ["all": all ? "true" : "false"]
        if let f = filters,
           let data = try? JSONSerialization.data(withJSONObject: f),
           let str = String(data: data, encoding: .utf8) {
            query["filters"] = str
        }
        let (statusCode, body) = try await request(method: .GET, path: "/v1.41/containers/json", query: query)
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
        return try jsonArray(from: body)
    }

    /// Returns raw container details (`GET /containers/{id}/json`).
    public func getContainerDetails(_ id: String) async throws -> [String: Any] {
        let (statusCode, body) = try await request(method: .GET, path: "/v1.41/containers/\(id)/json")
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
        return try jsonObject(from: body)
    }

    /// Returns the bridge network IP of a container.
    public func bridgeIp(_ id: String) async throws -> String {
        let details = try await getContainerDetails(id)
        let ns = details["NetworkSettings"] as? [String: Any]
        if let networks = ns?["Networks"] as? [String: Any],
           let bridge = networks["bridge"] as? [String: Any],
           let ip = bridge["IPAddress"] as? String,
           !ip.isEmpty {
            return ip
        }
        if let ip = ns?["IPAddress"] as? String, !ip.isEmpty { return ip }
        throw DockerClientError.unexpectedResponse("Could not get bridge IP for \(id)")
    }

    /// Returns the gateway IP of a container's default network.
    public func gatewayIp(_ id: String) async throws -> String {
        let details = try await getContainerDetails(id)
        let ns = details["NetworkSettings"] as? [String: Any]
        if let networks = ns?["Networks"] as? [String: Any],
           let bridge = networks["bridge"] as? [String: Any],
           let gw = bridge["Gateway"] as? String,
           !gw.isEmpty {
            return gw
        }
        if let gw = ns?["Gateway"] as? String, !gw.isEmpty { return gw }
        throw DockerClientError.unexpectedResponse("Could not get gateway IP for \(id)")
    }

    /// Authenticates against a Docker registry.
    public func login(auth: DockerAuthInfo) async throws {
        let body: [String: Any] = [
            "serveraddress": auth.registry,
            "username": auth.username,
            "password": auth.password,
        ]
        let (statusCode, respBody) = try await request(method: .POST, path: "/v1.41/auth", body: body)
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, String(data: respBody, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Network management

    /// Creates a Docker network and returns its ID.
    public func createNetwork(_ name: String, options: [String: Any]? = nil) async throws -> String {
        var body: [String: Any] = ["Name": name]
        if let opts = options { body["Options"] = opts }
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
    public func connectNetwork(_ networkId: String, containerId: String, aliases: [String] = []) async throws {
        var body: [String: Any] = ["Container": containerId]
        if !aliases.isEmpty {
            body["EndpointConfig"] = ["Aliases": aliases]
        }
        let (statusCode, respBody) = try await request(
            method: .POST,
            path: "/v1.41/networks/\(networkId)/connect",
            body: body
        )
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, String(data: respBody, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Exec

    /// Runs a command inside a running container and returns (exitCode, output).
    public func execInContainer(_ id: String, command: [String]) async throws -> (exitCode: Int, output: Data) {
        // Create exec
        let createBody: [String: Any] = [
            "AttachStdout": true,
            "AttachStderr": true,
            "Cmd": command,
        ]
        let (createStatus, createBody_) = try await request(
            method: .POST, path: "/v1.41/containers/\(id)/exec", body: createBody
        )
        guard createStatus == 201 else {
            throw DockerClientError.apiError(createStatus, String(data: createBody_, encoding: .utf8) ?? "")
        }
        let createJson = try jsonObject(from: createBody_)
        guard let execId = createJson["Id"] as? String else {
            throw DockerClientError.unexpectedResponse("No exec Id")
        }

        // Start exec
        let startBody: [String: Any] = ["Detach": false, "Tty": false]
        let (startStatus, output) = try await request(
            method: .POST, path: "/v1.41/exec/\(execId)/start", body: startBody
        )
        guard startStatus == 200 else {
            throw DockerClientError.apiError(startStatus, String(data: output, encoding: .utf8) ?? "")
        }

        // Inspect to get exit code
        let (inspectStatus, inspectBody) = try await request(
            method: .GET, path: "/v1.41/exec/\(execId)/json"
        )
        guard inspectStatus == 200 else {
            throw DockerClientError.apiError(inspectStatus, String(data: inspectBody, encoding: .utf8) ?? "")
        }
        let inspectJson = try jsonObject(from: inspectBody)
        let exitCode = inspectJson["ExitCode"] as? Int ?? 0

        return (exitCode: exitCode, output: stripDockerMultiplexHeader(output))
    }

    // MARK: - Inspect

    /// Returns a typed `ContainerInspectInfo` for the given container ID.
    public func getContainerInspectInfo(_ id: String) async throws -> ContainerInspectInfo {
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
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
    }

    /// Downloads a tar archive from a container path.
    public func getArchive(_ id: String, path: String) async throws -> Data {
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

    // MARK: - Logs

    /// Returns the stdout and stderr logs of a container.
    public func getLogs(_ id: String) async throws -> (stdout: Data, stderr: Data) {
        let (statusCode, body) = try await request(
            method: .GET,
            path: "/v1.41/containers/\(id)/logs",
            query: ["stdout": "true", "stderr": "true"]
        )
        guard statusCode == 200 else {
            throw DockerClientError.apiError(statusCode, String(data: body, encoding: .utf8) ?? "")
        }
        return demuxDockerLogs(body)
    }

    // MARK: - Image operations

    /// Builds a Docker image from a local context directory.
    public func buildImage(
        contextPath: String,
        tag: String? = nil,
        noCache: Bool = false,
        dockerfile: String? = nil
    ) async throws -> String {
        // Build tar of the context directory
        let contextURL = URL(fileURLWithPath: contextPath)
        let tarData = try buildTransferTar(.path(contextURL), destination: ".")

        var query: [String: String] = ["nocache": noCache ? "1" : "0"]
        if let t = tag { query["t"] = t }
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
        // Extract image ID from build stream
        let responseText = String(data: body, encoding: .utf8) ?? ""
        for line in responseText.components(separatedBy: "\n") {
            if let data = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let aux = json["aux"] as? [String: Any],
               let idStr = aux["ID"] as? String {
                return idStr
            }
        }
        return tag ?? ""
    }
}

// MARK: - Docker multiplexed stream helpers

/// Strips the 8-byte Docker multiplexed-stream header from exec/log output.
///
/// The Docker exec attach API prefixes each frame with an 8-byte header:
/// `[stream_type(1)] [0 0 0] [size(4 big-endian)]`
func stripDockerMultiplexHeader(_ data: Data) -> Data {
    var result = Data()
    var offset = 0
    while offset + 8 <= data.count {
        let size = Int(data[offset + 4]) << 24
            | Int(data[offset + 5]) << 16
            | Int(data[offset + 6]) << 8
            | Int(data[offset + 7])
        offset += 8
        if offset + size <= data.count {
            result.append(data[offset..<offset + size])
            offset += size
        } else {
            break
        }
    }
    return result.isEmpty ? data : result
}

/// Demultiplexes Docker log stream into separate stdout and stderr.
func demuxDockerLogs(_ data: Data) -> (stdout: Data, stderr: Data) {
    var stdout = Data()
    var stderr = Data()
    var offset = 0
    while offset + 8 <= data.count {
        let streamType = data[offset]
        let size = Int(data[offset + 4]) << 24
            | Int(data[offset + 5]) << 16
            | Int(data[offset + 6]) << 8
            | Int(data[offset + 7])
        offset += 8
        if offset + size <= data.count {
            let chunk = data[offset..<offset + size]
            if streamType == 1 { stdout.append(chunk) }
            else if streamType == 2 { stderr.append(chunk) }
            offset += size
        } else {
            break
        }
    }
    return (stdout: stdout, stderr: stderr)
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
