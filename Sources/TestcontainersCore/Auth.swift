/// Docker registry authentication helpers.
///
/// Parses the `DOCKER_AUTH_CONFIG` environment variable and converts the
/// encoded credentials into a list of `DockerAuthInfo` values that
/// `DockerClient` can pass to `POST /auth`.
import Foundation

/// Holds the credentials required to authenticate against a single Docker registry.
public struct DockerAuthInfo {
    /// The registry hostname, e.g. `"https://index.docker.io/v1/"`.
    public let registry: String
    /// The account name.
    public let username: String
    /// The account password or personal-access token.
    public let password: String

    public init(registry: String, username: String, password: String) {
        self.registry = registry
        self.username = username
        self.password = password
    }
}

// One-shot warning flags — printed to stderr the first time the key is seen.
private var credHelpersWarning: String? = "DOCKER_AUTH_CONFIG is experimental, credHelpers not supported yet"
private var credsStoreWarning: String? = "DOCKER_AUTH_CONFIG is experimental, credsStore not supported yet"

/// Parses a JSON Docker `config.json`-style auth configuration string.
///
/// The expected format mirrors what `docker login` writes into
/// `~/.docker/config.json`:
/// ```json
/// {
///   "auths": {
///     "https://index.docker.io/v1/": {
///       "auth": "<base64(username:password)>"
///     }
///   }
/// }
/// ```
///
/// - Returns a list of `DockerAuthInfo` with one entry per registry found
///   under the `"auths"` key. The list is empty when `"auths"` is present
///   but contains no entries.
/// - Returns `nil` when the `"auths"` key is absent.
/// - Emits a one-time warning to stderr when `credHelpers` or `credsStore`
///   keys are present.
/// - Throws `AuthParseError` when the JSON is invalid or `"auth"` values
///   cannot be base64-decoded.
public func parseDockerAuthConfig(_ authConfig: String) throws -> [DockerAuthInfo]? {
    guard let data = authConfig.data(using: .utf8) else {
        throw AuthParseError.invalidJSON("cannot convert to data")
    }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AuthParseError.invalidJSON("not a JSON object")
    }

    if json["credHelpers"] != nil, let warning = credHelpersWarning {
        fputs("\(warning)\n", stderr)
        credHelpersWarning = nil
    }
    if json["credsStore"] != nil, let warning = credsStoreWarning {
        fputs("\(warning)\n", stderr)
        credsStoreWarning = nil
    }

    guard let auths = json["auths"] as? [String: Any] else {
        return nil
    }

    var result: [DockerAuthInfo] = []
    for (registry, value) in auths {
        guard let entry = value as? [String: Any],
              let authB64 = entry["auth"] as? String,
              let decoded = Data(base64Encoded: authB64),
              let authStr = String(data: decoded, encoding: .utf8)
        else {
            throw AuthParseError.invalidBase64(registry)
        }
        guard let colonIdx = authStr.firstIndex(of: ":") else {
            fputs(
                "testcontainers: skipping auth entry for registry \"\(registry)\" — "
                    + "decoded credentials contain no colon separator.\n",
                stderr
            )
            continue
        }
        let username = String(authStr[authStr.startIndex..<colonIdx])
        let password = String(authStr[authStr.index(after: colonIdx)...])
        result.append(DockerAuthInfo(registry: registry, username: username, password: password))
    }
    return result
}

/// Errors thrown by `parseDockerAuthConfig`.
public enum AuthParseError: Error, CustomStringConvertible {
    case invalidJSON(String)
    case invalidBase64(String)

    public var description: String {
        switch self {
        case .invalidJSON(let reason): return "Could not parse docker auth config: \(reason)"
        case .invalidBase64(let registry): return "Cannot base64-decode auth for registry: \(registry)"
        }
    }
}
