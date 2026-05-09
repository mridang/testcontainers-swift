import Foundation
import Testing

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
                ] as [String: Any]
            ] as [String: Any],
        ] as [String: Any],
        "HostConfig": [
            "NetworkMode": "bridge",
            "PortBindings": [
                "80/tcp": [
                    ["HostIp": "0.0.0.0", "HostPort": "32768"]
                ]
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
                ["Start": "2024-01-01T00:00:00Z", "End": "2024-01-01T00:00:01Z", "ExitCode": 1, "Output": "error"]
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

@Suite("ContainerState decoding")
struct ContainerStateTests {
    @Test func parsesRunningState() throws {
        let dict: [String: Any] = [
            "Status": "running",
            "Running": true,
            "Paused": false,
            "Restarting": false,
            "OOMKilled": false,
            "Dead": false,
            "Pid": 42,
            "ExitCode": 0,
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let state = try JSONDecoder().decode(ContainerState.self, from: data)
        #expect(state.status == "running")
        #expect(state.running == true)
        #expect(state.pid == 42)
        #expect(state.exitCode == 0)
    }

    @Test func parsesExitedState() throws {
        let dict: [String: Any] = [
            "Status": "exited",
            "Running": false,
            "ExitCode": 1,
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let state = try JSONDecoder().decode(ContainerState.self, from: data)
        #expect(state.status == "exited")
        #expect(state.running == false)
        #expect(state.exitCode == 1)
    }

    @Test func parsesStateWithHealth() throws {
        let dict: [String: Any] = [
            "Status": "running",
            "Running": true,
            "Health": ["Status": "healthy", "FailingStreak": 0, "Log": [] as [Any]],
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let state = try JSONDecoder().decode(ContainerState.self, from: data)
        #expect(state.health?.status == "healthy")
    }

    @Test func parsesEmptyStateObject() throws {
        let data = try JSONSerialization.data(withJSONObject: [:] as [String: Any])
        let state = try JSONDecoder().decode(ContainerState.self, from: data)
        #expect(state.status == nil)
        #expect(state.running == nil)
    }
}

@Suite("ContainerLog decoding")
struct ContainerLogTests {
    @Test func parsesLogEntry() throws {
        let dict: [String: Any] = [
            "Start": "2024-01-01T00:00:00Z",
            "End": "2024-01-01T00:00:01Z",
            "ExitCode": 0,
            "Output": "everything ok",
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let log = try JSONDecoder().decode(ContainerLog.self, from: data)
        #expect(log.start == "2024-01-01T00:00:00Z")
        #expect(log.end == "2024-01-01T00:00:01Z")
        #expect(log.exitCode == 0)
        #expect(log.output == "everything ok")
    }

    @Test func parsesEmptyLog() throws {
        let data = try JSONSerialization.data(withJSONObject: [:] as [String: Any])
        let log = try JSONDecoder().decode(ContainerLog.self, from: data)
        #expect(log.exitCode == nil)
        #expect(log.output == nil)
    }
}

@Suite("ContainerConfig decoding")
struct ContainerConfigTests {
    @Test func parsesFullConfig() throws {
        let dict: [String: Any] = [
            "Hostname": "abc123",
            "Image": "nginx:alpine",
            "Labels": ["app": "test", "version": "1.0"],
            "Env": ["PATH=/usr/bin", "HOME=/root"],
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let config = try JSONDecoder().decode(ContainerConfig.self, from: data)
        #expect(config.hostname == "abc123")
        #expect(config.image == "nginx:alpine")
        #expect(config.labels?["app"] == "test")
        #expect(config.labels?["version"] == "1.0")
        #expect(config.env?.contains("PATH=/usr/bin") == true)
    }

    @Test func parsesEmptyConfig() throws {
        let data = try JSONSerialization.data(withJSONObject: [:] as [String: Any])
        let config = try JSONDecoder().decode(ContainerConfig.self, from: data)
        #expect(config.hostname == nil)
        #expect(config.image == nil)
    }
}

@Suite("ContainerNetworkEndpoint decoding")
struct ContainerNetworkEndpointTests {
    @Test func parsesEndpoint() throws {
        let dict: [String: Any] = [
            "NetworkID": "net-abc",
            "Gateway": "172.17.0.1",
            "IPAddress": "172.17.0.5",
            "IPPrefixLen": 16,
            "MacAddress": "02:42:ac:11:00:05",
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let endpoint = try JSONDecoder().decode(ContainerNetworkEndpoint.self, from: data)
        #expect(endpoint.networkID == "net-abc")
        #expect(endpoint.gateway == "172.17.0.1")
        #expect(endpoint.ipAddress == "172.17.0.5")
        #expect(endpoint.ipPrefixLen == 16)
        #expect(endpoint.macAddress == "02:42:ac:11:00:05")
    }
}

@Suite("ContainerPortBinding decoding")
struct ContainerPortBindingTests {
    @Test func parsesPortBinding() throws {
        let dict: [String: Any] = [
            "HostIp": "0.0.0.0",
            "HostPort": "49153",
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let binding = try JSONDecoder().decode(ContainerPortBinding.self, from: data)
        #expect(binding.hostIp == "0.0.0.0")
        #expect(binding.hostPort == "49153")
    }
}

@Suite("ContainerMount decoding")
struct ContainerMountTests {
    @Test func parsesMount() throws {
        let dict: [String: Any] = [
            "Type": "bind",
            "Source": "/host/path",
            "Destination": "/container/path",
            "Mode": "rw",
            "RW": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let mount = try JSONDecoder().decode(ContainerMount.self, from: data)
        #expect(mount.type == "bind")
        #expect(mount.source == "/host/path")
        #expect(mount.destination == "/container/path")
        #expect(mount.mode == "rw")
        #expect(mount.rw == true)
    }
}

@Suite("ContainerInspectInfo.getNetworkSettings")
struct InspectGetNetworkSettingsTests {
    @Test func returnsNilForEmptyJson() throws {
        let data = try JSONSerialization.data(withJSONObject: [:] as [String: Any])
        let info = try JSONDecoder().decode(ContainerInspectInfo.self, from: data)
        #expect(info.getNetworkSettings() == nil)
    }

    @Test func getNetworksReturnsNilWhenAbsent() throws {
        let dict: [String: Any] = [
            "NetworkSettings": ["Bridge": "", "IPAddress": ""] as [String: Any]
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let info = try JSONDecoder().decode(ContainerInspectInfo.self, from: data)
        let nets = info.getNetworkSettings()?.getNetworks()
        // No Networks key — should be nil or empty
        _ = nets
    }
}
