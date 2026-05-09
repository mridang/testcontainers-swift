import Testing

@testable import TestcontainersCore

@Suite("ContainerStartException")
struct ContainerStartExceptionTests {
    @Test func hasMessage() {
        let e = ContainerStartException("failed to start")
        #expect(e.message == "failed to start")
    }

    @Test func localizedDescriptionContainsClassName() {
        let e = ContainerStartException("boom")
        #expect(e.localizedDescription.contains("ContainerStartException"))
        #expect(e.localizedDescription.contains("boom"))
    }

    @Test func exactToStringFormat() {
        let e = ContainerStartException("boom")
        #expect(e.localizedDescription == "ContainerStartException: boom")
    }

    @Test func canBeThrown() throws {
        #expect(throws: ContainerStartException.self) {
            throw ContainerStartException("boom")
        }
    }
}

@Suite("ContainerConnectException")
struct ContainerConnectExceptionTests {
    @Test func hasMessage() {
        let e = ContainerConnectException("cannot connect")
        #expect(e.message == "cannot connect")
    }

    @Test func exactFormat() {
        let e = ContainerConnectException("oops")
        #expect(e.localizedDescription == "ContainerConnectException: oops")
    }

    @Test func canBeThrown() throws {
        #expect(throws: ContainerConnectException.self) {
            throw ContainerConnectException("oops")
        }
    }
}

@Suite("ContainerIsNotRunning")
struct ContainerIsNotRunningTests {
    @Test func hasMessage() {
        let e = ContainerIsNotRunning("not running")
        #expect(e.message == "not running")
    }

    @Test func exactFormat() {
        let e = ContainerIsNotRunning("dead")
        #expect(e.localizedDescription == "ContainerIsNotRunning: dead")
    }

    @Test func canBeThrown() throws {
        #expect(throws: ContainerIsNotRunning.self) {
            throw ContainerIsNotRunning("dead")
        }
    }
}

@Suite("NoSuchPortExposed")
struct NoSuchPortExposedTests {
    @Test func hasMessage() {
        let e = NoSuchPortExposed("port 8080 not exposed")
        #expect(e.message == "port 8080 not exposed")
    }

    @Test func exactFormat() {
        let e = NoSuchPortExposed("9999")
        #expect(e.localizedDescription == "NoSuchPortExposed: 9999")
    }

    @Test func canBeThrown() throws {
        #expect(throws: NoSuchPortExposed.self) {
            throw NoSuchPortExposed("9999")
        }
    }
}

@Suite("Exception type isolation")
struct ExceptionIsolationTests {
    @Test func startIsNotConnect() {
        let e: Error = ContainerStartException("x")
        #expect(!(e is ContainerConnectException))
    }

    @Test func isNotRunningIsNotStart() {
        let e: Error = ContainerIsNotRunning("x")
        #expect(!(e is ContainerStartException))
    }

    @Test func noSuchPortIsNotIsNotRunning() {
        let e: Error = NoSuchPortExposed("x")
        #expect(!(e is ContainerIsNotRunning))
    }

    @Test func allFourTypesAreDistinct() {
        let a: any Error = ContainerStartException("a")
        let b: any Error = ContainerConnectException("b")
        let c: any Error = ContainerIsNotRunning("c")
        let d: any Error = NoSuchPortExposed("d")
        // Each is a different concrete type
        #expect(!(a is ContainerConnectException))
        #expect(!(b is ContainerIsNotRunning))
        #expect(!(c is NoSuchPortExposed))
        #expect(!(d is ContainerStartException))
    }
}
