/// Docker Compose integration for testcontainers-swift.
///
/// `DockerCompose` wraps the `docker compose` CLI to bring up, introspect,
/// and tear down multi-container stacks in tests. `ComposeContainer` models a
/// single running service inside the stack and implements `WaitStrategyTarget`
/// so that all built-in wait strategies work with Compose services.
import Foundation
import TestcontainersCore

// One-shot deprecation warning for getConfig — printed on the first call only.
private var getConfigWarningPrinted = false

private let configExperimentalWarning =
    "get_config is experimental, see testcontainers/testcontainers-python#669"

/// IP version preference used when selecting a published port URL.
public enum IpVersion {
    /// Prefer IPv4 addresses.
    case ipv4
    /// Prefer IPv6 addresses.
    case ipv6
}

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
        let sshHost = getDockerHostHostname()
        if let ssh = sshHost,
           url == "0.0.0.0" || url == "127.0.0.1" || url == "localhost"
               || url == "::" || url == "::1" {
            normalizedUrl = ssh
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

/// Represents a single running service container within a Docker Compose stack.
///
/// Instances are returned by `DockerCompose.containers()` and
/// `DockerCompose.container(_:)`. They implement `WaitStrategyTarget` so
/// standard wait strategies work directly with Compose services.
public class ComposeContainer: WaitStrategyTarget {
    public var id: String?
    public var name: String?
    public var command: String?
    public var project: String?
    public var service: String?
    public var state: String?
    public var health: String?
    public var exitCode: Int?
    public var publishers: [PublishedPortModel] = []

    internal weak var dockerCompose: DockerCompose?
    private var cachedContainerInfo: ContainerInspectInfo?

    public init() {}

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

    public func containerHostIp() -> String { "127.0.0.1" }

    public func exposedPort(_ port: Int) async throws -> Int { port }

    public func logs() throws -> (stdout: Data, stderr: Data) {
        guard let compose = dockerCompose else {
            throw ComposeError.noReference("DockerCompose reference not set on ComposeContainer")
        }
        guard let svc = service else {
            throw ComposeError.noReference("Service name not set on ComposeContainer")
        }
        let logOutput = try compose.getLogs(services: [svc])
        return (stdout: Data(logOutput.utf8), stderr: Data())
    }

    public func exec(_ command: [String]) async throws -> (exitCode: Int, output: Data) {
        guard let compose = dockerCompose else {
            throw ComposeError.noReference("DockerCompose reference not set on ComposeContainer")
        }
        guard let svc = service else {
            throw ComposeError.noReference("Service name not set on ComposeContainer")
        }
        let result = try compose.exec(serviceName: svc, command: command)
        return (exitCode: result.exitCode, output: Data(result.output.utf8))
    }

    public func reload() {}

    public var status: String { state ?? "unknown" }

    /// Returns the full Docker inspect information for this container.
    public func containerInfo() async throws -> ContainerInspectInfo? {
        if let cached = cachedContainerInfo { return cached }
        guard let compose = dockerCompose, let containerId = id else { return nil }
        do {
            let info = try await compose.dockerClient.getContainerInspectInfo(containerId)
            cachedContainerInfo = info
            return info
        } catch {
            return nil
        }
    }
}

/// Manages a Docker Compose stack in tests.
///
/// Wraps the `docker compose` CLI to bring up a multi-service stack, wait for
/// services to be healthy, introspect containers, and tear the stack down.
public class DockerCompose {
    /// The directory used as the working directory for all Compose commands.
    public let context: String

    /// Compose file(s) to pass with `-f`.
    public let composeFileName: [String]?

    /// Whether to run `docker compose pull` before `up`. Defaults to `false`.
    public var pull: Bool = false

    /// Whether to pass `--build` to `docker compose up`. Defaults to `false`.
    public var build: Bool = false

    /// Whether to wait for services to be healthy. Defaults to `true`.
    public var wait: Bool = true

    /// Whether to preserve volumes when stopping. Defaults to `false`.
    public var keepVolumes: Bool = false

    /// `--env-file` argument(s) passed to every Compose command.
    public var envFile: [String]?

    /// Optional subset of services to bring up / tear down.
    public var services: [String]?

    /// Path to the `docker` executable, or `nil` to use the system `docker`.
    public var dockerCommandPath: String?

    /// `--profile` arguments passed to every Compose command.
    public var profiles: [String]?

    /// Whether to pass `--quiet` to `docker compose pull`. Defaults to `false`.
    public var quietPull: Bool = false

    /// Whether to pass `--quiet-build` to `docker compose up --build`. Defaults to `false`.
    public var quietBuild: Bool = false

    internal lazy var dockerClient: DockerClient = DockerClient()

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
        self.composeFileName = composeFileName
        self.pull = pull
        self.build = build
        self.wait = wait
        self.keepVolumes = keepVolumes
        self.envFile = envFile
        self.services = services
        self.dockerCommandPath = dockerCommandPath
        self.profiles = profiles
        self.quietPull = quietPull
        self.quietBuild = quietBuild
    }

    // MARK: - Compose command base

    private var composeCommandProperty: [String] {
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
    }

    // MARK: - Lifecycle

    /// Brings the Compose stack up.
    public func start() throws {
        if pull {
            try runCommand(composeCommandProperty + ["pull"] + (quietPull ? ["--quiet"] : []))
        }

        var upCmd = composeCommandProperty + ["up"]
        if build { upCmd += ["--build"] }
        if build && quietBuild { upCmd += ["--quiet-build"] }
        upCmd += wait ? ["--wait"] : ["--detach"]
        upCmd += services ?? []
        try runCommand(upCmd)
    }

    /// Tears the Compose stack down.
    ///
    /// - `down: true` — runs `docker compose down --volumes`.
    /// - `down: false` — runs `docker compose stop`.
    public func stop(down: Bool = true) throws {
        let cmd: [String]
        if down {
            cmd = composeCommandProperty + ["down", "--volumes"] + (services ?? [])
        } else {
            cmd = composeCommandProperty + ["stop"] + (services ?? [])
        }
        try runCommand(cmd)
    }

    // MARK: - Container introspection

    /// Returns log output for the specified services.
    public func getLogs(services: [String]? = nil) throws -> String {
        let cmd = composeCommandProperty + ["logs"] + (services ?? [])
        let result = try runCommand(cmd)
        return result.stdout
    }

    /// Returns the resolved Compose configuration as a JSON object.
    ///
    /// A deprecation warning is printed to stderr on the first call.
    public func getConfig(
        pathResolution: Bool = true,
        normalize: Bool = true,
        interpolate: Bool = true
    ) throws -> [String: Any] {
        if !getConfigWarningPrinted {
            fputs(configExperimentalWarning + "\n", stderr)
            getConfigWarningPrinted = true
        }
        var cmd = composeCommandProperty + ["config", "--format", "json"]
        if !pathResolution { cmd += ["--no-path-resolution"] }
        if !normalize { cmd += ["--no-normalize"] }
        if !interpolate { cmd += ["--no-interpolate"] }
        let result = try runCommand(cmd)
        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ComposeError.parseError("Failed to parse docker compose config output")
        }
        return json
    }

    /// Returns the list of containers in the stack.
    ///
    /// Handles both Docker 24 array-per-output and Docker 25+ one-object-per-line formats.
    public func getContainers(includeAll: Bool = false) throws -> [ComposeContainer] {
        var cmd = composeCommandProperty + ["ps", "--format", "json"]
        if includeAll { cmd += ["-a"] }
        let result = try runCommand(cmd)
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty { return [] }

        var containers: [ComposeContainer] = []
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) else {
                fputs("testcontainers: ignoring unparseable line from docker compose ps: \(trimmed)\n", stderr)
                continue
            }
            if let arr = decoded as? [[String: Any]] {
                containers += arr.map { ComposeContainer(from: $0) }
            } else if let obj = decoded as? [String: Any] {
                containers.append(ComposeContainer(from: obj))
            }
        }
        for c in containers { c.dockerCompose = self }
        return containers
    }

    /// Returns a single `ComposeContainer` from the stack.
    public func container(serviceName: String? = nil) throws -> ComposeContainer {
        if let name = serviceName {
            let matching = try getContainers().filter { $0.service == name }
            if matching.isEmpty {
                throw ContainerIsNotRunning("\(name) is not running in the compose context")
            }
            return matching[0]
        } else {
            let all = try getContainers()
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
    public func exec(serviceName: String, command: [String]) throws -> (exitCode: Int, output: String) {
        let cmd = composeCommandProperty + ["exec", "-T", serviceName] + command
        let result = try runCommandAllowingFailure(cmd)
        return (exitCode: result.exitCode, output: result.stdout)
    }

    /// Polls `url` until it returns an HTTP 2xx response.
    public func waitFor(url: String) async throws {
        let timeout = testcontainersConfig.timeout
        let deadline = ContinuousClock.now + .seconds(Int(timeout))
        while ContinuousClock.now < deadline {
            do {
                guard let u = URL(string: url) else { break }
                let (_, response) = try await URLSession.shared.data(from: u)
                if let http = response as? HTTPURLResponse,
                   http.statusCode >= 200 && http.statusCode < 300 {
                    return
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
        try compose.start()
        do {
            let result = try await fn(compose)
            try compose.stop(down: !compose.keepVolumes)
            return result
        } catch {
            try? compose.stop(down: !compose.keepVolumes)
            throw error
        }
    }

    // MARK: - Private helpers

    @discardableResult
    private func runCommand(_ cmd: [String]) throws -> (stdout: String, stderr: String) {
        let result = try runCommandAllowingFailure(cmd)
        if result.exitCode != 0 {
            throw ComposeError.processError(
                cmd.joined(separator: " "),
                result.exitCode,
                result.stderr
            )
        }
        return (stdout: result.stdout, stderr: result.stderr)
    }

    private func runCommandAllowingFailure(_ cmd: [String]) throws -> (stdout: String, stderr: String, exitCode: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = cmd
        process.currentDirectoryURL = URL(fileURLWithPath: context)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        return (stdout: stdout, stderr: stderr, exitCode: Int(process.terminationStatus))
    }
}

/// Errors thrown by Compose operations.
public enum ComposeError: Error, CustomStringConvertible {
    case processError(String, Int, String)
    case noReference(String)
    case parseError(String)

    public var description: String {
        switch self {
        case .processError(let cmd, let code, let stderr):
            return "Process '\(cmd)' exited with code \(code): \(stderr)"
        case .noReference(let m), .parseError(let m):
            return m
        }
    }
}
