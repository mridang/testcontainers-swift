/// Docker label constants and factory for testcontainers-managed resources.
///
/// Every container, network, and image created by this library is stamped with
/// a set of well-known `org.testcontainers.*` labels. The Reaper (ryuk) reads
/// these labels to identify and clean up orphaned resources.
import Foundation

/// The root namespace for all testcontainers Docker labels.
///
/// Any user-supplied label key that starts with this prefix is rejected by
/// `createLabels(image:labels:)` because those keys are reserved for internal use.
public let testcontainersNamespace = "org.testcontainers"

/// Label key indicating that the resource was created by testcontainers.
/// The value is always `"true"`.
public let labelTestcontainers = testcontainersNamespace

/// Label key carrying the unique session identifier.
/// Its value is the process-scoped `sessionId` UUID.
public let labelSessionId = "org.testcontainers.session-id"

/// Label key carrying the testcontainers library version.
/// The value is `tcVersion`.
public let labelVersion = "org.testcontainers.version"

/// Label key identifying the language binding.
/// The value is always `labelLangValue` (`"swift"`).
public let labelLang = "org.testcontainers.lang"

/// The current version of this Swift testcontainers library.
///
/// Hardcoded constant — kept in sync with git tags on every release by
/// the `.releaserc.json` `prepareCmd` step.
public let tcVersion = "1.0.5"

/// The language binding identifier placed in `labelLang`.
public let labelLangValue = "swift"

/// A UUID that is unique to the current Swift process.
///
/// Created once at module initialisation and reused for every container,
/// network, and image created during the lifetime of the process.
public let sessionId: String = UUID().uuidString.lowercased()

/// Returns the standard set of Docker labels for a container or network.
///
/// Merges the caller-supplied `labels` dictionary with the four built-in
/// testcontainers labels:
///
/// | Label key | Value |
/// |---|---|
/// | `org.testcontainers` | `"true"` |
/// | `org.testcontainers.version` | `tcVersion` |
/// | `org.testcontainers.lang` | `"swift"` |
/// | `org.testcontainers.session-id` | `sessionId` (omitted for ryuk) |
///
/// - Parameters:
///   - image: The image name being used. When `image` matches the configured
///     ryuk image, the session-id label is **omitted** so that ryuk itself is
///     not tracked by another ryuk instance.
///   - labels: Optional caller-supplied labels. Must not contain any key that
///     starts with `org.testcontainers` — doing so throws `LabelsError`.
///
/// - Throws: `LabelsError.reservedNamespace` if any key in `labels` starts
///   with the reserved `org.testcontainers` namespace.
public func createLabels(
    image: String,
    labels: [String: String]? = nil
) throws -> [String: String] {
    let effective = labels ?? [:]
    for key in effective.keys {
        if key.hasPrefix(testcontainersNamespace) {
            throw LabelsError.reservedNamespace(key)
        }
    }

    var result = effective
    result[labelLang] = labelLangValue
    result[labelTestcontainers] = "true"
    result[labelVersion] = tcVersion

    let ryukFull = testcontainersConfig.hubImageNamePrefix + testcontainersConfig.ryukImage
    if image != ryukFull {
        result[labelSessionId] = sessionId
    }
    return result
}

/// Errors thrown by label operations.
public enum LabelsError: Error, CustomStringConvertible {
    case reservedNamespace(String)

    public var description: String {
        switch self {
        case .reservedNamespace:
            return "The org.testcontainers namespace is reserved for internal use"
        }
    }
}
