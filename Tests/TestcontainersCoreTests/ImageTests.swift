import Foundation
import Testing

@testable import TestcontainersCore

@Suite("DockerImage")
struct ImageTests {
    @Test func pathIsStoredCorrectly() {
        let image = DockerImage(path: "/my/context")
        #expect(image.path == "/my/context")
    }

    @Test func defaultTagIsNil() {
        let image = DockerImage(path: "/some/path")
        #expect(image.tag == nil)
    }

    @Test func customTagIsStored() {
        let image = DockerImage(path: "/my/context", tag: "myapp:test")
        #expect(image.tag == "myapp:test")
    }

    @Test func defaultCleanUpIsTrue() {
        let image = DockerImage(path: "/some/path")
        #expect(image.cleanUp == true)
    }

    @Test func cleanUpFalseIsRespected() {
        let image = DockerImage(path: "/some/path", cleanUp: false)
        #expect(image.cleanUp == false)
    }

    @Test func defaultDockerfilePathIsNil() {
        let image = DockerImage(path: "/some/path")
        #expect(image.dockerfilePath == nil)
    }

    @Test func customDockerfilePathIsStored() {
        let image = DockerImage(path: "/ctx", dockerfilePath: "Dockerfile.prod")
        #expect(image.dockerfilePath == "Dockerfile.prod")
    }

    @Test func defaultNoCacheIsFalse() {
        let image = DockerImage(path: "/some/path")
        #expect(image.noCache == false)
    }

    @Test func noCacheTrueIsRespected() {
        let image = DockerImage(path: "/some/path", noCache: true)
        #expect(image.noCache == true)
    }

    @Test func shortIdIsEmptyBeforeBuild() {
        let image = DockerImage(path: "/some/path")
        #expect(image.shortId.isEmpty)
    }

    @Test func logsIsEmptyBeforeBuild() {
        let image = DockerImage(path: "/some/path")
        #expect(image.logs.isEmpty)
    }

    @Test func removeBeforeBuildIsNoOp() async throws {
        // cleanUp defaults to true but imageId is nil — guard let exits cleanly
        let image = DockerImage(path: "/some/path")
        try await image.remove()
    }

    @Test func removeWithCleanUpFalseIsNoOp() async throws {
        let image = DockerImage(path: "/some/path", cleanUp: false)
        try await image.remove()
    }

    // MARK: - shortId logic (white-box)

    @Test func shortIdStripsShA256Prefix() {
        // The logic: strip "sha256:", take first 12 chars
        let fullId = "sha256:abcdef1234567890abcdef"
        let stripped = fullId.hasPrefix("sha256:") ? String(fullId.dropFirst(7)) : fullId
        let shortId = stripped.count > 12 ? String(stripped.prefix(12)) : stripped
        #expect(shortId == "abcdef123456")
    }

    @Test func shortIdWithoutPrefixTruncatesTo12() {
        let fullId = "abcdef1234567890"
        let stripped = fullId.hasPrefix("sha256:") ? String(fullId.dropFirst(7)) : fullId
        let shortId = stripped.count > 12 ? String(stripped.prefix(12)) : stripped
        #expect(shortId == "abcdef123456")
    }

    @Test func shortIdWithExactly12CharsIsUnchanged() {
        let fullId = "123456789012"
        let stripped = fullId.hasPrefix("sha256:") ? String(fullId.dropFirst(7)) : fullId
        let shortId = stripped.count > 12 ? String(stripped.prefix(12)) : stripped
        #expect(shortId == "123456789012")
    }

    @Test func shortIdWithFewerThan12CharsIsUnchanged() {
        let fullId = "abc"
        let stripped = fullId.hasPrefix("sha256:") ? String(fullId.dropFirst(7)) : fullId
        let shortId = stripped.count > 12 ? String(stripped.prefix(12)) : stripped
        #expect(shortId == "abc")
    }
}
