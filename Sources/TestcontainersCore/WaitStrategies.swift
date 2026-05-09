/// Concrete wait strategies for testcontainers-swift.
///
/// All 8 strategies are 1:1 ports of the Dart/Python implementations.
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - waitForLogs convenience function

/// Waits until a specific log message appears in the container's output.
///
/// Convenience wrapper around `LogMessageWaitStrategy`.
///
/// - Parameters:
///   - container: The target container to watch.
///   - predicate: A pattern string to search for in the container's log output.
///   - timeout: Maximum wait time. Defaults to `testcontainersConfig.timeout`.
///   - interval: Poll interval. Default: 1 second.
///   - predicateStreamsAnd: When `true`, the pattern must match **both** stdout
///     and stderr. Default: `false`.
/// - Returns: The elapsed `Duration` from start to the log message appearing.
@discardableResult
public func waitForLogs(
    _ container: any WaitStrategyTarget,
    _ predicate: String,
    timeout: Duration? = nil,
    interval: Duration = .seconds(1),
    predicateStreamsAnd: Bool = false
) async throws -> Duration {
    let cfg = testcontainersConfig
    let effectiveTimeout = timeout ?? .milliseconds(Int(cfg.timeout * 1000))
    let strategy = LogMessageWaitStrategy(predicate, predicateStreamsAnd: predicateStreamsAnd)
    _ = strategy.withStartupTimeout(effectiveTimeout)
    _ = strategy.withPollInterval(interval)
    let start = ContinuousClock.now
    try await strategy.waitUntilReady(target: container)
    return ContinuousClock.now - start
}

// MARK: - 1. LogMessageWaitStrategy

/// Waits until a pattern appears in the container's log output.
///
/// By default stdout OR stderr must contain the pattern. Set
/// `predicateStreamsAnd: true` to require both streams to match.
public final class LogMessageWaitStrategy: WaitStrategy {
    private let pattern: NSRegularExpression
    private let times: Int
    private let predicateStreamsAnd: Bool

    // A regex that never matches anything — used as a safe fallback when an
    // invalid pattern string is supplied (avoids a crash while also never
    // accidentally succeeding).
    private static let neverMatchPattern = try! NSRegularExpression(pattern: "(?!)", options: [])

    /// Creates a strategy waiting for `pattern` to appear in container logs.
    ///
    /// - Parameters:
    ///   - pattern: A `String` compiled as a multiline regex.
    ///   - times: Number of times the pattern must appear. Default `1`.
    ///   - predicateStreamsAnd: When `true`, both stdout AND stderr must match.
    public init(
        _ pattern: String,
        times: Int = 1,
        predicateStreamsAnd: Bool = false
    ) {
        self.pattern =
            (try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]))
            ?? LogMessageWaitStrategy.neverMatchPattern
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
            await target.reload()
            let (stdoutData, stderrData) = try await target.logs()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            if self.predicateStreamsAnd {
                return self.countMatches(in: stdout) >= self.times
                    && self.countMatches(in: stderr) >= self.times
            } else {
                return self.countMatches(in: stdout) >= self.times
                    || self.countMatches(in: stderr) >= self.times
            }
        }

        if !ready {
            if !notExitedStatuses.contains(target.status) {
                throw WaitStrategyError.containerExited(
                    "Container exited before log message found. Status: \(target.status)"
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
    private var _statusCodes: Set<Int> = [200]
    private var _statusCodeMatcher: ((Int) -> Bool)?
    private var _responsePredicate: ((String) -> Bool)?
    private var _useTls: Bool = false
    private var _insecureTls: Bool = false
    private var _headers: [String: String] = [:]
    private var _method: String = "GET"
    private var _body: String?

    /// Creates a strategy waiting for an HTTP response on `port` at `path`.
    ///
    /// `path` defaults to `"/"` and is normalised to start with `/`.
    public init(port: Int, path: String = "/") {
        self.port = port
        self.path = path.hasPrefix("/") ? path : "/\(path)"
        super.init()
    }

    /// Creates an `HttpWaitStrategy` from a full URL string.
    ///
    /// The port, path, and TLS flag are extracted automatically from `url`.
    /// When the scheme is `https`, `usingTls()` is called implicitly.
    public convenience init(url: String) {
        guard let parsed = URLComponents(string: url) else {
            self.init(port: 80)
            return
        }
        let effectivePort: Int
        if let port = parsed.port {
            effectivePort = port
        } else {
            effectivePort = parsed.scheme == "https" ? 443 : 80
        }
        let effectivePath = parsed.path.isEmpty ? "/" : parsed.path
        self.init(port: effectivePort, path: effectivePath)
        if parsed.scheme == "https" {
            _ = self.usingTls()
        }
    }

    @discardableResult public func forStatusCode(_ code: Int) -> Self {
        _statusCodes.insert(code)
        return self
    }

    @discardableResult public func forStatusCodeMatching(_ pred: @escaping (Int) -> Bool) -> Self {
        _statusCodeMatcher = pred
        return self
    }

    @discardableResult public func forResponsePredicate(_ pred: @escaping (String) -> Bool) -> Self {
        _responsePredicate = pred
        return self
    }

    @discardableResult public func usingTls(insecure: Bool = false) -> Self {
        _useTls = true
        _insecureTls = insecure
        return self
    }

    @discardableResult public func withHeader(_ name: String, _ value: String) -> Self {
        _headers[name] = value
        return self
    }

    @discardableResult public func withBasicCredentials(_ user: String, _ password: String) -> Self {
        let encoded = Data("\(user):\(password)".utf8).base64EncodedString()
        _headers["Authorization"] = "Basic \(encoded)"
        return self
    }

    @discardableResult public func withMethod(_ m: String) -> Self {
        _method = m.uppercased()
        return self
    }

    @discardableResult public func withBody(_ b: String) -> Self {
        _body = b
        return self
    }

    /// The current set of HTTP headers that will be sent with each probe request.
    /// Exposed for unit testing only.
    public var testHeaders: [String: String] { _headers }

    /// The HTTP method that will be used for each probe request.
    /// Exposed for unit testing only.
    public var testMethod: String { _method }

    /// The set of HTTP status codes that are considered successful.
    /// Exposed for unit testing only.
    public var testStatusCodes: Set<Int> { _statusCodes }

    override public func waitUntilReady(target: any WaitStrategyTarget) async throws {
        let scheme = _useTls ? "https" : "http"
        let host = try await target.containerHostIp()
        let mappedPort = try await target.exposedPort(port)
        let urlString = "\(scheme)://\(host):\(mappedPort)\(path)"

        let ready = try await poll(
            {
                guard let url = URL(string: urlString) else { return false }
                var request = URLRequest(url: url, timeoutInterval: 1.0)
                request.httpMethod = self._method
                for (k, v) in self._headers { request.setValue(v, forHTTPHeaderField: k) }
                if let b = self._body { request.httpBody = Data(b.utf8) }

                let session: URLSession
                #if canImport(Darwin)
                    if self._insecureTls {
                        let config = URLSessionConfiguration.default
                        session = URLSession(configuration: config, delegate: InsecureTLSDelegate(), delegateQueue: nil)
                    } else {
                        session = URLSession.shared
                    }
                #else
                    session = URLSession.shared
                #endif

                let (data, response) = try await session.data(for: request)
                guard let httpResp = response as? HTTPURLResponse else { return false }
                let code = httpResp.statusCode

                let codeOk: Bool
                if let pred = self._statusCodeMatcher {
                    codeOk = pred(code)
                } else {
                    codeOk = self._statusCodes.contains(code)
                }
                guard codeOk else { return false }
                if let pred = self._responsePredicate {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    return pred(body)
                }
                return true
            },
            transientExceptions: [URLError.self]
        )

        if !ready {
            throw WaitStrategyError.timeout("HTTP endpoint \(urlString) not ready within \(startupTimeout).")
        }
    }
}

// Accept any TLS certificate (for insecure mode).
// Darwin (macOS/iOS) only — swift-corelibs-foundation on Linux does not expose
// the Security framework APIs required for server-trust credential handling.
#if canImport(Darwin)
    private final class InsecureTLSDelegate: NSObject, URLSessionDelegate {
        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                let trust = challenge.protectionSpace.serverTrust
            {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
#endif

// MARK: - 3. HealthcheckWaitStrategy

/// Waits until the container's built-in health check reports `"healthy"`.
public final class HealthcheckWaitStrategy: WaitStrategy {
    override public func waitUntilReady(target: any WaitStrategyTarget) async throws {
        let ready = try await poll {
            await target.reload()

            var healthStatus: String?
            do {
                let info = try await target.containerInfo()
                healthStatus = info?.state?.health?.status
            } catch {
                FileHandle.standardError.write(
                    Data("testcontainers: error fetching health status: \(error)\n".utf8)
                )
                healthStatus = nil
            }

            guard let status = healthStatus, !status.isEmpty else {
                throw WaitStrategyError.containerExited(
                    "Container has no health check configured: \(target)"
                )
            }
            if status == "healthy" { return true }
            if status == "unhealthy" {
                let (stdout, stderrData) = try await target.logs()
                var combined = stdout
                combined.append(stderrData)
                let logs = String(data: combined, encoding: .utf8) ?? ""
                throw WaitStrategyError.unhealthy("Container is unhealthy. Logs: \(logs)")
            }
            return false  // "starting" — keep waiting
        }

        if !ready {
            throw WaitStrategyError.timeout("Container not healthy within \(startupTimeout).")
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
        let host = try await target.containerHostIp()
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
            await target.reload()
            let s = target.status
            if s == "running" { return true }
            if !Self.continueStatuses.contains(s) {
                try throwStopIteration()
            }
            return false
        }
        if !ready {
            throw WaitStrategyError.containerExited(
                "Container not running. Status: \(target.status)"
            )
        }
    }
}

// MARK: - 7. CompositeWaitStrategy

/// Chains multiple wait strategies and runs them in sequence.
///
/// All child strategies are applied in order; the container is considered
/// ready only after **every** strategy succeeds.
///
/// `withStartupTimeout` and `withPollInterval` are propagated to all child
/// strategies so that a single call configures the entire chain.
public final class CompositeWaitStrategy: WaitStrategy {
    private let strategies: [WaitStrategy]

    /// Creates a `CompositeWaitStrategy` from a list of child strategies.
    public init(_ strategies: [WaitStrategy]) {
        self.strategies = strategies
        super.init()
    }

    @discardableResult
    override public func withStartupTimeout(_ timeout: Duration) -> Self {
        for s in strategies { s.withStartupTimeout(timeout) }
        startupTimeout = timeout
        return self
    }

    @discardableResult
    override public func withPollInterval(_ interval: Duration) -> Self {
        for s in strategies { s.withPollInterval(interval) }
        pollInterval = interval
        return self
    }

    @discardableResult
    override public func withTransientExceptions(_ exceptions: [any Error.Type]) -> Self {
        for s in strategies { s.withTransientExceptions(exceptions) }
        transientExceptionTypes.append(contentsOf: exceptions)
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

    /// Creates an `ExecWaitStrategy` that runs a single shell command string.
    public convenience init(shell command: String, expectedExitCode: Int = 0) {
        self.init([command], expectedExitCode: expectedExitCode)
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
                #if canImport(Darwin)
                    hints.ai_socktype = SOCK_STREAM
                #else
                    hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
                #endif
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

private func withTimeout<T: Sendable>(
    _ duration: Duration,
    _ work: @escaping @Sendable () async throws -> T
) async throws -> T {
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
