import Foundation
import Testing

@testable import TestcontainersCore

@Suite("parseDockerAuthConfig")
struct AuthTests {
    @Test func parsesValidAuthsSection() throws {
        let creds = "myuser:mypassword"
        let encoded = Data(creds.utf8).base64EncodedString()
        let config = """
            {"auths":{"https://index.docker.io/v1/":{"auth":"\(encoded)"}}}
            """
        let result = try parseDockerAuthConfig(config)
        let r = try #require(result)
        #expect(r.count == 1)
        #expect(r[0].registry == "https://index.docker.io/v1/")
        #expect(r[0].username == "myuser")
        #expect(r[0].password == "mypassword")
    }

    @Test func returnsNilWhenNoAuthsSection() throws {
        let config = """
            {"credHelpers":{"amazonaws.com":"ecr-login"}}
            """
        let result = try parseDockerAuthConfig(config)
        #expect(result == nil)
    }

    @Test func returnsNilWhenOnlyCredsStore() throws {
        let config = """
            {"credsStore":"ecr-login"}
            """
        let result = try parseDockerAuthConfig(config)
        #expect(result == nil)
    }

    @Test func parsesMultipleAuths() throws {
        let auth1 = Data("user1:pass1".utf8).base64EncodedString()
        let auth2 = Data("user_new:pass_new".utf8).base64EncodedString()
        let auth3 = Data("abc:123".utf8).base64EncodedString()
        let config = """
            {"auths":{"localhost:5000":{"auth":"\(auth1)"},"https://example.com":{"auth":"\(auth2)"},"example2.com":{"auth":"\(auth3)"}}}
            """
        let result = try parseDockerAuthConfig(config)
        let r = try #require(result)
        #expect(r.count == 3)
    }

    @Test func returnsNilForUnknownTopLevelKey() throws {
        let config = """
            {"key":"value"}
            """
        let result = try parseDockerAuthConfig(config)
        #expect(result == nil)
    }

    @Test func throwsOnInvalidJson() {
        #expect(throws: (any Error).self) {
            _ = try parseDockerAuthConfig("not json")
        }
    }

    @Test func mixedConfigReturnsOnlyAuthsEntries() throws {
        let auth1 = Data("user1:pass1".utf8).base64EncodedString()
        let config = """
            {"auths":{"localhost:5000":{"auth":"\(auth1)"}},"credHelpers":{"amazonaws.com":"ecr-login"},"credsStore":"ecr-login"}
            """
        let result = try parseDockerAuthConfig(config)
        let r = try #require(result)
        #expect(r.count == 1)
        #expect(r[0].registry == "localhost:5000")
    }

    @Test func skipsEntryWithNoColonInCredentials() throws {
        let badAuth = Data("nocolon".utf8).base64EncodedString()
        let config = """
            {"auths":{"https://bad.example.com":{"auth":"\(badAuth)"}}}
            """
        let result = try parseDockerAuthConfig(config)
        let r = try #require(result)
        #expect(r.isEmpty)
    }

    @Test func skipsMalformedEntryButKeepsValidSibling() throws {
        let badAuth = Data("nocolon".utf8).base64EncodedString()
        let goodAuth = Data("user:pass".utf8).base64EncodedString()
        let config = """
            {"auths":{"bad.example.com":{"auth":"\(badAuth)"},"good.example.com":{"auth":"\(goodAuth)"}}}
            """
        let result = try parseDockerAuthConfig(config)
        let r = try #require(result)
        #expect(r.count == 1)
        #expect(r[0].registry == "good.example.com")
        #expect(r[0].username == "user")
    }

    @Test func returnsEmptyListForEmptyAuthsMap() throws {
        let config = """
            {"auths":{}}
            """
        let result = try parseDockerAuthConfig(config)
        let r = try #require(result)
        #expect(r.isEmpty)
    }

    @Test func passwordMayContainColons() throws {
        let auth = Data("user:pass:with:colons".utf8).base64EncodedString()
        let config = """
            {"auths":{"registry.example.com":{"auth":"\(auth)"}}}
            """
        let result = try parseDockerAuthConfig(config)
        let r = try #require(result)
        #expect(r[0].username == "user")
        #expect(r[0].password == "pass:with:colons")
    }

    @Test func dockerAuthInfoHasCorrectFields() {
        let info = DockerAuthInfo(registry: "reg", username: "user", password: "pass")
        #expect(info.registry == "reg")
        #expect(info.username == "user")
        #expect(info.password == "pass")
    }

    @Test func throwsWhenAuthsValueIsArray() {
        // Structurally invalid: "auths" is a JSON array instead of an object map.
        let config = #"{"auths":["not","a","map"]}"#
        #expect(throws: (any Error).self) {
            _ = try parseDockerAuthConfig(config)
        }
    }
}
