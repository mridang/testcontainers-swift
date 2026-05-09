/// Wait-strategy infrastructure for testcontainers-swift.
///
/// `WaitStrategyTarget` is the protocol that any container type must conform to
/// for wait strategies to work. `WaitStrategy` is the open base class that
/// concrete strategies subclass.
import Foundation

/// Internal sentinel thrown by `ContainerStatusWaitStrategy` to break the poll loop.
public struct StopPollingError: Error {}

/// Throws `StopPollingError` to signal that the poll loop should stop immediately
/// without waiting for the timeout.
///
/// Used by `ContainerStatusWaitStrategy` when the container enters an
/// unexpected state (e.g. `"exited"` or `"dead"`) from which it cannot recover.
public func throwStopIteration() throws -> Never {
    throw StopPollingError()
}

/// Statuses that mean the container has not yet finished starting.
public let notExitedStatuses: Set<String> = ["running", "created"]

/// The interface that containers must implement for wait strategies.
///
/// Both `DockerContainer` and `ComposeContainer` conform to this protocol.
public protocol WaitStrategyTarget: AnyObject {
    /// Returns the host IP address used to reach this container.
    func containerHostIp() async throws -> String

    /// Returns the host port mapped to the given container port.
    func exposedPort(_ port: Int) async throws -> Int

    /// The underlying container object.
    ///
    /// For `DockerContainer` this is `self`. For `ComposeContainer` this is
    /// also `self`. Prefer calling typed methods on `WaitStrategyTarget`
    /// directly instead of casting this value.
    var wrappedContainer: AnyObject { get }

    /// Returns the raw stdout and stderr log bytes.
    func logs() async throws -> (stdout: Data, stderr: Data)

    /// Executes a command inside the container and returns the exit code and output.
    func exec(_ command: [String]) async throws -> (exitCode: Int, output: Data)

    /// Returns the full Docker inspect information for this container.
    ///
    /// The result is lazily loaded and cached by most implementations. Returns
    /// `nil` when the container has not yet been started or when the inspect
    /// call fails.
    func containerInfo() async throws -> ContainerInspectInfo?

    /// Reloads the container's state from the Docker daemon.
    ///
    /// Called by polling strategies between attempts to pick up status changes.
    func reload() async

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
    public var startupTimeout: Duration

    /// Time between successive polling attempts.
    /// Defaults to `testcontainersConfig.sleepTime` (1 s by default).
    public var pollInterval: Duration

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
    ///
    /// A transient exception causes the current poll attempt to be silently
    /// retried. `URLError` and `CancellationError` are always transient.
    @discardableResult
    public func withTransientExceptions(_ exceptions: [any Error.Type]) -> Self {
        transientExceptionTypes.append(contentsOf: exceptions)
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
                let isTransient =
                    allTransient.contains { type(of: error) == $0 }
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
