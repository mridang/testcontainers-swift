/// Custom Docker image builder.
///
/// `DockerImage` builds a Docker image from a local build context (a directory
/// containing a `Dockerfile`) and optionally removes the image after use. The
/// static `use(_:_:)` helper combines build and remove with a try/finally guarantee.
import Foundation

/// A Docker image built from a local context directory.
///
/// Use `build()` to trigger the Docker daemon to build the image from `path`.
/// The resulting image can then be referenced by `DockerContainer` using its
/// `tag` or `shortId`.
///
/// Example:
/// ```swift
/// try await DockerImage.use(
///     DockerImage(path: "./my-service", tag: "my-service:test")
/// ) { image in
///     let container = DockerContainer(image.tag!)
///     try await DockerContainer.use(container) { c in
///         // run tests against c
///     }
/// }
/// ```
public class DockerImage {
    /// The path to the Docker build context directory.
    public let path: String

    /// Optional image tag applied to the built image (e.g. `"myapp:test"`).
    public let tag: String?

    /// Whether to remove the image after `use()` completes. Defaults to `true`.
    public let cleanUp: Bool

    /// Optional path to the Dockerfile relative to `path`.
    public let dockerfilePath: String?

    /// Whether to disable the Docker build cache (`--no-cache`). Defaults to `false`.
    public let noCache: Bool

    private let dockerClient: DockerClient
    private var imageId: String?
    private var buildLogs: [[String: Any]] = []

    /// Creates a `DockerImage` from the given parameters.
    public init(
        path: String,
        tag: String? = nil,
        cleanUp: Bool = true,
        dockerfilePath: String? = nil,
        noCache: Bool = false,
        dockerClient: DockerClient? = nil
    ) {
        self.path = path
        self.tag = tag
        self.cleanUp = cleanUp
        self.dockerfilePath = dockerfilePath
        self.noCache = noCache
        self.dockerClient = dockerClient ?? DockerClient()
    }

    /// Returns the first 12 characters of the image ID (the "short" form).
    ///
    /// The `sha256:` prefix is stripped before truncating. Returns an empty
    /// string before `build()` is called.
    public var shortId: String {
        let id = imageId ?? ""
        let stripped = id.hasPrefix("sha256:") ? String(id.dropFirst(7)) : id
        return stripped.count > 12 ? String(stripped.prefix(12)) : stripped
    }

    /// Builds the Docker image and returns `self`.
    ///
    /// Sends the contents of `path` as a tar archive to the Docker daemon's
    /// `POST /build` endpoint. The resulting image ID is stored in `shortId`.
    @discardableResult
    public func build() async throws -> DockerImage {
        let (id, logs) = try await dockerClient.buildImage(
            contextPath: path,
            tag: tag,
            noCache: noCache,
            dockerfile: dockerfilePath
        )
        imageId = id
        buildLogs = logs
        return self
    }

    /// Removes the image from the local Docker image cache.
    ///
    /// Has no effect if `cleanUp` is `false` or if `build()` was never called.
    public func remove(force: Bool = true, noPrune: Bool = false) async throws {
        guard let id = imageId, cleanUp else { return }
        try await dockerClient.removeImage(id, force: force, noPrune: noPrune)
    }

    /// The build log as a list of JSON log objects.
    ///
    /// Each element is a dictionary decoded from one line of the streaming build
    /// response. Empty before `build()` is called.
    public var logs: [[String: Any]] { buildLogs }

    /// Builds `image`, runs `fn` with it, and removes it afterwards.
    ///
    /// The image is removed even if `fn` throws.
    public static func use<T>(
        _ image: DockerImage,
        _ fn: (DockerImage) async throws -> T
    ) async throws -> T {
        try await image.build()
        do {
            let result = try await fn(image)
            try await image.remove()
            return result
        } catch {
            try? await image.remove()
            throw error
        }
    }
}
