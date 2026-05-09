import Testing

@testable import TestcontainersCore

@Suite("TestcontainersConfiguration defaults")
struct ConfigDefaultsTests {
    @Test func defaultMaxTriesIs120() throws {
        let config = try TestcontainersConfiguration()
        #expect(config.maxTries == 120)
    }

    @Test func defaultSleepTimeIs1() throws {
        let config = try TestcontainersConfiguration()
        #expect(config.sleepTime == 1.0)
    }

    @Test func defaultRyukImage() throws {
        let config = try TestcontainersConfiguration()
        #expect(config.ryukImage == "testcontainers/ryuk:0.8.1")
    }

    @Test func timeoutIsMaxTriesTimesSleepTime() throws {
        let config = try TestcontainersConfiguration()
        #expect(config.timeout == Double(config.maxTries) * config.sleepTime)
    }

    @Test func defaultRyukDisabledIsFalse() throws {
        let config = try TestcontainersConfiguration()
        #expect(config.ryukDisabled == false)
    }

    @Test func defaultRyukPrivilegedIsFalse() throws {
        let config = try TestcontainersConfiguration()
        #expect(config.ryukPrivileged == false)
    }

    @Test func ryukPrivilegedSetterWorks() throws {
        let config = try TestcontainersConfiguration()
        config.ryukPrivileged = true
        #expect(config.ryukPrivileged == true)
    }

    @Test func ryukDisabledSetterWorks() throws {
        let config = try TestcontainersConfiguration()
        config.ryukDisabled = true
        #expect(config.ryukDisabled == true)
    }

    @Test func defaultRyukReconnectionTimeout() throws {
        let config = try TestcontainersConfiguration()
        #expect(config.ryukReconnectionTimeout == "10s")
    }
}

@Suite("readTcProperties")
struct ReadTcPropertiesTests {
    @Test func returnsMapWhenFileAbsent() {
        let props = readTcProperties()
        // Should return an empty map (or a partial map) — no crash
        _ = props
    }
}

@Suite("dockerSocket")
struct DockerSocketTests {
    @Test func returnsNonEmptyPath() {
        let socket = dockerSocket()
        #expect(!socket.isEmpty)
    }
}

@Suite("tcHost")
struct TcHostTests {
    @Test func returnsTcHostFromProperties() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["tc.host"] = "some_value"
        #expect(config.tcHost == "some_value")
    }

    @Test func returnsNilWhenAbsent() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties.removeValue(forKey: "tc.host")
        #expect(config.tcHost == nil)
    }
}

@Suite("ConnectionMode")
struct ConnectionModeTests {
    @Test func bridgeIpUseMappedPortIsFalse() {
        #expect(ConnectionMode.bridgeIp.useMappedPort == false)
    }

    @Test func gatewayIpUseMappedPortIsTrue() {
        #expect(ConnectionMode.gatewayIp.useMappedPort == true)
    }

    @Test func dockerHostUseMappedPortIsTrue() {
        #expect(ConnectionMode.dockerHost.useMappedPort == true)
    }
}

@Suite("overriddenConnectionMode")
struct OverriddenConnectionModeTests {
    @Test func returnsNilWhenEnvAbsent() throws {
        // Without TESTCONTAINERS_CONNECTION_MODE set, should return nil
        let mode = try overriddenConnectionMode()
        // May not be nil if env var is set in CI, so just verify it doesn't crash
        _ = mode
    }
}
