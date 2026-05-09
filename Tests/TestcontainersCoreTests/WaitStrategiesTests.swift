import Foundation
import Testing

@testable import TestcontainersCore

// MARK: - Mock WaitStrategyTarget

final class MockWaitStrategyTarget: WaitStrategyTarget {
    var statusValue: String = "running"
    var logsResult: (stdout: Data, stderr: Data) = (Data(), Data())
    var execResult: (exitCode: Int, output: Data) = (0, Data())
    var exposedPortValue: Int = 1234
    var reloadCallCount: Int = 0
    var _containerInfoResult: ContainerInspectInfo?

    func containerHostIp() async throws -> String { "127.0.0.1" }
    func exposedPort(_ port: Int) async throws -> Int { exposedPortValue }
    var wrappedContainer: AnyObject { self }
    func logs() async throws -> (stdout: Data, stderr: Data) { logsResult }
    func exec(_ command: [String]) async throws -> (exitCode: Int, output: Data) { execResult }
    func containerInfo() async throws -> ContainerInspectInfo? { _containerInfoResult }
    func reload() async { reloadCallCount += 1 }
    var status: String { statusValue }
}

@Suite("WaitStrategy poll loop")
struct WaitStrategyPollTests {
    @Test func returnsTrueImmediatelyWhenCheckSucceeds() async throws {
        let strategy = WaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(100)
        var callCount = 0
        let result = try await strategy.poll {
            callCount += 1
            return true
        }
        #expect(result == true)
        #expect(callCount == 1)
    }

    @Test func retriesUntilSuccess() async throws {
        let strategy = WaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        var callCount = 0
        let result = try await strategy.poll {
            callCount += 1
            return callCount >= 3
        }
        #expect(result == true)
        #expect(callCount == 3)
    }

    @Test func returnsFalseOnTimeoutWhenNeverReady() async throws {
        let strategy = WaitStrategy()
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        let result = try await strategy.poll { false }
        #expect(result == false)
    }

    @Test func returnsFalseOnStopPollingError() async throws {
        let strategy = WaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        let result = try await strategy.poll {
            throw StopPollingError()
        }
        #expect(result == false)
    }

    @Test func swallowsURLErrors() async throws {
        let strategy = WaitStrategy()
        strategy.startupTimeout = .seconds(2)
        strategy.pollInterval = .milliseconds(10)
        var callCount = 0
        let result = try await strategy.poll {
            callCount += 1
            if callCount < 3 { throw URLError(.notConnectedToInternet) }
            return true
        }
        #expect(result == true)
    }

    @Test func rethrowsNonTransientErrors() async throws {
        let strategy = WaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        let customError = WaitStrategyError.containerExited("exited")
        do {
            _ = try await strategy.poll {
                throw customError
            }
            Issue.record("Expected error to be thrown")
        } catch WaitStrategyError.containerExited {
            // expected
        }
    }
}

@Suite("ContainerStatusWaitStrategy")
struct ContainerStatusWaitStrategyTests {
    @Test func returnsTrueWhenStatusIsRunning() async throws {
        let target = MockWaitStrategyTarget()
        target.statusValue = "running"
        let strategy = ContainerStatusWaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func throwsOnUnexpectedStatus() async throws {
        let target = MockWaitStrategyTarget()
        target.statusValue = "exited"
        let strategy = ContainerStatusWaitStrategy()
        strategy.startupTimeout = .milliseconds(200)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected error")
        } catch {
            // expected — status not in continueStatuses
        }
    }

    @Test func continueStatusesContainsCreatedAndRestarting() {
        #expect(ContainerStatusWaitStrategy.continueStatuses.contains("created"))
        #expect(ContainerStatusWaitStrategy.continueStatuses.contains("restarting"))
    }
}

@Suite("LogMessageWaitStrategy")
struct LogMessageWaitStrategyTests {
    @Test func matchesPatternInStdout() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (
            stdout: Data("Server started!\n".utf8),
            stderr: Data()
        )
        let strategy = LogMessageWaitStrategy("Server started!")
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func matchesPatternInStderr() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (
            stdout: Data(),
            stderr: Data("ready for connections\n".utf8)
        )
        let strategy = LogMessageWaitStrategy("ready for connections")
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func throwsTimeoutWhenPatternNeverAppears() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("no match\n".utf8), stderr: Data())
        let strategy = LogMessageWaitStrategy("NEVER_APPEAR")
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout {
            // expected
        }
    }
}

@Suite("ExecWaitStrategy")
struct ExecWaitStrategyTests {
    @Test func succeedsWhenExitCodeMatches() async throws {
        let target = MockWaitStrategyTarget()
        target.execResult = (exitCode: 0, output: Data())
        let strategy = ExecWaitStrategy(["echo", "ok"])
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func throwsTimeoutWhenExitCodeNeverMatches() async throws {
        let target = MockWaitStrategyTarget()
        target.execResult = (exitCode: 1, output: Data())
        let strategy = ExecWaitStrategy(["false"], expectedExitCode: 0)
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout {
            // expected
        }
    }
}

@Suite("CompositeWaitStrategy")
struct CompositeWaitStrategyTests {
    @Test func runsAllStrategiesInOrder() async throws {
        let target = MockWaitStrategyTarget()
        target.statusValue = "running"
        target.logsResult = (stdout: Data("ready\n".utf8), stderr: Data())
        target.execResult = (exitCode: 0, output: Data())

        let strategy = CompositeWaitStrategy([
            ContainerStatusWaitStrategy(),
            LogMessageWaitStrategy("ready"),
            ExecWaitStrategy(["true"]),
        ])
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }
}

@Suite("FileExistsWaitStrategy")
struct FileExistsWaitStrategyTests {
    @Test func succeedsWhenExecReturnsZero() async throws {
        let target = MockWaitStrategyTarget()
        target.execResult = (exitCode: 0, output: Data())
        let strategy = FileExistsWaitStrategy("/app/ready")
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func filePath() {
        let strategy = FileExistsWaitStrategy("/app/ready")
        #expect(strategy.filePath == "/app/ready")
    }

    @Test func timesOutWhenFileNeverExists() async throws {
        let target = MockWaitStrategyTarget()
        target.execResult = (exitCode: 1, output: Data())
        let strategy = FileExistsWaitStrategy("/never/exists")
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout {
            // expected
        }
    }
}

@Suite("HealthcheckWaitStrategy")
struct HealthcheckWaitStrategyTests {
    @Test func returnsImmediatelyWhenHealthy() async throws {
        let target = MockWaitStrategyTarget()
        // Provide a healthy ContainerInspectInfo
        target.containerInfoResult = makeInspectInfo(healthStatus: "healthy")
        let strategy = HealthcheckWaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func throwsWhenUnhealthy() async throws {
        let target = MockWaitStrategyTarget()
        target.containerInfoResult = makeInspectInfo(healthStatus: "unhealthy")
        let strategy = HealthcheckWaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected WaitStrategyError.unhealthy")
        } catch WaitStrategyError.unhealthy {
            // expected
        }
    }

    @Test func throwsWhenNoHealthCheck() async throws {
        let target = MockWaitStrategyTarget()
        target.containerInfoResult = makeInspectInfo(healthStatus: nil)
        let strategy = HealthcheckWaitStrategy()
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected WaitStrategyError.containerExited")
        } catch WaitStrategyError.containerExited {
            // expected — no health check configured
        }
    }
}

@Suite("HttpWaitStrategy (builder)")
struct HttpWaitStrategyBuilderTests {
    @Test func constructsWithDefaultPath() {
        // Just verify it initializes without error
        let strategy = HttpWaitStrategy(port: 8080)
        #expect(strategy.startupTimeout > .zero)
    }

    @Test func constructsWithCustomPath() {
        let strategy = HttpWaitStrategy(port: 8080, path: "/health")
        #expect(strategy.startupTimeout > .zero)
    }

    @Test func withStartupTimeoutIsChainable() {
        let strategy = HttpWaitStrategy(port: 8080).withStartupTimeout(.seconds(30))
        #expect(strategy.startupTimeout == .seconds(30))
    }

    @Test func withPollIntervalIsChainable() {
        let strategy = HttpWaitStrategy(port: 8080).withPollInterval(.milliseconds(500))
        #expect(strategy.pollInterval == .milliseconds(500))
    }

    @Test func forStatusCodeReturnsChainableResult() {
        // Builder returns self — result should be same object
        let strategy = HttpWaitStrategy(port: 8080)
        let returned = strategy.forStatusCode(200)
        #expect(returned === strategy)
    }

    @Test func usingTlsReturnsChainableResult() {
        let strategy = HttpWaitStrategy(port: 443)
        let returned = strategy.usingTls()
        #expect(returned === strategy)
    }

    @Test func withMethodReturnsChainableResult() {
        let strategy = HttpWaitStrategy(port: 8080)
        let returned = strategy.withMethod("POST")
        #expect(returned === strategy)
    }
}

@Suite("WaitStrategy transient exception handling")
struct WaitStrategyTransientTests {
    @Test func cancellationErrorIsSwallowed() async throws {
        let strategy = WaitStrategy()
        strategy.startupTimeout = .seconds(2)
        strategy.pollInterval = .milliseconds(10)
        var count = 0
        let result = try await strategy.poll {
            count += 1
            if count < 3 { throw CancellationError() }
            return true
        }
        #expect(result == true)
        #expect(count == 3)
    }

    @Test func customTransientExceptionIsSwallowed() async throws {
        struct MyTransientError: Error {}
        let strategy = WaitStrategy()
        strategy.startupTimeout = .seconds(2)
        strategy.pollInterval = .milliseconds(10)
        var count = 0
        let result = try await strategy.poll(
            {
                count += 1
                if count < 3 { throw MyTransientError() }
                return true
            },
            transientExceptions: [MyTransientError.self]
        )
        #expect(result == true)
    }

    @Test func nonTransientErrorIsRethrown() async throws {
        struct FatalError: Error {}
        let strategy = WaitStrategy()
        strategy.startupTimeout = .seconds(2)
        strategy.pollInterval = .milliseconds(10)
        await #expect(throws: FatalError.self) {
            _ = try await strategy.poll { throw FatalError() }
        }
    }
}

@Suite("WaitStrategy builder methods")
struct WaitStrategyBuilderTests {
    @Test func withStartupTimeoutReturnsSelF() {
        let strategy = ExecWaitStrategy(["echo"])
        let returned = strategy.withStartupTimeout(.seconds(60))
        #expect(returned === strategy)
        #expect(strategy.startupTimeout == .seconds(60))
    }

    @Test func withPollIntervalReturnsSelf() {
        let strategy = ExecWaitStrategy(["echo"])
        let returned = strategy.withPollInterval(.milliseconds(200))
        #expect(returned === strategy)
        #expect(strategy.pollInterval == .milliseconds(200))
    }
}

@Suite("notExitedStatuses")
struct NotExitedStatusesTests {
    @Test func containsRunning() {
        #expect(notExitedStatuses.contains("running"))
    }

    @Test func containsCreated() {
        #expect(notExitedStatuses.contains("created"))
    }

    @Test func doesNotContainExited() {
        #expect(!notExitedStatuses.contains("exited"))
    }
}

// MARK: - Helpers

private func makeInspectInfo(healthStatus: String?) -> ContainerInspectInfo? {
    var dict: [String: Any] = [:]
    if let status = healthStatus {
        dict["State"] = ["Health": ["Status": status, "FailingStreak": 0, "Log": [] as [Any]]]
    } else {
        dict["State"] = ["Status": "running"] as [String: Any]
    }
    let data = try? JSONSerialization.data(withJSONObject: dict)
    return data.flatMap { try? JSONDecoder().decode(ContainerInspectInfo.self, from: $0) }
}

// Extend MockWaitStrategyTarget with containerInfo support
extension MockWaitStrategyTarget {
    var containerInfoResult: ContainerInspectInfo? {
        get { _containerInfoResult }
        set { _containerInfoResult = newValue }
    }
}
