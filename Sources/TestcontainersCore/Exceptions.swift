/// Exception types thrown by testcontainers-swift.
///
/// All error types conform to `Error` and carry a human-readable `message`
/// string. They are thrown from `DockerContainer` and `DockerCompose` lifecycle
/// methods when something goes wrong with a container's lifecycle or networking.

/// Thrown when a container cannot be started.
///
/// This typically indicates a problem at the `docker run` / `POST
/// /containers/{id}/start` level — for example an invalid image name, an
/// image that cannot be pulled, a port that is already bound, or insufficient
/// Docker daemon permissions.
public struct ContainerStartException: Error, CustomStringConvertible {
    /// Human-readable description of why the container could not be started.
    public let message: String

    /// Creates a `ContainerStartException` with the given `message`.
    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "ContainerStartException: \(message)" }
    public var localizedDescription: String { description }
}

/// Thrown when a running container cannot be reached over the network.
///
/// Raised when the host IP address or mapped port of a container cannot be
/// determined, or when the Reaper (ryuk) TCP handshake fails after all
/// retry attempts are exhausted.
public struct ContainerConnectException: Error, CustomStringConvertible {
    /// Human-readable description of why the connection could not be established.
    public let message: String

    /// Creates a `ContainerConnectException` with the given `message`.
    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "ContainerConnectException: \(message)" }
    public var localizedDescription: String { description }
}

/// Thrown when an operation requires a running container but the container is
/// not (or is no longer) in the `running` state.
///
/// Common triggers include calling `DockerCompose.container` when the
/// requested service has exited, or calling `DockerCompose.container`
/// without a service name when there is not exactly one running container.
public struct ContainerIsNotRunning: Error, CustomStringConvertible {
    /// Human-readable description of which container is not running and why.
    public let message: String

    /// Creates a `ContainerIsNotRunning` with the given `message`.
    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "ContainerIsNotRunning: \(message)" }
    public var localizedDescription: String { description }
}

/// Thrown when a requested port is not exposed by the container.
///
/// Raised by `ComposeContainer.publisher` when no matching publisher can be
/// found for the requested port, host, or IP-version combination.
public struct NoSuchPortExposed: Error, CustomStringConvertible {
    /// Human-readable description of which port was not found and on which service.
    public let message: String

    /// Creates a `NoSuchPortExposed` with the given `message`.
    public init(_ message: String) {
        self.message = message
    }

    public var description: String { "NoSuchPortExposed: \(message)" }
    public var localizedDescription: String { description }
}
