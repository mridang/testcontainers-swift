/// Concrete wait strategies for testcontainers-swift.
///
/// All 8 strategies are 1:1 ports of the Dart/Python implementations.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - 1. LogMessageWaitStrategy

/// Waits until a pattern appears in the container's log output.
///
/// By default stdout OR stderr must contain the pattern. Set
/// `predicateStreamsAnd: true` to require both streams to match.
public final class LogMessageWaitStrategy: WaitStrategy {
    private let pattern: NSRegularExpression
    private let times: Int
    private let predicateStreamsAnd: Bool

    /// Creates a strategy waiting for `pattern` to appear in container logs.
    ///
    /// - Parameters:
    ///   - pattern: A `String` (compiled as a multiline regex) or `NSRegularExpression`.
    ///   - times: Number of times the pattern must appear. Default `1`.
    ///   - predicateStreamsAnd: When `true`, both stdout AND stderr must match.
    public init(
        _ pattern: String,
        times: Int = 1,
        predicateStreamsAnd: Bool = false
    ) {
        self.pattern = (try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]))
            ?? NSRegularExpression()
        self.times = times
        self.predicateStreamsAnd = predicateStreamsAnd
        super.init()
    }

    public init(
        _ pattern: NSRegularExpression,
        times: Int = 1,
        predicateStreamsAnd: Bool = false
    ) {
        self.pattern = pattern
        self.times = times
        self.predicateStreamsAnd = predicateStreamsAnd
        super.init()
    }

    private func countMatches(in text: String) -> Int {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.numberOfMatches(in: text, range: range)
    }

    override public func waitUntilReady(target: any WaitStrategyTarget) async throws {
        let ready = try await poll {
            target.reload()
            let (stdoutData, stderrData) = try target.logs()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            if self.predicateStreamsAnd {
                return self.countMatches(in: stdout) >= self.times
                    && self.countMatches(in: stderr) >= self.times
            } else {
                return self.countMatches(in: stdout) + self.countMatches(in: stderr) >= self.times
            }
        }

        if !ready {
            if !notExitedStatuses.contains(target.status) {
                throw WaitStrategyError.containerExited(
                    "Container exited before log message matched. Status: \(target.status)"
                )
            }
            throw WaitStrategyError.timeout(
                "Log message '\(pattern.pattern)' not found within \(startupTimeout). "
                    + "Container status: \(target.status)"
            )
        }
    }
}

// MARK: - 2. HttpWaitStrategy

/// Waits until an HTTP endpoint returns a successful response.
public final class HttpWaitStrategy: WaitStrategy {
    private let port: Int
    private let path: String
    private var statusCodes: Set<Int> = [200]
    private var statusCodePredicate: ((Int) -> Bool)?
    private var responsePredicate: ((String) -> Bool)?
    private var useTls: Bool = false
    private var insecureTls: Bool = false
    private var headers: [String: String] = [:]
    private var method: String = "GET"
    private var body: String?

    /// Creates a strategy waiting for an HTTP response on `port` at `path`.
    public init(port: Int, path: String = "/") {
        self.port = port
        self.path = path
        super.init()
    }

    @discardableResult public func forStatusCode(_ code: Int) -> Self {
        statusCodes = [code]; return self
    }

    @discardableResult public func forStatusCodeMatching(_ pred: @escaping (Int) -> Bool) -> Self {
        statusCodePredicate = pred; return self
    }

    @discardableResult public func forResponsePredicate(_ pred: @escaping (String) -> Bool) -> Self {
        responsePredicate = pred; return self
    }

    @discardableResult public func usingTls(insecure: Bool = false) -> Self {
        useTls = true; insecureTls = insecure; return self
    }

    @discardableResult public func withHeader(_ name: String, _ value: String) -> Self {
        headers[name] = value; return self
    }

    @discardableResult public func withBasicCredentials(_ user: String, _ password: String) -> Self {
        let encoded = Data("\(user):\(password)".utf8).base64EncodedString()
        headers["Authorization"] = "Basic \(encoded)"
        return self
    }

    @discardableResult public func withMethod(_ m: String) -> Self {
        method = m; return self
    }

    @discardableResult public func withBody(_ b: String) -> Self {
        body = b; return self
    }

    override public func waitUntilReady(target: any WaitStrategyTarget) async throws {
        let scheme = useTls ? "https" : "http"
        let host = target.containerHostIp()
        let mappedPort = try await target.exposedPort(port)
        let urlString = "\(scheme)://\(host):\(mappedPort)\(path)"

        let ready = try await poll(transientExceptions: [URLError.self]) {
            guard let url = URL(string: urlString) else { return false }
            var request = URLRequest(url: url, timeoutInterval: 1.0)
            request.httpMethod = self.method
            for (k, v) in self.headers { request.setValue(v, forHTTPHeaderField: k) }
            if let b = self.body { request.httpBody = Data(b.utf8) }

            let session: URLSession
            if self.insecureTls {
                let config = URLSessionConfiguration.default
                session = URLSession(configuration: config, delegate: InsecureTLSDelegate(), delegateQueue: nil)
            } else {
                session = URLSession.shared
            }

            let (data, response) = try await session.data(for: request)
            guard let httpResp = response as? HTTPURLResponse else { return false }
            let code = httpResp.statusCode

            // statusCode < 300 = success
            let codeOk: Bool
            if let pred = self.statusCodePredicate {
                codeOk = pred(code)
            } else {
                codeOk = self.statusCodes.contains(code)
            }
            guard codeOk else {
                throw URLError(.badServerResponse)
            }
            if let pred = self.responsePredicate {
                let body = String(data: data, encoding: .utf8) ?? ""
                return pred(body)
            }
            return true
        }

        if !ready {
            throw WaitStrategyError.timeout("HTTP endpoint \(urlString) not ready within \(startupTimeout).")
        }
    }
}

// Accept any TLS certificate (for insecure mode)
private final class InsecureTLSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - 3. HealthcheckWaitStrategy

/// Waits until the container's built-in health check reports `"healthy"`.
public final class HealthcheckWaitStrategy: WaitStrategy {
    override public func waitUntilReady(target: any WaitStrategyTarget) async throws {
        let ready = try await poll {
            target.reload()
            // Health status requires an inspect; check via logs/status is approximated
            // by reading status string from target which must be set by the container
            // Containers implementing this must expose "healthy"/"unhealthy" via status.
            let s = target.status
            if s == "unhealthy" {
                let (stdout, _) = try target.logs()
                let logText = String(data: stdout, encoding: .utf8) ?? ""
                throw WaitStrategyError.unhealthy("Container is unhealthy. Logs:\n\(logText)")
            }
            if s == "healthy" { return true }
            if !notExitedStatuses.contains(s) {
                throw StopPollingError()
            }
            return false
        }
        if !ready {
            throw WaitStrategyError.timeout("Container did not become healthy within \(startupTimeout).")
        }
    }
}

// MARK: - 4. PortWaitStrategy

/// Waits until the container's port accepts TCP connections.
public final class PortWaitStrategy: WaitStrategy {
    private let port: Int

    public init(_ port: Int) {
        self.port = port
        super.init()
    }

    override public func waitUntilReady(target: any WaitStrategyTarget) async throws {
        let host = target.containerHostIp()
        let mappedPort = try await target.exposedPort(port)

        let ready = try await poll {
            do {
                let socket = try await withTimeout(.seconds(1)) {
                    try await TCPProbe.connect(host: host, port: mappedPort)
                }
                socket.close()
                return true
            } catch {
                return false
            }
        }
        if !ready {
            throw WaitStrategyError.timeout("Port \(port) not open within \(startupTimeout).")
        }
    }
}

// MARK: - 5. FileExistsWaitStrategy

/// Waits until a specific file exists on the container's filesystem.
///
/// Runs `test -f <filePath>` inside the container on each poll attempt.
public final class FileExistsWaitStrategy: WaitStrategy {
    /// The absolute path inside the container to check for existence.
    public let filePath: String

    public init(_ filePath: String) {
        self.filePath = filePath
        super.init()
    }

    override public func waitUntilReady(target: any WaitStrategyTarget) async throws {
        let fp = filePath
        let ready = try await poll {
            let (exitCode, _) = try await target.exec(["test", "-f", fp])
            return exitCode == 0
        }
        if !ready {
            var listing = "(unavailable)"
            let parent = (filePath as NSString).deletingLastPathComponent
            if let (_, output) = try? await target.exec(["ls", "-la", parent]) {
                listing = String(data: output, encoding: .utf8) ?? listing
            }
            throw WaitStrategyError.timeout(
                "File \(filePath) not found in container within \(startupTimeout). "
                    + "Parent directory contents: \(listing)"
            )
        }
    }
}

// MARK: - 6. ContainerStatusWaitStrategy

/// Waits until the container's lifecycle status is `"running"`.
///
/// If the status moves to any state not in `continueStatuses`, stops
/// immediately and throws rather than waiting for the full timeout.
public final class ContainerStatusWaitStrategy: WaitStrategy {
    public static let continueStatuses: Set<String> = ["created", "restarting"]

    override public func waitUntilReady(target: any WaitStrategyTarget) async throws {
        let ready = try await poll {
            target.reload()
            let s = target.status
            if s == "running" { return true }
            if !Self.continueStatuses.contains(s) {
                throw StopPollingError()
            }
            return false
        }
        if !ready {
            throw WaitStrategyError.timeout(
                "Container never reached 'running' status. Final status: \(target.status)"
            )
        }
    }
}

// MARK: - 7. CompositeWaitStrategy

/// Runs multiple wait strategies in sequence.
public final class CompositeWaitStrategy: WaitStrategy {
    private var strategies: [WaitStrategy]

    public init(_ strategies: WaitStrategy...) {
        self.strategies = strategies
        super.init()
    }

    override public func withStartupTimeout(_ timeout: Duration) -> Self {
        for s in strategies { s.withStartupTimeout(timeout) }
        startupTimeout = timeout
        return self
    }

    override public func withPollInterval(_ interval: Duration) -> Self {
        for s in strategies { s.withPollInterval(interval) }
        pollInterval = interval
        return self
    }

    override public func waitUntilReady(target: any WaitStrategyTarget) async throws {
        for strategy in strategies {
            try await strategy.waitUntilReady(target: target)
        }
    }
}

// MARK: - 8. ExecWaitStrategy

/// Waits until running a command inside the container exits with an expected code.
public final class ExecWaitStrategy: WaitStrategy {
    private let command: [String]
    private let expectedExitCode: Int

    public init(_ command: [String], expectedExitCode: Int = 0) {
        self.command = command
        self.expectedExitCode = expectedExitCode
        super.init()
    }

    override public func waitUntilReady(target: any WaitStrategyTarget) async throws {
        let cmd = command
        let expected = expectedExitCode
        let ready = try await poll {
            let (exitCode, _) = try await target.exec(cmd)
            return exitCode == expected
        }
        if !ready {
            throw WaitStrategyError.timeout(
                "Exec command \(command) did not return exit code \(expectedExitCode) within \(startupTimeout)."
            )
        }
    }
}

// MARK: - Errors

/// Errors thrown by wait strategies.
public enum WaitStrategyError: Error, CustomStringConvertible {
    case timeout(String)
    case containerExited(String)
    case unhealthy(String)

    public var description: String {
        switch self {
        case .timeout(let m), .containerExited(let m), .unhealthy(let m): return m
        }
    }
}

// MARK: - TCP probe helper

private struct TCPSocket {
    let fd: Int32
    func close() { Foundation.close(fd) }
}

private enum TCPProbe {
    static func connect(host: String, port: Int) async throws -> TCPSocket {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var res: UnsafeMutablePointer<addrinfo>?
                defer { if res != nil { freeaddrinfo(res) } }

                let portStr = "\(port)"
                let rc = getaddrinfo(host, portStr, &hints, &res)
                guard rc == 0, let info = res else {
                    continuation.resume(throwing: URLError(.cannotConnectToHost))
                    return
                }
                let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
                guard fd >= 0 else {
                    continuation.resume(throwing: URLError(.cannotConnectToHost))
                    return
                }
                let connRc = Foundation.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
                if connRc == 0 {
                    continuation.resume(returning: TCPSocket(fd: fd))
                } else {
                    Foundation.close(fd)
                    continuation.resume(throwing: URLError(.cannotConnectToHost))
                }
            }
        }
    }
}

// MARK: - Timeout helper

private func withTimeout<T: Sendable>(_ duration: Duration, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw URLError(.timedOut)
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
