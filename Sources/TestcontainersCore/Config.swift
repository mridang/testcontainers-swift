/// Runtime configuration for testcontainers-swift.
///
/// Configuration is read from two sources (in priority order):
/// 1. Environment variables — standard testcontainers env vars such as
///    `TC_MAX_TRIES`, `TESTCONTAINERS_RYUK_DISABLED`, etc.
/// 2. `~/.testcontainers.properties` — a Java-style `key=value` file
///    read by `readTcProperties()`.
///
/// The global singleton `testcontainersConfig` is created once at import
/// time and reused throughout the library.
import Foundation

/// Truthy string values accepted when parsing boolean configuration flags.
///
/// Comparisons are always case-insensitive.
private let enableFlags: Set<String> = ["yes", "true", "t", "y", "1"]

/// Determines how `DockerClient` computes the host IP address and port for
/// containers.
public enum ConnectionMode: Equatable {
    /// Use the container's bridge-network IP address directly.
    /// Ports are NOT remapped — the container port is used as-is.
    case bridgeIp

    /// Use the default-gateway IP of the Docker bridge network.
    /// Ports ARE remapped via the Docker daemon's host-port mapping.
    case gatewayIp

    /// Use the Docker host's address (as resolved by `DockerClient.host()`).
    /// Ports ARE remapped. This is the default mode on the host machine.
    case dockerHost

    /// Returns `true` when this connection mode requires the Docker-assigned
    /// ephemeral host port rather than the container's internal port number.
    public var useMappedPort: Bool { self != .bridgeIp }
}

/// Returns the path to the Docker Unix socket.
///
/// Resolution order:
/// 1. `TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE` — explicit socket path.
/// 2. `DOCKER_HOST` starting with `unix://` — custom Unix socket path.
/// 3. `$XDG_RUNTIME_DIR/docker.sock` — rootless Docker socket (if the file exists).
/// 4. `/var/run/docker.sock` — the standard system-wide Docker socket.
public func dockerSocket() -> String {
    let env = ProcessInfo.processInfo.environment

    if let override = env["TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE"], !override.isEmpty {
        return override
    }

    let dockerHost = env["DOCKER_HOST"] ?? ""
    if dockerHost.hasPrefix("unix://") {
        let socketPath = String(dockerHost.dropFirst("unix://".count))
        if !socketPath.isEmpty { return socketPath }
    }

    if let xdg = env["XDG_RUNTIME_DIR"], !xdg.isEmpty {
        let rootless = "\(xdg)/docker.sock"
        if FileManager.default.fileExists(atPath: rootless) { return rootless }
    }

    return "/var/run/docker.sock"
}

/// Parses the `TESTCONTAINERS_CONNECTION_MODE` environment variable.
///
/// Returns the corresponding `ConnectionMode`, or `nil` when absent or empty.
/// Throws `ConfigurationError` when the variable is set to an unrecognised value.
public func overriddenConnectionMode() throws -> ConnectionMode? {
    let val = ProcessInfo.processInfo.environment["TESTCONTAINERS_CONNECTION_MODE"] ?? ""
    guard !val.isEmpty else { return nil }
    switch val {
    case "bridge_ip":   return .bridgeIp
    case "gateway_ip":  return .gatewayIp
    case "docker_host": return .dockerHost
    default:
        throw ConfigurationError.invalidConnectionMode(val)
    }
}

/// Reads `~/.testcontainers.properties` and returns its key-value pairs.
///
/// Lines without `=` are ignored. Keys and values are stripped of
/// leading/trailing whitespace. Quoted values are NOT supported.
/// Returns an empty dictionary when the file does not exist.
public func readTcProperties() -> [String: String] {
    let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
    let path = "\(home)/.testcontainers.properties"
    guard
        FileManager.default.fileExists(atPath: path),
        let contents = try? String(contentsOfFile: path, encoding: .utf8)
    else { return [:] }

    var settings: [String: String] = [:]
    for line in contents.components(separatedBy: "\n") {
        guard let idx = line.firstIndex(of: "=") else { continue }
        let key = String(line[line.startIndex..<idx]).trimmingCharacters(in: .whitespaces)
        let valueStart = line.index(after: idx)
        let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
        settings[key] = value
    }
    return settings
}

/// Errors thrown by configuration parsing.
public enum ConfigurationError: Error, CustomStringConvertible {
    case invalidConnectionMode(String)
    case invalidInt(String, String)
    case invalidDouble(String, String)

    public var description: String {
        switch self {
        case .invalidConnectionMode(let v):
            return "Error parsing TESTCONTAINERS_CONNECTION_MODE value \"\(v)\". "
                + "Expected one of: bridge_ip, gateway_ip, docker_host."
        case .invalidInt(let envVar, let v):
            return "Invalid value for \(envVar): \"\(v)\" is not a valid integer."
        case .invalidDouble(let envVar, let v):
            return "Invalid value for \(envVar): \"\(v)\" is not a valid number."
        }
    }
}

/// Holds all runtime-tunable configuration for testcontainers-swift.
///
/// Values are read from environment variables at construction time and can be
/// overridden programmatically (useful in tests). The global singleton
/// `testcontainersConfig` is the authoritative source used throughout the library.
public class TestcontainersConfiguration {

    /// Creates a configuration object by reading from environment variables
    /// and `~/.testcontainers.properties`.
    public init() {
        let env = ProcessInfo.processInfo.environment
        let props = readTcProperties()
        self.tcProperties = props

        self.maxTries = {
            let raw = env["TC_MAX_TRIES"] ?? "120"
            return Int(raw) ?? 120
        }()
        self.sleepTime = {
            let raw = env["TC_POOLING_INTERVAL"] ?? "1"
            return Double(raw) ?? 1.0
        }()
        self.ryukImage = env["RYUK_CONTAINER_IMAGE"] ?? "testcontainers/ryuk:0.8.1"
        self.ryukReconnectionTimeout = env["RYUK_RECONNECTION_TIMEOUT"] ?? "10s"
        self.tcHostOverride = env["TC_HOST"] ?? env["TESTCONTAINERS_HOST_OVERRIDE"]
        self.connectionModeOverride = try? overriddenConnectionMode()
        self.hubImageNamePrefix = env["TESTCONTAINERS_HUB_IMAGE_NAME_PREFIX"] ?? ""
        self.dockerAuthConfig = env["DOCKER_AUTH_CONFIG"]
    }

    /// Maximum number of polling attempts before a wait strategy gives up.
    /// Controlled by `TC_MAX_TRIES`. Default: `120`.
    public let maxTries: Int

    /// Sleep duration in seconds between wait-strategy poll attempts.
    /// Controlled by `TC_POOLING_INTERVAL`. Default: `1.0`.
    public let sleepTime: Double

    /// Docker image used to run the Ryuk resource-reaper container.
    /// Controlled by `RYUK_CONTAINER_IMAGE`. Default: `"testcontainers/ryuk:0.8.1"`.
    public let ryukImage: String

    /// Timeout string passed to Ryuk via the `RYUK_RECONNECTION_TIMEOUT`
    /// environment variable inside the Ryuk container.
    /// Controlled by `RYUK_RECONNECTION_TIMEOUT`. Default: `"10s"`.
    public let ryukReconnectionTimeout: String

    /// Overrides the host address returned by `DockerClient.host()`.
    /// Controlled by `TC_HOST` or `TESTCONTAINERS_HOST_OVERRIDE`. `nil` = no override.
    public let tcHostOverride: String?

    /// Overrides the automatic connection-mode detection.
    /// `nil` means auto-detection is used.
    public let connectionModeOverride: ConnectionMode?

    /// Optional prefix prepended to every image name.
    /// Controlled by `TESTCONTAINERS_HUB_IMAGE_NAME_PREFIX`. Default: `""`.
    public let hubImageNamePrefix: String

    /// Properties loaded from `~/.testcontainers.properties`.
    /// Mutable so tests can inject properties without touching the filesystem.
    public var tcProperties: [String: String]

    /// Raw JSON string from `DOCKER_AUTH_CONFIG`, or `nil`.
    public var dockerAuthConfig: String?

    /// The effective startup timeout in seconds: `maxTries × sleepTime`.
    public var timeout: Double { Double(maxTries) * sleepTime }

    // MARK: Lazily resolved flags

    private var _ryukPrivileged: Bool?
    private var _ryukDisabled: Bool?
    private var _ryukDockerSocket: String?

    private func resolveFlag(envName: String, propName: String) -> Bool {
        if let envVal = ProcessInfo.processInfo.environment[envName] {
            return enableFlags.contains(envVal.lowercased())
        }
        if let propVal = tcProperties[propName] {
            return enableFlags.contains(propVal.lowercased())
        }
        return false
    }

    /// Whether the Ryuk container should run with Docker `--privileged` mode.
    /// Controlled by `TESTCONTAINERS_RYUK_PRIVILEGED` or `ryuk.container.privileged`.
    /// Default: `false`.
    public var ryukPrivileged: Bool {
        get { _ryukPrivileged ?? resolveFlag(envName: "TESTCONTAINERS_RYUK_PRIVILEGED", propName: "ryuk.container.privileged") }
        set { _ryukPrivileged = newValue }
    }

    /// Whether the Ryuk resource-reaper is disabled.
    /// Controlled by `TESTCONTAINERS_RYUK_DISABLED` or `ryuk.disabled`. Default: `false`.
    public var ryukDisabled: Bool {
        get { _ryukDisabled ?? resolveFlag(envName: "TESTCONTAINERS_RYUK_DISABLED", propName: "ryuk.disabled") }
        set { _ryukDisabled = newValue }
    }

    /// The Docker socket path used by the Ryuk reaper container.
    /// Defaults to `dockerSocket()` on first access.
    public var ryukDockerSocket: String {
        get { _ryukDockerSocket ?? dockerSocket() }
        set { _ryukDockerSocket = newValue }
    }

    /// Returns the `tc.host` value from `~/.testcontainers.properties`, or `nil`.
    public var tcHost: String? { tcProperties["tc.host"] }
}

/// The process-wide testcontainers configuration singleton.
///
/// Constructed once at module initialisation. All library internals read their
/// defaults from this object. You can mutate individual fields to influence
/// behaviour without restarting the process.
public let testcontainersConfig = TestcontainersConfiguration()
