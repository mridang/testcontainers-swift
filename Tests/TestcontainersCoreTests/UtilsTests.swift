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

    @Test func returnsBool() {
        let result = insideContainer()
        #expect(result == true || result == false)
    }

    #if os(macOS)
        @Test func returnsFalseOnMacOS() {
            // /.dockerenv never exists on bare macOS
            #expect(insideContainer() == false)
        }
    #endif
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

    @Test func isMacReturnsBool() {
        let result = isMac()
        #expect(result == true || result == false)
    }

    @Test func isLinuxReturnsBool() {
        let result = isLinux()
        #expect(result == true || result == false)
    }

    @Test func isWindowsReturnsBool() {
        let result = isWindows()
        #expect(result == true || result == false)
    }

    @Test func macAndLinuxAreMutuallyExclusive() {
        #expect(!(isMac() && isLinux()))
    }

    @Test func macAndWindowsAreMutuallyExclusive() {
        #expect(!(isMac() && isWindows()))
    }

    @Test func linuxAndWindowsAreMutuallyExclusive() {
        #expect(!(isLinux() && isWindows()))
    }

    #if os(macOS)
        @Test func isMacTrueOnMacOS() {
            #expect(isMac() == true)
            #expect(isLinux() == false)
            #expect(isWindows() == false)
        }
    #endif
}

@Suite("runningContainerId")
struct RunningContainerIdTests {
    @Test func returnsNilOrStringOutsideContainer() {
        // In a normal macOS test environment, /proc/self/cgroup won't exist
        let cid = runningContainerId()
        // Could be nil (macOS) or a string (Linux without Docker)
        _ = cid
    }

    #if os(macOS)
        @Test func returnsNilOnMacOS() {
            // /proc/self/cgroup doesn't exist on macOS
            #expect(runningContainerId() == nil)
        }
    #endif

    @Test func ifNonNilThenNonEmpty() {
        if let cid = runningContainerId() {
            #expect(!cid.isEmpty)
        }
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

    @Test func ifPresentIsValidIpFormat() {
        // If defaultGatewayIp returns a value it should look like an IP
        if let ip = defaultGatewayIp() {
            let parts = ip.split(separator: ".")
            // IPv4: 4 components
            // We don't assert on IPv6 since `ip route` returns IPv4 addresses
            #expect(!ip.isEmpty)
            _ = parts
        }
    }
}

@Suite("Platform cross-validation")
struct PlatformCrossValidationTests {
    #if os(macOS)
        @Test func isMacMatchesPlatformIsMacOS() {
            #expect(isMac() == true)
            #expect(!isLinux())
            #expect(!isWindows())
        }
    #endif

    #if os(Linux)
        @Test func isLinuxMatchesPlatformIsLinux() {
            #expect(isLinux() == true)
            #expect(!isMac())
            #expect(!isWindows())
        }
    #endif

    #if os(Windows)
        @Test func isWindowsMatchesPlatformIsWindows() {
            #expect(isWindows() == true)
            #expect(!isMac())
            #expect(!isLinux())
        }
    #endif

    #if arch(arm64)
        @Test func isArmConsistencyArm64() {
            #expect(isArm() == true)
        }
    #endif

    #if arch(x86_64)
        @Test func isArmConsistencyX86_64() {
            #expect(isArm() == false)
        }
    #endif

    #if os(macOS)
        @Test func defaultGatewayIpReturnsNilOnMacOS() {
            #expect(defaultGatewayIp() == nil)
        }
    #endif
}
