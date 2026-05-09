/// Docker container lifecycle and the Ryuk resource-reaper.
///
/// `DockerContainer` is the primary public API for managing a single container.
/// It uses a fluent builder API for configuration, and exposes `start()`, `stop()`,
/// and the static `use(_:_:)` helper for lifecycle management.
///
/// `Reaper` is the singleton that manages the Ryuk side-car container, which
/// is responsible for cleaning up orphaned testcontainers resources after the
/// test process exits.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A Docker container managed by testcontainers-swift.
///
/// Instantiate with an image name and chain builder methods to configure it,
/// then call `start()` to create and start the container. Use `use(_:_:)` for
/// automatic start + stop with a try/finally guarantee.
///
/// Example:
/// ```swift
/// try await DockerContainer.use(
///     DockerContainer("redis:7")
///         .withExposedPorts(6379)
///         .waitingFor(PortWaitStrategy(6379))
/// ) { container in
///     let port = try await container.exposedPort(6379)
///     // run tests
/// }
/// ```
public class DockerContainer: WaitStrategyTarget {

    // MARK: - Public properties

    /// The Docker image name used to create the container.
    public let image: String

    private var _env: [String: String] = [:]
    private var _ports: [Int: Int?] = [:]
    private var _volumes: [String: MountConfig] = [:]
    private var _tmpfs: [String: String] = [:]
    private var _command: Any? // String or [String]
    private var _name: String?
    private var _network: Network?
    private var _networkAliases: [String]?
    private var _kwargs: [String: Any] = [:]
    private var _waitStrategy: WaitStrategy?
    private var _transferableSpecs: [TransferSpec] = []
    private let dockerClient: DockerClient

    private var containerId: String?
    private var cachedContainerInfo: ContainerInspectInfo?
    private var cachedStatus: String = "not_started"

    /// Environment variables injected into the container.
    public var env: [String: String] { _env }

    /// Port map: container port → optional host port.
    public var ports: [Int: Int?] { _ports }

    /// Volume bind mounts.
    public var volumes: [String: MountConfig] { _volumes }

    /// Tmpfs mounts: container path → size string.
    public var tmpfs: [String: String] { _tmpfs }

    /// The command override, or `nil` when using the image default.
    public var command: Any? { _command }

    /// The container name, or `nil` when none was set.
    public var name: String? { _name }

    /// The `Network` the container will be attached to, or `nil`.
    public var network: Network? { _network }

    /// DNS aliases on `network`, or `nil`.
    public var networkAliases: [String]? { _networkAliases }

    /// Extra Docker `HostConfig` fields.
    public var kwargs: [String: Any] { _kwargs }

    // MARK: - Init

    /// Creates a `DockerContainer` for `image`.
    ///
    /// The `TestcontainersConfiguration.hubImageNamePrefix` is prepended to
    /// `image` automatically.
    public init(_ image: String, dockerClient: DockerClient? = nil) {
        self.image = testcontainersConfig.hubImageNamePrefix + image
        self.dockerClient = dockerClient ?? DockerClient()
    }

    // MARK: - Builder methods

    /// Sets a single environment variable.
    @discardableResult
    public func withEnv(_ key: String, _ value: String) -> Self {
        _env[key] = value
        return self
    }

    /// Merges `variables` into the container's environment map.
    @discardableResult
    public func withEnvs(_ variables: [String: String]) -> Self {
        _env.merge(variables) { _, new in new }
        return self
    }

    /// Reads environment variables from a `.env`-style file and merges them.
    ///
    /// - Blank lines and lines starting with `#` are skipped.
    /// - Each line must contain `=`; the part before the first `=` is the key.
    /// - `${VAR}` references are expanded using variables already resolved
    ///   earlier in the same file.
    @discardableResult
    public func withEnvFile(_ path: String) -> Self {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return self
        }
        var resolved: [String: String] = [:]
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
            // Expand ${VAR} references using already-resolved variables
            let value = expandVars(rawValue, using: resolved)
            resolved[key] = value
            _env[key] = value
        }
        return self
    }

    /// Maps `containerPort` to an optional fixed `hostPort`.
    @discardableResult
    public func withBindPorts(_ containerPort: Int, _ hostPort: Int? = nil) -> Self {
        // Use updateValue to store nil values without removing the key
        _ports.updateValue(hostPort, forKey: containerPort)
        return self
    }

    /// Exposes each port with an ephemeral host port.
    @discardableResult
    public func withExposedPorts(_ ports: Int...) -> Self {
        for p in ports { _ports.updateValue(nil, forKey: p) }
        return self
    }

    /// Attaches the container to `network`.
    @discardableResult
    public func withNetwork(_ network: Network) -> Self {
        _network = network
        return self
    }

    /// Sets DNS aliases for the container on its network.
    @discardableResult
    public func withNetworkAliases(_ aliases: String...) -> Self {
        _networkAliases = aliases
        return self
    }

    /// Overrides the default command run by the container.
    @discardableResult
    public func withCommand(_ command: String) -> Self {
        _command = command
        return self
    }

    /// Overrides the default command with an explicit argument list.
    @discardableResult
    public func withCommand(_ command: [String]) -> Self {
        _command = command
        return self
    }

    /// Assigns a fixed name to the container.
    @discardableResult
    public func withName(_ name: String) -> Self {
        _name = name
        return self
    }

    /// Adds a volume bind mount.
    @discardableResult
    public func withVolumeMapping(_ host: String, _ container: String, _ mode: String) -> Self {
        _volumes[host] = MountConfig(hostPath: container, mode: mode)
        return self
    }

    /// Adds a tmpfs mount at `containerPath`.
    @discardableResult
    public func withTmpfsMount(_ containerPath: String, size: String? = nil) -> Self {
        _tmpfs[containerPath] = size ?? ""
        return self
    }

    /// Merges `kwargs` into the extra Docker `HostConfig` fields.
    @discardableResult
    public func withKwargs(_ kwargs: [String: Any]) -> Self {
        _kwargs.merge(kwargs) { _, new in new }
        return self
    }

    /// Attaches a `WaitStrategy` that `start()` will invoke after the container is running.
    @discardableResult
    public func waitingFor(_ strategy: WaitStrategy) -> Self {
        _waitStrategy = strategy
        return self
    }

    /// Schedules `transferable` to be copied into the container at `destination`
    /// with Unix permission `mode` when `start()` is called.
    @discardableResult
    public func withCopyIntoContainer(
        _ transferable: Transferable,
        _ destination: String,
        _ mode: Int = kDefaultTransferMode
    ) -> Self {
        _transferableSpecs.append((data: transferable, destination: destination, mode: mode))
        return self
    }

    /// Conditionally adds `platform: 'linux/amd64'` emulation when running on ARM64.
    @discardableResult
    public func maybeEmulateAmd64() -> Self {
        if isArm() && _kwargs["platform"] == nil {
            return withKwargs(["platform": "linux/amd64"])
        }
        return self
    }

    // MARK: - Lifecycle

    /// Creates and starts the container, then runs the wait strategy.
    ///
    /// Steps:
    /// 1. Ensures `Reaper` is running (unless Ryuk is disabled).
    /// 2. Creates the container via `DockerClient.createContainer`.
    /// 3. Copies any scheduled transferables into the container.
    /// 4. Starts the container.
    /// 5. Runs the wait strategy if one was set.
    @discardableResult
    public func start() async throws -> DockerContainer {
        let isRyuk = image == testcontainersConfig.hubImageNamePrefix + testcontainersConfig.ryukImage
        if !testcontainersConfig.ryukDisabled && !isRyuk {
            _ = try await Reaper.getInstance()
        }

        let cmdArray: [String]?
        switch _command {
        case nil:
            cmdArray = nil
        case let list as [String]:
            cmdArray = list
        case let str as String:
            cmdArray = Self.splitCommand(str)
        default:
            throw ContainerStartException("command must be a String or [String]")
        }

        let newId = try await dockerClient.createContainer(
            image: image,
            command: cmdArray,
            env: _env,
            name: _name,
            ports: _ports,
            volumes: _volumes,
            network: _network?.name,
            networkAliases: _networkAliases ?? [],
            labels: (try? createLabels(image: image)) ?? [:],
            kwargs: _kwargs
        )
        containerId = newId

        for spec in _transferableSpecs {
            try await transferIntoContainer(spec.data, spec.destination, spec.mode)
        }

        try await dockerClient.startContainer(newId)
        cachedStatus = "running"

        try await _waitStrategy?.waitUntilReady(target: self)

        return self
    }

    /// Removes the container.
    ///
    /// - Parameters:
    ///   - force: Send SIGKILL if still running. Default: `true`.
    ///   - deleteVolume: Remove anonymous volumes. Default: `true`.
    public func stop(force: Bool = true, deleteVolume: Bool = true) async throws {
        guard let id = containerId else { return }
        try await dockerClient.removeContainer(id, force: force, removeVolumes: deleteVolume)
    }

    // MARK: - WaitStrategyTarget conformance

    public func containerHostIp() -> String {
        guard containerId != nil else { return "localhost" }
        return dockerClient.host()
    }

    public func exposedPort(_ port: Int) async throws -> Int {
        try await ContainerStatusWaitStrategy().waitUntilReady(target: self)
        if dockerClient.connectionMode().useMappedPort {
            guard let id = containerId else {
                throw ContainerStartException("Container must be started first.")
            }
            return try await dockerClient.port(containerId: id, port: port)
        }
        return port
    }

    public func logs() throws -> (stdout: Data, stderr: Data) {
        guard let id = containerId else {
            throw ContainerStartException("Container must be started first.")
        }
        // logs() is sync in the protocol but we need async — use semaphore
        let sema = DispatchSemaphore(value: 0)
        var result: (Data, Data) = (Data(), Data())
        var thrownError: Error?
        Task {
            do {
                result = try await dockerClient.getLogs(id)
            } catch {
                thrownError = error
            }
            sema.signal()
        }
        sema.wait()
        if let e = thrownError { throw e }
        return (stdout: result.0, stderr: result.1)
    }

    public func exec(_ command: [String]) async throws -> (exitCode: Int, output: Data) {
        guard let id = containerId else {
            throw ContainerStartException("Container must be started first.")
        }
        return try await dockerClient.execInContainer(id, command: command)
    }

    public func reload() {
        guard let id = containerId else { return }
        Task {
            do {
                let details = try await dockerClient.getContainerDetails(id)
                if let state = details["State"] as? [String: Any],
                   let s = state["Status"] as? String {
                    cachedStatus = s
                }
                cachedContainerInfo = nil
            } catch {
                cachedStatus = "unknown"
            }
        }
    }

    public var status: String { cachedStatus }

    // MARK: - Extra API

    /// Returns the underlying `DockerClient` instance.
    public var dockerClientInstance: DockerClient { dockerClient }

    /// Returns detailed inspect information for this container.
    public func containerInfo() async throws -> ContainerInspectInfo? {
        if let cached = cachedContainerInfo { return cached }
        guard let id = containerId else { return nil }
        do {
            let info = try await dockerClient.getContainerInspectInfo(id)
            cachedContainerInfo = info
            return info
        } catch {
            return nil
        }
    }

    /// Copies `transferable` into the running container immediately.
    public func copyIntoContainer(
        _ transferable: Transferable,
        _ destination: String,
        _ mode: Int = kDefaultTransferMode
    ) async throws {
        try await transferIntoContainer(transferable, destination, mode)
    }

    // MARK: - Private helpers

    private func transferIntoContainer(
        _ transferable: Transferable,
        _ destination: String,
        _ mode: Int
    ) async throws {
        guard let id = containerId else {
            throw ContainerStartException("Container must be started first.")
        }
        let tarData = try buildTransferTar(transferable, destination: destination, mode: mode)
        try await dockerClient.putArchive(id, path: "/", tarData: tarData)
    }

    /// Splits a shell command string into tokens, respecting single and double quotes.
    public static func splitCommand(_ command: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        for ch in command {
            if inSingle {
                if ch == "'" { inSingle = false } else { current.append(ch) }
            } else if inDouble {
                if ch == "\"" { inDouble = false } else { current.append(ch) }
            } else if ch == "'" {
                inSingle = true
            } else if ch == "\"" {
                inDouble = true
            } else if ch == " " || ch == "\t" {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - use()

    /// Starts `container`, runs `fn` with it, and stops it afterwards.
    ///
    /// The container is stopped even if `fn` throws.
    public static func use<T>(
        _ container: DockerContainer,
        _ fn: (DockerContainer) async throws -> T
    ) async throws -> T {
        try await container.start()
        do {
            let result = try await fn(container)
            try await container.stop()
            return result
        } catch {
            try? await container.stop()
            throw error
        }
    }
}

// MARK: - Expand ${VAR} helper

private func expandVars(_ value: String, using resolved: [String: String]) -> String {
    var result = value
    // Match ${VAR} patterns
    let pattern = try? NSRegularExpression(pattern: #"\$\{([^}]+)\}"#)
    guard let regex = pattern else { return value }
    let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
    // Process in reverse order to preserve offsets
    for match in matches.reversed() {
        let fullRange = match.range(at: 0)
        let varRange = match.range(at: 1)
        if let varName = Range(varRange, in: value).map({ String(value[$0]) }) {
            let replacement = resolved[varName] ?? ""
            if let swiftRange = Range(fullRange, in: result) {
                result = result.replacingCharacters(in: swiftRange, with: replacement)
            }
        }
    }
    return result
}

// MARK: - Reaper

/// Singleton that manages the Ryuk resource-reaper side-car container.
///
/// Ryuk is a small Docker helper that listens on a TCP socket and removes all
/// Docker resources labelled with the current session ID when the TCP
/// connection is dropped. This ensures containers don't accumulate even when
/// the test process crashes.
public final actor Reaper {
    private static var _instance: Reaper?
    private static var _initTask: Task<Reaper, Error>?

    private var reaperSocket: FileHandle?

    /// Returns the singleton `Reaper`, creating it if necessary.
    public static func getInstance() async throws -> Reaper {
        if let existing = _instance { return existing }

        if let task = _initTask {
            return try await task.value
        }

        let task = Task<Reaper, Error> {
            let reaper = try await createInstance()
            _instance = reaper
            return reaper
        }
        _initTask = task
        return try await task.value
    }

    /// Resets the singleton (used in test teardown).
    public static func deleteInstance() async {
        _initTask = nil
        if let instance = _instance {
            await instance.closeSocket()
        }
        _instance = nil
    }

    private func closeSocket() {
        reaperSocket?.closeFile()
        reaperSocket = nil
    }

    private static func createInstance() async throws -> Reaper {
        let cfg = testcontainersConfig
        let ryukContainer = DockerContainer(cfg.ryukImage)
            .withName("testcontainers-ryuk-\(sessionId)")
            .withExposedPorts(8080)
            .withVolumeMapping(cfg.ryukDockerSocket, "/var/run/docker.sock", "rw")
            .withKwargs(["privileged": cfg.ryukPrivileged, "autoRemove": true])
            .withEnv("RYUK_RECONNECTION_TIMEOUT", cfg.ryukReconnectionTimeout)
            .waitingFor(
                LogMessageWaitStrategy(".* Started!")
                    .withStartupTimeout(.seconds(20))
            )

        try await ryukContainer.start()

        let containerHost = ryukContainer.containerHostIp()
        let containerPort = try await ryukContainer.exposedPort(8080)

        if containerHost.isEmpty || containerPort == 0 {
            throw ContainerConnectException(
                "Could not obtain network details for ryuk container. "
                    + "Host: \(containerHost) Port: \(containerPort)"
            )
        }

        // Connect TCP socket with retries
        var lastError: Error?
        var socketFd: Int32 = -1
        for _ in 0..<50 {
            do {
                socketFd = try connectTCP(host: containerHost, port: containerPort)
                lastError = nil
                break
            } catch {
                lastError = error
                try? await Task.sleep(for: .milliseconds(500))
            }
        }

        if let error = lastError {
            throw ContainerConnectException("Failed to connect to Ryuk: \(error)")
        }

        guard socketFd >= 0 else {
            throw ContainerConnectException("Failed to connect to Ryuk: invalid socket")
        }

        // Send session-ID label registration message
        let msg = "label=\(labelSessionId)=\(sessionId)\r\n"
        let msgData = Data(msg.utf8)
        msgData.withUnsafeBytes { ptr in
            _ = Foundation.write(socketFd, ptr.baseAddress!, msgData.count)
        }

        let fh = FileHandle(fileDescriptor: socketFd, closeOnDealloc: false)
        let reaper = Reaper()
        await reaper.storeSocket(fh)
        return reaper
    }

    private func storeSocket(_ fh: FileHandle) {
        reaperSocket = fh
    }
}

// MARK: - TCP connect helper

private func connectTCP(host: String, port: Int) throws -> Int32 {
    var hints = addrinfo()
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    var res: UnsafeMutablePointer<addrinfo>?
    defer { if res != nil { freeaddrinfo(res) } }

    let rc = getaddrinfo(host, "\(port)", &hints, &res)
    guard rc == 0, let info = res else {
        throw ContainerConnectException("getaddrinfo failed for \(host):\(port)")
    }

    let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
    guard fd >= 0 else {
        throw ContainerConnectException("socket() failed")
    }

    // Set 1-second connect timeout via SO_SNDTIMEO
    var tv = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    let connRc = Foundation.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
    if connRc != 0 {
        Foundation.close(fd)
        throw ContainerConnectException("connect() failed")
    }
    return fd
}
