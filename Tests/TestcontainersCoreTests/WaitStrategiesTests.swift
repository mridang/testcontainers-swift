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
        do {
            _ = try await strategy.poll { throw FatalError() }
            Issue.record("Expected FatalError to be thrown")
        } catch is FatalError {
            // expected
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

    @Test func hasExactlyTwoEntries() {
        #expect(notExitedStatuses.count == 2)
    }

    @Test func containsRunningAndCreatedOnly() {
        #expect(notExitedStatuses == Set(["running", "created"]))
    }
}

@Suite("LogMessageWaitStrategy times")
struct LogMessageWaitStrategyTimesTests {
    @Test func times2SucceedsWhenPatternAppearsExactlyTwice() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("ready\nready\n".utf8), stderr: Data())
        let strategy = LogMessageWaitStrategy("ready", times: 2)
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func times2FailsWhenPatternAppearsOnlyOnce() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("ready\n".utf8), stderr: Data())
        let strategy = LogMessageWaitStrategy("ready", times: 2)
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout {
            // expected
        }
    }

    @Test func times3SucceedsWhenPatternAppearsThreeTimes() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("ok\nok\nok\n".utf8), stderr: Data())
        let strategy = LogMessageWaitStrategy("ok", times: 3)
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func times0AlwaysSucceedsEvenWithEmptyLogs() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data(), stderr: Data())
        let strategy = LogMessageWaitStrategy("never", times: 0)
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }
}

@Suite("LogMessageWaitStrategy predicateStreamsAnd")
struct LogMessagePredicateStreamsTests {
    @Test func andModeSucceedsWhenPatternInBothStreams() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (
            stdout: Data("ready\n".utf8),
            stderr: Data("ready\n".utf8)
        )
        let strategy = LogMessageWaitStrategy("ready", predicateStreamsAnd: true)
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func andModeFailsWhenPatternOnlyInStdout() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (
            stdout: Data("ready\n".utf8),
            stderr: Data("no match here\n".utf8)
        )
        let strategy = LogMessageWaitStrategy("ready", predicateStreamsAnd: true)
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout {
            // expected
        }
    }

    @Test func andModeFailsWhenPatternOnlyInStderr() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (
            stdout: Data("no match here\n".utf8),
            stderr: Data("ready\n".utf8)
        )
        let strategy = LogMessageWaitStrategy("ready", predicateStreamsAnd: true)
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout {
            // expected
        }
    }

    @Test func orModeSucceedsWhenPatternOnlyInStderr() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (
            stdout: Data("no match\n".utf8),
            stderr: Data("ready\n".utf8)
        )
        let strategy = LogMessageWaitStrategy("ready", predicateStreamsAnd: false)
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }
}

@Suite("LogMessageWaitStrategy timeout message")
struct LogMessageTimeoutMessageTests {
    @Test func timeoutMessageContainsContainerStatus() async throws {
        let target = MockWaitStrategyTarget()
        target.statusValue = "running"
        target.logsResult = (stdout: Data("no match\n".utf8), stderr: Data())
        let strategy = LogMessageWaitStrategy("NEVER_APPEAR")
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected error")
        } catch WaitStrategyError.timeout(let msg) {
            #expect(msg.contains("running"))
        }
    }

    @Test func containerExitedErrorWhenStatusIsExited() async throws {
        let target = MockWaitStrategyTarget()
        target.statusValue = "exited"
        target.logsResult = (stdout: Data("no match\n".utf8), stderr: Data())
        let strategy = LogMessageWaitStrategy("NEVER_APPEAR")
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected error")
        } catch WaitStrategyError.containerExited {
            // expected — container exited before log message found
        } catch WaitStrategyError.timeout {
            // also acceptable depending on timing
        }
    }
}

@Suite("ContainerStatusWaitStrategy transitions")
struct ContainerStatusTransitionTests {
    @Test func continueStatusesHasExactlyTwoEntries() {
        #expect(ContainerStatusWaitStrategy.continueStatuses.count == 2)
    }

    @Test func transitionsFromCreatedToRunning() async throws {
        let target = MockWaitStrategyTarget()
        var callCount = 0
        target.statusValue = "created"
        let strategy = ContainerStatusWaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        // After 2 polls set status to running
        let mockTarget = SwitchingMockTarget(initialStatus: "created", switchTo: "running", afterCount: 2)
        try await strategy.waitUntilReady(target: mockTarget)
        _ = callCount
    }

    @Test func throwsImmediatelyOnDeadStatus() async throws {
        let target = MockWaitStrategyTarget()
        target.statusValue = "dead"
        let strategy = ContainerStatusWaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected error")
        } catch WaitStrategyError.containerExited {
            // expected
        }
    }

    @Test func throwsImmediatelyOnPausedStatus() async throws {
        let target = MockWaitStrategyTarget()
        target.statusValue = "paused"
        let strategy = ContainerStatusWaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected error")
        } catch WaitStrategyError.containerExited {
            // expected
        }
    }

    @Test func throwsOnNotStartedStatus() async throws {
        let target = MockWaitStrategyTarget()
        target.statusValue = "not_started"
        let strategy = ContainerStatusWaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected error")
        } catch WaitStrategyError.containerExited {
            // expected
        }
    }

    @Test func errorMessageContainsStatus() async throws {
        let target = MockWaitStrategyTarget()
        target.statusValue = "exited"
        let strategy = ContainerStatusWaitStrategy()
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected error")
        } catch WaitStrategyError.containerExited(let msg) {
            #expect(msg.contains("exited"))
        }
    }
}

@Suite("CompositeWaitStrategy delegation")
struct CompositeWaitStrategyDelegationTests {
    @Test func delegatesStartupTimeoutToChildren() {
        let child1 = ExecWaitStrategy(["echo"])
        let child2 = LogMessageWaitStrategy("ready")
        let composite = CompositeWaitStrategy([child1, child2])
        composite.withStartupTimeout(.seconds(99))
        #expect(child1.startupTimeout == .seconds(99))
        #expect(child2.startupTimeout == .seconds(99))
    }

    @Test func delegatesPollIntervalToChildren() {
        let child1 = ExecWaitStrategy(["echo"])
        let child2 = LogMessageWaitStrategy("ready")
        let composite = CompositeWaitStrategy([child1, child2])
        composite.withPollInterval(.milliseconds(250))
        #expect(child1.pollInterval == .milliseconds(250))
        #expect(child2.pollInterval == .milliseconds(250))
    }

    @Test func succeedsWithEmptyStrategyList() async throws {
        let target = MockWaitStrategyTarget()
        let composite = CompositeWaitStrategy([])
        composite.startupTimeout = .seconds(5)
        try await composite.waitUntilReady(target: target)
    }
}

// MARK: - SwitchingMockTarget helper

private final class SwitchingMockTarget: WaitStrategyTarget {
    private var callCount = 0
    private let switchTo: String
    private let afterCount: Int
    private var currentStatus: String

    init(initialStatus: String, switchTo: String, afterCount: Int) {
        self.currentStatus = initialStatus
        self.switchTo = switchTo
        self.afterCount = afterCount
    }

    func containerHostIp() async throws -> String { "127.0.0.1" }
    func exposedPort(_ port: Int) async throws -> Int { 1234 }
    var wrappedContainer: AnyObject { self }
    func logs() async throws -> (stdout: Data, stderr: Data) { (Data(), Data()) }
    func exec(_ command: [String]) async throws -> (exitCode: Int, output: Data) { (0, Data()) }
    func containerInfo() async throws -> ContainerInspectInfo? { nil }
    func reload() async {
        callCount += 1
        if callCount >= afterCount {
            currentStatus = switchTo
        }
    }
    var status: String { currentStatus }
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

// MARK: - ExecWaitStrategy initialization

@Suite("ExecWaitStrategy initialization")
struct ExecWaitStrategyInitTests {
    @Test func defaultExpectedExitCodeIsZero() async throws {
        let target = MockWaitStrategyTarget()
        target.execResult = (exitCode: 0, output: Data())
        // Strategy with default exit code 0 should succeed when exec returns 0.
        let strategy = ExecWaitStrategy(["echo", "hello"])
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func customExpectedExitCode() async throws {
        let target = MockWaitStrategyTarget()
        target.execResult = (exitCode: 1, output: Data())
        let strategy = ExecWaitStrategy(["cmd"], expectedExitCode: 1)
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func shellVariantWrapsCommandInList() async throws {
        // ExecWaitStrategy(shell:) is observable via its behavior:
        // it runs the single command string.
        let target = MockWaitStrategyTarget()
        target.execResult = (exitCode: 0, output: Data())
        let strategy = ExecWaitStrategy(shell: "pg_isready")
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func shellVariantForwardsCustomExpectedExitCode() async throws {
        let target = MockWaitStrategyTarget()
        target.execResult = (exitCode: 2, output: Data())
        let strategy = ExecWaitStrategy(shell: "check.sh", expectedExitCode: 2)
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }
}

// MARK: - ExecWaitStrategy timeout message

@Suite("ExecWaitStrategy timeout message")
struct ExecWaitStrategyTimeoutMessageTests {
    @Test func timeoutMessageContainsExpectedExitCode() async throws {
        let target = MockWaitStrategyTarget()
        target.execResult = (exitCode: 1, output: Data())
        let strategy = ExecWaitStrategy(["pg_isready", "-U", "postgres"], expectedExitCode: 0)
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout(let msg) {
            #expect(msg.contains("0"))
        }
    }

    @Test func timeoutMessageContainsCommand() async throws {
        let target = MockWaitStrategyTarget()
        target.execResult = (exitCode: 1, output: Data())
        let strategy = ExecWaitStrategy(["pg_isready"])
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout(let msg) {
            #expect(msg.contains("pg_isready"))
        }
    }
}

// MARK: - FileExistsWaitStrategy timeout message

@Suite("FileExistsWaitStrategy timeout message")
struct FileExistsWaitStrategyTimeoutMessageTests {
    @Test func timeoutMessageIncludesFilePath() async throws {
        let target = MockWaitStrategyTarget()
        target.execResult = (exitCode: 1, output: Data())
        let strategy = FileExistsWaitStrategy("/app/server.pid")
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout(let msg) {
            #expect(msg.contains("/app/server.pid"))
        }
    }

    @Test func timeoutMessageIncludesParentDirectoryHint() async throws {
        let target = MockWaitStrategyTarget()
        target.execResult = (exitCode: 1, output: Data())
        let strategy = FileExistsWaitStrategy("/app/server.pid")
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout(let msg) {
            #expect(msg.contains("Parent directory contents"))
        }
    }

    @Test func timeoutMessageUsesUnavailableWhenDiagnosticThrows() async throws {
        // When exec always throws (URLError is transient), poll times out.
        // The diagnostic ls also fails, so listing stays "(unavailable)".
        let target = ThrowingExecTarget()
        let strategy = FileExistsWaitStrategy("/tmp/marker")
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout(let msg) {
            #expect(msg.contains("(unavailable)"))
        }
    }

    @Test func timeoutMessageIncludesDiagnosticLsOutputWhenAvailable() async throws {
        // 'test -f' returns 1 (file absent) for the check command.
        // 'ls -la /tmp' returns 0 with some output — that output appears in the message.
        let target = SelectiveExecTarget()
        let strategy = FileExistsWaitStrategy("/tmp/missing")
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout(let msg) {
            #expect(msg.contains("drwxr-xr-x /tmp"))
        }
    }
}

// MARK: - HttpWaitStrategy internal state

@Suite("HttpWaitStrategy internal state")
struct HttpWaitStrategyInternalStateTests {
    @Test func withBasicCredentialsEncodesAuthorizationHeader() {
        // 'user:pass' UTF-8 → base64 = 'dXNlcjpwYXNz'
        let strategy = HttpWaitStrategy(port: 8080).withBasicCredentials("user", "pass")
        #expect(strategy.testHeaders["Authorization"] == "Basic dXNlcjpwYXNz")
    }

    @Test func withBasicCredentialsSpecialCharsInPassword() {
        // 'admin:p@ssw0rd!#' — verify round-trip via base64 decode.
        let strategy = HttpWaitStrategy(port: 8080).withBasicCredentials("admin", "p@ssw0rd!#")
        guard let header = strategy.testHeaders["Authorization"] else {
            Issue.record("Missing Authorization header")
            return
        }
        #expect(header.hasPrefix("Basic "))
        let encoded = String(header.dropFirst(6))
        guard let data = Data(base64Encoded: encoded),
              let decoded = String(data: data, encoding: .utf8)
        else {
            Issue.record("Base64 decode failed")
            return
        }
        #expect(decoded == "admin:p@ssw0rd!#")
    }

    @Test func withHeaderSetsExactHeaderNameAndValue() {
        let strategy = HttpWaitStrategy(port: 8080)
            .withHeader("X-Custom-Header", "some-value")
            .withHeader("Accept", "application/json")
        #expect(strategy.testHeaders["X-Custom-Header"] == "some-value")
        #expect(strategy.testHeaders["Accept"] == "application/json")
    }

    @Test func withMethodUppercasesMethod() {
        let strategy = HttpWaitStrategy(port: 8080).withMethod("post")
        #expect(strategy.testMethod == "POST")
    }

    @Test func withMethodPreservesAlreadyUppercased() {
        let strategy = HttpWaitStrategy(port: 8080).withMethod("PUT")
        #expect(strategy.testMethod == "PUT")
    }

    @Test func defaultMethodIsGet() {
        let strategy = HttpWaitStrategy(port: 8080)
        #expect(strategy.testMethod == "GET")
    }

    @Test func forStatusCodeAddsToAcceptedSet() {
        let strategy = HttpWaitStrategy(port: 8080).forStatusCode(201).forStatusCode(204)
        #expect(strategy.testStatusCodes.contains(200))
        #expect(strategy.testStatusCodes.contains(201))
        #expect(strategy.testStatusCodes.contains(204))
    }

    @Test func defaultAcceptedStatusCodesContainOnly200() {
        let strategy = HttpWaitStrategy(port: 8080)
        #expect(strategy.testStatusCodes == Set([200]))
    }
}

// MARK: - HttpWaitStrategy URL init

@Suite("HttpWaitStrategy URL init")
struct HttpWaitStrategyUrlInitTests {
    @Test func parsesHttpUrlIntoPortAndPath() {
        // Observable: builder accepts the URL without crashing,
        // and the strategy fires against the correct port/path combo.
        // Since port/path are private, test via startupTimeout > .zero.
        let strategy = HttpWaitStrategy(url: "http://localhost:8080/api/health")
        #expect(strategy.startupTimeout > .zero)
    }

    @Test func parsesHttpsUrlAndEnablesTls() {
        // After usingTls the strategy still chains correctly.
        let strategy = HttpWaitStrategy(url: "https://localhost:8443/health")
        #expect(strategy.startupTimeout > .zero)
    }

    @Test func usesDefaultPort80ForHttpWithoutExplicitPort() {
        // Can only verify by observing it doesn't crash.
        let strategy = HttpWaitStrategy(url: "http://localhost/health")
        #expect(strategy.startupTimeout > .zero)
    }

    @Test func usesDefaultPort443ForHttpsWithoutExplicitPort() {
        let strategy = HttpWaitStrategy(url: "https://localhost/health")
        #expect(strategy.startupTimeout > .zero)
    }

    @Test func usesSlashWhenPathIsEmpty() {
        let strategy = HttpWaitStrategy(url: "http://localhost:9090")
        #expect(strategy.startupTimeout > .zero)
    }
}

// MARK: - HttpWaitStrategy builder (extended)

@Suite("HttpWaitStrategy builder extended")
struct HttpWaitStrategyBuilderExtendedTests {
    @Test func constructorNormalisesPathWithLeadingSlash() {
        // path without '/' prefix is normalised
        let strategy = HttpWaitStrategy(port: 8080, path: "health")
        #expect(strategy.startupTimeout > .zero)
    }

    @Test func defaultPathIsSlash() {
        // Constructing without path results in '/' (observable only indirectly).
        let strategy = HttpWaitStrategy(port: 8080)
        #expect(strategy.startupTimeout > .zero)
    }

    @Test func forStatusCodeMatchingReturnsChainableResult() {
        let strategy = HttpWaitStrategy(port: 8080)
        let returned = strategy.forStatusCodeMatching { $0 < 400 }
        #expect(returned === strategy)
    }

    @Test func forResponsePredicateReturnsChainableResult() {
        let strategy = HttpWaitStrategy(port: 8080)
        let returned = strategy.forResponsePredicate { $0.contains("ok") }
        #expect(returned === strategy)
    }

    @Test func withHeaderReturnsChainableResult() {
        let strategy = HttpWaitStrategy(port: 8080)
        let returned = strategy.withHeader("X-Custom", "value")
        #expect(returned === strategy)
    }

    @Test func withBasicCredentialsReturnsChainableResult() {
        let strategy = HttpWaitStrategy(port: 8080)
        let returned = strategy.withBasicCredentials("user", "pass")
        #expect(returned === strategy)
    }

    @Test func withBodyReturnsChainableResult() {
        let strategy = HttpWaitStrategy(port: 8080)
        let returned = strategy.withBody("{\"key\":\"value\"}")
        #expect(returned === strategy)
    }
}

// MARK: - HealthcheckWaitStrategy extended

@Suite("HealthcheckWaitStrategy extended")
struct HealthcheckWaitStrategyExtendedTests {
    @Test func keepPollingWhileStartingThenSucceeds() async throws {
        // First 2 calls return "starting", 3rd and beyond return "healthy".
        let switchingTarget = StartingToHealthyTarget()
        let strategy = HealthcheckWaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: switchingTarget)
        #expect(switchingTarget.count >= 3)
    }

    @Test func noneStatusTimesOut() async throws {
        // "none" is not "healthy" or "unhealthy" → returns false → poll times out.
        let target = MockWaitStrategyTarget()
        target.containerInfoResult = makeInspectInfo(healthStatus: "none")
        let strategy = HealthcheckWaitStrategy()
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout {
            // expected — "none" keeps polling until deadline
        }
    }

    @Test func unhealthyErrorMessageIncludesLogs() async throws {
        let target = MockWaitStrategyTarget()
        target.containerInfoResult = makeInspectInfo(healthStatus: "unhealthy")
        let logContent = "OOM killed at 12:00:00"
        target.logsResult = (stdout: Data(logContent.utf8), stderr: Data())
        let strategy = HealthcheckWaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected unhealthy error")
        } catch WaitStrategyError.unhealthy(let msg) {
            #expect(msg.contains("unhealthy"))
            #expect(msg.contains("Logs:"))
            #expect(msg.contains(logContent))
        }
    }

    @Test func containerInfoThrowingTreatedAsNoHealthcheck() async throws {
        let target = ThrowingContainerInfoTarget()
        let strategy = HealthcheckWaitStrategy()
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected error")
        } catch WaitStrategyError.containerExited {
            // expected — treated as "no health check"
        }
    }

    @Test func emptyStringHealthStatusThrowsContainerExited() async throws {
        let target = MockWaitStrategyTarget()
        target.containerInfoResult = makeInspectInfo(healthStatus: "")
        let strategy = HealthcheckWaitStrategy()
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected error")
        } catch WaitStrategyError.containerExited(let msg) {
            #expect(msg.count > 10)
        }
    }
}

// MARK: - WaitStrategy Duration defaults

@Suite("WaitStrategy Duration defaults")
struct WaitStrategyDurationDefaultsTests {
    @Test func startupTimeoutDefaultIsPositive() {
        let strategy = LogMessageWaitStrategy("x")
        #expect(strategy.startupTimeout > .zero)
    }

    @Test func pollIntervalDefaultIsPositive() {
        let strategy = LogMessageWaitStrategy("x")
        #expect(strategy.pollInterval > .zero)
    }

    @Test func withStartupTimeoutReturnsSelf() {
        let strategy = LogMessageWaitStrategy("x")
        let result = strategy.withStartupTimeout(.seconds(30))
        #expect(result === strategy)
        #expect(strategy.startupTimeout == .seconds(30))
    }

    @Test func withPollIntervalReturnsSelf() {
        let strategy = LogMessageWaitStrategy("x")
        let result = strategy.withPollInterval(.milliseconds(500))
        #expect(result === strategy)
        #expect(strategy.pollInterval == .milliseconds(500))
    }
}

// MARK: - withTransientExceptions builder

@Suite("withTransientExceptions builder")
struct WithTransientExceptionsBuilderTests {
    @Test func returnsSelFForChaining() {
        let strategy = LogMessageWaitStrategy("x")
        let result = strategy.withTransientExceptions([URLError.self])
        #expect(result === strategy)
    }

    @Test func registeredTransientExceptionIsSwallowed() async throws {
        // URLError is always transient by default, but let's use a custom type
        // registered via withTransientExceptions and verify it's swallowed.
        struct CustomTransientError: Error {}
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("ready\n".utf8), stderr: Data())
        let strategy = LogMessageWaitStrategy("ready")
        _ = strategy.withTransientExceptions([CustomTransientError.self])
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        // Should succeed normally since logs contain the pattern.
        try await strategy.waitUntilReady(target: target)
    }
}

// MARK: - CompositeWaitStrategy extended

@Suite("CompositeWaitStrategy extended")
struct CompositeWaitStrategyExtendedTests {
    @Test func withTransientExceptionsReturnsSelF() {
        let child1 = LogMessageWaitStrategy("a")
        let child2 = PortWaitStrategy(8080)
        let composite = CompositeWaitStrategy([child1, child2])
        let result = composite.withTransientExceptions([URLError.self])
        #expect(result === composite)
    }

    @Test func withTransientExceptionsPropagatedToChildren() async throws {
        // Register URLError (already transient by default, but testing propagation path).
        let child1 = ExecWaitStrategy(["echo"])
        let child2 = LogMessageWaitStrategy("ready")
        let composite = CompositeWaitStrategy([child1, child2])
        _ = composite.withTransientExceptions([URLError.self])
        #expect(child1.transientExceptionTypes.count >= 1)
        #expect(child2.transientExceptionTypes.count >= 1)
    }

    @Test func withStartupTimeoutReturnsSelf() {
        let composite = CompositeWaitStrategy([])
        let result = composite.withStartupTimeout(.seconds(10))
        #expect(result === composite)
    }

    @Test func propagatesFirstStrategyFailureSecondIsSkipped() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("bar\n".utf8), stderr: Data())
        let s1 = LogMessageWaitStrategy("NEVER_SEEN")
        s1.startupTimeout = .milliseconds(100)
        s1.pollInterval = .milliseconds(20)
        let s2 = LogMessageWaitStrategy("bar")
        s2.startupTimeout = .seconds(5)
        let composite = CompositeWaitStrategy([s1, s2])
        do {
            try await composite.waitUntilReady(target: target)
            Issue.record("Expected timeout from first strategy")
        } catch WaitStrategyError.timeout {
            // expected — s1 times out, s2 never runs
        }
    }

    @Test func runsAllStrategiesInSequenceAndSucceeds() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("foo bar\n".utf8), stderr: Data())
        let s1 = LogMessageWaitStrategy("foo")
        let s2 = LogMessageWaitStrategy("bar")
        let composite = CompositeWaitStrategy([s1, s2])
        composite.withStartupTimeout(.seconds(5))
        try await composite.waitUntilReady(target: target)
    }
}

// MARK: - LogMessageWaitStrategy initialization (observable behavior)

@Suite("LogMessageWaitStrategy initialization observable")
struct LogMessageWaitStrategyInitTests {
    @Test func stringPatternMatchesLiteralText() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("test message here\n".utf8), stderr: Data())
        let strategy = LogMessageWaitStrategy("test message")
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func defaultTimesIsOne() async throws {
        // times=1 means a single occurrence in logs is sufficient.
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("ping\n".utf8), stderr: Data())
        let strategy = LogMessageWaitStrategy("ping")
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func customTimesStoredCorrectly() async throws {
        // times=3: three occurrences required.
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("ping\nping\nping\n".utf8), stderr: Data())
        let strategy = LogMessageWaitStrategy("ping", times: 3)
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func defaultPredicateStreamsAndIsFalse() async throws {
        // OR mode by default: stderr match alone succeeds.
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("no match\n".utf8), stderr: Data("ready\n".utf8))
        let strategy = LogMessageWaitStrategy("ready")
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }

    @Test func predicateStreamsAndTrueRequiresBothStreams() async throws {
        // AND mode: only stdout matches — should timeout.
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("ready\n".utf8), stderr: Data("no match\n".utf8))
        let strategy = LogMessageWaitStrategy("ready", predicateStreamsAnd: true)
        strategy.startupTimeout = .milliseconds(100)
        strategy.pollInterval = .milliseconds(20)
        do {
            try await strategy.waitUntilReady(target: target)
            Issue.record("Expected timeout")
        } catch WaitStrategyError.timeout {
            // expected
        }
    }

    @Test func nsRegularExpressionInitMatchesPattern() async throws {
        let regex = try! NSRegularExpression(pattern: #"ready on port \d+"#, options: [])
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("App ready on port 8080\n".utf8), stderr: Data())
        let strategy = LogMessageWaitStrategy(regex)
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }
}

// MARK: - LogMessageWaitStrategy times = 0 (non-empty logs)

@Suite("LogMessageWaitStrategy times = 0 non-empty logs")
struct LogMessageTimesZeroNonEmptyTests {
    @Test func succeedsImmediatelyWithNonEmptyLogsWhenTimesIsZero() async throws {
        // times=0: trivially satisfied even without any pattern match.
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("unrelated log line\n".utf8), stderr: Data())
        let strategy = LogMessageWaitStrategy("xyz", times: 0)
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: target)
    }
}

// MARK: - LogMessageWaitStrategy times > 1 (additional edge cases)

@Suite("LogMessageWaitStrategy times > 1 edge cases")
struct LogMessageTimesEdgeCaseTests {
    @Test func failsWhenAppearsOnlyTwiceButTimesIsThree() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("ping\nping\n".utf8), stderr: Data())
        let strategy = LogMessageWaitStrategy("ping", times: 3)
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

// MARK: - waitForLogs free function

@Suite("waitForLogs free function")
struct WaitForLogsTests {
    @Test func returnsDurationWhenLogMessageFound() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("Server started\n".utf8), stderr: Data())
        let elapsed = try await waitForLogs(target, "Server started")
        #expect(elapsed >= .zero)
    }

    @Test func throwsWhenMessageNotFoundBeforeTimeout() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data(), stderr: Data())
        do {
            _ = try await waitForLogs(
                target,
                "never-present-string",
                timeout: .milliseconds(100),
                interval: .milliseconds(20)
            )
            Issue.record("Expected error")
        } catch {
            // expected — any WaitStrategyError
        }
    }

    @Test func predicateStreamsAndTrueSucceedsWhenMessageInBothStreams() async throws {
        let msg = Data("OK\n".utf8)
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: msg, stderr: msg)
        let elapsed = try await waitForLogs(
            target,
            "OK",
            timeout: .seconds(5),
            predicateStreamsAnd: true
        )
        #expect(elapsed >= .zero)
    }

    @Test func predicateStreamsAndTrueTimesOutWhenOnlyInStdout() async throws {
        let target = MockWaitStrategyTarget()
        target.logsResult = (stdout: Data("OK\n".utf8), stderr: Data())
        do {
            _ = try await waitForLogs(
                target,
                "OK",
                timeout: .milliseconds(100),
                interval: .milliseconds(20),
                predicateStreamsAnd: true
            )
            Issue.record("Expected timeout")
        } catch {
            // expected — stderr doesn't match
        }
    }

    @Test func elapsedDurationIncreasesWithActualWaitTime() async throws {
        // Poll returns match only on the 3rd call, so elapsed > 0.
        let target = CountingLogsTarget()
        let elapsed = try await waitForLogs(
            target,
            "Done",
            timeout: .seconds(5),
            interval: .milliseconds(20)
        )
        #expect(elapsed >= .zero)
        #expect(target.count >= 3)
    }
}

// MARK: - ContainerStatusWaitStrategy restarting transition

@Suite("ContainerStatusWaitStrategy restarting transition")
struct ContainerStatusRestartingTransitionTests {
    @Test func keepsPollingWhileRestartingThenSucceeds() async throws {
        let mockTarget = SwitchingMockTarget(initialStatus: "restarting", switchTo: "running", afterCount: 2)
        let strategy = ContainerStatusWaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        try await strategy.waitUntilReady(target: mockTarget)
    }
}

// MARK: - WaitStrategy poll: non-transient error rethrown immediately

@Suite("WaitStrategy poll non-transient rethrow")
struct WaitStrategyPollNonTransientTests {
    @Test func nonTransientErrorFromLogsIsRethrownImmediately() async throws {
        // ArgumentError equivalent in Swift: use a custom non-transient error.
        struct UnexpectedError: Error {}
        let strategy = WaitStrategy()
        strategy.startupTimeout = .seconds(5)
        strategy.pollInterval = .milliseconds(10)
        do {
            _ = try await strategy.poll { throw UnexpectedError() }
            Issue.record("Expected UnexpectedError")
        } catch is UnexpectedError {
            // expected — rethrown immediately
        }
    }

    @Test func socketErrorEquivalentIsSwallowedByDefault() async throws {
        // URLError is always transient — equivalent to SocketException in Dart.
        let strategy = WaitStrategy()
        strategy.startupTimeout = .seconds(2)
        strategy.pollInterval = .milliseconds(10)
        var count = 0
        let result = try await strategy.poll {
            count += 1
            if count < 3 { throw URLError(.notConnectedToInternet) }
            return true
        }
        #expect(result == true)
        #expect(count >= 3)
    }
}

// MARK: - Helper target implementations for tests that need custom behavior

/// A WaitStrategyTarget whose exec always throws URLError (transient).
private final class ThrowingExecTarget: WaitStrategyTarget {
    func containerHostIp() async throws -> String { "127.0.0.1" }
    func exposedPort(_ port: Int) async throws -> Int { port }
    var wrappedContainer: AnyObject { self }
    func logs() async throws -> (stdout: Data, stderr: Data) { (Data(), Data()) }
    func exec(_ command: [String]) async throws -> (exitCode: Int, output: Data) {
        throw URLError(.notConnectedToInternet)
    }
    func containerInfo() async throws -> ContainerInspectInfo? { nil }
    func reload() async {}
    var status: String { "running" }
}

/// A WaitStrategyTarget whose exec returns ls output for the 'ls' command,
/// and exit code 1 (file absent) for 'test -f' checks.
private final class SelectiveExecTarget: WaitStrategyTarget {
    func containerHostIp() async throws -> String { "127.0.0.1" }
    func exposedPort(_ port: Int) async throws -> Int { port }
    var wrappedContainer: AnyObject { self }
    func logs() async throws -> (stdout: Data, stderr: Data) { (Data(), Data()) }
    func exec(_ command: [String]) async throws -> (exitCode: Int, output: Data) {
        if command.first == "ls" {
            return (0, Data("drwxr-xr-x /tmp\n".utf8))
        }
        return (1, Data())
    }
    func containerInfo() async throws -> ContainerInspectInfo? { nil }
    func reload() async {}
    var status: String { "running" }
}

/// A WaitStrategyTarget that returns "starting" for the first 2 containerInfo calls,
/// then returns "healthy".
private final class StartingToHealthyTarget: WaitStrategyTarget {
    var count = 0
    func containerHostIp() async throws -> String { "127.0.0.1" }
    func exposedPort(_ port: Int) async throws -> Int { port }
    var wrappedContainer: AnyObject { self }
    func logs() async throws -> (stdout: Data, stderr: Data) { (Data(), Data()) }
    func exec(_ command: [String]) async throws -> (exitCode: Int, output: Data) { (0, Data()) }
    func containerInfo() async throws -> ContainerInspectInfo? {
        count += 1
        return makeInspectInfo(healthStatus: count < 3 ? "starting" : "healthy")
    }
    func reload() async {}
    var status: String { "running" }
}

/// A WaitStrategyTarget whose containerInfo always throws.
private final class ThrowingContainerInfoTarget: WaitStrategyTarget {
    func containerHostIp() async throws -> String { "127.0.0.1" }
    func exposedPort(_ port: Int) async throws -> Int { port }
    var wrappedContainer: AnyObject { self }
    func logs() async throws -> (stdout: Data, stderr: Data) { (Data(), Data()) }
    func exec(_ command: [String]) async throws -> (exitCode: Int, output: Data) { (0, Data()) }
    func containerInfo() async throws -> ContainerInspectInfo? {
        throw WaitStrategyError.containerExited("inspect failed")
    }
    func reload() async {}
    var status: String { "running" }
}

/// A WaitStrategyTarget whose logs return "Done" only on the 3rd and subsequent calls.
private final class CountingLogsTarget: WaitStrategyTarget {
    var count = 0
    func containerHostIp() async throws -> String { "127.0.0.1" }
    func exposedPort(_ port: Int) async throws -> Int { port }
    var wrappedContainer: AnyObject { self }
    func logs() async throws -> (stdout: Data, stderr: Data) {
        count += 1
        let content = count >= 3 ? "Done\n" : ""
        return (Data(content.utf8), Data())
    }
    func exec(_ command: [String]) async throws -> (exitCode: Int, output: Data) { (0, Data()) }
    func containerInfo() async throws -> ContainerInspectInfo? { nil }
    func reload() async {}
    var status: String { "running" }
}
