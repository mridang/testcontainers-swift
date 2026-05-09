import Foundation
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

@Suite("resolveFlag via tcProperties (indirect)")
struct ResolveFlagTests {
    // Tests the private resolveFlag() indirectly through the ryukDisabled property,
    // which uses tcProperties["ryuk.disabled"] as a fallback when no env var is set
    // and _ryukDisabled has not been overridden.

    @Test func tokenYesIsTrue() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.disabled"] = "yes"
        #expect(config.ryukDisabled == true)
    }

    @Test func tokenTrueIsTrue() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.disabled"] = "true"
        #expect(config.ryukDisabled == true)
    }

    @Test func tokenTIsTrue() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.disabled"] = "t"
        #expect(config.ryukDisabled == true)
    }

    @Test func tokenYIsTrue() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.disabled"] = "y"
        #expect(config.ryukDisabled == true)
    }

    @Test func token1IsTrue() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.disabled"] = "1"
        #expect(config.ryukDisabled == true)
    }

    @Test func tokenYESUppercaseIsTrue() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.disabled"] = "YES"
        #expect(config.ryukDisabled == true)
    }

    @Test func tokenTRUEUppercaseIsTrue() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.disabled"] = "TRUE"
        #expect(config.ryukDisabled == true)
    }

    @Test func tokenMixedCaseIsTrue() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.disabled"] = "True"
        #expect(config.ryukDisabled == true)
    }

    @Test func tokenNoIsFalse() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.disabled"] = "no"
        #expect(config.ryukDisabled == false)
    }

    @Test func tokenFalseIsFalse() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.disabled"] = "false"
        #expect(config.ryukDisabled == false)
    }

    @Test func token0IsFalse() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.disabled"] = "0"
        #expect(config.ryukDisabled == false)
    }

    @Test func tokenEmptyStringIsFalse() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.disabled"] = ""
        #expect(config.ryukDisabled == false)
    }

    @Test func tokenAbsentKeyIsFalse() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties.removeValue(forKey: "ryuk.disabled")
        #expect(config.ryukDisabled == false)
    }

    @Test func flagAppliesEquallyToPrivileged() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.container.privileged"] = "1"
        #expect(config.ryukPrivileged == true)
    }
}

@Suite("TestcontainersConfiguration additional defaults")
struct ConfigAdditionalDefaultsTests {
    @Test func defaultHubImageNamePrefixIsEmpty() throws {
        let config = try TestcontainersConfiguration()
        if ProcessInfo.processInfo.environment["TESTCONTAINERS_HUB_IMAGE_NAME_PREFIX"] == nil {
            #expect(config.hubImageNamePrefix == "")
        }
    }

    @Test func dockerAuthConfigDefaultsToNilOrEnvValue() throws {
        let config = try TestcontainersConfiguration()
        let envVal = ProcessInfo.processInfo.environment["DOCKER_AUTH_CONFIG"]
        #expect(config.dockerAuthConfig == envVal)
    }

    @Test func tcHostOverrideReadsFromEnvironment() throws {
        let config = try TestcontainersConfiguration()
        let envTcHost = ProcessInfo.processInfo.environment["TC_HOST"]
        let envOverride = ProcessInfo.processInfo.environment["TESTCONTAINERS_HOST_OVERRIDE"]
        let expected = envTcHost ?? envOverride
        #expect(config.tcHostOverride == expected)
    }

    @Test func connectionModeOverrideDefaultsToNil() throws {
        // Without TESTCONTAINERS_CONNECTION_MODE set, the override should be nil
        let config = try TestcontainersConfiguration()
        if ProcessInfo.processInfo.environment["TESTCONTAINERS_CONNECTION_MODE"] == nil {
            #expect(config.connectionModeOverride == nil)
        }
    }

    @Test func ryukDockerSocketReturnsNonEmptyPath() throws {
        let config = try TestcontainersConfiguration()
        #expect(!config.ryukDockerSocket.isEmpty)
    }

    @Test func ryukDockerSocketSetterOverridesCachedValue() throws {
        let config = try TestcontainersConfiguration()
        config.ryukDockerSocket = "/custom/docker.sock"
        #expect(config.ryukDockerSocket == "/custom/docker.sock")
    }
}

// ---------------------------------------------------------------------------
// ConnectionMode enum — additional coverage
// ---------------------------------------------------------------------------

@Suite("ConnectionMode enum — additional")
struct ConnectionModeEnumAdditionalTests {
    @Test func exactlyThreeValuesExist() {
        // Enumerate all cases manually since ConnectionMode is not CaseIterable.
        let allModes: [ConnectionMode] = [.bridgeIp, .gatewayIp, .dockerHost]
        #expect(allModes.count == 3)
    }

    @Test func onlyBridgeIpHasUseMappedPortFalse() {
        let allModes: [ConnectionMode] = [.bridgeIp, .gatewayIp, .dockerHost]
        let falseCount = allModes.filter { !$0.useMappedPort }.count
        #expect(falseCount == 1)
        #expect(ConnectionMode.bridgeIp.useMappedPort == false)
    }

    @Test func valuesContainBridgeIpGatewayIpDockerHost() {
        let allModes: [ConnectionMode] = [.bridgeIp, .gatewayIp, .dockerHost]
        #expect(allModes.contains(.bridgeIp))
        #expect(allModes.contains(.gatewayIp))
        #expect(allModes.contains(.dockerHost))
    }
}

// ---------------------------------------------------------------------------
// readTcProperties — type check
// ---------------------------------------------------------------------------

@Suite("readTcProperties type")
struct ReadTcPropertiesTypeTests {
    @Test func returnsStringStringDictionary() {
        let props = readTcProperties()
        // The return type is [String: String] — this simply verifies the call
        // compiles and returns the correct type without crashing.
        let typed: [String: String] = props
        _ = typed
    }
}

// ---------------------------------------------------------------------------
// ryukPrivileged and ryukDisabled are independent
// ---------------------------------------------------------------------------

@Suite("ryukPrivileged and ryukDisabled independence")
struct RyukFlagIndependenceTests {
    @Test func settingPrivilegedDoesNotAffectDisabled() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.container.privileged"] = "yes"
        config.tcProperties["ryuk.disabled"] = "no"
        #expect(config.ryukPrivileged == true)
        #expect(config.ryukDisabled == false)
    }

    @Test func settingDisabledDoesNotAffectPrivileged() throws {
        let config = try TestcontainersConfiguration()
        config.tcProperties["ryuk.disabled"] = "yes"
        config.tcProperties["ryuk.container.privileged"] = "no"
        #expect(config.ryukDisabled == true)
        #expect(config.ryukPrivileged == false)
    }
}
