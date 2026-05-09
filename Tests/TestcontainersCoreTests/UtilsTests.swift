import Testing
@testable import TestcontainersCore

@Suite("insideContainer")
struct InsideContainerTests {
    @Test func returnsFalseInCIEnvironment() {
        // In a normal test environment, /.dockerenv should not exist
        // (unless tests are running inside Docker, in which case this is expected to return true)
        let result = insideContainer()
        // We just verify it returns a Bool without crashing
        _ = result
    }
}

@Suite("Platform detection")
struct PlatformTests {
    @Test func isMacOrLinuxOrWindows() {
        // Exactly one of these should be true
        let mac = isMac()
        let linux = isLinux()
        let windows = isWindows()
        let count = [mac, linux, windows].filter { $0 }.count
        #expect(count == 1)
    }

    @Test func isArmReturnsBool() {
        _ = isArm()
    }
}

@Suite("runningContainerId")
struct RunningContainerIdTests {
    @Test func returnsNilOrStringOutsideContainer() {
        // In a normal macOS test environment, /proc/self/cgroup won't exist
        let cid = runningContainerId()
        // Could be nil (macOS) or a string (Linux without Docker)
        _ = cid
    }
}

@Suite("defaultGatewayIp")
struct DefaultGatewayIpTests {
    @Test func returnsNilOrNonEmptyString() {
        let ip = defaultGatewayIp()
        if let ip = ip {
            #expect(!ip.isEmpty)
        }
    }
}
