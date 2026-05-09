/// Semantic version comparison utility used internally by testcontainers-swift.
///
/// `ComparableVersion` parses a `major.minor.patch` version string and
/// exposes all comparison operators so that minimum Docker API version
/// requirements can be checked at runtime.

/// A parsed semantic version that supports full ordering.
///
/// Only the strict three-part `major.minor.patch` format is accepted. All
/// integer parts must be non-negative.
///
/// Version values are immutable. Comparison is lexicographic on the
/// `(major, minor, patch)` tuple.
///
/// Example:
/// ```swift
/// let v = try ComparableVersion("1.41.0")
/// assert(v > (try ComparableVersion("1.40.0")))
/// ```
public struct ComparableVersion: Comparable, Equatable, CustomStringConvertible {
    /// The major version component.
    public let major: Int

    /// The minor version component.
    public let minor: Int

    /// The patch version component.
    public let patch: Int

    // The original string, preserved so description round-trips correctly.
    private let original: String

    // Pre-computed tuple for comparisons.
    private let parts: [Int]

    /// Creates a `ComparableVersion` by parsing `version`.
    ///
    /// The `version` string must be in `major.minor.patch` format where all
    /// three components are non-negative integers.
    ///
    /// Throws `ComparableVersionError.invalidFormat` if `version` does not
    /// have exactly three dot-separated integer parts.
    public init(_ version: String) throws {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else {
            throw ComparableVersionError.invalidFormat(version)
        }
        guard
            let maj = Int(components[0]),
            let min = Int(components[1]),
            let pat = Int(components[2])
        else {
            throw ComparableVersionError.invalidFormat(version)
        }
        self.original = version
        self.major = maj
        self.minor = min
        self.patch = pat
        self.parts = [maj, min, pat]
    }

    /// Returns the canonical version string, e.g. `"1.2.3"`.
    public var description: String { original }

    /// Compares two versions. Returns `true` when `lhs` is strictly less than `rhs`.
    public static func < (lhs: ComparableVersion, rhs: ComparableVersion) -> Bool {
        for i in 0..<3 {
            let diff = lhs.parts[i] - rhs.parts[i]
            if diff != 0 { return diff < 0 }
        }
        return false
    }

    /// Returns `true` when `lhs` equals `rhs`.
    public static func == (lhs: ComparableVersion, rhs: ComparableVersion) -> Bool {
        lhs.parts == rhs.parts
    }
}

/// Errors thrown by `ComparableVersion`.
public enum ComparableVersionError: Error, CustomStringConvertible {
    case invalidFormat(String)

    public var description: String {
        switch self {
        case .invalidFormat(let v): return "Invalid version string: \(v)"
        }
    }
}
