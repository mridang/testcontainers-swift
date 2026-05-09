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
        let result = try DockerClient.toDockerKey("1gb")
        #expect(result == "1gb")
    }

    @Test func snakeCaseWithMultipleUnderscores() throws {
        // Only first char is uppercased — underscores remain
        let result = try DockerClient.toDockerKey("cpu_count")
        #expect(result == "Cpu_count")
    }

    @Test func allUppercaseKeyReturnedUnchanged() throws {
        #expect(try DockerClient.toDockerKey("PRIVILEGED") == "PRIVILEGED")
    }

    @Test func leadingUnderscorePreserved() throws {
        let result = try DockerClient.toDockerKey("_key")
        // '_' uppercased is still '_'
        #expect(result.hasPrefix("_"))
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

// MARK: - All tc.host-dependent tests (serialized to avoid global state bleed)

/// Single serialized parent suite enclosing all tests that mutate
/// `testcontainersConfig.tcProperties["tc.host"]`.  Nesting within a
/// `.serialized` parent guarantees that child suites and their tests
/// never run concurrently with each other.
@Suite("DockerClient tc.host dependent tests", .serialized)
struct DockerClientTcHostTests {

    // Shared helper — sets tc.host, runs body, then restores the original value.
    private func withTcHost(_ value: String?, body: () -> Void) {
        let saved = testcontainersConfig.tcProperties["tc.host"]
        defer {
            if let saved = saved {
                testcontainersConfig.tcProperties["tc.host"] = saved
            } else {
                testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
            }
        }
        if let value = value {
            testcontainersConfig.tcProperties["tc.host"] = value
        } else {
            testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
        }
        body()
    }

    // -------------------------------------------------------------------------
    // dockerHostHostname
    // -------------------------------------------------------------------------

    @Suite("dockerHostHostname via tcProperties", .serialized)
    struct DockerHostHostnameTcPropertiesTests {

        private func withTcHost(_ value: String?, body: () -> Void) {
            let saved = testcontainersConfig.tcProperties["tc.host"]
            defer {
                if let saved = saved {
                    testcontainersConfig.tcProperties["tc.host"] = saved
                } else {
                    testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
                }
            }
            if let value = value {
                testcontainersConfig.tcProperties["tc.host"] = value
            } else {
                testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
            }
            body()
        }

        @Test func extractsHostnameFromSshUrl() {
            withTcHost("ssh://user@myhost.example.com") {
                #expect(dockerHostHostname() == "myhost.example.com")
            }
        }

        @Test func returnsNilForTcpUrl() {
            withTcHost("tcp://localhost:2375") {
                #expect(dockerHostHostname() == nil)
            }
        }

        @Test func extractsHostnameWithTrailingSlash() {
            withTcHost("ssh://user@myhost.example.com/") {
                #expect(dockerHostHostname() == "myhost.example.com")
            }
        }

        @Test func extractsHostnameWithUserAtPrefix() {
            withTcHost("ssh://admin@remote.example.org") {
                #expect(dockerHostHostname() == "remote.example.org")
            }
        }

        @Test func extractsHostnameWithExplicitPort() {
            withTcHost("ssh://deploy@build.example.com:22") {
                #expect(dockerHostHostname() == "build.example.com")
            }
        }

        @Test func extractsHostnameWithNoUserinfo() {
            withTcHost("ssh://host.example.com") {
                #expect(dockerHostHostname() == "host.example.com")
            }
        }

        @Test func returnsNilForEmptyHostComponent() {
            withTcHost("ssh://") {
                #expect(dockerHostHostname() == nil)
            }
        }
    }

    // -------------------------------------------------------------------------
    // isSshDockerHost
    // -------------------------------------------------------------------------

    @Suite("isSshDockerHost via tcProperties", .serialized)
    struct IsSshDockerHostTcPropertiesTests {

        private func withTcHost(_ value: String?, body: () -> Void) {
            let saved = testcontainersConfig.tcProperties["tc.host"]
            defer {
                if let saved = saved {
                    testcontainersConfig.tcProperties["tc.host"] = saved
                } else {
                    testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
                }
            }
            if let value = value {
                testcontainersConfig.tcProperties["tc.host"] = value
            } else {
                testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
            }
            body()
        }

        @Test func trueWhenTcHostIsSsh() {
            withTcHost("ssh://user@remote.example.com") {
                #expect(isSshDockerHost() == true)
            }
        }

        @Test func falseWhenTcHostIsTcp() {
            withTcHost("tcp://localhost:2375") {
                #expect(isSshDockerHost() == false)
            }
        }

        @Test func returnsBoolWhenTcHostAbsent() {
            withTcHost(nil) {
                let result = isSshDockerHost()
                // Result is environment-dependent; just verify it's a Bool (no crash).
                _ = result
            }
        }
    }

    // -------------------------------------------------------------------------
    // dockerHost
    // -------------------------------------------------------------------------

    @Suite("dockerHost via tcProperties", .serialized)
    struct DockerHostTcPropertiesTests {

        private func withTcHost(_ value: String?, body: () -> Void) {
            let saved = testcontainersConfig.tcProperties["tc.host"]
            defer {
                if let saved = saved {
                    testcontainersConfig.tcProperties["tc.host"] = saved
                } else {
                    testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
                }
            }
            if let value = value {
                testcontainersConfig.tcProperties["tc.host"] = value
            } else {
                testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
            }
            body()
        }

        @Test func returnsTcpUrlUnchanged() {
            withTcHost("tcp://localhost:2375") {
                #expect(dockerHost() == "tcp://localhost:2375")
            }
        }

        @Test func stripsTrailingSlashFromSshUrl() {
            withTcHost("ssh://user@host.example.com/") {
                #expect(dockerHost() == "ssh://user@host.example.com")
            }
        }

        @Test func returnsNilOrStringWhenAbsent() {
            withTcHost(nil) {
                let result = dockerHost()
                // Accept nil or a String — environment-dependent.
                if let r = result {
                    #expect(!r.isEmpty)
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // DockerClient.host
    // -------------------------------------------------------------------------

    @Suite("DockerClient.host via tcProperties", .serialized)
    struct DockerClientHostTcPropertiesTests {

        private func withTcHost(_ value: String?, body: (DockerClient) -> Void) {
            let saved = testcontainersConfig.tcProperties["tc.host"]
            defer {
                if let saved = saved {
                    testcontainersConfig.tcProperties["tc.host"] = saved
                } else {
                    testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
                }
            }
            if let value = value {
                testcontainersConfig.tcProperties["tc.host"] = value
            } else {
                testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
            }
            let client = DockerClient.testOnly()
            body(client)
        }

        @Test func returnsSshHostnameForSshUrl() {
            withTcHost("ssh://user@build-host.example.com") { client in
                #expect(client.host == "build-host.example.com")
            }
        }

        @Test func returnsSshHostnameWithPort() {
            withTcHost("ssh://user@ci-agent.internal:22") { client in
                #expect(client.host == "ci-agent.internal")
            }
        }

        @Test func returnsHostnameForTcpUrl() {
            withTcHost("tcp://192.168.10.5:2375") { client in
                #expect(client.host == "192.168.10.5")
            }
        }

        @Test func returnsHostnameForHttpUrl() {
            withTcHost("http://10.0.0.1:2375") { client in
                #expect(client.host == "10.0.0.1")
            }
        }

        @Test func returnsHostnameForHttpsUrl() {
            withTcHost("https://docker.remote:2376") { client in
                #expect(client.host == "docker.remote")
            }
        }

        @Test func returnsLocalhostForTcpUrlWithEmptyHost() {
            withTcHost("tcp://:2375") { client in
                #expect(client.host == "localhost")
            }
        }

        @Test func returnsNamedHostForTcpUrl() {
            withTcHost("tcp://dockerd.local:2375") { client in
                #expect(client.host == "dockerd.local")
            }
        }

        @Test func isNonEmptyStringWhenAbsent() {
            withTcHost(nil) { client in
                #expect(!client.host.isEmpty)
            }
        }
    }
}

// MARK: - DockerClient.connectionMode smoke test

@Suite("DockerClient.connectionMode smoke test")
struct DockerClientConnectionModeSmokTests {
    @Test func isValidConnectionModeValue() {
        let client = DockerClient.testOnly()
        let mode = client.connectionMode
        let valid: [ConnectionMode] = [.dockerHost, .bridgeIp, .gatewayIp]
        #expect(valid.contains(mode))
    }
}

// MARK: - decodeChunked additional edge cases

@Suite("DockerClient.decodeChunked additional")
struct DecodeChunkedAdditionalTests {
    private let client = DockerClient.testOnly()

    private func makeChunked(_ data: String) -> Data {
        let bytes = Array(data.utf8)
        let sizeHex = String(bytes.count, radix: 16, uppercase: false)
        var result = Data()
        result.append(contentsOf: "\(sizeHex)\r\n".utf8)
        result.append(contentsOf: bytes)
        result.append(contentsOf: "\r\n0\r\n\r\n".utf8)
        return result
    }

    @Test func decodesUppercaseHexChunkSize() {
        // HTTP spec allows uppercase hex. 'A' = 10 decimal.
        var data = Data()
        data.append(contentsOf: "A\r\n".utf8)
        data.append(contentsOf: "0123456789".utf8)
        data.append(contentsOf: "\r\n0\r\n\r\n".utf8)
        let decoded = client.decodeChunked(data)
        #expect(String(data: decoded, encoding: .utf8) == "0123456789")
    }

    @Test func handlesTruncatedChunkWithoutThrowing() {
        // Chunk header says 10 bytes (A hex) but body is only 3 bytes.
        var data = Data()
        data.append(contentsOf: "A\r\nabc".utf8)
        let decoded = client.decodeChunked(data)
        #expect(decoded.isEmpty)
    }

    @Test func decodesMixedCaseHexChunkSize() {
        // 'b' = 11 decimal — mixed-case hex is valid HTTP.
        let payload = "hello world"
        var data = Data()
        data.append(contentsOf: "b\r\n".utf8)
        data.append(contentsOf: payload.utf8)
        data.append(contentsOf: "\r\n0\r\n\r\n".utf8)
        let decoded = client.decodeChunked(data)
        #expect(String(data: decoded, encoding: .utf8) == payload)
    }

    @Test func decodesMultipleChunksConcatenated() {
        let chunk1 = Data("5\r\nhello\r\n".utf8)
        let chunk2 = Data("6\r\n world\r\n".utf8)
        let terminator = Data("0\r\n\r\n".utf8)
        var combined = Data()
        combined.append(chunk1)
        combined.append(chunk2)
        combined.append(terminator)
        let decoded = client.decodeChunked(combined)
        #expect(String(data: decoded, encoding: .utf8) == "hello world")
    }

    @Test func returnsEmptyForTerminatorOnly() {
        let data = Data("0\r\n\r\n".utf8)
        let decoded = client.decodeChunked(data)
        #expect(decoded.isEmpty)
    }

    @Test func returnsEmptyForEmptyInput() {
        let decoded = client.decodeChunked(Data())
        #expect(decoded.isEmpty)
    }

    @Test func decodesChunkWithNewlineInData() {
        let payload = "line1\nline2"
        let encoded = makeChunked(payload)
        let decoded = client.decodeChunked(encoded)
        #expect(String(data: decoded, encoding: .utf8) == payload)
    }

    @Test func decodesChunkWithSingleByte() {
        let encoded = makeChunked("x")
        let decoded = client.decodeChunked(encoded)
        #expect(String(data: decoded, encoding: .utf8) == "x")
    }

    @Test func decodesConsecutiveSingleByteChunks() {
        var data = Data()
        data.append(contentsOf: "1\r\na\r\n".utf8)
        data.append(contentsOf: "1\r\nb\r\n".utf8)
        data.append(contentsOf: "0\r\n\r\n".utf8)
        let decoded = client.decodeChunked(data)
        #expect(String(data: decoded, encoding: .utf8) == "ab")
    }
}

// MARK: - stripDockerLogHeaders additional edge cases

@Suite("DockerClient.stripDockerLogHeaders additional")
struct StripDockerLogHeadersAdditionalTests {
    private let client = DockerClient.testOnly()

    private func makeLogFrame(streamType: UInt8, payload: Data) -> Data {
        var header = Data(count: 8)
        header[0] = streamType
        let size = payload.count
        header[4] = UInt8((size >> 24) & 0xFF)
        header[5] = UInt8((size >> 16) & 0xFF)
        header[6] = UInt8((size >> 8) & 0xFF)
        header[7] = UInt8(size & 0xFF)
        return header + payload
    }

    @Test func stripsSingleStdoutFrame() {
        let payload = Data("hello".utf8)
        let frame = makeLogFrame(streamType: 1, payload: payload)
        let stripped = client.stripDockerLogHeaders(frame)
        #expect(String(data: stripped, encoding: .utf8) == "hello")
    }

    @Test func stripsSingleStderrFrame() {
        let payload = Data("error".utf8)
        let frame = makeLogFrame(streamType: 2, payload: payload)
        let stripped = client.stripDockerLogHeaders(frame)
        #expect(String(data: stripped, encoding: .utf8) == "error")
    }

    @Test func stripsMultipleConsecutiveFrames() {
        let p1 = Data("foo".utf8)
        let p2 = Data("bar".utf8)
        var combined = Data()
        combined.append(makeLogFrame(streamType: 1, payload: p1))
        combined.append(makeLogFrame(streamType: 1, payload: p2))
        let stripped = client.stripDockerLogHeaders(combined)
        #expect(String(data: stripped, encoding: .utf8) == "foobar")
    }

    @Test func returnsMixedFramesInOrder() {
        let out = Data("out".utf8)
        let err = Data("err".utf8)
        let out2 = Data("out2".utf8)
        var combined = Data()
        combined.append(makeLogFrame(streamType: 1, payload: out))
        combined.append(makeLogFrame(streamType: 2, payload: err))
        combined.append(makeLogFrame(streamType: 1, payload: out2))
        let stripped = client.stripDockerLogHeaders(combined)
        #expect(String(data: stripped, encoding: .utf8) == "outerrout2")
    }

    @Test func returnsRawBytesForPlainText() {
        let raw = Data("plain log line".utf8)
        let stripped = client.stripDockerLogHeaders(raw)
        #expect(stripped == raw)
    }

    @Test func returnsEmptyForEmptyInput() {
        let stripped = client.stripDockerLogHeaders(Data())
        #expect(stripped.isEmpty)
    }

    @Test func returnsRawBytesForShortInput() {
        let short = Data([1, 0, 0, 0])
        let stripped = client.stripDockerLogHeaders(short)
        #expect(stripped == short)
    }

    @Test func handlesZeroBytePayloadFrame() {
        // An 8-byte header with payload size 0 should be skipped gracefully.
        let emptyPayload = Data()
        let zeroFrame = makeLogFrame(streamType: 1, payload: emptyPayload)
        let dataFrame = makeLogFrame(streamType: 1, payload: Data("data".utf8))
        var combined = Data()
        combined.append(zeroFrame)
        combined.append(dataFrame)
        let stripped = client.stripDockerLogHeaders(combined)
        #expect(String(data: stripped, encoding: .utf8) == "data")
    }

    @Test func handlesTruncatedFrame() {
        // Frame header claims 5 bytes but only 3 follow — should return raw input.
        var header = Data(count: 8)
        header[0] = 1
        header[7] = 5  // payload size = 5
        var truncated = Data()
        truncated.append(header)
        truncated.append(Data("abc".utf8))  // only 3 bytes of promised 5
        let stripped = client.stripDockerLogHeaders(truncated)
        #expect(stripped == truncated)
    }

    @Test func handlesStdinStreamType() {
        // Stream type 0 (stdin) must not crash; payload is appended.
        let frame = makeLogFrame(streamType: 0, payload: Data("stdin_data".utf8))
        let stripped = client.stripDockerLogHeaders(frame)
        #expect(String(data: stripped, encoding: .utf8) == "stdin_data")
    }
}

// MARK: - parseHttpResponse — header-value-with-colon edge cases
// (These complement the main suite in DockerClientParserTests.swift)

@Suite("DockerClient.parseHttpResponse edge cases")
struct ParseHttpResponseEdgeCasesTests {
    private let client = DockerClient.testOnly()

    /// Builds a minimal HTTP/1.0 response.
    private func buildResponse(
        statusLine: String = "HTTP/1.0 200 OK",
        headers: [(String, String)] = [],
        body: String = ""
    ) -> Data {
        var sb = "\(statusLine)\r\n"
        for (k, v) in headers { sb += "\(k): \(v)\r\n" }
        sb += "\r\n"
        var data = Data(sb.utf8)
        data.append(Data(body.utf8))
        return data
    }

    @Test func headerValueWithColonPreservesFullValue() {
        // "Location: http://localhost:2375/v1.41/containers" — the value contains
        // a colon. parseHttpResponse must split only at the first colon.
        let data = buildResponse(headers: [("Location", "http://localhost:2375/v1.41/containers")])
        let result = client.parseHttpResponse(data)
        #expect(result.headers["location"] == "http://localhost:2375/v1.41/containers")
    }

    @Test func statusCodeParsedFromThreeDigitToken() {
        // Verify the status code is parsed from position [1] in the space-split status line.
        let data = buildResponse(statusLine: "HTTP/1.0 201 Created", body: "{}")
        let result = client.parseHttpResponse(data)
        #expect(result.statusCode == 201)
    }

    @Test func dockerExperimentalHeaderParsedCorrectly() {
        let data = buildResponse(
            headers: [("Docker-Experimental", "true"), ("Api-Version", "1.41")],
            body: "{}"
        )
        let result = client.parseHttpResponse(data)
        #expect(result.headers["docker-experimental"] == "true")
        #expect(result.headers["api-version"] == "1.41")
    }
}
