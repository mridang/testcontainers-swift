import Testing
import Foundation
import TestcontainersCore
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

@Suite("Compose unit tests")
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
        let container = ComposeContainer()
        container.publishers = [
            PublishedPortModel(url: "0.0.0.0", targetPort: 80, publishedPort: 8080, protocol_: "tcp"),
        ]
        #expect(throws: NoSuchPortExposed.self) {
            _ = try container.publisher(byPort: 9999)
        }
    }

    @Test func publisherReturnsMatchingPublisher() throws {
        let container = ComposeContainer()
        container.publishers = [
            PublishedPortModel(url: "0.0.0.0", targetPort: 80, publishedPort: 8080, protocol_: "tcp"),
        ]
        let pub = try container.publisher(byPort: 80)
        #expect(pub.publishedPort == 8080)
    }

    @Test func composeContainerStatusIsStateOrUnknown() {
        let container = ComposeContainer()
        #expect(container.status == "unknown")
        container.state = "running"
        #expect(container.status == "running")
    }

    @Test func composeContainerHostIpIs127001() {
        let container = ComposeContainer()
        #expect(container.containerHostIp() == "127.0.0.1")
    }

    @Test func composeContainerExposedPortReturnsPassthrough() async throws {
        let container = ComposeContainer()
        let port = try await container.exposedPort(8080)
        #expect(port == 8080)
    }
}

// MARK: - Integration tests (require Docker)

@Suite("Compose integration tests", .tags(.docker))
struct ComposeIntegrationTests {
    @Test func composeStop() async throws {
        let compose = DockerCompose(context: fixture("basic"))
        try compose.start()
        try compose.stop()
    }

    @Test func composeStartStop() async throws {
        let compose = DockerCompose(context: fixture("basic"))
        try compose.start()
        let containers = try compose.getContainers()
        #expect(!containers.isEmpty)
        try compose.stop()
    }

    @Test func startStopMultiple() async throws {
        let compose = DockerCompose(context: fixture("basic_multiple"))
        try compose.start()
        let containers = try compose.getContainers()
        #expect(containers.count >= 2)
        try compose.stop()
    }

    @Test func composeE2E() async throws {
        try await DockerCompose.use(DockerCompose(context: fixture("basic"))) { _ in
        }
    }

    @Test func composeLogs() async throws {
        try await DockerCompose.use(DockerCompose(context: fixture("basic"))) { compose in
            let logs = try compose.getLogs()
            #expect(!logs.isEmpty)
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
            let containers = try compose.getContainers()
            #expect(!containers.isEmpty)
        }
    }

    @Test func execInContainer() async throws {
        try await DockerCompose.use(DockerCompose(context: fixture("basic"))) { compose in
            let container = try compose.container()
            let svc = try #require(container.service)
            let result = try compose.exec(serviceName: svc, command: ["echo", "hello"])
            #expect(result.exitCode == 0)
            #expect(result.output.contains("hello"))
        }
    }

    @Test func execInContainerMultiple() async throws {
        try await DockerCompose.use(DockerCompose(context: fixture("basic_multiple"))) { compose in
            let containers = try compose.getContainers()
            for container in containers {
                if let svc = container.service {
                    let result = try compose.exec(serviceName: svc, command: ["true"])
                    #expect(result.exitCode == 0)
                }
            }
        }
    }

    @Test func composeConfig() async throws {
        for fixtureName in ["basic", "basic_multiple", "basic_volume", "port_single", "port_multiple"] {
            let compose = DockerCompose(context: fixture(fixtureName))
            try compose.start()
            defer { try? compose.stop() }
            let config = try compose.getConfig()
            #expect(!config.isEmpty)
        }
    }

    @Test func composeProfileSupport() async throws {
        for profile in ["profile1", "profile2"] {
            let compose = DockerCompose(
                context: fixture("profile_support"),
                profiles: [profile]
            )
            try compose.start()
            let containers = try compose.getContainers()
            #expect(!containers.isEmpty)
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
