import Foundation
import Testing

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
        let c = DockerContainer("nginx:alpine").withExposedPorts([80, 443])
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

    @Test func withVolumeMappingReadOnlyMode() {
        let c = DockerContainer("alpine").withVolumeMapping("/data", "/data", "ro")
        #expect(c.volumes["/data"]?.mode == "ro")
    }

    @Test func multipleVolumeMappingsAccumulate() {
        let c = DockerContainer("alpine")
            .withVolumeMapping("/a", "/container/a", "rw")
            .withVolumeMapping("/b", "/container/b", "ro")
        #expect(c.volumes.count == 2)
        #expect(c.volumes["/a"]?.mode == "rw")
        #expect(c.volumes["/b"]?.mode == "ro")
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
        let c = DockerContainer("alpine").withNetworkAliases(["alias1", "alias2"])
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
        #expect(
            DockerContainer.splitCommand(#"nginx -c "/etc/nginx/nginx.conf""#) == [
                "nginx", "-c", "/etc/nginx/nginx.conf",
            ]
        )
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
    @Test func containerHostIpReturnsLocalhostBeforeStart() async throws {
        let c = DockerContainer("alpine")
        let ip = try await c.containerHostIp()
        #expect(ip == "localhost")
    }

    @Test func reloadCompletesWithoutErrorBeforeStart() async {
        let c = DockerContainer("alpine")
        await c.reload()  // should not crash
    }

    @Test func statusReturnsNotStartedBeforeStart() {
        let c = DockerContainer("alpine")
        #expect(c.status == "not_started")
    }

    @Test func logsThrowsBeforeStart() async {
        let c = DockerContainer("alpine")
        await #expect(throws: ContainerStartException.self) {
            _ = try await c.logs()
        }
    }

    @Test func containerInfoReturnsNilBeforeStart() async throws {
        let c = DockerContainer("alpine")
        let info = try await c.containerInfo()
        #expect(info == nil)
    }

    @Test func wrappedContainerReturnsSelf() {
        let c = DockerContainer("alpine")
        #expect(c.wrappedContainer === c)
    }

    @Test func execThrowsBeforeStart() async {
        let c = DockerContainer("alpine")
        await #expect(throws: ContainerStartException.self) {
            _ = try await c.exec(["echo", "hello"])
        }
    }

    @Test func exposedPortThrowsBeforeStart() async {
        let c = DockerContainer("alpine")
        await #expect(throws: (any Error).self) {
            _ = try await c.exposedPort(8080)
        }
    }

    @Test func stopBeforeStartCompletesWithoutError() async throws {
        let c = DockerContainer("alpine")
        try await c.stop()
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

    @Test func withOnlyCommentsProducesNoEnvVars() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_env_comments_\(Int.random(in: 1...99999))")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let envFile = tmp.appendingPathComponent(".env")
        try "# comment 1\n# comment 2\n\n".write(to: envFile, atomically: true, encoding: .utf8)

        let c = DockerContainer("alpine").withEnvFile(envFile.path)
        #expect(c.env.isEmpty)
    }

    @Test func mergesWithPreExistingEnvVar() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_env_merge_\(Int.random(in: 1...99999))")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let envFile = tmp.appendingPathComponent(".env")
        try "FROM_FILE=yes\n".write(to: envFile, atomically: true, encoding: .utf8)

        let c = DockerContainer("alpine")
            .withEnv("FROM_CODE", "also")
            .withEnvFile(envFile.path)
        #expect(c.env["FROM_CODE"] == "also")
        #expect(c.env["FROM_FILE"] == "yes")
    }

    @Test func fileVarOverwritesPreExistingKey() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_env_overwrite_\(Int.random(in: 1...99999))")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let envFile = tmp.appendingPathComponent(".env")
        try "KEY=new\n".write(to: envFile, atomically: true, encoding: .utf8)

        let c = DockerContainer("alpine")
            .withEnv("KEY", "old")
            .withEnvFile(envFile.path)
        #expect(c.env["KEY"] == "new")
    }
}

@Suite("DockerContainer withCopyIntoContainer accumulation")
struct ContainerTransferableTests {
    @Test func singleSpecReturnsChainedInstance() {
        let c = DockerContainer("alpine")
        let result = c.withCopyIntoContainer(.bytes(Data([1, 2, 3])), "/app/file")
        #expect(result === c)
    }

    @Test func multipleCallsReturnSameInstance() {
        let c = DockerContainer("alpine")
        let r1 = c.withCopyIntoContainer(.bytes(Data([1])), "/a")
        let r2 = r1.withCopyIntoContainer(.bytes(Data([2])), "/b")
        #expect(r1 === c)
        #expect(r2 === c)
    }
}

// ---------------------------------------------------------------------------
// Additional builder tests (ported from Dart reference)
// ---------------------------------------------------------------------------

@Suite("DockerContainer builder — additional")
struct DockerContainerBuilderAdditionalTests {
    @Test func withExposedPortsEmptyListLeavesPortsUnchanged() {
        let c = DockerContainer("alpine").withExposedPorts([])
        #expect(c.ports.isEmpty)
    }

    @Test func withNetworkAliasesEmptyListYieldsEmptyNotNil() {
        let c = DockerContainer("alpine").withNetworkAliases([])
        #expect(c.networkAliases != nil)
        #expect(c.networkAliases!.isEmpty)
    }

    @Test func withTmpfsMountOverwritesExistingPathOnDuplicateCall() {
        let c = DockerContainer("alpine")
            .withTmpfsMount("/run")
            .withTmpfsMount("/run", size: "128m")
        #expect(c.tmpfs.count == 1)
        #expect(c.tmpfs["/run"] == "128m")
    }
}

// ---------------------------------------------------------------------------
// configure() hook tests
// ---------------------------------------------------------------------------

/// A subclass whose configure() is a no-op — it only calls super.configure().
private class _BaseContainer: DockerContainer, @unchecked Sendable {
    func triggerConfigure() { configure() }
}

/// A subclass that overrides configure() to inject a known env variable.
private class _ConfiguringContainer: DockerContainer, @unchecked Sendable {
    override func configure() {
        withEnv("CONFIGURED", "true")
        super.configure()
    }
    func triggerConfigure() { configure() }
}

@Suite("DockerContainer.configure hook")
struct ConfigureHookTests {
    @Test func baseConfigureIsANoOp() {
        let c = _BaseContainer("alpine")
        c.triggerConfigure()
        #expect(c.env.isEmpty)
        #expect(c.ports.isEmpty)
        #expect(c.volumes.isEmpty)
    }

    @Test func subclassCanAddEnvVarsInConfigure() {
        let c = _ConfiguringContainer("alpine")
        c.triggerConfigure()
        #expect(c.env["CONFIGURED"] == "true")
    }

    @Test func configureCanBeCalledMultipleTimesIdempotently() {
        let c = _ConfiguringContainer("alpine")
        c.triggerConfigure()
        c.triggerConfigure()
        #expect(c.env["CONFIGURED"] == "true")
        #expect(c.env.count == 1)
    }
}

// ---------------------------------------------------------------------------
// dockerClient getter tests
// ---------------------------------------------------------------------------

@Suite("DockerContainer.dockerClient")
struct DockerClientGetterTests {
    @Test func dockerClientGetterReturnsNonNil() {
        let c = DockerContainer("alpine")
        // Just accessing the property should not crash; it always returns a value.
        let client = c.dockerClient
        _ = client  // silence unused-variable warning
        #expect(true)
    }

    @Test func dockerClientReturnsSameInstanceOnRepeatedAccess() {
        let c = DockerContainer("alpine")
        #expect(c.dockerClient === c.dockerClient)
    }
}

// ---------------------------------------------------------------------------
// Lifecycle before start — additional
// ---------------------------------------------------------------------------

@Suite("DockerContainer lifecycle before start — additional")
struct ContainerPreStartAdditionalTests {
    @Test func stopWithForceFalseBeforeStartIsNoOp() async throws {
        let c = DockerContainer("alpine")
        try await c.stop(force: false, deleteVolume: false)
    }

    @Test func waitThrowsBeforeStart() async {
        let c = DockerContainer("alpine")
        do {
            _ = try await c.wait()
            #expect(Bool(false), "Expected wait() to throw before start")
        } catch {
            #expect(error is ContainerStartException)
        }
    }

    @Test func execShellThrowsBeforeStart() async {
        let c = DockerContainer("alpine")
        do {
            _ = try await c.execShell("echo hello")
            #expect(Bool(false), "Expected execShell to throw before start")
        } catch {
            #expect(error is ContainerStartException)
        }
    }

    @Test func copyFromContainerThrowsBeforeStart() async {
        let c = DockerContainer("alpine")
        do {
            try await c.copyFromContainer("/etc/hosts", "/tmp/out.tar")
            #expect(Bool(false), "Expected copyFromContainer to throw before start")
        } catch {
            #expect(error is ContainerStartException)
        }
    }
}

// ---------------------------------------------------------------------------
// splitCommand — additional edge cases
// ---------------------------------------------------------------------------

@Suite("DockerContainer.splitCommand — additional")
struct SplitCommandAdditionalTests {
    @Test func singleQuotedArgPreservesDoubleQuotesInside() {
        #expect(DockerContainer.splitCommand(#"echo '"hello"'"#) == ["echo", #""hello""#])
    }

    @Test func doubleQuotedArgPreservesSingleQuotesInside() {
        #expect(DockerContainer.splitCommand("echo \"'hello'\" ") == ["echo", "'hello'"])
    }

    @Test func adjacentWordAndQuoteMergeIntoOneToken() {
        // foo"bar" → foobar  (standard sh adjacency behaviour)
        #expect(DockerContainer.splitCommand(#"foo"bar""#) == ["foobar"])
    }

    @Test func multipleBackslashesRemainLiteral() {
        #expect(DockerContainer.splitCommand(#"cmd --arg=a\\b\\c"#) == ["cmd", #"--arg=a\\b\\c"#])
    }

    @Test func backslashBeforeSpaceDoesNotEscapeSpace() {
        // Without backslash-escape support, backslash+space still splits on the space.
        #expect(DockerContainer.splitCommand(#"a\ b"#) == [#"a\"#, "b"])
    }
}

// ---------------------------------------------------------------------------
// withEnvFile — additional edge cases
// ---------------------------------------------------------------------------

@Suite("DockerContainer withEnvFile — additional")
struct ContainerEnvFileAdditionalTests {
    private func makeTempDir(suffix: String) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_env_\(suffix)_\(Int.random(in: 1...99999))")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    @Test func resolvesUnknownVarToEmptyString() throws {
        let tmp = try makeTempDir(suffix: "missing_var")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let envFile = tmp.appendingPathComponent(".env")
        try "KEY=prefix-${MISSING_VAR}-suffix\n".write(to: envFile, atomically: true, encoding: .utf8)

        let c = DockerContainer("alpine").withEnvFile(envFile.path)
        #expect(c.env["KEY"] == "prefix--suffix")
    }

    @Test func handlesCRLFLineEndings() throws {
        let tmp = try makeTempDir(suffix: "crlf")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let envFile = tmp.appendingPathComponent(".env")
        // Windows-style CRLF: the trim inside withEnvFile strips the trailing \r.
        try Data("A=1\r\nB=2\r\n".utf8).write(to: envFile)

        let c = DockerContainer("alpine").withEnvFile(envFile.path)
        #expect(c.env["A"] == "1")
        #expect(c.env["B"] == "2")
    }

    @Test func doesNotExpandDollarWithoutBraces() throws {
        let tmp = try makeTempDir(suffix: "nobrace")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let envFile = tmp.appendingPathComponent(".env")
        // The regex requires ${VAR} braces; bare $VAR is left as-is.
        try "KEY=prefix-$SIMPLE-suffix\n".write(to: envFile, atomically: true, encoding: .utf8)

        let c = DockerContainer("alpine").withEnvFile(envFile.path)
        #expect(c.env["KEY"] == "prefix-$SIMPLE-suffix")
    }

    @Test func doesNotUsePreExistingEnvVarsForInterpolation() throws {
        let tmp = try makeTempDir(suffix: "preexisting")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // The `resolved` map inside withEnvFile starts empty — variables set
        // by withEnv() before calling withEnvFile() are NOT visible to ${VAR}.
        let envFile = tmp.appendingPathComponent(".env")
        try "DERIVED=hello-${HOST}\n".write(to: envFile, atomically: true, encoding: .utf8)

        let c = DockerContainer("alpine")
            .withEnv("HOST", "example.com")
            .withEnvFile(envFile.path)

        #expect(c.env["DERIVED"] == "hello-")
        #expect(c.env["HOST"] == "example.com")
    }

    @Test func nonExistentFileIsHandledSilently() {
        // Swift uses `try?` so a missing file is a silent no-op (no throw).
        let missingPath = "/tmp/__tc_no_such_env_\(Int.random(in: 1...999999))__"
        let c = DockerContainer("alpine").withEnvFile(missingPath)
        #expect(c.env.isEmpty)
    }
}
