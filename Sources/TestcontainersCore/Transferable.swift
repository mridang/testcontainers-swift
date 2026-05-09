/// Utilities for copying files and directories into running containers.
///
/// The `Transferable` enum represents content that can be transferred into a
/// Docker container via the `PUT /containers/{id}/archive` API endpoint.
/// `buildTransferTar(_:destination:mode:)` packs a `Transferable` into an
/// in-memory tar archive ready to be sent over the Docker socket.
import Foundation

/// Default Unix file permission bits used when copying files into containers.
/// Equivalent to octal `0644` (owner read/write, group read, other read).
public let kDefaultTransferMode: Int = 0x1A4

/// Content that can be copied into a running container.
///
/// - `bytes(Data)` — in-memory byte data placed as a single file.
/// - `path(URL)` — a file or directory on the local filesystem.
public enum Transferable {
    /// Raw in-memory bytes to copy as a single file.
    case bytes(Data)
    /// A local file or directory URL to copy.
    case path(URL)
}

/// A specification describing a single copy-into-container operation.
///
/// Fields:
/// 1. `data` — the `Transferable` source.
/// 2. `destination` — entry path within the tar archive.
/// 3. `mode` — Unix file permission bits (defaults to `kDefaultTransferMode`).
public typealias TransferSpec = (data: Transferable, destination: String, mode: Int)

/// Builds an in-memory tar archive from `transferable` and returns the raw bytes.
///
/// The archive contains a single entry (or multiple entries for a directory)
/// with `destination` as the path within the archive and `mode` as the Unix
/// permission bits.
///
/// - Parameters:
///   - transferable: The content to pack.
///   - destination: The path of the entry inside the tar archive.
///   - mode: Unix permission bits. Defaults to `kDefaultTransferMode` (`0o644`).
///
/// - Throws: `TransferableError` when the path doesn't exist.
public func buildTransferTar(
    _ transferable: Transferable,
    destination: String,
    mode: Int = kDefaultTransferMode
) throws -> Data {
    var tarData = Data()

    switch transferable {
    case .bytes(let bytes):
        tarData.append(tarEntry(name: destination, data: bytes, mode: mode))

    case .path(let url):
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw TransferableError.pathNotFound(url.path)
        }
        if isDir.boolValue {
            let dirName = url.lastPathComponent
            let base = destination.hasSuffix("/") ? destination : destination + "/"
            let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
            while let fileURL = enumerator?.nextObject() as? URL {
                let isRegular = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                guard isRegular else { continue }
                let relativePath = String(fileURL.path.dropFirst(url.path.count))
                let entryName = base + dirName + relativePath
                let data = try Data(contentsOf: fileURL)
                tarData.append(tarEntry(name: entryName, data: data, mode: mode))
            }
        } else {
            let data = try Data(contentsOf: url)
            tarData.append(tarEntry(name: destination, data: data, mode: mode))
        }
    }

    // End-of-archive marker: two 512-byte zero blocks.
    tarData.append(Data(count: 1024))
    return tarData
}

/// Errors thrown by `buildTransferTar`.
public enum TransferableError: Error, CustomStringConvertible {
    case pathNotFound(String)

    public var description: String {
        switch self {
        case .pathNotFound(let p): return "Path \(p) is neither a file nor directory"
        }
    }
}

// MARK: - Minimal ustar TAR writer

/// Builds a single ustar tar entry (header + data, both padded to 512-byte blocks).
private func tarEntry(name: String, data: Data, mode: Int) -> Data {
    var header = Data(count: 512)

    func write(_ string: String, at offset: Int, maxLength: Int) {
        let bytes = Array(string.utf8.prefix(maxLength))
        for (i, b) in bytes.enumerated() {
            header[offset + i] = b
        }
    }

    func writeOctal(_ value: Int, at offset: Int, length: Int) {
        let s = String(value, radix: 8).leftPadded(toLength: length - 1, with: "0")
        write(s, at: offset, maxLength: length - 1)
    }

    // Trim leading slash from name
    let entryName = name.hasPrefix("/") ? String(name.dropFirst()) : name

    write(entryName, at: 0, maxLength: 100)  // name
    writeOctal(mode, at: 100, length: 8)  // mode
    writeOctal(0, at: 108, length: 8)  // uid
    writeOctal(0, at: 116, length: 8)  // gid
    writeOctal(data.count, at: 124, length: 12)  // size
    writeOctal(Int(Date().timeIntervalSince1970), at: 136, length: 12)  // mtime
    header[156] = UInt8(ascii: "0")  // typeflag: regular file
    write("ustar", at: 257, maxLength: 6)  // magic
    write("00", at: 263, maxLength: 2)  // version

    // Checksum: sum of all header bytes with checksum field treated as spaces.
    for i in 148..<156 { header[i] = 32 }  // spaces for checksum field
    let checksum = header.reduce(0) { $0 + Int($1) }
    writeOctal(checksum, at: 148, length: 7)
    header[155] = 32  // trailing space after checksum

    // Data padded to multiple of 512.
    var entry = header
    entry.append(data)
    let remainder = data.count % 512
    if remainder != 0 {
        entry.append(Data(count: 512 - remainder))
    }
    return entry
}

extension String {
    fileprivate func leftPadded(toLength length: Int, with character: Character) -> String {
        let padCount = max(0, length - self.count)
        return String(repeating: character, count: padCount) + self
    }
}
