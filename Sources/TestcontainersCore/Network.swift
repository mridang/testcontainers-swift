/// Docker network lifecycle management.
///
/// `Network` creates and removes a user-defined Docker bridge network. Containers
/// can be placed on the same `Network` so they can communicate by service name
/// without publishing ports to the host.
import Foundation

/// A Docker user-defined network managed by testcontainers-swift.
///
/// Networks are created lazily via `create()` and removed via `remove()`. The
/// static `use(_:)` helper combines both operations with a try/finally guarantee,
/// matching the context-manager pattern used in testcontainers-python.
///
/// Example:
/// ```swift
/// try await Network.use { network in
///     let db = DockerContainer("postgres:16")
///         .withNetwork(network)
///         .withNetworkAliases("db")
///     // db is reachable from app containers at hostname 'db'
/// }
/// ```
public class Network {
    /// The unique name assigned to this network (random UUID).
    public let name: String

    /// The Docker-assigned network ID, or `nil` before `create()` is called.
    public private(set) var id: String?

    private let dockerClient: DockerClient

    /// Creates a `Network` with a randomly generated name.
    ///
    /// An optional `dockerClient` can be injected for testing; the default
    /// instance reads connection settings from the environment.
    public init(dockerClient: DockerClient? = nil) {
        self.name = UUID().uuidString.lowercased()
        self.dockerClient = dockerClient ?? DockerClient()
    }

    /// Creates the Docker network and returns `self`.
    ///
    /// Stores the Docker-assigned `id` for use in subsequent `connect()` and
    /// `remove()` calls.
    @discardableResult
    public func create() async throws -> Network {
        id = try await dockerClient.createNetwork(name)
        return self
    }

    /// Removes the Docker network.
    ///
    /// Safe to call even if `create()` was never called — does nothing in that case.
    public func remove() async throws {
        guard let networkId = id else { return }
        try await dockerClient.removeNetwork(networkId)
    }

    /// Attaches `containerId` to this network.
    ///
    /// Optional `networkAliases` are DNS names through which other containers
    /// on the same network can reach `containerId`.
    ///
    /// Throws a `StateError` if `create()` has not been called yet.
    public func connect(_ containerId: String, networkAliases: [String]? = nil) async throws {
        guard let networkId = id else {
            throw NetworkError.notCreated(
                "Network must be created before connecting a container. Call create() first."
            )
        }
        try await dockerClient.connectNetwork(networkId, containerId, aliases: networkAliases ?? [])
    }

    /// Creates a network, runs `fn` with it, and removes the network afterwards.
    ///
    /// The network is removed even if `fn` throws. This is the recommended way
    /// to use a `Network` in a test to ensure cleanup.
    public static func use<T>(_ fn: (Network) async throws -> T) async throws -> T {
        let network = Network()
        try await network.create()
        do {
            let result = try await fn(network)
            try await network.remove()
            return result
        } catch {
            try? await network.remove()
            throw error
        }
    }
}

/// Errors thrown by `Network`.
public enum NetworkError: Error, CustomStringConvertible {
    case notCreated(String)

    public var description: String {
        switch self {
        case .notCreated(let m): return m
        }
    }
}
