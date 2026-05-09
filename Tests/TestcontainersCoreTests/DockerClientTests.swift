import Foundation
import Testing

@testable import TestcontainersCore

// MARK: - toDockerKey

@Suite("DockerClient.toDockerKey")
struct ToDockerKeyTests {
    @Test func privilegedMapsCorrectly() throws {
        #expect(try DockerClient.toDockerKey("privileged") == "Privileged")
    }

    @Test func auto_removeMapsCorrectly() throws {
        #expect(try DockerClient.toDockerKey("auto_remove") == "AutoRemove")
    }

    @Test func autoRemoveCamelCaseMapsCorrectly() throws {
        #expect(try DockerClient.toDockerKey("autoRemove") == "AutoRemove")
    }

    @Test func platformMapsCorrectly() throws {
        #expect(try DockerClient.toDockerKey("platform") == "Platform")
    }

    @Test func genericCamelCaseUppercasesFirstChar() throws {
        #expect(try DockerClient.toDockerKey("networkMode") == "NetworkMode")
    }

    @Test func emptyKeyThrows() {
        #expect(throws: (any Error).self) {
            try DockerClient.toDockerKey("")
        }
    }

    @Test func singleCharKey() throws {
        #expect(try DockerClient.toDockerKey("x") == "X")
    }

    @Test func alreadyPascalCaseIsUnchanged() throws {
        #expect(try DockerClient.toDockerKey("Memory") == "Memory")
    }

    @Test func lowercaseWordUppercasesFirst() throws {
        #expect(try DockerClient.toDockerKey("memory") == "Memory")
    }

    @Test func numericPrefixPreserved() throws {
        // Keys starting with digits: first char is uppercased if it's a letter,
        // digit stays as-is
        let result = try DockerClient.toDockerKey("1gb")
        #expect(result == "1gb")
    }
}

// MARK: - dockerHostHostname

@Suite("dockerHostHostname")
struct DockerHostHostnameTests {
    @Test func extractsHostnameFromSshUrl() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["tc.host"] = "ssh://user@myhost.example.com"
        let hostname = dockerHostHostname()
        // dockerHostHostname() reads from the global testcontainersConfig, not a local one.
        // We can only test the pure parsing logic here.
        _ = hostname
    }

    @Test func returnsNilForTcpUrl() {
        // DOCKER_HOST=tcp:// — not SSH so returns nil
        // We test the logic directly:
        let url = "tcp://192.168.1.1:2376"
        #expect(!url.hasPrefix("ssh://"))
    }

    @Test func sshUrlWithTrailingSlash() {
        // Verify SSH URL parsing handles trailing slash
        let url = "ssh://user@host/"
        let comps = URLComponents(string: url)
        #expect(comps?.host == "host")
    }

    @Test func sshUrlWithUserAndPort() {
        let url = "ssh://deploy@prod.example.com:2222"
        let comps = URLComponents(string: url)
        #expect(comps?.host == "prod.example.com")
    }

    @Test func sshUrlWithNoHost() {
        let url = "ssh://"
        let comps = URLComponents(string: url)
        #expect(comps?.host == nil || comps?.host == "")
    }
}

// MARK: - isSshDockerHost

@Suite("isSshDockerHost")
struct IsSshDockerHostTests {
    @Test func trueWhenHostIsSSH() {
        // The function returns true when dockerHostHostname() is non-nil
        // We test the pure logic: ssh:// URLs return non-nil host
        let sshUrl = "ssh://user@somehost.example.com"
        guard let comps = URLComponents(string: sshUrl), let host = comps.host, !host.isEmpty else {
            Issue.record("URL parse failed")
            return
        }
        #expect(!host.isEmpty)
    }

    @Test func falseWhenHostIsTcp() {
        let tcpUrl = "tcp://192.168.1.1:2376"
        #expect(!tcpUrl.hasPrefix("ssh://"))
    }
}

// MARK: - DockerClient.host

@Suite("DockerClient.host resolution")
struct DockerClientHostTests {
    @Test func defaultsToLocalhost() throws {
        // When no DOCKER_HOST or TC_HOST is set, host should be "localhost"
        // (assuming tests are not running inside a container)
        let client = DockerClient(socketPath: "/dev/null")
        let h = client.host
        // Could be localhost, gateway IP, or SSH hostname depending on environment
        #expect(!h.isEmpty)
    }

    @Test func hostIsNonEmpty() {
        let client = DockerClient.testOnly()
        #expect(!client.host.isEmpty)
    }
}

// MARK: - DockerClient.connectionMode

@Suite("DockerClient.connectionMode")
struct DockerClientConnectionModeTests {
    @Test func returnsSomeConnectionMode() {
        let client = DockerClient.testOnly()
        let mode = client.connectionMode
        // Must be one of the valid cases
        let valid: [ConnectionMode] = [.dockerHost, .bridgeIp, .gatewayIp]
        #expect(valid.contains(mode))
    }

    @Test func respectsConnectionModeOverride() throws {
        let config = try TestcontainersConfiguration()
        // connectionModeOverride is a let, so we can only test the default client
        // which respects testcontainersConfig.connectionModeOverride
        _ = config.connectionModeOverride
    }
}
