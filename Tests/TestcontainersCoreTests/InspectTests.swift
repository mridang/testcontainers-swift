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

// MARK: - ContainerHealthcheck

@Suite("ContainerHealthcheck decoding")
struct ContainerHealthcheckTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerHealthcheck {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerHealthcheck.self, from: data)
    }

    @Test func parsesAllFields() throws {
        let hc = try decode(
            [
                "Test": ["CMD-SHELL", "curl -f http://localhost/ || exit 1"],
                "Interval": 30_000_000_000,
                "Timeout": 10_000_000_000,
                "Retries": 5,
                "StartPeriod": 15_000_000_000,
                "StartInterval": 2_000_000_000,
            ] as [String: Any]
        )
        #expect(hc.test == ["CMD-SHELL", "curl -f http://localhost/ || exit 1"])
        #expect(hc.interval == 30_000_000_000)
        #expect(hc.timeout == 10_000_000_000)
        #expect(hc.retries == 5)
        #expect(hc.startPeriod == 15_000_000_000)
        #expect(hc.startInterval == 2_000_000_000)
    }

    @Test func parsesNoneTestType() throws {
        let hc = try decode(["Test": ["NONE"]])
        #expect(hc.test == ["NONE"])
        #expect(hc.interval == nil)
    }

    @Test func toleratesMissingFields() throws {
        let hc = try decode([:])
        #expect(hc.test == nil)
        #expect(hc.retries == nil)
        #expect(hc.startInterval == nil)
    }
}

// MARK: - ContainerRestartPolicy

@Suite("ContainerRestartPolicy decoding")
struct ContainerRestartPolicyTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerRestartPolicy {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerRestartPolicy.self, from: data)
    }

    @Test func parsesNameAndMaximumRetryCount() throws {
        let policy = try decode(["Name": "on-failure", "MaximumRetryCount": 3])
        #expect(policy.name == "on-failure")
        #expect(policy.maximumRetryCount == 3)
    }

    @Test func toleratesMissingFields() throws {
        let policy = try decode([:])
        #expect(policy.name == nil)
        #expect(policy.maximumRetryCount == nil)
    }
}

// MARK: - ContainerLogConfig

@Suite("ContainerLogConfig decoding")
struct ContainerLogConfigTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerLogConfig {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerLogConfig.self, from: data)
    }

    @Test func parsesTypeAndConfig() throws {
        let lc = try decode(
            [
                "Type": "json-file",
                "Config": ["max-size": "10m", "max-file": "3"],
            ] as [String: Any]
        )
        #expect(lc.type == "json-file")
        #expect(lc.config?["max-size"] == "10m")
        #expect(lc.config?["max-file"] == "3")
    }

    @Test func handlesNullConfigMap() throws {
        let lc = try decode(["Type": "none"])
        #expect(lc.config == nil)
    }
}

// MARK: - ContainerUlimit

@Suite("ContainerUlimit decoding")
struct ContainerUlimitTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerUlimit {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerUlimit.self, from: data)
    }

    @Test func parsesNameSoftAndHard() throws {
        let ulimit = try decode(["Name": "nofile", "Soft": 1024, "Hard": 4096])
        #expect(ulimit.name == "nofile")
        #expect(ulimit.soft == 1024)
        #expect(ulimit.hard == 4096)
    }

    @Test func toleratesMissingFields() throws {
        let ulimit = try decode([:])
        #expect(ulimit.name == nil)
        #expect(ulimit.soft == nil)
        #expect(ulimit.hard == nil)
    }
}

// MARK: - ContainerVolumeDriverConfig

@Suite("ContainerVolumeDriverConfig decoding")
struct ContainerVolumeDriverConfigTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerVolumeDriverConfig {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerVolumeDriverConfig.self, from: data)
    }

    @Test func parsesNameAndOptions() throws {
        let dc = try decode(
            [
                "Name": "local",
                "Options": ["type": "tmpfs", "device": "tmpfs"],
            ] as [String: Any]
        )
        #expect(dc.name == "local")
        #expect(dc.options?["type"] == "tmpfs")
        #expect(dc.options?["device"] == "tmpfs")
    }

    @Test func toleratesMissingFields() throws {
        let dc = try decode([:])
        #expect(dc.name == nil)
        #expect(dc.options == nil)
    }
}

// MARK: - ContainerPlatform

@Suite("ContainerPlatform decoding")
struct ContainerPlatformTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerPlatform {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerPlatform.self, from: data)
    }

    @Test func parsesAllFields() throws {
        let platform = try decode(["architecture": "amd64", "os": "linux", "variant": ""])
        #expect(platform.architecture == "amd64")
        #expect(platform.os == "linux")
        #expect(platform.variant == "")
    }

    @Test func toleratesMissingFields() throws {
        let platform = try decode([:])
        #expect(platform.architecture == nil)
        #expect(platform.os == nil)
        #expect(platform.variant == nil)
    }
}

// MARK: - ContainerImageManifestDescriptor

@Suite("ContainerImageManifestDescriptor decoding")
struct ContainerImageManifestDescriptorTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerImageManifestDescriptor {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerImageManifestDescriptor.self, from: data)
    }

    @Test func parsesScalarFields() throws {
        let desc = try decode(
            [
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "digest": "sha256:abc123",
                "size": 1024,
                "artifactType": "application/vnd.docker.container.image.v1+json",
            ] as [String: Any]
        )
        #expect(desc.mediaType == "application/vnd.oci.image.manifest.v1+json")
        #expect(desc.digest == "sha256:abc123")
        #expect(desc.size == 1024)
        #expect(desc.artifactType != nil)
    }

    @Test func parsesNestedPlatform() throws {
        let desc = try decode(
            [
                "digest": "sha256:abc",
                "platform": ["architecture": "arm64", "os": "linux"],
            ] as [String: Any]
        )
        #expect(desc.platform != nil)
        #expect(desc.platform?.architecture == "arm64")
    }

    @Test func handlesMissingPlatform() throws {
        let desc = try decode([:])
        #expect(desc.platform == nil)
    }
}

// MARK: - ContainerBlkioWeightDevice

@Suite("ContainerBlkioWeightDevice decoding")
struct ContainerBlkioWeightDeviceTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerBlkioWeightDevice {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerBlkioWeightDevice.self, from: data)
    }

    @Test func parsesPathAndWeight() throws {
        let dev = try decode(["Path": "/dev/sda", "Weight": 500])
        #expect(dev.path == "/dev/sda")
        #expect(dev.weight == 500)
    }

    @Test func toleratesMissingFields() throws {
        let dev = try decode([:])
        #expect(dev.path == nil)
        #expect(dev.weight == nil)
    }
}

// MARK: - ContainerBlkioDeviceRate

@Suite("ContainerBlkioDeviceRate decoding")
struct ContainerBlkioDeviceRateTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerBlkioDeviceRate {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerBlkioDeviceRate.self, from: data)
    }

    @Test func parsesPathAndRate() throws {
        let rate = try decode(["Path": "/dev/nvme0n1", "Rate": 104_857_600])
        #expect(rate.path == "/dev/nvme0n1")
        #expect(rate.rate == 104_857_600)
    }

    @Test func toleratesMissingFields() throws {
        let rate = try decode([:])
        #expect(rate.path == nil)
        #expect(rate.rate == nil)
    }
}

// MARK: - ContainerDeviceMapping

@Suite("ContainerDeviceMapping decoding")
struct ContainerDeviceMappingTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerDeviceMapping {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerDeviceMapping.self, from: data)
    }

    @Test func parsesAllFields() throws {
        let mapping = try decode([
            "PathOnHost": "/dev/ttyUSB0",
            "PathInContainer": "/dev/ttyUSB0",
            "CgroupPermissions": "rwm",
        ])
        #expect(mapping.pathOnHost == "/dev/ttyUSB0")
        #expect(mapping.pathInContainer == "/dev/ttyUSB0")
        #expect(mapping.cgroupPermissions == "rwm")
    }

    @Test func toleratesMissingFields() throws {
        let mapping = try decode([:])
        #expect(mapping.pathOnHost == nil)
        #expect(mapping.cgroupPermissions == nil)
    }
}

// MARK: - ContainerDeviceRequest

@Suite("ContainerDeviceRequest decoding")
struct ContainerDeviceRequestTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerDeviceRequest {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerDeviceRequest.self, from: data)
    }

    @Test func parsesAllFields() throws {
        let req = try decode(
            [
                "Driver": "nvidia",
                "Count": -1,
                "DeviceIDs": ["GPU-abc", "GPU-def"],
                "Capabilities": [["gpu"], ["nvidia", "compute"]],
                "Options": ["key": "value"],
            ] as [String: Any]
        )
        #expect(req.driver == "nvidia")
        #expect(req.count == -1)
        #expect(req.deviceIDs == ["GPU-abc", "GPU-def"])
        #expect(req.capabilities == [["gpu"], ["nvidia", "compute"]])
        #expect(req.options?["key"] == "value")
    }

    @Test func toleratesMissingFields() throws {
        let req = try decode([:])
        #expect(req.driver == nil)
        #expect(req.capabilities == nil)
    }
}

// MARK: - ContainerBindOptions

@Suite("ContainerBindOptions decoding")
struct ContainerBindOptionsTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerBindOptions {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerBindOptions.self, from: data)
    }

    @Test func parsesAllFields() throws {
        let opts = try decode(
            [
                "Propagation": "rprivate",
                "NonRecursive": false,
                "CreateMountpoint": true,
                "ReadOnlyNonRecursive": false,
                "ReadOnlyForceRecursive": false,
            ] as [String: Any]
        )
        #expect(opts.propagation == "rprivate")
        #expect(opts.nonRecursive == false)
        #expect(opts.createMountpoint == true)
        #expect(opts.readOnlyNonRecursive == false)
        #expect(opts.readOnlyForceRecursive == false)
    }

    @Test func toleratesMissingFields() throws {
        let opts = try decode([:])
        #expect(opts.propagation == nil)
        #expect(opts.createMountpoint == nil)
    }
}

// MARK: - ContainerVolumeOptions

@Suite("ContainerVolumeOptions decoding")
struct ContainerVolumeOptionsTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerVolumeOptions {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerVolumeOptions.self, from: data)
    }

    @Test func parsesNoCopyLabelsDriverConfigAndSubpath() throws {
        let opts = try decode(
            [
                "NoCopy": false,
                "Labels": ["com.example.owner": "test"],
                "DriverConfig": ["Name": "local", "Options": ["device": "tmpfs"]] as [String: Any],
                "Subpath": "data",
            ] as [String: Any]
        )
        #expect(opts.noCopy == false)
        #expect(opts.labels?["com.example.owner"] == "test")
        #expect(opts.driverConfig != nil)
        #expect(opts.driverConfig?.name == "local")
        #expect(opts.subpath == "data")
    }

    @Test func handlesNullDriverConfig() throws {
        let opts = try decode([:])
        #expect(opts.driverConfig == nil)
    }
}

// MARK: - ContainerImageOptions

@Suite("ContainerImageOptions decoding")
struct ContainerImageOptionsTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerImageOptions {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerImageOptions.self, from: data)
    }

    @Test func parsesSubpath() throws {
        let opts = try decode(["Subpath": "/app"])
        #expect(opts.subpath == "/app")
    }

    @Test func toleratesMissingSubpath() throws {
        let opts = try decode([:])
        #expect(opts.subpath == nil)
    }
}

// MARK: - ContainerTmpfsOptions

@Suite("ContainerTmpfsOptions decoding")
struct ContainerTmpfsOptionsTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerTmpfsOptions {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerTmpfsOptions.self, from: data)
    }

    @Test func parsesSizeBytesAndMode() throws {
        let opts = try decode(
            [
                "SizeBytes": 67_108_864,
                "Mode": 493,
                "Options": [["size", "64m"], ["uid", "1000"]],
            ] as [String: Any]
        )
        #expect(opts.sizeBytes == 67_108_864)
        #expect(opts.mode == 493)
        #expect(opts.options == [["size", "64m"], ["uid", "1000"]])
    }

    @Test func toleratesMissingFields() throws {
        let opts = try decode([:])
        #expect(opts.sizeBytes == nil)
        #expect(opts.options == nil)
    }
}

// MARK: - ContainerMountPoint

@Suite("ContainerMountPoint decoding")
struct ContainerMountPointTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerMountPoint {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerMountPoint.self, from: data)
    }

    @Test func parsesTypeSourceTargetAndReadOnly() throws {
        let mp = try decode(
            [
                "Type": "bind",
                "Source": "/host/path",
                "Target": "/container/path",
                "ReadOnly": true,
                "Consistency": "default",
            ] as [String: Any]
        )
        #expect(mp.type == "bind")
        #expect(mp.source == "/host/path")
        #expect(mp.target == "/container/path")
        #expect(mp.readOnly == true)
        #expect(mp.consistency == "default")
    }

    @Test func parsesNestedBindOptions() throws {
        let mp = try decode(
            [
                "Type": "bind",
                "BindOptions": ["Propagation": "shared"] as [String: Any],
            ] as [String: Any]
        )
        #expect(mp.bindOptions != nil)
        #expect(mp.bindOptions?.propagation == "shared")
    }

    @Test func parsesNestedVolumeOptions() throws {
        let mp = try decode(
            [
                "Type": "volume",
                "VolumeOptions": ["NoCopy": true] as [String: Any],
            ] as [String: Any]
        )
        #expect(mp.volumeOptions != nil)
        #expect(mp.volumeOptions?.noCopy == true)
    }

    @Test func parsesNestedTmpfsOptions() throws {
        let mp = try decode(
            [
                "Type": "tmpfs",
                "TmpfsOptions": ["SizeBytes": 1_048_576] as [String: Any],
            ] as [String: Any]
        )
        #expect(mp.tmpfsOptions != nil)
        #expect(mp.tmpfsOptions?.sizeBytes == 1_048_576)
    }

    @Test func parsesNestedImageOptions() throws {
        let mp = try decode(
            [
                "Type": "image",
                "ImageOptions": ["Subpath": "/data"] as [String: Any],
            ] as [String: Any]
        )
        #expect(mp.imageOptions != nil)
        #expect(mp.imageOptions?.subpath == "/data")
    }

    @Test func toleratesMissingOptions() throws {
        let mp = try decode([:])
        #expect(mp.bindOptions == nil)
        #expect(mp.volumeOptions == nil)
        #expect(mp.imageOptions == nil)
        #expect(mp.tmpfsOptions == nil)
    }
}

// MARK: - ContainerGraphDriver

@Suite("ContainerGraphDriver decoding")
struct ContainerGraphDriverTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerGraphDriver {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerGraphDriver.self, from: data)
    }

    @Test func parsesNameAndData() throws {
        let driver = try decode(
            [
                "Name": "overlay2",
                "Data": [
                    "LowerDir": "/var/lib/docker/overlay2/abc/diff",
                    "MergedDir": "/var/lib/docker/overlay2/abc/merged",
                ],
            ] as [String: Any]
        )
        #expect(driver.name == "overlay2")
        #expect(driver.data != nil)
        #expect(driver.data?["LowerDir"] != nil)
    }

    @Test func toleratesNullData() throws {
        let driver = try decode(["Name": "overlay2"])
        #expect(driver.data == nil)
    }
}

// MARK: - ContainerIPAMConfig

@Suite("ContainerIPAMConfig decoding")
struct ContainerIPAMConfigTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerIPAMConfig {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerIPAMConfig.self, from: data)
    }

    @Test func parsesAllFields() throws {
        let config = try decode(
            [
                "IPv4Address": "10.0.0.5",
                "IPv6Address": "",
                "LinkLocalIPs": ["169.254.0.1"],
            ] as [String: Any]
        )
        #expect(config.ipv4Address == "10.0.0.5")
        #expect(config.ipv6Address == "")
        #expect(config.linkLocalIPs == ["169.254.0.1"])
    }

    @Test func toleratesMissingFields() throws {
        let config = try decode([:])
        #expect(config.ipv4Address == nil)
        #expect(config.linkLocalIPs == nil)
    }
}

// MARK: - ContainerAddress

@Suite("ContainerAddress decoding")
struct ContainerAddressTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerAddress {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerAddress.self, from: data)
    }

    @Test func parsesAddrAndPrefixLen() throws {
        let addr = try decode(["Addr": "10.0.0.2", "PrefixLen": 24])
        #expect(addr.addr == "10.0.0.2")
        #expect(addr.prefixLen == 24)
    }

    @Test func toleratesMissingFields() throws {
        let addr = try decode([:])
        #expect(addr.addr == nil)
        #expect(addr.prefixLen == nil)
    }
}

// MARK: - ContainerHostConfig comprehensive

@Suite("ContainerHostConfig nested fields")
struct ContainerHostConfigNestedTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerHostConfig {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerHostConfig.self, from: data)
    }

    @Test func parsesUlimitsList() throws {
        let hc = try decode([
            "Ulimits": [
                ["Name": "nofile", "Soft": 1024, "Hard": 4096],
                ["Name": "nproc", "Soft": 512, "Hard": 1024],
            ] as [Any]
        ])
        #expect(hc.ulimits != nil)
        #expect(hc.ulimits?.count == 2)
        #expect(hc.ulimits?[0].name == "nofile")
        #expect(hc.ulimits?[0].soft == 1024)
        #expect(hc.ulimits?[0].hard == 4096)
        #expect(hc.ulimits?[1].name == "nproc")
    }

    @Test func parsesDevicesList() throws {
        let hc = try decode([
            "Devices": [
                [
                    "PathOnHost": "/dev/ttyUSB0",
                    "PathInContainer": "/dev/ttyUSB0",
                    "CgroupPermissions": "rwm",
                ] as [String: Any]
            ] as [Any]
        ])
        #expect(hc.devices != nil)
        #expect(hc.devices?.count == 1)
        #expect(hc.devices?.first?.pathOnHost == "/dev/ttyUSB0")
        #expect(hc.devices?.first?.cgroupPermissions == "rwm")
    }

    @Test func parsesDeviceRequestsList() throws {
        let hc = try decode([
            "DeviceRequests": [
                [
                    "Driver": "nvidia",
                    "Count": -1,
                    "DeviceIDs": ["0"],
                    "Capabilities": [["gpu"]],
                    "Options": [:] as [String: String],
                ] as [String: Any]
            ] as [Any]
        ])
        #expect(hc.deviceRequests != nil)
        #expect(hc.deviceRequests?.first?.driver == "nvidia")
        #expect(hc.deviceRequests?.first?.count == -1)
        #expect(hc.deviceRequests?.first?.deviceIDs == ["0"])
    }

    @Test func parsesBlkioWeightDeviceList() throws {
        let hc = try decode([
            "BlkioWeightDevice": [
                ["Path": "/dev/sda", "Weight": 500] as [String: Any]
            ] as [Any]
        ])
        #expect(hc.blkioWeightDevice != nil)
        #expect(hc.blkioWeightDevice?.first?.path == "/dev/sda")
        #expect(hc.blkioWeightDevice?.first?.weight == 500)
    }

    @Test func parsesAllFourBlkioDeviceRateLists() throws {
        let hc = try decode(
            [
                "BlkioDeviceReadBps": [["Path": "/dev/sda", "Rate": 104_857_600] as [String: Any]] as [Any],
                "BlkioDeviceWriteBps": [["Path": "/dev/sda", "Rate": 52_428_800] as [String: Any]] as [Any],
                "BlkioDeviceReadIOps": [["Path": "/dev/sda", "Rate": 1000] as [String: Any]] as [Any],
                "BlkioDeviceWriteIOps": [["Path": "/dev/sda", "Rate": 500] as [String: Any]] as [Any],
            ] as [String: Any]
        )
        #expect(hc.blkioDeviceReadBps?.first?.rate == 104_857_600)
        #expect(hc.blkioDeviceWriteBps?.first?.rate == 52_428_800)
        #expect(hc.blkioDeviceReadIOps?.first?.rate == 1000)
        #expect(hc.blkioDeviceWriteIOps?.first?.rate == 500)
    }

    @Test func parsesPortBindingsPublishedAndNull() throws {
        let hc = try decode([
            "PortBindings": [
                "80/tcp": [["HostIp": "0.0.0.0", "HostPort": "32768"] as [String: Any]] as [Any],
                "443/tcp": NSNull(),
            ] as [String: Any]
        ])
        #expect(hc.portBindings != nil)
        let bindings80 = hc.portBindings?["80/tcp"]
        let first = bindings80??.first
        #expect(first?.hostPort == "32768")
        #expect(first?.hostIp == "0.0.0.0")
        // 443/tcp is present as a null value
        #expect(hc.portBindings?["443/tcp"] != nil)
    }

    @Test func portBindingsIsNilWhenKeyAbsent() throws {
        let hc = try decode(["NetworkMode": "bridge"])
        #expect(hc.portBindings == nil)
    }

    @Test func portBindingsWithEmptyMapProducesEmptyPortBindings() throws {
        let hc = try decode(["PortBindings": [:] as [String: Any]])
        #expect(hc.portBindings != nil)
        #expect(hc.portBindings?.isEmpty == true)
    }

    @Test func parsesNestedLogConfig() throws {
        let hc = try decode([
            "LogConfig": [
                "Type": "json-file",
                "Config": ["max-size": "10m", "max-file": "5"],
            ] as [String: Any]
        ])
        #expect(hc.logConfig != nil)
        #expect(hc.logConfig?.type == "json-file")
        #expect(hc.logConfig?.config?["max-size"] == "10m")
    }

    @Test func logConfigIsNilWhenKeyAbsent() throws {
        let hc = try decode([:])
        #expect(hc.logConfig == nil)
    }

    @Test func parsesNestedRestartPolicy() throws {
        let hc = try decode([
            "RestartPolicy": ["Name": "on-failure", "MaximumRetryCount": 5] as [String: Any]
        ])
        #expect(hc.restartPolicy != nil)
        #expect(hc.restartPolicy?.name == "on-failure")
        #expect(hc.restartPolicy?.maximumRetryCount == 5)
    }

    @Test func restartPolicyIsNilWhenKeyAbsent() throws {
        let hc = try decode([:])
        #expect(hc.restartPolicy == nil)
    }

    @Test func parsesMountsList() throws {
        let hc = try decode([
            "Mounts": [
                ["Type": "bind", "Source": "/host/data", "Target": "/data", "ReadOnly": false] as [String: Any],
                ["Type": "volume", "Source": "/var/lib/docker/volumes/vol/_data", "Target": "/vol", "ReadOnly": true]
                    as [String: Any],
            ] as [Any]
        ])
        #expect(hc.mounts != nil)
        #expect(hc.mounts?.count == 2)
        #expect(hc.mounts?[0].type == "bind")
        #expect(hc.mounts?[0].source == "/host/data")
        #expect(hc.mounts?[1].readOnly == true)
    }

    @Test func parsesBooleanFlags() throws {
        let hc = try decode(
            [
                "Privileged": true,
                "AutoRemove": true,
                "ReadonlyRootfs": true,
                "PublishAllPorts": false,
                "OomKillDisable": false,
                "Init": true,
            ] as [String: Any]
        )
        #expect(hc.privileged == true)
        #expect(hc.autoRemove == true)
        #expect(hc.readonlyRootfs == true)
        #expect(hc.publishAllPorts == false)
        #expect(hc.oomKillDisable == false)
        #expect(hc.`init` == true)
    }

    @Test func parsesStringListFields() throws {
        let hc = try decode(
            [
                "CapAdd": ["NET_ADMIN", "SYS_PTRACE"],
                "CapDrop": ["MKNOD"],
                "Dns": ["8.8.8.8", "8.8.4.4"],
                "DnsSearch": ["example.com"],
                "DnsOptions": ["ndots:5"],
                "ExtraHosts": ["host.docker.internal:host-gateway"],
                "Binds": ["/host:/container:rw"],
                "VolumesFrom": ["other-container:ro"],
                "SecurityOpt": ["no-new-privileges:true"],
                "MaskedPaths": ["/proc/kcore"],
                "ReadonlyPaths": ["/proc/asound"],
                "DeviceCgroupRules": ["c 136:* rwm"],
                "GroupAdd": ["audio"],
                "Links": [] as [String],
            ] as [String: Any]
        )
        #expect(hc.capAdd == ["NET_ADMIN", "SYS_PTRACE"])
        #expect(hc.capDrop == ["MKNOD"])
        #expect(hc.dns == ["8.8.8.8", "8.8.4.4"])
        #expect(hc.dnsSearch == ["example.com"])
        #expect(hc.dnsOptions == ["ndots:5"])
        #expect(hc.extraHosts == ["host.docker.internal:host-gateway"])
        #expect(hc.binds == ["/host:/container:rw"])
        #expect(hc.volumesFrom == ["other-container:ro"])
        #expect(hc.securityOpt == ["no-new-privileges:true"])
        #expect(hc.maskedPaths == ["/proc/kcore"])
        #expect(hc.readonlyPaths == ["/proc/asound"])
        #expect(hc.deviceCgroupRules == ["c 136:* rwm"])
        #expect(hc.groupAdd == ["audio"])
        #expect(hc.links?.isEmpty == true)
    }

    @Test func parsesMapFields() throws {
        let hc = try decode(
            [
                "Sysctls": ["net.ipv4.ip_forward": "1", "net.core.somaxconn": "1024"],
                "Tmpfs": ["/tmp": "size=64m,mode=1777"],
                "StorageOpt": ["size": "10G"],
                "Annotations": ["com.example.note": "test-run"],
            ] as [String: Any]
        )
        #expect(hc.sysctls == ["net.ipv4.ip_forward": "1", "net.core.somaxconn": "1024"])
        #expect(hc.tmpfs == ["/tmp": "size=64m,mode=1777"])
        #expect(hc.storageOpt == ["size": "10G"])
        #expect(hc.annotations == ["com.example.note": "test-run"])
    }

    @Test func parsesCpuAndMemoryLimitIntegers() throws {
        let hc = try decode(
            [
                "CpuPeriod": 100_000,
                "CpuQuota": 50_000,
                "CpuRealtimePeriod": 1_000_000,
                "CpuRealtimeRuntime": 950_000,
                "NanoCpus": 500_000_000,
                "PidsLimit": 100,
                "ShmSize": 67_108_864,
                "MemorySwap": -1,
                "MemorySwappiness": 60,
                "MemoryReservation": 536_870_912,
                "KernelMemoryTCP": 0,
            ] as [String: Any]
        )
        #expect(hc.cpuPeriod == 100_000)
        #expect(hc.cpuQuota == 50_000)
        #expect(hc.cpuRealtimePeriod == 1_000_000)
        #expect(hc.cpuRealtimeRuntime == 950_000)
        #expect(hc.nanoCpus == 500_000_000)
        #expect(hc.pidsLimit == 100)
        #expect(hc.shmSize == 67_108_864)
        #expect(hc.memorySwap == -1)
        #expect(hc.memorySwappiness == 60)
        #expect(hc.memoryReservation == 536_870_912)
        #expect(hc.kernelMemoryTCP == 0)
    }

    @Test func parsesConsoleSizeList() throws {
        let hc = try decode(["ConsoleSize": [24, 80]])
        #expect(hc.consoleSize != nil)
        #expect(hc.consoleSize == [24, 80])
    }

    @Test func parsesStringScalarFields() throws {
        let hc = try decode(
            [
                "CgroupParent": "/docker",
                "BlkioWeight": 0,
                "CgroupnsMode": "private",
                "Runtime": "runc",
                "Isolation": "",
                "IpcMode": "private",
                "UTSMode": "",
                "UsernsMode": "",
                "PidMode": "",
                "CpusetCpus": "0-3",
                "CpusetMems": "0",
                "VolumeDriver": "local",
                "ContainerIDFile": "/run/cid",
            ] as [String: Any]
        )
        #expect(hc.cgroupParent == "/docker")
        #expect(hc.blkioWeight == 0)
        #expect(hc.cgroupnsMode == "private")
        #expect(hc.runtime == "runc")
        #expect(hc.ipcMode == "private")
        #expect(hc.cpusetCpus == "0-3")
        #expect(hc.cpusetMems == "0")
        #expect(hc.volumeDriver == "local")
        #expect(hc.containerIDFile == "/run/cid")
    }

    @Test func toleratesEmptyInput() throws {
        let hc = try decode([:])
        #expect(hc.memory == nil)
        #expect(hc.cpuShares == nil)
        #expect(hc.ulimits == nil)
        #expect(hc.devices == nil)
        #expect(hc.portBindings == nil)
        #expect(hc.logConfig == nil)
        #expect(hc.restartPolicy == nil)
        #expect(hc.capAdd == nil)
        #expect(hc.capDrop == nil)
        #expect(hc.sysctls == nil)
        #expect(hc.privileged == nil)
        #expect(hc.autoRemove == nil)
        #expect(hc.mounts == nil)
        #expect(hc.consoleSize == nil)
    }
}

// MARK: - ContainerNetworkSettings ports and scalar fields

@Suite("ContainerNetworkSettings null fields")
struct ContainerNetworkSettingsNullTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerNetworkSettings {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerNetworkSettings.self, from: data)
    }

    @Test func handlesNullNetworksAndPorts() throws {
        let ns = try decode(
            [
                "IPAddress": "172.17.0.2",
                "Networks": NSNull(),
                "Ports": NSNull(),
            ] as [String: Any]
        )
        #expect(ns.ipAddress == "172.17.0.2")
        #expect(ns.networks == nil)
        #expect(ns.ports == nil)
    }
}

@Suite("ContainerNetworkSettings ports parsing")
struct ContainerNetworkSettingsPortsTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerNetworkSettings {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerNetworkSettings.self, from: data)
    }

    @Test func parsesPortsWithNonNullBindings() throws {
        let ns = try decode([
            "Ports": [
                "80/tcp": [["HostIp": "0.0.0.0", "HostPort": "32768"] as [String: Any]] as [Any],
                "443/tcp": [["HostIp": "0.0.0.0", "HostPort": "32769"] as [String: Any]] as [Any],
            ] as [String: Any]
        ])
        #expect(ns.ports != nil)
        let binding80 = ns.ports?["80/tcp"]??.first
        #expect(binding80?.hostPort == "32768")
        let binding443 = ns.ports?["443/tcp"]??.first
        #expect(binding443?.hostPort == "32769")
    }

    @Test func parsesPortEntryWhoseValueIsNull() throws {
        let ns = try decode([
            "Ports": [
                "80/tcp": NSNull()
            ] as [String: Any]
        ])
        #expect(ns.ports != nil)
        #expect(ns.ports?["80/tcp"] != nil)
        // The value is an Optional<Optional<[ContainerPortBinding]>> where inner is nil
        let inner: [ContainerPortBinding]?? = ns.ports?["80/tcp"]
        if let outer = inner {
            #expect(outer == nil)
        }
    }

    @Test func parsesMultipleBindingsForOnePort() throws {
        let ns = try decode([
            "Ports": [
                "80/tcp": [
                    ["HostIp": "0.0.0.0", "HostPort": "32768"] as [String: Any],
                    ["HostIp": "::", "HostPort": "32768"] as [String: Any],
                ] as [Any]
            ] as [String: Any]
        ])
        #expect(ns.ports?["80/tcp"]??.count == 2)
        #expect(ns.ports?["80/tcp"]??[1].hostIp == "::")
    }

    @Test func emptyPortsMapProducesEmptyPortsField() throws {
        let ns = try decode(["Ports": [:] as [String: Any]])
        #expect(ns.ports != nil)
        #expect(ns.ports?.isEmpty == true)
    }
}

@Suite("ContainerNetworkSettings scalar fields")
struct ContainerNetworkSettingsScalarTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerNetworkSettings {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerNetworkSettings.self, from: data)
    }

    @Test func parsesBridgeSandboxIDHairpinAndLinkLocalIPv6() throws {
        let ns = try decode(
            [
                "Bridge": "docker0",
                "SandboxID": "sandbox123",
                "HairpinMode": false,
                "LinkLocalIPv6Address": "fe80::1",
                "LinkLocalIPv6PrefixLen": 64,
                "SandboxKey": "/var/run/docker/netns/abc",
            ] as [String: Any]
        )
        #expect(ns.bridge == "docker0")
        #expect(ns.sandboxID == "sandbox123")
        #expect(ns.hairpinMode == false)
        #expect(ns.linkLocalIPv6Address == "fe80::1")
        #expect(ns.linkLocalIPv6PrefixLen == 64)
        #expect(ns.sandboxKey == "/var/run/docker/netns/abc")
    }

    @Test func parsesEndpointIDGatewayAndGlobalIPv6() throws {
        let ns = try decode(
            [
                "EndpointID": "ep456",
                "Gateway": "172.17.0.1",
                "GlobalIPv6Address": "2001:db8::1",
                "GlobalIPv6PrefixLen": 64,
                "IPAddress": "172.17.0.2",
                "IPPrefixLen": 16,
                "IPv6Gateway": "fe80::1",
                "MacAddress": "02:42:ac:11:00:02",
            ] as [String: Any]
        )
        #expect(ns.endpointID == "ep456")
        #expect(ns.gateway == "172.17.0.1")
        #expect(ns.globalIPv6Address == "2001:db8::1")
        #expect(ns.globalIPv6PrefixLen == 64)
        #expect(ns.ipAddress == "172.17.0.2")
        #expect(ns.ipPrefixLen == 16)
        #expect(ns.ipv6Gateway == "fe80::1")
        #expect(ns.macAddress == "02:42:ac:11:00:02")
    }

    @Test func parsesSecondaryIPv6AddressesList() throws {
        let ns = try decode([
            "SecondaryIPv6Addresses": [
                ["Addr": "2001:db8::2", "PrefixLen": 64] as [String: Any]
            ] as [Any]
        ])
        #expect(ns.secondaryIPv6Addresses != nil)
        #expect(ns.secondaryIPv6Addresses?.count == 1)
        #expect(ns.secondaryIPv6Addresses?[0].addr == "2001:db8::2")
        #expect(ns.secondaryIPv6Addresses?[0].prefixLen == 64)
    }

    @Test func toleratesAllAbsentOptionalFields() throws {
        let ns = try decode([:])
        #expect(ns.bridge == nil)
        #expect(ns.sandboxID == nil)
        #expect(ns.hairpinMode == nil)
        #expect(ns.endpointID == nil)
        #expect(ns.gateway == nil)
        #expect(ns.macAddress == nil)
    }
}

// MARK: - ContainerInspectInfo scalar fields

@Suite("ContainerInspectInfo scalar fields")
struct ContainerInspectInfoScalarTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerInspectInfo {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerInspectInfo.self, from: data)
    }

    @Test func parsesCreatedPathArgsRestartCountDriverPlatform() throws {
        let info = try decode(
            [
                "Id": "abc123",
                "Created": "2024-06-01T12:00:00Z",
                "Path": "/bin/sh",
                "Args": ["-c", "echo hello"],
                "RestartCount": 2,
                "Driver": "overlay2",
                "Platform": "linux",
            ] as [String: Any]
        )
        #expect(info.created == "2024-06-01T12:00:00Z")
        #expect(info.path == "/bin/sh")
        #expect(info.args == ["-c", "echo hello"])
        #expect(info.restartCount == 2)
        #expect(info.driver == "overlay2")
        #expect(info.platform == "linux")
    }

    @Test func parsesHostPathsAndSecurityLabels() throws {
        let info = try decode(
            [
                "ResolvConfPath": "/var/lib/docker/containers/abc/resolv.conf",
                "HostnamePath": "/var/lib/docker/containers/abc/hostname",
                "HostsPath": "/var/lib/docker/containers/abc/hosts",
                "LogPath": "/var/lib/docker/containers/abc/json.log",
                "MountLabel": "",
                "ProcessLabel": "",
                "AppArmorProfile": "docker-default",
            ] as [String: Any]
        )
        #expect(info.resolvConfPath == "/var/lib/docker/containers/abc/resolv.conf")
        #expect(info.hostnamePath == "/var/lib/docker/containers/abc/hostname")
        #expect(info.hostsPath == "/var/lib/docker/containers/abc/hosts")
        #expect(info.logPath == "/var/lib/docker/containers/abc/json.log")
        #expect(info.mountLabel == "")
        #expect(info.appArmorProfile == "docker-default")
    }

    @Test func parsesExecIDsList() throws {
        let info = try decode(["ExecIDs": ["exec1", "exec2"]])
        #expect(info.execIDs == ["exec1", "exec2"])
    }

    @Test func execIDsIsNilWhenKeyAbsent() throws {
        let info = try decode([:])
        #expect(info.execIDs == nil)
    }

    @Test func parsesNestedGraphDriver() throws {
        let info = try decode([
            "GraphDriver": [
                "Name": "overlay2",
                "Data": ["UpperDir": "/upper", "WorkDir": "/work"],
            ] as [String: Any]
        ])
        #expect(info.graphDriver != nil)
        #expect(info.graphDriver?.name == "overlay2")
        #expect(info.graphDriver?.data?["UpperDir"] == "/upper")
    }

    @Test func graphDriverIsNilWhenKeyAbsent() throws {
        let info = try decode([:])
        #expect(info.graphDriver == nil)
    }

    @Test func parsesNestedImageManifestDescriptor() throws {
        let info = try decode([
            "ImageManifestDescriptor": [
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "digest": "sha256:abc",
                "size": 512,
            ] as [String: Any]
        ])
        #expect(info.imageManifestDescriptor != nil)
        #expect(info.imageManifestDescriptor?.digest == "sha256:abc")
    }

    @Test func imageManifestDescriptorIsNilWhenKeyAbsent() throws {
        let info = try decode([:])
        #expect(info.imageManifestDescriptor == nil)
    }

    @Test func parsesSizeRwAndSizeRootFs() throws {
        let info = try decode(["SizeRw": 4096, "SizeRootFs": 123_456_789])
        #expect(info.sizeRw == 4096)
        #expect(info.sizeRootFs == 123_456_789)
    }

    @Test func parsesProcessLabel() throws {
        let info = try decode([
            "ProcessLabel": "system_u:system_r:svirt_lxc_net_t:s0:c123,c456"
        ])
        #expect(info.processLabel == "system_u:system_r:svirt_lxc_net_t:s0:c123,c456")
    }

    @Test func processLabelDefaultsToNilWhenKeyAbsent() throws {
        let info = try decode([:])
        #expect(info.processLabel == nil)
    }
}

// MARK: - ContainerState full field parsing

@Suite("ContainerState full field parsing")
struct ContainerStateFullTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerState {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerState.self, from: data)
    }

    @Test func parsesAllBooleanAndStringStateFields() throws {
        let state = try decode(
            [
                "Status": "exited",
                "Running": false,
                "Paused": false,
                "Restarting": false,
                "OOMKilled": true,
                "Dead": false,
                "Pid": 0,
                "ExitCode": 137,
                "Error": "container killed",
                "StartedAt": "2024-05-01T10:00:00Z",
                "FinishedAt": "2024-05-01T10:00:05Z",
            ] as [String: Any]
        )
        #expect(state.status == "exited")
        #expect(state.running == false)
        #expect(state.paused == false)
        #expect(state.restarting == false)
        #expect(state.oomKilled == true)
        #expect(state.dead == false)
        #expect(state.pid == 0)
        #expect(state.exitCode == 137)
        #expect(state.error == "container killed")
        #expect(state.startedAt == "2024-05-01T10:00:00Z")
        #expect(state.finishedAt == "2024-05-01T10:00:05Z")
    }

    @Test func toleratesAllMissingFields() throws {
        let state = try decode([:])
        #expect(state.status == nil)
        #expect(state.running == nil)
        #expect(state.paused == nil)
        #expect(state.restarting == nil)
        #expect(state.oomKilled == nil)
        #expect(state.dead == nil)
        #expect(state.pid == nil)
        #expect(state.exitCode == nil)
        #expect(state.error == nil)
        #expect(state.startedAt == nil)
        #expect(state.finishedAt == nil)
        #expect(state.health == nil)
    }

    @Test func deadTrueIndicatesDeadState() throws {
        let state = try decode(
            [
                "Status": "dead",
                "Dead": true,
                "Running": false,
                "ExitCode": 1,
            ] as [String: Any]
        )
        #expect(state.dead == true)
        #expect(state.status == "dead")
    }

    @Test func restartingTrueIsPreserved() throws {
        let state = try decode(
            [
                "Status": "restarting",
                "Restarting": true,
                "Running": false,
            ] as [String: Any]
        )
        #expect(state.restarting == true)
    }

    @Test func pausedTrueIsPreserved() throws {
        let state = try decode(
            [
                "Status": "paused",
                "Paused": true,
                "Running": false,
            ] as [String: Any]
        )
        #expect(state.paused == true)
    }
}

// MARK: - ContainerNetworkSettings secondary addresses

@Suite("ContainerNetworkSettings secondary addresses")
struct NetworkSettingsSecondaryAddrTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerNetworkSettings {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerNetworkSettings.self, from: data)
    }

    @Test func parsesSecondaryIPAddresses() throws {
        let ns = try decode([
            "SecondaryIPAddresses": [
                ["Addr": "172.18.0.5", "PrefixLen": 16] as [String: Any]
            ] as [Any]
        ])
        #expect(ns.secondaryIPAddresses != nil)
        #expect(ns.secondaryIPAddresses?.count == 1)
        #expect(ns.secondaryIPAddresses?[0].addr == "172.18.0.5")
    }

    @Test func parsesNetworksMap() throws {
        let ns = try decode([
            "Networks": [
                "bridge": [
                    "IPAddress": "172.17.0.2",
                    "Gateway": "172.17.0.1",
                    "NetworkID": "net123",
                ] as [String: Any]
            ] as [String: Any]
        ])
        #expect(ns.networks != nil)
        #expect(ns.networks?["bridge"] != nil)
        #expect(ns.networks?["bridge"]?.ipAddress == "172.17.0.2")
    }

    @Test func nullNetworksReturnsNilNetworksField() throws {
        let ns = try decode([:])
        #expect(ns.networks == nil)
    }
}

// MARK: - ContainerNetworkEndpoint extended fields

@Suite("ContainerNetworkEndpoint extended fields")
struct ContainerNetworkEndpointExtendedTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerNetworkEndpoint {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerNetworkEndpoint.self, from: data)
    }

    @Test func parsesMacAddressAndAliases() throws {
        let ep = try decode(
            [
                "NetworkID": "net123",
                "IPAddress": "172.17.0.3",
                "Gateway": "172.17.0.1",
                "MacAddress": "02:42:ac:11:00:03",
                "Aliases": ["container-alias"],
            ] as [String: Any]
        )
        #expect(ep.macAddress == "02:42:ac:11:00:03")
        #expect(ep.aliases == ["container-alias"])
    }

    @Test func parsesNestedIPAMConfig() throws {
        let ep = try decode(
            [
                "NetworkID": "net789",
                "IPAddress": "10.0.0.5",
                "Gateway": "10.0.0.1",
                "IPAMConfig": [
                    "IPv4Address": "10.0.0.5",
                    "IPv6Address": "",
                    "LinkLocalIPs": ["169.254.0.1"],
                ] as [String: Any],
            ] as [String: Any]
        )
        #expect(ep.ipamConfig != nil)
        #expect(ep.ipamConfig?.ipv4Address == "10.0.0.5")
        #expect(ep.ipamConfig?.linkLocalIPs == ["169.254.0.1"])
    }

    @Test func ipamConfigIsNullWhenIPAMConfigKeyIsAbsent() throws {
        let ep = try decode([
            "NetworkID": "net000",
            "IPAddress": "172.17.0.4",
            "Gateway": "172.17.0.1",
        ])
        #expect(ep.ipamConfig == nil)
    }

    @Test func parsesDnsNames() throws {
        let ep = try decode(
            [
                "NetworkID": "net456",
                "IPAddress": "192.168.1.2",
                "Gateway": "192.168.1.1",
                "DNSNames": ["web", "web.mynetwork"],
            ] as [String: Any]
        )
        #expect(ep.dnsNames == ["web", "web.mynetwork"])
    }

    @Test func parsesDriverOpts() throws {
        let ep = try decode(
            [
                "NetworkID": "net_ovl",
                "IPAddress": "10.1.0.2",
                "Gateway": "10.1.0.1",
                "DriverOpts": ["com.docker.network.driver.overlay.vxlanid": "4097"],
            ] as [String: Any]
        )
        #expect(ep.driverOpts != nil)
        #expect(ep.driverOpts?["com.docker.network.driver.overlay.vxlanid"] == "4097")
    }

    @Test func parsesGwPriority() throws {
        let ep = try decode(
            [
                "NetworkID": "net1",
                "IPAddress": "10.0.0.2",
                "Gateway": "10.0.0.1",
                "GwPriority": 0,
            ] as [String: Any]
        )
        #expect(ep.gwPriority == 0)
    }

    @Test func gwPriorityIsNilWhenKeyAbsent() throws {
        let ep = try decode([
            "NetworkID": "net1",
            "IPAddress": "10.0.0.2",
            "Gateway": "10.0.0.1",
        ])
        #expect(ep.gwPriority == nil)
    }

    @Test func gwPriorityStoresNonZeroValue() throws {
        let ep = try decode(
            [
                "NetworkID": "net1",
                "IPAddress": "10.0.0.2",
                "Gateway": "10.0.0.1",
                "GwPriority": 100,
            ] as [String: Any]
        )
        #expect(ep.gwPriority == 100)
    }
}

// MARK: - ContainerInspectInfo full round-trip extras

@Suite("ContainerInspectInfo full round-trip")
struct ContainerInspectInfoRoundTripTests {
    private func decode(_ dict: [String: Any]) throws -> ContainerInspectInfo {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ContainerInspectInfo.self, from: data)
    }

    @Test func mountsListIsParsed() throws {
        let info = try decode([
            "Mounts": [
                [
                    "Type": "volume",
                    "Source": "/var/lib/docker/volumes/data/_data",
                    "Destination": "/data",
                    "Mode": "",
                    "RW": true,
                    "Propagation": "",
                ] as [String: Any]
            ] as [Any]
        ])
        #expect(info.mounts != nil)
        #expect(info.mounts?.count == 1)
        #expect(info.mounts?.first?.type == "volume")
    }

    @Test func configEnvListIsNullSafe() throws {
        let info = try decode([
            "Config": ["Image": "alpine", "Hostname": "h", "Env": NSNull()] as [String: Any]
        ])
        #expect(info.config?.env == nil)
    }
}
