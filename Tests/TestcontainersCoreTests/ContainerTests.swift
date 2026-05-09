import Testing
import Foundation
@testable import TestcontainersCore

@Suite("DockerContainer builder")
struct DockerContainerBuilderTests {
    @Test func withEnvAddsEnvironmentVariable() {
        let c = DockerContainer("nginx:alpine").withEnv("FOO", "bar")
        #expect(c.env["FOO"] == "bar")
    }

    @Test func withEnvsAddsMultipleVariables() {
        let c = DockerContainer("nginx:alpine").withEnvs(["A": "1", "B": "2"])
        #expect(c.env["A"] == "1")
        #expect(c.env["B"] == "2")
    }

    @Test func withBindPortsMapsPort() {
        let c = DockerContainer("nginx:alpine").withBindPorts(80, 8080)
        #expect(c.ports[80] == 8080)
    }

    @Test func withBindPortsWithoutHostPortIsEphemeral() {
        let c = DockerContainer("nginx:alpine").withBindPorts(8080)
        #expect(c.ports[8080]! == nil)
    }

    @Test func withExposedPortsExposesWithNullHostPort() {
        let c = DockerContainer("nginx:alpine").withExposedPorts(80, 443)
        #expect(c.ports[80]! == nil)
        #expect(c.ports[443]! == nil)
    }

    @Test func withExposedPortsWithNoArgs() {
        let c = DockerContainer("alpine")
        #expect(c.ports.isEmpty)
    }

    @Test func withEnvsWithEmptyMapLeavesEnvUnchanged() {
        let c = DockerContainer("alpine").withEnv("X", "1").withEnvs([:])
        #expect(c.env["X"] == "1")
        #expect(c.env.count == 1)
    }

    @Test func withEnvsMergesWithPreExisting() {
        let c = DockerContainer("alpine").withEnv("EXISTING", "keep").withEnvs(["NEW": "add"])
        #expect(c.env["EXISTING"] == "keep")
        #expect(c.env["NEW"] == "add")
    }

    @Test func withEnvsOverwritesOnKeyCollision() {
        let c = DockerContainer("alpine").withEnv("KEY", "old").withEnvs(["KEY": "new"])
        #expect(c.env["KEY"] == "new")
    }

    @Test func withCommandAcceptsString() {
        let c = DockerContainer("alpine").withCommand("echo hello")
        #expect((c.command as? String) == "echo hello")
    }

    @Test func withCommandAcceptsArray() {
        let c = DockerContainer("alpine").withCommand(["echo", "hello"])
        #expect((c.command as? [String]) == ["echo", "hello"])
    }

    @Test func withNameSetsContainerName() {
        let c = DockerContainer("alpine").withName("my-container")
        #expect(c.name == "my-container")
    }

    @Test func withVolumeMappingAddsVolume() {
        let c = DockerContainer("alpine").withVolumeMapping("/host/path", "/container/path", "rw")
        // Key is host path; MountConfig.hostPath stores the container bind path
        #expect(c.volumes["/host/path"] != nil)
        #expect(c.volumes["/host/path"]?.hostPath == "/container/path")
        #expect(c.volumes["/host/path"]?.mode == "rw")
    }

    @Test func withKwargsSetExtraKwargs() {
        let c = DockerContainer("alpine").withKwargs(["privileged": true])
        #expect(c.kwargs["privileged"] as? Bool == true)
    }

    @Test func withKwargsMergesSuccessiveCalls() {
        let c = DockerContainer("alpine")
            .withKwargs(["privileged": true])
            .withKwargs(["autoRemove": true])
        #expect(c.kwargs["privileged"] as? Bool == true)
        #expect(c.kwargs["autoRemove"] as? Bool == true)
    }

    @Test func withKwargsOverwritesIndividualKeysOnCollision() {
        let c = DockerContainer("alpine")
            .withKwargs(["privileged": false])
            .withKwargs(["privileged": true])
        #expect(c.kwargs["privileged"] as? Bool == true)
    }

    @Test func imageGetsHubPrefix() {
        let c = DockerContainer("nginx:alpine")
        #expect(c.image.contains("nginx:alpine"))
    }

    @Test func maybeEmulateAmd64DoesNotOverwriteUserSetPlatform() {
        let c = DockerContainer("alpine")
            .withKwargs(["platform": "linux/arm64"])
        c.maybeEmulateAmd64()
        #expect(c.kwargs["platform"] as? String == "linux/arm64")
    }

    @Test func maybeEmulateAmd64ReturnsSameInstance() {
        let c = DockerContainer("alpine")
        let result = c.maybeEmulateAmd64()
        #expect(result === c)
    }

    @Test func withCopyIntoContainerReturnsSameInstance() {
        let c = DockerContainer("alpine")
        let result = c.withCopyIntoContainer(.bytes(Data([1, 2, 3])), "/app/file")
        #expect(result === c)
    }

    @Test func chainedBuilderReturnsSameInstance() {
        let c = DockerContainer("alpine")
        let result = c.withEnv("X", "1").withName("n").withCommand("sh")
        #expect(result === c)
    }

    @Test func waitingForReturnsSameInstance() {
        let c = DockerContainer("alpine")
        let strategy = LogMessageWaitStrategy("ready")
        let result = c.waitingFor(strategy)
        #expect(result === c)
    }

    @Test func withTmpfsMountAddsPathWithoutSize() {
        let c = DockerContainer("alpine").withTmpfsMount("/tmp/ramdisk")
        #expect(c.tmpfs["/tmp/ramdisk"] == "")
    }

    @Test func withTmpfsMountAddsPathWithSize() {
        let c = DockerContainer("alpine").withTmpfsMount("/run", size: "64m")
        #expect(c.tmpfs["/run"] == "64m")
    }

    @Test func multipleTmpfsMountsAccumulate() {
        let c = DockerContainer("alpine")
            .withTmpfsMount("/tmp/a")
            .withTmpfsMount("/tmp/b", size: "32m")
        #expect(c.tmpfs.count == 2)
        #expect(c.tmpfs["/tmp/a"] != nil)
        #expect(c.tmpfs["/tmp/b"] == "32m")
    }

    @Test func withNetworkSetsNetworkReference() {
        let network = Network()
        let c = DockerContainer("alpine").withNetwork(network)
        #expect(c.network === network)
    }

    @Test func withNetworkAliasesSetsAliases() {
        let c = DockerContainer("alpine").withNetworkAliases("alias1", "alias2")
        #expect(c.networkAliases == ["alias1", "alias2"])
    }

    @Test func networkAliasesIsNilBeforeSet() {
        let c = DockerContainer("alpine")
        #expect(c.networkAliases == nil)
    }

    @Test func statusDefaultsToNotStarted() {
        let c = DockerContainer("alpine")
        #expect(c.status == "not_started")
    }
}

@Suite("DockerContainer.splitCommand")
struct SplitCommandTests {
    @Test func splitsOnSpaces() {
        #expect(DockerContainer.splitCommand("nginx -g daemon off;") == ["nginx", "-g", "daemon", "off;"])
    }

    @Test func handlesSingleQuotedArgumentWithSpaces() {
        #expect(DockerContainer.splitCommand("echo 'hello world'") == ["echo", "hello world"])
    }

    @Test func handlesDoubleQuotedArgumentWithSpaces() {
        #expect(DockerContainer.splitCommand(#"nginx -c "/etc/nginx/nginx.conf""#) == ["nginx", "-c", "/etc/nginx/nginx.conf"])
    }

    @Test func handlesMultipleConsecutiveSpaces() {
        #expect(DockerContainer.splitCommand("a  b   c") == ["a", "b", "c"])
    }

    @Test func handlesTabAsWhitespace() {
        #expect(DockerContainer.splitCommand("a\tb") == ["a", "b"])
    }

    @Test func returnsEmptyListForEmptyString() {
        #expect(DockerContainer.splitCommand("").isEmpty)
    }

    @Test func returnsEmptyListForWhitespaceOnly() {
        #expect(DockerContainer.splitCommand("   ").isEmpty)
    }

    @Test func singleTokenWithoutSpaces() {
        #expect(DockerContainer.splitCommand("sh") == ["sh"])
    }

    @Test func unclosedDoubleQuote() {
        #expect(DockerContainer.splitCommand("\"hello world") == ["hello world"])
    }

    @Test func unclosedSingleQuote() {
        #expect(DockerContainer.splitCommand("'hello world") == ["hello world"])
    }

    @Test func emptyQuotedArgIsDropped() {
        #expect(DockerContainer.splitCommand("cmd ''") == ["cmd"])
        #expect(DockerContainer.splitCommand("cmd \"\"") == ["cmd"])
    }

    @Test func backslashIsTreatedAsLiteral() {
        #expect(DockerContainer.splitCommand(#"a\b"#) == [#"a\b"#])
    }
}

@Suite("DockerContainer WaitStrategyTarget before start")
struct ContainerPreStartTests {
    @Test func containerHostIpReturnsLocalhostBeforeStart() {
        let c = DockerContainer("alpine")
        #expect(c.containerHostIp() == "localhost")
    }

    @Test func reloadCompletesWithoutErrorBeforeStart() {
        let c = DockerContainer("alpine")
        c.reload() // should not crash
    }

    @Test func statusReturnsNotStartedBeforeStart() {
        let c = DockerContainer("alpine")
        #expect(c.status == "not_started")
    }

    @Test func logsThrowsBeforeStart() {
        let c = DockerContainer("alpine")
        #expect(throws: ContainerStartException.self) {
            _ = try c.logs()
        }
    }

    @Test func containerInfoReturnsNilBeforeStart() async throws {
        let c = DockerContainer("alpine")
        let info = try await c.containerInfo()
        #expect(info == nil)
    }
}

@Suite("DockerContainer withEnvFile")
struct ContainerEnvFileTests {
    @Test func loadsKeyValuePairs() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_env_\(Int.random(in: 1...99999))")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let envFile = tmp.appendingPathComponent(".env")
        try "FOO=bar\nBAZ=qux\n".write(to: envFile, atomically: true, encoding: .utf8)

        let c = DockerContainer("alpine").withEnvFile(envFile.path)
        #expect(c.env["FOO"] == "bar")
        #expect(c.env["BAZ"] == "qux")
    }

    @Test func expandsVarReferences() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_env_interp_\(Int.random(in: 1...99999))")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let content = "DOMAIN=example.org\nADMIN_EMAIL=admin@${DOMAIN}\nROOT_URL=${DOMAIN}/app\n"
        let envFile = tmp.appendingPathComponent(".env")
        try content.write(to: envFile, atomically: true, encoding: .utf8)

        let c = DockerContainer("alpine").withEnvFile(envFile.path)
        #expect(c.env["DOMAIN"] == "example.org")
        #expect(c.env["ADMIN_EMAIL"] == "admin@example.org")
        #expect(c.env["ROOT_URL"] == "example.org/app")
    }

    @Test func skipsBlankLinesAndComments() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_env_skip_\(Int.random(in: 1...99999))")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let envFile = tmp.appendingPathComponent(".env")
        try "# This is a comment\n\nKEY=value\n".write(to: envFile, atomically: true, encoding: .utf8)

        let c = DockerContainer("alpine").withEnvFile(envFile.path)
        #expect(c.env.count == 1)
        #expect(c.env["KEY"] == "value")
    }

    @Test func skipsLinesWithoutEqualsSign() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_env_noeq_\(Int.random(in: 1...99999))")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let envFile = tmp.appendingPathComponent(".env")
        try "VALID=value\nNOEQUALSSIGN\nALSO_VALID=ok\n".write(to: envFile, atomically: true, encoding: .utf8)

        let c = DockerContainer("alpine").withEnvFile(envFile.path)
        #expect(c.env["VALID"] == "value")
        #expect(c.env["ALSO_VALID"] == "ok")
        #expect(c.env["NOEQUALSSIGN"] == nil)
    }

    @Test func handlesValuesWithEqualsSign() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_env_eqval_\(Int.random(in: 1...99999))")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let envFile = tmp.appendingPathComponent(".env")
        try "SECRET=abc=123==\n".write(to: envFile, atomically: true, encoding: .utf8)

        let c = DockerContainer("alpine").withEnvFile(envFile.path)
        #expect(c.env["SECRET"] == "abc=123==")
    }

    @Test func trimsWhitespace() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_env_trim_\(Int.random(in: 1...99999))")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let envFile = tmp.appendingPathComponent(".env")
        try "  KEY  =  value  \n".write(to: envFile, atomically: true, encoding: .utf8)

        let c = DockerContainer("alpine").withEnvFile(envFile.path)
        #expect(c.env["KEY"] == "value")
    }
}
