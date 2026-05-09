/// Runtime environment probes used by testcontainers-swift.
///
/// These free functions inspect the current process's host environment to
/// detect whether the code is running inside a Docker container, to discover
/// the default gateway IP address, and to identify the host operating system
/// and CPU architecture. The results drive connection-mode selection in
/// `DockerClient`.
import Foundation

/// Returns `true` when the current process is running inside a Docker container.
///
/// Detection strategy: checks for the existence of `/.dockerenv`, which
/// Docker places in every container's root filesystem.
public func insideContainer() -> Bool {
    FileManager.default.fileExists(atPath: "/.dockerenv")
}

/// Returns the host machine's default-route gateway IP address.
///
/// Runs `ip route` and parses the line that starts with `default` to extract
/// the gateway address. Returns `nil` if the command is unavailable or fails.
public func defaultGatewayIp() -> String? {
    let result = runProcess("sh", args: ["-c", "ip route|awk '/default/ { print $3 }'"])
    guard result.exitCode == 0 else { return nil }
    let ip = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    return ip.isEmpty ? nil : ip
}

/// Returns `true` when the current CPU architecture is ARM (64-bit).
///
/// Runs `uname -m` and checks whether the machine type string equals
/// `arm64` or `aarch64`.
public func isArm() -> Bool {
    let result = runProcess("uname", args: ["-m"])
    let machine = result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return machine == "arm64" || machine == "aarch64"
}

/// Returns `true` when the current platform is macOS.
public func isMac() -> Bool {
    #if os(macOS)
    return true
    #else
    return false
    #endif
}

/// Returns `true` when the current platform is Linux.
public func isLinux() -> Bool {
    #if os(Linux)
    return true
    #else
    return false
    #endif
}

/// Returns `true` when the current platform is Windows.
public func isWindows() -> Bool {
    #if os(Windows)
    return true
    #else
    return false
    #endif
}

/// Returns the Docker container ID of the current process, or `nil`.
///
/// Reads `/proc/self/cgroup` and looks for lines whose cgroup path starts
/// with `/docker/`. The hex string that follows is the container ID.
public func runningContainerId() -> String? {
    let path = "/proc/self/cgroup"
    guard
        FileManager.default.fileExists(atPath: path),
        let contents = try? String(contentsOfFile: path, encoding: .utf8)
    else { return nil }

    for line in contents.components(separatedBy: "\n") {
        let cgroupPath = line.components(separatedBy: ":").last ?? ""
        if cgroupPath.hasPrefix("/docker/") {
            return String(cgroupPath.dropFirst("/docker/".count))
        }
    }
    return nil
}

// MARK: - Internal helper

struct ProcessResult {
    let exitCode: Int32
    let output: String
}

func runProcess(_ executable: String, args: [String]) -> ProcessResult {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + args
    process.standardOutput = pipe
    process.standardError = Pipe() // suppress stderr

    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            exitCode: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    } catch {
        return ProcessResult(exitCode: -1, output: "")
    }
}
