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

    func containerHostIp() async throws -> String { "127.0.0.1" }
    func exposedPort(_ port: Int) async throws -> Int { exposedPortValue }
    var wrappedContainer: AnyObject { self }
    func logs() async throws -> (stdout: Data, stderr: Data) { logsResult }
    func exec(_ command: [String]) async throws -> (exitCode: Int, output: Data) { execResult }
    func containerInfo() async throws -> ContainerInspectInfo? { nil }
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
}
