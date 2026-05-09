import Testing
import Foundation
@testable import TestcontainersCore

@Suite("ContainerInspectInfo decoding")
struct InspectTests {
    let sampleJSON: [String: Any] = [
        "Id": "abc123def456",
        "Created": "2024-01-01T00:00:00Z",
        "Name": "/my-container",
        "Image": "sha256:deadbeef",
        "Platform": "linux",
        "State": [
            "Status": "running",
            "Running": true,
            "Paused": false,
            "Restarting": false,
            "OOMKilled": false,
            "Dead": false,
            "Pid": 1234,
            "ExitCode": 0,
            "Error": "",
            "StartedAt": "2024-01-01T00:00:01Z",
            "FinishedAt": "0001-01-01T00:00:00Z",
        ] as [String: Any],
        "Config": [
            "Hostname": "abc123de",
            "Image": "nginx:alpine",
            "Labels": ["app": "test"],
            "Env": ["PATH=/usr/local/sbin:/usr/local/bin"],
        ] as [String: Any],
        "NetworkSettings": [
            "Bridge": "",
            "IPAddress": "172.17.0.2",
            "Gateway": "172.17.0.1",
            "Networks": [
                "bridge": [
                    "NetworkID": "net123",
                    "Gateway": "172.17.0.1",
                    "IPAddress": "172.17.0.2",
                    "IPPrefixLen": 16,
                ] as [String: Any],
            ] as [String: Any],
        ] as [String: Any],
        "HostConfig": [
            "NetworkMode": "bridge",
            "PortBindings": [
                "80/tcp": [
                    ["HostIp": "0.0.0.0", "HostPort": "32768"],
                ],
            ] as [String: Any],
        ] as [String: Any],
        "Mounts": [] as [Any],
    ]

    private func decode(_ dict: [String: Any]) throws -> ContainerInspectInfo {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerInspectInfo.self, from: data)
    }

    @Test func parsesIdAndName() throws {
        let info = try decode(sampleJSON)
        #expect(info.id == "abc123def456")
        #expect(info.name == "/my-container")
    }

    @Test func parsesState() throws {
        let info = try decode(sampleJSON)
        #expect(info.state != nil)
        #expect(info.state?.status == "running")
        #expect(info.state?.running == true)
        #expect(info.state?.pid == 1234)
    }

    @Test func parsesConfig() throws {
        let info = try decode(sampleJSON)
        #expect(info.config != nil)
        #expect(info.config?.image == "nginx:alpine")
        #expect(info.config?.labels?["app"] == "test")
    }

    @Test func parsesNetworkSettings() throws {
        let info = try decode(sampleJSON)
        let ns = info.networkSettings
        #expect(ns != nil)
        let networks = ns?.getNetworks()
        #expect(networks != nil)
        #expect(networks?["bridge"] != nil)
        #expect(networks?["bridge"]?.ipAddress == "172.17.0.2")
        #expect(networks?["bridge"]?.gateway == "172.17.0.1")
        #expect(networks?["bridge"]?.networkID == "net123")
    }

    @Test func parsesHostConfigPortBindings() throws {
        let info = try decode(sampleJSON)
        #expect(info.hostConfig != nil)
        let bindings = info.hostConfig?.portBindings
        #expect(bindings != nil)
        #expect(bindings?["80/tcp"] != nil)
        // portBindings values are optional arrays: [String: [ContainerPortBinding]?]?
        let portList = bindings?["80/tcp"] as? [ContainerPortBinding]
        #expect(portList?.first?.hostPort == "32768")
    }

    @Test func survivesUnknownJsonKeys() throws {
        var json = sampleJSON
        json["UnknownField"] = "ignored"
        _ = try decode(json)
    }

    @Test func handlesMissingOptionalFields() throws {
        let info = try decode([:])
        #expect(info.id == nil)
        #expect(info.state == nil)
        #expect(info.config == nil)
    }

    @Test func getNetworkSettingsMethod() throws {
        let info = try decode(sampleJSON)
        #expect(info.getNetworkSettings() != nil)
    }
}

@Suite("ContainerHealth decoding")
struct ContainerHealthTests {
    @Test func parsesHealthStatus() throws {
        let dict: [String: Any] = [
            "Status": "healthy",
            "FailingStreak": 0,
            "Log": [] as [Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let health = try JSONDecoder().decode(ContainerHealth.self, from: data)
        #expect(health.status == "healthy")
        #expect(health.failingStreak == 0)
    }

    @Test func parsesUnhealthyStatus() throws {
        let dict: [String: Any] = [
            "Status": "unhealthy",
            "FailingStreak": 3,
            "Log": [
                ["Start": "2024-01-01T00:00:00Z", "End": "2024-01-01T00:00:01Z", "ExitCode": 1, "Output": "error"],
            ] as [Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let health = try JSONDecoder().decode(ContainerHealth.self, from: data)
        #expect(health.status == "unhealthy")
        #expect(health.failingStreak == 3)
        #expect(health.log?.count == 1)
        #expect(health.log?.first?.exitCode == 1)
    }
}
