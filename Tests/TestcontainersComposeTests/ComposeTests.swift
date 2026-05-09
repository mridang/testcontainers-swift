import Foundation
import TestcontainersCore
import Testing

@testable import TestcontainersCompose

// MARK: - Helpers

private func fixturesPath() -> String {
    // Bundle.module provides the compose_fixtures resource directory
    Bundle.module.resourcePath.flatMap {
        URL(fileURLWithPath: $0)
            .appendingPathComponent("compose_fixtures")
            .path
    } ?? "./Tests/TestcontainersComposeTests/compose_fixtures"
}

private func fixture(_ name: String) -> String {
    "\(fixturesPath())/\(name)"
}

// MARK: - Unit tests (no Docker required)

@Suite("Compose unit tests", .serialized)
struct ComposeUnitTests {
    @Test func composeNoFileName() {
        let basic = DockerCompose(context: fixture("basic"))
        #expect(basic.composeFileName == nil)
    }

    @Test func composeStrFileName() {
        let basic = DockerCompose(
            context: fixture("basic"),
            composeFileName: ["docker-compose.yaml"]
        )
        #expect(basic.composeFileName == ["docker-compose.yaml"])
    }

    @Test func composeListFileName() {
        let basic = DockerCompose(
            context: fixture("basic"),
            composeFileName: ["a.yaml", "b.yaml"]
        )
        #expect(basic.composeFileName == ["a.yaml", "b.yaml"])
    }

    @Test func containerInfoNullWithoutReference() async throws {
        let container = ComposeContainer()
        let info = try await container.containerInfo()
        #expect(info == nil)
    }

    @Test func normalizeSSH_replacesWildcard() {
        let saved = testcontainersConfig.tcProperties["tc.host"]
        defer {
            if let saved = saved {
                testcontainersConfig.tcProperties["tc.host"] = saved
            } else {
                testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
            }
        }
        testcontainersConfig.tcProperties["tc.host"] = "ssh://user@10.0.0.5"
        let model = PublishedPortModel(url: "0.0.0.0", targetPort: 80, publishedPort: 9999, protocol_: "tcp")
        let result = model.normalize()
        #expect(result.url == "10.0.0.5")
        #expect(result.publishedPort == 9999)
    }

    @Test func normalizeSSH_replacesLoopback() {
        let saved = testcontainersConfig.tcProperties["tc.host"]
        defer {
            if let saved = saved {
                testcontainersConfig.tcProperties["tc.host"] = saved
            } else {
                testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
            }
        }
        testcontainersConfig.tcProperties["tc.host"] = "ssh://user@10.0.0.5"
        let model = PublishedPortModel(url: "127.0.0.1", targetPort: 80, publishedPort: 9999, protocol_: "tcp")
        let result = model.normalize()
        #expect(result.url == "10.0.0.5")
    }

    @Test func normalizeSSH_replacesIpv6Any() {
        let saved = testcontainersConfig.tcProperties["tc.host"]
        defer {
            if let saved = saved {
                testcontainersConfig.tcProperties["tc.host"] = saved
            } else {
                testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
            }
        }
        testcontainersConfig.tcProperties["tc.host"] = "ssh://user@10.0.0.5"
        let model = PublishedPortModel(url: "::", targetPort: 80, publishedPort: 9999, protocol_: "tcp")
        let result = model.normalize()
        #expect(result.url == "10.0.0.5")
    }

    @Test func normalizeNonSSH_keepsOriginal() {
        let saved = testcontainersConfig.tcProperties["tc.host"]
        defer {
            if let saved = saved {
                testcontainersConfig.tcProperties["tc.host"] = saved
            } else {
                testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
            }
        }
        testcontainersConfig.tcProperties["tc.host"] = "tcp://localhost:2375"
        let model = PublishedPortModel(url: "0.0.0.0", targetPort: 80, publishedPort: 9999, protocol_: "tcp")
        let result = model.normalize()
        #expect(result.url == "0.0.0.0")
    }

    @Test func publishedPortModelParsesAllFields() {
        let dict: [String: Any] = [
            "URL": "0.0.0.0",
            "TargetPort": 80,
            "PublishedPort": 32768,
            "Protocol": "tcp",
        ]
        let model = PublishedPortModel(from: dict)
        #expect(model.url == "0.0.0.0")
        #expect(model.targetPort == 80)
        #expect(model.publishedPort == 32768)
        #expect(model.protocol_ == "tcp")
    }

    @Test func publishedPortModelToleratesNullFields() {
        let model = PublishedPortModel(from: [:])
        #expect(model.url == nil)
        #expect(model.targetPort == nil)
        #expect(model.publishedPort == nil)
        #expect(model.protocol_ == nil)
    }

    @Test func normalizeReturnsSelfWhenNoChange() {
        let saved = testcontainersConfig.tcProperties["tc.host"]
        defer {
            if let saved = saved {
                testcontainersConfig.tcProperties["tc.host"] = saved
            } else {
                testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
            }
        }
        testcontainersConfig.tcProperties.removeValue(forKey: "tc.host")
        let model = PublishedPortModel(url: "10.0.0.1", targetPort: 80, publishedPort: 9999, protocol_: "tcp")
        let result = model.normalize()
        #expect(result.url == "10.0.0.1")
    }

    @Test func publisherThrowsNoSuchPortWhenNoneMatch() throws {
        let container = ComposeContainer(
            publishers: [
                PublishedPortModel(url: "0.0.0.0", targetPort: 80, publishedPort: 8080, protocol_: "tcp")
            ]
        )
        #expect(throws: NoSuchPortExposed.self) {
            _ = try container.publisher(byPort: 9999)
        }
    }

    @Test func publisherReturnsMatchingPublisher() throws {
        let container = ComposeContainer(
            publishers: [
                PublishedPortModel(url: "0.0.0.0", targetPort: 80, publishedPort: 8080, protocol_: "tcp")
            ]
        )
        let pub = try container.publisher(byPort: 80)
        #expect(pub.publishedPort == 8080)
    }

    @Test func composeContainerStatusIsStateOrUnknown() {
        let unknown = ComposeContainer()
        #expect(unknown.status == "unknown")
        let running = ComposeContainer(state: "running")
        #expect(running.status == "running")
    }

    @Test func composeContainerHostIpIs127001() async throws {
        let container = ComposeContainer()
        let ip = try await container.containerHostIp()
        #expect(ip == "127.0.0.1")
    }

    @Test func composeContainerExposedPortReturnsPassthrough() async throws {
        let container = ComposeContainer()
        let port = try await container.exposedPort(8080)
        #expect(port == 8080)
    }
}

// MARK: - Additional unit tests

@Suite("Compose additional unit tests", .serialized)
struct ComposeAdditionalUnitTests {

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
    // PublishedPortModel.normalize() non-SSH paths
    // -------------------------------------------------------------------------

    @Test func normalizeNonSSH_keepsTcpOriginal() {
        withTcHost("tcp://localhost:2375") {
            let model = PublishedPortModel(url: "0.0.0.0", targetPort: 80, publishedPort: 9999, protocol_: "tcp")
            let result = model.normalize()
            // TCP is not SSH — no rewrite expected.
            #expect(result.url == "0.0.0.0")
            #expect(result.publishedPort == 9999)
        }
    }

    @Test func normalizeReturnsSameInstanceWhenNoRewrite() {
        withTcHost(nil) {
            let model = PublishedPortModel(url: "192.168.1.1", targetPort: 80, publishedPort: 9999, protocol_: "tcp")
            let result = model.normalize()
            // No SSH host and not 0.0.0.0 on Windows — identical object expected.
            #expect(result.url == "192.168.1.1")
            #expect(result.publishedPort == 9999)
        }
    }

    @Test func normalizeSSH_replacesLocalhostUrl() {
        withTcHost("ssh://user@myhost.example.com") {
            let model = PublishedPortModel(url: "localhost", targetPort: 80, publishedPort: 9999, protocol_: "tcp")
            let result = model.normalize()
            #expect(result.url == "myhost.example.com")
            #expect(result.publishedPort == 9999)
        }
    }

    @Test func normalizeSSH_replacesIpv6Loopback() {
        withTcHost("ssh://user@myhost.example.com") {
            let model = PublishedPortModel(url: "::1", targetPort: 443, publishedPort: 8443, protocol_: "tcp")
            let result = model.normalize()
            #expect(result.url == "myhost.example.com")
            #expect(result.publishedPort == 8443)
        }
    }

    @Test func normalizeSSH_doesNotRewritePublicIp() {
        // A public IP is not in the loopback set — no rewrite.
        withTcHost("ssh://user@remote.example.com") {
            let model = PublishedPortModel(url: "203.0.113.5", targetPort: 80, publishedPort: 32770, protocol_: "tcp")
            let result = model.normalize()
            #expect(result.url == "203.0.113.5")
        }
    }

    @Test func normalizeSSH_returnsNewInstanceWhenRewritten() {
        withTcHost("ssh://user@myhost.example.com") {
            let model = PublishedPortModel(url: "0.0.0.0", targetPort: 80, publishedPort: 9999, protocol_: "tcp")
            let result = model.normalize()
            // URL was rewritten — result is a different instance with all other fields preserved.
            #expect(result.url == "myhost.example.com")
            #expect(result.targetPort == 80)
            #expect(result.publishedPort == 9999)
            #expect(result.protocol_ == "tcp")
        }
    }

    // -------------------------------------------------------------------------
    // PublishedPortModel with partial / nil fields
    // -------------------------------------------------------------------------

    @Test func publishedPortModelPartialFields() {
        let model = PublishedPortModel(url: "0.0.0.0")
        #expect(model.url == "0.0.0.0")
        #expect(model.targetPort == nil)
        #expect(model.publishedPort == nil)
        #expect(model.protocol_ == nil)
    }

    @Test func publishedPortModelAllNilFields() {
        let model = PublishedPortModel()
        #expect(model.url == nil)
        #expect(model.targetPort == nil)
        #expect(model.publishedPort == nil)
        #expect(model.protocol_ == nil)
    }

    @Test func publishedPortModelNormalizeWithNilUrl() {
        withTcHost("ssh://user@remote.example.com") {
            // Nil URL — none of the branch conditions match → returns self.
            let model = PublishedPortModel(targetPort: 80, publishedPort: 9999)
            let result = model.normalize()
            #expect(result.url == nil)
        }
    }

    // -------------------------------------------------------------------------
    // ComposeContainer.publisher(byHost:)
    // -------------------------------------------------------------------------

    @Test func publisherFiltersByHost() throws {
        let container = ComposeContainer(
            publishers: [
                PublishedPortModel(url: "0.0.0.0", targetPort: 80, publishedPort: 32768, protocol_: "tcp"),
                PublishedPortModel(url: "127.0.0.1", targetPort: 80, publishedPort: 32769, protocol_: "tcp"),
            ]
        )
        let pub = try container.publisher(byPort: 80, byHost: "127.0.0.1")
        #expect(pub.publishedPort == 32769)
    }

    @Test func publisherThrowsWhenByHostNoMatch() {
        let container = ComposeContainer(
            publishers: [
                PublishedPortModel(url: "0.0.0.0", targetPort: 80, publishedPort: 32768, protocol_: "tcp")
            ]
        )
        #expect(throws: NoSuchPortExposed.self) {
            _ = try container.publisher(byPort: 80, byHost: "192.168.1.1")
        }
    }

    @Test func publisherThrowsWhenAmbiguous() {
        // Two IPv4 publishers on the same target port — ambiguous.
        let container = ComposeContainer(
            publishers: [
                PublishedPortModel(url: "0.0.0.0", targetPort: 80, publishedPort: 32768, protocol_: "tcp"),
                PublishedPortModel(url: "127.0.0.1", targetPort: 80, publishedPort: 32769, protocol_: "tcp"),
            ]
        )
        #expect(throws: NoSuchPortExposed.self) {
            _ = try container.publisher(byPort: 80)
        }
    }

    // -------------------------------------------------------------------------
    // ComposeContainer.publisher(byPort:preferIpVersion:)
    // -------------------------------------------------------------------------

    @Test func publisherWithIpv4PreferenceFiltersIpv6() throws {
        // IPv6 url contains ':' — excluded when preferring IPv4.
        let container = ComposeContainer(
            publishers: [
                PublishedPortModel(url: "::", targetPort: 80, publishedPort: 32770, protocol_: "tcp"),
                PublishedPortModel(url: "0.0.0.0", targetPort: 80, publishedPort: 32768, protocol_: "tcp"),
            ]
        )
        let pub = try container.publisher(byPort: 80, preferIpVersion: .ipv4)
        #expect(pub.publishedPort == 32768)
    }

    @Test func publisherWithIpv6PreferenceFiltersIpv4() throws {
        let container = ComposeContainer(
            publishers: [
                PublishedPortModel(url: "::", targetPort: 80, publishedPort: 32770, protocol_: "tcp"),
                PublishedPortModel(url: "0.0.0.0", targetPort: 80, publishedPort: 32768, protocol_: "tcp"),
            ]
        )
        let pub = try container.publisher(byPort: 80, preferIpVersion: .ipv6)
        #expect(pub.publishedPort == 32770)
    }

    @Test func publisherWithNilUrlTreatedAsIpv4() throws {
        // Nil url: contains(":") returns false → treated as IPv4.
        let container = ComposeContainer(
            publishers: [
                PublishedPortModel(targetPort: 80, publishedPort: 32768, protocol_: "tcp")
            ]
        )
        let pub = try container.publisher(byPort: 80, preferIpVersion: .ipv4)
        #expect(pub.publishedPort == 32768)
    }

    @Test func publisherWithNilUrlExcludedForIpv6() {
        let container = ComposeContainer(
            publishers: [
                PublishedPortModel(targetPort: 80, publishedPort: 32768, protocol_: "tcp")
            ]
        )
        #expect(throws: NoSuchPortExposed.self) {
            _ = try container.publisher(byPort: 80, preferIpVersion: .ipv6)
        }
    }

    // -------------------------------------------------------------------------
    // DockerCompose constructor defaults
    // -------------------------------------------------------------------------

    @Test func dockerComposeDefaultsAreCorrect() {
        let dc = DockerCompose(context: "/tmp")
        #expect(dc.pull == false)
        #expect(dc.build == false)
        #expect(dc.wait == true)
        #expect(dc.keepVolumes == false)
        #expect(dc.quietPull == false)
        #expect(dc.quietBuild == false)
        #expect(dc.composeFileName == nil)
        #expect(dc.envFile == nil)
        #expect(dc.services == nil)
        #expect(dc.profiles == nil)
        #expect(dc.dockerCommandPath == nil)
    }

    @Test func dockerComposeStoresContext() {
        let dc = DockerCompose(context: "/my/project")
        #expect(dc.context == "/my/project")
    }

    // -------------------------------------------------------------------------
    // DockerCompose.waitingFor
    // -------------------------------------------------------------------------

    @Test func waitingForStoresStrategyAndReturnsSelf() {
        let dc = DockerCompose(context: "/tmp")
        let strategy = LogMessageWaitStrategy("ready")
        let result = dc.waitingFor(["web": strategy])
        // Fluent API — returns the same instance.
        #expect(result === dc)
    }

    @Test func waitingForEmptyMapReturnsSelf() {
        let dc = DockerCompose(context: "/tmp")
        let result = dc.waitingFor([:])
        #expect(result === dc)
    }

    // -------------------------------------------------------------------------
    // DockerCompose.composeCommandProperty
    // -------------------------------------------------------------------------

    @Test func composeCommandPropertyDefaultsToDockerCompose() {
        let dc = DockerCompose(context: "/tmp")
        #expect(dc.composeCommandProperty == ["docker", "compose"])
    }

    @Test func composeCommandPropertyUsesDockerCommandPath() {
        let dc = DockerCompose(context: "/tmp", dockerCommandPath: "/usr/local/bin/docker")
        #expect(dc.composeCommandProperty == ["/usr/local/bin/docker", "compose"])
    }

    @Test func composeCommandPropertyIncludesFileFlags() {
        let dc = DockerCompose(context: "/tmp", composeFileName: ["a.yaml", "b.yaml"])
        #expect(dc.composeCommandProperty == ["docker", "compose", "-f", "a.yaml", "-f", "b.yaml"])
    }

    @Test func composeCommandPropertyIncludesProfileFlags() {
        let dc = DockerCompose(context: "/tmp", profiles: ["debug", "metrics"])
        #expect(
            dc.composeCommandProperty
                == ["docker", "compose", "--profile", "debug", "--profile", "metrics"]
        )
    }

    @Test func composeCommandPropertyIncludesEnvFileFlags() {
        let dc = DockerCompose(context: "/tmp", envFile: [".env", ".env.local"])
        #expect(
            dc.composeCommandProperty
                == ["docker", "compose", "--env-file", ".env", "--env-file", ".env.local"]
        )
    }

    @Test func composeCommandPropertyFlagOrderIsCorrect() {
        // Order: -f … --profile … --env-file …
        let dc = DockerCompose(
            context: "/tmp",
            composeFileName: ["docker-compose.yaml"],
            envFile: [".env"],
            profiles: ["debug"]
        )
        #expect(
            dc.composeCommandProperty
                == ["docker", "compose", "-f", "docker-compose.yaml", "--profile", "debug", "--env-file", ".env"]
        )
    }

    @Test func composeCommandPropertyIsCachedAcrossAccesses() {
        let dc = DockerCompose(context: "/tmp", composeFileName: ["a.yaml"])
        // lazy var — computed once and returned on subsequent reads.
        let first = dc.composeCommandProperty
        let second = dc.composeCommandProperty
        #expect(first == second)
    }

    // -------------------------------------------------------------------------
    // IpVersion enum
    // -------------------------------------------------------------------------

    @Test func ipVersionEnumHasIpv4Case() {
        let v: IpVersion = .ipv4
        if case .ipv4 = v {
        } else {
            Issue.record("IpVersion.ipv4 case missing")
        }
    }

    @Test func ipVersionEnumHasIpv6Case() {
        let v: IpVersion = .ipv6
        if case .ipv6 = v {
        } else {
            Issue.record("IpVersion.ipv6 case missing")
        }
    }

    // -------------------------------------------------------------------------
    // ComposeContainer default constructor
    // -------------------------------------------------------------------------

    @Test func composeContainerDefaultConstructorLeavesAllNil() {
        let container = ComposeContainer()
        #expect(container.id == nil)
        #expect(container.name == nil)
        #expect(container.command == nil)
        #expect(container.project == nil)
        #expect(container.service == nil)
        #expect(container.state == nil)
        #expect(container.health == nil)
        #expect(container.exitCode == nil)
        #expect(container.publishers.isEmpty)
    }

    // -------------------------------------------------------------------------
    // ComposeContainer.from(dict:) parsing
    // -------------------------------------------------------------------------

    @Test func composeContainerFromDictParsesAllScalarFields() {
        let dict: [String: Any] = [
            "ID": "deadbeef",
            "Name": "myproject_web_1",
            "Command": "nginx -g daemon off;",
            "Project": "myproject",
            "Service": "web",
            "State": "running",
            "Health": "healthy",
            "ExitCode": 0,
        ]
        let c = ComposeContainer(from: dict)
        #expect(c.id == "deadbeef")
        #expect(c.name == "myproject_web_1")
        #expect(c.command == "nginx -g daemon off;")
        #expect(c.project == "myproject")
        #expect(c.service == "web")
        #expect(c.state == "running")
        #expect(c.health == "healthy")
        #expect(c.exitCode == 0)
    }

    @Test func composeContainerFromDictParsesPublishers() {
        let dict: [String: Any] = [
            "ID": "abc",
            "Service": "web",
            "State": "running",
            "Publishers": [
                ["URL": "0.0.0.0", "TargetPort": 80, "PublishedPort": 32768, "Protocol": "tcp"] as [String: Any]
            ],
        ]
        let c = ComposeContainer(from: dict)
        #expect(c.publishers.count == 1)
        #expect(c.publishers[0].targetPort == 80)
        #expect(c.publishers[0].publishedPort == 32768)
    }

    @Test func composeContainerFromDictToleratesMissingFields() {
        let c = ComposeContainer(from: [:])
        #expect(c.id == nil)
        #expect(c.service == nil)
        #expect(c.publishers.isEmpty)
    }

    // -------------------------------------------------------------------------
    // ComposeContainer.containerInfo returns nil without dockerCompose
    // -------------------------------------------------------------------------

    @Test func containerInfoReturnsNilWithIdButNoDockerCompose() async throws {
        let container = ComposeContainer(id: "abc123", service: "web")
        let info = try await container.containerInfo()
        #expect(info == nil)
    }

    @Test func containerInfoCalledTwiceReturnNilBothTimes() async throws {
        let container = ComposeContainer(id: "abc123")
        let first = try await container.containerInfo()
        let second = try await container.containerInfo()
        #expect(first == nil)
        #expect(second == nil)
    }

    // -------------------------------------------------------------------------
    // ComposeContainer.logs / exec throw without reference
    // -------------------------------------------------------------------------

    @Test func logsThrowsWithoutDockerComposeReference() async {
        let container = ComposeContainer(service: "web")
        do {
            _ = try await container.logs()
            Issue.record("Expected an error to be thrown")
        } catch {
            // Any error is acceptable here — the reference is missing.
        }
    }

    @Test func execThrowsWithoutDockerComposeReference() async {
        let container = ComposeContainer(service: "web")
        do {
            _ = try await container.exec(["echo", "hi"])
            Issue.record("Expected an error to be thrown")
        } catch {
            // Any error is acceptable here — the reference is missing.
        }
    }

    // -------------------------------------------------------------------------
    // ComposeContainer.reload is a no-op
    // -------------------------------------------------------------------------

    @Test func reloadCompletesWithoutError() async {
        let container = ComposeContainer(service: "web")
        await container.reload()
    }
}

// MARK: - Integration tests (require Docker)

@Suite("Compose integration tests", .serialized, .tags(.docker))
struct ComposeIntegrationTests {
    @Test func composeStop() async throws {
        let compose = DockerCompose(context: fixture("basic"))
        try await compose.start()
        try compose.stop()
    }

    @Test func composeStartStop() async throws {
        let compose = DockerCompose(context: fixture("basic"))
        try await compose.start()
        let allContainers = try compose.containers()
        #expect(!allContainers.isEmpty)
        try compose.stop()
    }

    @Test func startStopMultiple() async throws {
        let compose = DockerCompose(context: fixture("basic_multiple"))
        try await compose.start()
        let allContainers = try compose.containers()
        #expect(allContainers.count >= 2)
        try compose.stop()
    }

    @Test func composeE2E() async throws {
        try await DockerCompose.use(DockerCompose(context: fixture("basic"))) { _ in
        }
    }

    @Test func composeLogs() async throws {
        try await DockerCompose.use(DockerCompose(context: fixture("basic"))) { compose in
            let (stdout, stderr) = try compose.logs()
            #expect(!stdout.isEmpty || !stderr.isEmpty)
        }
    }

    @Test func composeVolumes() async throws {
        try await DockerCompose.use(
            DockerCompose(context: fixture("basic_volume"), keepVolumes: true)
        ) { _ in
        }
    }

    @Test func composePorts() async throws {
        try await DockerCompose.use(DockerCompose(context: fixture("port_single"))) { compose in
            let container = try compose.container()
            let pub = try container.publisher(byPort: 80)
            #expect(pub.publishedPort != nil)
            #expect(pub.publishedPort! > 0)
        }
    }

    @Test func composeMultiplePorts() async throws {
        try await DockerCompose.use(DockerCompose(context: fixture("port_multiple"))) { compose in
            let allContainers = try compose.containers()
            #expect(!allContainers.isEmpty)
        }
    }

    @Test func execInContainer() async throws {
        try await DockerCompose.use(DockerCompose(context: fixture("basic"))) { compose in
            let container = try compose.container()
            let svc = try #require(container.service)
            let (stdout, _, exitCode) = try compose.execInContainer(["echo", "hello"], serviceName: svc)
            #expect(exitCode == 0)
            #expect(stdout.contains("hello"))
        }
    }

    @Test func execInContainerMultiple() async throws {
        try await DockerCompose.use(DockerCompose(context: fixture("basic_multiple"))) { compose in
            let allContainers = try compose.containers()
            for container in allContainers {
                if let svc = container.service {
                    let (_, _, exitCode) = try compose.execInContainer(["true"], serviceName: svc)
                    #expect(exitCode == 0)
                }
            }
        }
    }

    @Test func composeConfig() async throws {
        for fixtureName in ["basic", "basic_multiple", "basic_volume", "port_single", "port_multiple"] {
            let compose = DockerCompose(context: fixture(fixtureName))
            try await compose.start()
            defer { try? compose.stop() }
            let cfg = try compose.config()
            #expect(!cfg.isEmpty)
        }
    }

    @Test func composeProfileSupport() async throws {
        for profile in ["profile1", "profile2"] {
            let compose = DockerCompose(
                context: fixture("profile_support"),
                profiles: [profile]
            )
            try await compose.start()
            let allContainers = try compose.containers()
            #expect(!allContainers.isEmpty)
            try compose.stop()
        }
    }

    @Test func containerInfo() async throws {
        try await DockerCompose.use(DockerCompose(context: fixture("basic"))) { compose in
            let container = try compose.container()
            let info = try await container.containerInfo()
            #expect(info != nil)
            #expect(info?.id != nil)
        }
    }

    @Test func containerInfoNetworkDetails() async throws {
        try await DockerCompose.use(DockerCompose(context: fixture("basic"))) { compose in
            let container = try compose.container()
            let info = try await container.containerInfo()
            let ns = info?.getNetworkSettings()
            #expect(ns != nil)
        }
    }
}

// MARK: - Tags

extension Tag {
    @Tag static var docker: Self
}
