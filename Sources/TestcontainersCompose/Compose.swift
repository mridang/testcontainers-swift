/// Docker Compose integration for testcontainers-swift.
///
/// `DockerCompose` wraps the `docker compose` CLI to bring up, introspect,
/// and tear down multi-container stacks in tests. `ComposeContainer` models a
/// single running service inside the stack and implements `WaitStrategyTarget`
/// so that all built-in wait strategies work with Compose services.
import Foundation
import TestcontainersCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// One-shot deprecation warning for config — printed on the first call only.
private nonisolated(unsafe) var _getConfigWarningPrinted = false

private let _configExperimentalWarning =
    "get_config is experimental, see testcontainers/testcontainers-python#669"

/// IP version preference used when selecting a published port URL.
public enum IpVersion {
    /// Prefer IPv4 addresses.
    case ipv4
    /// Prefer IPv6 addresses.
    case ipv6
}

// MARK: - PublishedPortModel

/// Describes a single published port for a Compose service.
public struct PublishedPortModel {
    /// Host IP address or hostname that the port is bound on.
    public let url: String?
    /// Container-side port number.
    public let targetPort: Int?
    /// Ephemeral port number on the host.
    public let publishedPort: Int?
    /// Transport protocol, e.g. `"tcp"` or `"udp"`.
    public let protocol_: String?

    public init(url: String? = nil, targetPort: Int? = nil, publishedPort: Int? = nil, protocol_: String? = nil) {
        self.url = url
        self.targetPort = targetPort
        self.publishedPort = publishedPort
        self.protocol_ = protocol_
    }

    /// Deserialises from Docker Compose JSON output.
    public init(from dict: [String: Any]) {
        self.url = dict["URL"] as? String
        self.targetPort = dict["TargetPort"] as? Int
        self.publishedPort = dict["PublishedPort"] as? Int
        self.protocol_ = dict["Protocol"] as? String
    }

    /// Returns a copy with `url` normalised for the current Docker host.
    ///
    /// - SSH Docker host: loopback addresses are replaced with the SSH hostname.
    /// - Windows: `0.0.0.0` is replaced with `127.0.0.1`.
    public func normalize() -> PublishedPortModel {
        var normalizedUrl = url
        if let ssh = dockerHostHostname() {
            if url == "0.0.0.0" || url == "127.0.0.1" || url == "localhost"
                || url == "::" || url == "::1"
            {
                normalizedUrl = ssh
            }
        } else {
            #if os(Windows)
                if url == "0.0.0.0" {
                    normalizedUrl = "127.0.0.1"
                }
            #endif
        }
        guard normalizedUrl != url else { return self }
        return PublishedPortModel(
            url: normalizedUrl,
            targetPort: targetPort,
            publishedPort: publishedPort,
            protocol_: protocol_
        )
    }
}

// MARK: - ComposeContainer

/// Represents a single running service container within a Docker Compose stack.
///
/// Instances are returned by `DockerCompose.containers()` and
/// `DockerCompose.container(_:)`. They implement `WaitStrategyTarget` so
/// standard wait strategies work directly with Compose services.
public class ComposeContainer: WaitStrategyTarget {
    /// Docker container ID (short or full hex string).
    public let id: String?

    /// Container name as assigned by Docker Compose.
    public let name: String?

    /// The command string the container's main process is running.
    public let command: String?

    /// Compose project name.
    public let project: String?

    /// Compose service name.
    public let service: String?

    /// Container state string, e.g. `"running"`, `"exited"`.
    public var state: String?

    /// Docker health-check status string.
    public let health: String?

    /// Exit code of the container's main process (when stopped).
    public let exitCode: Int?

    /// Published port mappings for this container, already normalised.
    public var publishers: [PublishedPortModel]

    internal var dockerCompose: DockerCompose?
    private var _cachedContainerInfo: ContainerInspectInfo?

    public init(
        id: String? = nil,
        name: String? = nil,
        command: String? = nil,
        project: String? = nil,
        service: String? = nil,
        state: String? = nil,
        health: String? = nil,
        exitCode: Int? = nil,
        publishers: [PublishedPortModel]? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.project = project
        self.service = service
        self.state = state
        self.health = health
        self.exitCode = exitCode
        self.publishers = publishers ?? []
    }

    public init(from dict: [String: Any]) {
        self.id = dict["ID"] as? String
        self.name = dict["Name"] as? String
        self.command = dict["Command"] as? String
        self.project = dict["Project"] as? String
        self.service = dict["Service"] as? String
        self.state = dict["State"] as? String
        self.health = dict["Health"] as? String
        self.exitCode = dict["ExitCode"] as? Int
        if let rawPublishers = dict["Publishers"] as? [[String: Any]] {
            self.publishers = rawPublishers.map { PublishedPortModel(from: $0).normalize() }
        } else {
            self.publishers = []
        }
    }

    // MARK: - Publisher lookup

    private static func matchesIpVersion(_ prefer: IpVersion, _ r: PublishedPortModel) -> Bool {
        let hasColon = r.url?.contains(":") ?? false
        return hasColon == (prefer == .ipv6)
    }

    /// Finds and returns the single `PublishedPortModel` matching the given filters.
    ///
    /// Throws `NoSuchPortExposed` when no matching publisher is found or when
    /// more than one publisher matches (ambiguous result).
    public func publisher(
        byPort: Int? = nil,
        byHost: String? = nil,
        preferIpVersion: IpVersion = .ipv4
    ) throws -> PublishedPortModel {
        var remaining = publishers.filter { Self.matchesIpVersion(preferIpVersion, $0) }
        if let port = byPort {
            remaining = remaining.filter { $0.targetPort == port }
        }
        if let host = byHost {
            remaining = remaining.filter { $0.url == host }
        }
        if remaining.isEmpty {
            throw NoSuchPortExposed(
                "No publisher found for service \(service ?? "?") "
                    + "(byPort=\(byPort.map { "\($0)" } ?? "any"), "
                    + "byHost=\(byHost ?? "any"), preferIpVersion=\(preferIpVersion))"
            )
        }
        if remaining.count != 1 {
            throw NoSuchPortExposed(
                "Ambiguous publisher for service \(service ?? "?"): expected exactly 1 "
                    + "but found \(remaining.count) "
                    + "(byPort=\(byPort.map { "\($0)" } ?? "any"), "
                    + "byHost=\(byHost ?? "any"), preferIpVersion=\(preferIpVersion))"
            )
        }
        return remaining[0]
    }

    // MARK: - WaitStrategyTarget

    public func containerHostIp() async throws -> String { "127.0.0.1" }

    public func exposedPort(_ port: Int) async throws -> Int { port }

    public var wrappedContainer: AnyObject { self }

    public func logs() async throws -> (stdout: Data, stderr: Data) {
        guard let compose = dockerCompose else {
            throw ComposeError.noReference("DockerCompose reference not set on ComposeContainer")
        }
        guard let svc = service else {
            throw ComposeError.noReference("Service name not set on ComposeContainer")
        }
        let (stdout, stderr) = compose.logs([svc])
        return (stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
    }

    public func exec(_ command: [String]) async throws -> (exitCode: Int, output: Data) {
        guard let compose = dockerCompose else {
            throw ComposeError.noReference("DockerCompose reference not set on ComposeContainer")
        }
        guard let svc = service else {
            throw ComposeError.noReference("Service name not set on ComposeContainer")
        }
        let (stdout, _, exitCode) = compose.execInContainer(command, serviceName: svc)
        return (exitCode: exitCode, output: Data(stdout.utf8))
    }

    public func containerInfo() async throws -> ContainerInspectInfo? {
        if let cached = _cachedContainerInfo { return cached }
        guard let compose = dockerCompose, let containerId = id else { return nil }
        do {
            let info = try await compose._dockerClient.containerInspectInfo(containerId)
            _cachedContainerInfo = info
            return info
        } catch {
            return nil
        }
    }

    public func reload() async {}

    public var status: String { state ?? "unknown" }
}

// MARK: - DockerCompose

/// Manages a Docker Compose stack in tests.
///
/// Wraps the `docker compose` CLI to bring up a multi-service stack, wait for
/// services to be healthy, introspect containers, and tear the stack down.
///
/// All Compose CLI commands are run synchronously via `Process`; failures throw
/// `ComposeError.processError`.
public class DockerCompose {
    /// The directory used as the working directory for all Compose commands.
    public let context: String

    /// Compose file(s) to pass with `-f`.
    public let composeFileName: [String]?

    /// Whether to run `docker compose pull` before `up`. Defaults to `false`.
    public let pull: Bool

    /// Whether to pass `--build` to `docker compose up`. Defaults to `false`.
    public let build: Bool

    /// Whether to wait for services to be healthy. Defaults to `true`.
    public let wait: Bool

    /// Whether to preserve volumes when stopping. Defaults to `false`.
    public let keepVolumes: Bool

    /// `--env-file` argument(s) passed to every Compose command.
    public let envFile: [String]?

    /// Optional subset of services to bring up / tear down.
    public let services: [String]?

    /// Path to the `docker` executable, or `nil` to use the system `docker`.
    public let dockerCommandPath: String?

    /// `--profile` arguments passed to every Compose command.
    public let profiles: [String]?

    /// Whether to pass `--quiet` to `docker compose pull`. Defaults to `false`.
    public let quietPull: Bool

    /// Whether to pass `--quiet-build` to `docker compose up --build`. Defaults to `false`.
    public let quietBuild: Bool

    private var _waitStrategies: [String: WaitStrategy]?
    internal lazy var _dockerClient: DockerClient = DockerClient()

    // MARK: - Init

    public init(
        context: String,
        composeFileName: [String]? = nil,
        pull: Bool = false,
        build: Bool = false,
        wait: Bool = true,
        keepVolumes: Bool = false,
        envFile: [String]? = nil,
        services: [String]? = nil,
        dockerCommandPath: String? = nil,
        profiles: [String]? = nil,
        quietPull: Bool = false,
        quietBuild: Bool = false
    ) {
        self.context = context
        self.composeFileName = composeFileName.map { Array($0) }
        self.pull = pull
        self.build = build
        self.wait = wait
        self.keepVolumes = keepVolumes
        self.envFile = envFile.map { Array($0) }
        self.services = services.map { Array($0) }
        self.dockerCommandPath = dockerCommandPath
        self.profiles = profiles.map { Array($0) }
        self.quietPull = quietPull
        self.quietBuild = quietBuild
    }

    // MARK: - Compose command base

    /// The base command prefix shared by all Compose CLI invocations.
    ///
    /// Lazily built and cached as an **unmodifiable** `[String]`.
    public private(set) lazy var composeCommandProperty: [String] = {
        var cmd: [String]
        if let dockerPath = dockerCommandPath {
            cmd = [dockerPath, "compose"]
        } else {
            cmd = ["docker", "compose"]
        }
        for f in composeFileName ?? [] { cmd += ["-f", f] }
        for p in profiles ?? [] { cmd += ["--profile", p] }
        for e in envFile ?? [] { cmd += ["--env-file", e] }
        return cmd
    }()

    // MARK: - waitingFor builder

    /// Registers per-service `WaitStrategy` instances to run after `up`.
    ///
    /// Returns `self` for chaining.
    @discardableResult
    public func waitingFor(_ strategies: [String: WaitStrategy]) -> DockerCompose {
        _waitStrategies = strategies
        return self
    }

    // MARK: - Lifecycle

    /// Brings the Compose stack up.
    ///
    /// Steps:
    /// 1. Optionally runs `docker compose pull` when `pull` is `true`.
    /// 2. Runs `docker compose up [--build] [--wait|--detach] [services…]`.
    /// 3. Runs any registered wait strategies against their respective containers.
    public func start() async throws {
        if pull {
            try _runCommand(composeCommandProperty + ["pull"] + (quietPull ? ["--quiet"] : []))
        }

        var upCmd = composeCommandProperty + ["up"]
        if build { upCmd += ["--build"] }
        if build && quietBuild { upCmd += ["--quiet-build"] }
        upCmd += wait ? ["--wait"] : ["--detach"]
        upCmd += services ?? []
        try _runCommand(upCmd)

        if let strategies = _waitStrategies {
            for (serviceName, strategy) in strategies {
                let target = try container(serviceName)
                try await strategy.waitUntilReady(target: target)
            }
        }
    }

    /// Tears the Compose stack down.
    ///
    /// - `down: true` (default) — runs `docker compose down --volumes`.
    /// - `down: false` — runs `docker compose stop`.
    public func stop(down: Bool = true) {
        let cmd: [String]
        if down {
            cmd = composeCommandProperty + ["down", "--volumes"] + (services ?? [])
        } else {
            cmd = composeCommandProperty + ["stop"] + (services ?? [])
        }
        _ = try? _runCommand(cmd)
    }

    // MARK: - Container introspection

    /// Returns log output for the specified services as `(stdout, stderr)`.
    ///
    /// When `services` is omitted, logs for all services are returned.
    public func logs(_ services: [String]? = nil) -> (String, String) {
        let cmd = composeCommandProperty + ["logs"] + (services ?? [])
        let result = _runCommandAllowingFailure(cmd)
        return (result.stdout, result.stderr)
    }

    /// **Experimental.** Returns the resolved Compose configuration as a JSON map.
    ///
    /// A deprecation warning is printed to stderr on the first call.
    public func config(
        pathResolution: Bool = true,
        normalize: Bool = true,
        interpolate: Bool = true
    ) throws -> [String: Any] {
        if !_getConfigWarningPrinted {
            FileHandle.standardError.write(Data((_configExperimentalWarning + "\n").utf8))
            _getConfigWarningPrinted = true
        }
        var cmd = composeCommandProperty + ["config", "--format", "json"]
        if !pathResolution { cmd += ["--no-path-resolution"] }
        if !normalize { cmd += ["--no-normalize"] }
        if !interpolate { cmd += ["--no-interpolate"] }
        let result = try _runCommand(cmd)
        guard let data = result.stdout.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ComposeError.parseError("Failed to parse docker compose config output")
        }
        return json
    }

    /// Returns the list of containers in the stack.
    ///
    /// Handles both Docker 24 array-per-output and Docker 25+ one-object-per-line formats.
    ///
    /// Each returned `ComposeContainer` has its `DockerCompose` back-reference
    /// set so that further operations (logs, inspect) work.
    public func containers(includeAll: Bool = false) -> [ComposeContainer] {
        var cmd = composeCommandProperty + ["ps", "--format", "json"]
        if includeAll { cmd += ["-a"] }
        let result = _runCommandAllowingFailure(cmd)
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty { return [] }

        var containerList: [ComposeContainer] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8),
                let decoded = try? JSONSerialization.jsonObject(with: data)
            else {
                FileHandle.standardError.write(
                    Data("testcontainers: ignoring unparseable line from docker compose ps: \(trimmed)\n".utf8)
                )
                continue
            }
            if let arr = decoded as? [[String: Any]] {
                containerList += arr.map { ComposeContainer(from: $0) }
            } else if let obj = decoded as? [String: Any] {
                containerList.append(ComposeContainer(from: obj))
            }
        }
        for c in containerList { c.dockerCompose = self }
        return containerList
    }

    /// Returns a single `ComposeContainer` from the stack.
    ///
    /// - `serviceName: nil` — there must be exactly one container running.
    /// - `serviceName` given — finds the container whose `service` matches.
    public func container(_ serviceName: String? = nil, includeAll: Bool = false) throws -> ComposeContainer {
        if let name = serviceName {
            let matching = containers(includeAll: includeAll).filter { $0.service == name }
            if matching.isEmpty {
                throw ContainerIsNotRunning("\(name) is not running in the compose context")
            }
            return matching[0]
        } else {
            let all = containers(includeAll: includeAll)
            if all.count != 1 {
                throw ContainerIsNotRunning(
                    "get_container failed because no service_name given "
                        + "and there is not exactly 1 container (but \(all.count))"
                )
            }
            return all[0]
        }
    }

    /// Runs `command` inside the named Compose service container.
    ///
    /// Returns `(stdout, stderr, exitCode)` — the raw output strings and the
    /// process exit code.
    public func execInContainer(_ command: [String], serviceName: String? = nil) -> (String, String, Int) {
        let svcName = serviceName ?? (try? container())?.service ?? ""
        let cmd = composeCommandProperty + ["exec", "-T", svcName] + command
        let result = _runCommandAllowingFailure(cmd)
        return (result.stdout, result.stderr, result.exitCode)
    }

    /// Returns the host IP address bound to a service's published port.
    public func serviceHost(serviceName: String? = nil, port: Int? = nil) throws -> String? {
        let svc = try container(serviceName)
        let pub = try svc.publisher(byPort: port).normalize()
        return pub.url
    }

    /// Returns the ephemeral host port number for a service's published port.
    public func servicePort(serviceName: String? = nil, port: Int? = nil) throws -> Int? {
        let pub = try container(serviceName).publisher(byPort: port).normalize()
        return pub.publishedPort
    }

    /// Returns both the normalised host address and ephemeral port for a service.
    public func serviceHostAndPort(serviceName: String? = nil, port: Int? = nil) throws -> (String?, Int?) {
        let pub = try container(serviceName).publisher(byPort: port).normalize()
        return (pub.url, pub.publishedPort)
    }

    /// Polls `url` until it returns an HTTP 2xx response.
    @discardableResult
    public func waitFor(url: String) async throws -> DockerCompose {
        let timeout = testcontainersConfig.timeout
        let deadline = ContinuousClock.now + .seconds(Int(timeout))
        while ContinuousClock.now < deadline {
            do {
                guard let u = URL(string: url) else { break }
                let (_, response) = try await URLSession.shared.data(from: u)
                if let http = response as? HTTPURLResponse,
                    http.statusCode >= 200 && http.statusCode < 300
                {
                    return self
                }
            } catch {}
            try await Task.sleep(for: .seconds(1))
        }
        throw WaitStrategyError.timeout("URL \(url) not ready within \(timeout)s")
    }

    // MARK: - use()

    /// Brings up `compose`, runs `fn` with it, and tears it down afterwards.
    ///
    /// Teardown uses `down --volumes` when `keepVolumes` is `false`, or
    /// `stop` when it is `true`.
    public static func use<T>(
        _ compose: DockerCompose,
        _ fn: (DockerCompose) async throws -> T
    ) async throws -> T {
        try await compose.start()
        do {
            let result = try await fn(compose)
            compose.stop(down: !compose.keepVolumes)
            return result
        } catch {
            compose.stop(down: !compose.keepVolumes)
            throw error
        }
    }

    // MARK: - Private helpers

    @discardableResult
    private func _runCommand(_ cmd: [String]) throws -> (stdout: String, stderr: String) {
        let result = _runCommandAllowingFailure(cmd)
        if result.exitCode != 0 {
            throw ComposeError.processError(
                cmd.joined(separator: " "),
                result.exitCode,
                result.stderr
            )
        }
        return (stdout: result.stdout, stderr: result.stderr)
    }

    private func _runCommandAllowingFailure(_ cmd: [String]) -> (stdout: String, stderr: String, exitCode: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = cmd
        process.currentDirectoryURL = URL(fileURLWithPath: context)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try? process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
        return (stdout: stdoutStr, stderr: stderrStr, exitCode: Int(process.terminationStatus))
    }
}

// MARK: - Errors

/// Errors thrown by Compose operations.
public enum ComposeError: Error, CustomStringConvertible {
    case processError(String, Int, String)
    case noReference(String)
    case parseError(String)

    public var description: String {
        switch self {
        case .processError(let cmd, let code, let stderrStr):
            return "Process '\(cmd)' exited with code \(code): \(stderrStr)"
        case .noReference(let m), .parseError(let m):
            return m
        }
    }
}
