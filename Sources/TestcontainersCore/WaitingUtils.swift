/// Wait-strategy infrastructure for testcontainers-swift.
///
/// `WaitStrategyTarget` is the protocol that any container type must conform to
/// for wait strategies to work. `WaitStrategy` is the open base class that
/// concrete strategies subclass.
import Foundation

/// Statuses that mean the container has not yet finished starting.
public let notExitedStatuses: Set<String> = ["running", "created"]

/// Internal sentinel thrown by `ContainerStatusWaitStrategy` to break the poll loop.
struct StopPollingError: Error {}

/// The interface that containers must implement for wait strategies.
///
/// Both `DockerContainer` and `ComposeContainer` conform to this protocol.
public protocol WaitStrategyTarget: AnyObject {
    /// Returns the host IP address used to reach this container.
    func containerHostIp() -> String

    /// Returns the host port mapped to the given container port.
    func exposedPort(_ port: Int) async throws -> Int

    /// Returns the raw stdout and stderr log bytes.
    func logs() throws -> (stdout: Data, stderr: Data)

    /// Executes a command inside the container and returns the exit code and output.
    func exec(_ command: [String]) async throws -> (exitCode: Int, output: Data)

    /// Reloads the container's state from the Docker daemon.
    func reload()

    /// The container's current lifecycle status, e.g. `"running"`, `"exited"`.
    var status: String { get }
}

/// Base class for all wait strategies.
///
/// Subclass this and override `waitUntilReady(target:)`. The `poll(_:)` helper
/// implements the adaptive-sleep retry loop shared by all strategies.
open class WaitStrategy {
    /// Maximum time to wait for the container to become ready.
    /// Defaults to `testcontainersConfig.timeout` (120 s by default).
    public var startupTimeout: Duration = .seconds(120)

    /// Time between successive polling attempts.
    /// Defaults to `testcontainersConfig.sleepTime` (1 s by default).
    public var pollInterval: Duration = .seconds(1)

    /// Exception types treated as transient failures — silently retried.
    public var transientExceptionTypes: [any Error.Type] = []

    /// Initialises a strategy using the global config defaults.
    public init() {
        let cfg = testcontainersConfig
        startupTimeout = .seconds(Int(cfg.timeout))
        pollInterval = .milliseconds(Int(cfg.sleepTime * 1000))
    }

    /// Sets the maximum startup timeout.
    @discardableResult
    public func withStartupTimeout(_ timeout: Duration) -> Self {
        startupTimeout = timeout
        return self
    }

    /// Sets the poll interval between readiness checks.
    @discardableResult
    public func withPollInterval(_ interval: Duration) -> Self {
        pollInterval = interval
        return self
    }

    /// Adds exception types that should be silently retried during polling.
    @discardableResult
    public func withTransientException(_ type: any Error.Type) -> Self {
        transientExceptionTypes.append(type)
        return self
    }

    /// Override in subclasses to implement the readiness check.
    open func waitUntilReady(target: any WaitStrategyTarget) async throws {
        fatalError("Subclasses must implement waitUntilReady(target:)")
    }

    // MARK: - Core poll loop

    /// Polls `check` until it returns `true`, the deadline is reached, or a
    /// non-transient error is thrown.
    ///
    /// - Returns: `true` when `check` returned `true`, `false` on timeout.
    /// - Throws: `StopPollingError` if the check signals early termination;
    ///   rethrows any non-transient error from `check`.
    @discardableResult
    public func poll(
        _ check: () async throws -> Bool,
        transientExceptions extra: [any Error.Type] = []
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + startupTimeout
        let allTransient = transientExceptionTypes + extra

        while ContinuousClock.now < deadline {
            let checkStart = ContinuousClock.now
            do {
                if try await check() { return true }
            } catch is StopPollingError {
                return false
            } catch {
                let isTransient = allTransient.contains { type(of: error) == $0 }
                    || error is URLError
                    || error is CancellationError
                if !isTransient { throw error }
            }
            let elapsed = ContinuousClock.now - checkStart
            let remaining = pollInterval - elapsed
            if remaining > .zero {
                try await Task.sleep(for: remaining)
            }
        }
        return false
    }
}
