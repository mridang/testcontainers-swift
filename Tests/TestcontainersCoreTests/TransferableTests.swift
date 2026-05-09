import Foundation
import Testing

@testable import TestcontainersCore

/// Minimal TAR parser to verify entries produced by buildTransferTar.
private struct TarEntry {
    let name: String
    let size: Int
    let mode: Int
    let data: Data
}

private func parseTar(_ data: Data) -> [TarEntry] {
    var entries: [TarEntry] = []
    var offset = 0
    while offset + 512 <= data.count {
        // Check for end-of-archive (two zero blocks)
        let block = data[offset..<offset + 512]
        if block.allSatisfy({ $0 == 0 }) { break }

        // Name field: bytes 0-99 (null-terminated)
        let nameBytes = data[offset..<offset + 100]
        let name = String(bytes: nameBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""

        // Mode field: bytes 100-107 (octal ASCII)
        let modeStr =
            String(bytes: data[offset + 100..<offset + 108].prefix(while: { $0 != 0 && $0 != 32 }), encoding: .utf8)
            ?? "0"
        let mode = Int(modeStr, radix: 8) ?? 0

        // Size field: bytes 124-135 (octal ASCII)
        let sizeStr =
            String(bytes: data[offset + 124..<offset + 136].prefix(while: { $0 != 0 && $0 != 32 }), encoding: .utf8)
            ?? "0"
        let size = Int(sizeStr, radix: 8) ?? 0

        offset += 512
        if size > 0 && offset + size <= data.count {
            let content = data[offset..<offset + size]
            entries.append(TarEntry(name: name, size: size, mode: mode, data: Data(content)))
            // Advance to next 512-byte boundary
            let blocks = (size + 511) / 512
            offset += blocks * 512
        } else if size == 0 {
            entries.append(TarEntry(name: name, size: 0, mode: mode, data: Data()))
        } else {
            break
        }
    }
    return entries
}

@Suite("buildTransferTar")
struct TransferableTests {
    @Test func producesValidTarFromBytes() throws {
        let bytes = Data("hello world".utf8)
        let tar = try buildTransferTar(.bytes(bytes), destination: "hello.txt")
        #expect(!tar.isEmpty)
        let entries = parseTar(tar)
        #expect(entries.count == 1)
        #expect(entries[0].name == "hello.txt")
        #expect(String(data: entries[0].data, encoding: .utf8) == "hello world")
    }

    @Test func setsCustomModeOnTarEntry() throws {
        let bytes = Data("data".utf8)
        let tar = try buildTransferTar(.bytes(bytes), destination: "data.txt", mode: 0x1FF)
        let entries = parseTar(tar)
        #expect(entries[0].mode == 0x1FF)
    }

    @Test func defaultModeIs0x1A4() throws {
        let bytes = Data("data".utf8)
        let tar = try buildTransferTar(.bytes(bytes), destination: "data.txt")
        let entries = parseTar(tar)
        #expect(entries[0].mode == 0x1A4)
    }

    @Test func kDefaultTransferModeIs644() {
        #expect(kDefaultTransferMode == 0x1A4)
        #expect(kDefaultTransferMode == 420)  // octal 644
    }

    @Test func producesValidTarFromFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_test_\(Int.random(in: 1...99999))")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = tmpDir.appendingPathComponent("hello.txt")
        try "file content".write(to: fileURL, atomically: true, encoding: .utf8)

        let tar = try buildTransferTar(.path(fileURL), destination: "/dest/hello.txt", mode: 0x1ED)
        let entries = parseTar(tar)
        #expect(entries.count == 1)
        #expect(entries[0].name == "dest/hello.txt")
        #expect(entries[0].mode == 0x1ED)
        #expect(String(data: entries[0].data, encoding: .utf8) == "file content")
    }

    @Test func producesValidTarFromDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_test_dir_\(Int.random(in: 1...99999))")
        let srcDir = tmpDir.appendingPathComponent("my_dir")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try "aaa".write(to: srcDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let tar = try buildTransferTar(.path(srcDir), destination: "/dest")
        let entries = parseTar(tar)
        #expect(!entries.isEmpty)
        let names = entries.map { $0.name }
        #expect(names.contains(where: { $0.contains("my_dir") }))
        #expect(names.contains(where: { $0.contains("a.txt") }))
    }

    @Test func throwsForNonExistentFilePath() {
        let fakeURL = URL(fileURLWithPath: "/tmp/__does_not_exist_\(Int.random(in: 1...99999))__")
        #expect(throws: TransferableError.self) {
            _ = try buildTransferTar(.path(fakeURL), destination: "/tmp/bad")
        }
    }

    @Test func emptyBytesProducesZeroByteEntry() throws {
        let tar = try buildTransferTar(.bytes(Data()), destination: "empty.txt")
        let entries = parseTar(tar)
        #expect(entries.count == 1)
        #expect(entries[0].name == "empty.txt")
        #expect(entries[0].size == 0)
    }

    @Test func emptyDirectoryProducesNoEntries() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc_empty_\(Int.random(in: 1...99999))")
        let emptyDir = tmpDir.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let tar = try buildTransferTar(.path(emptyDir), destination: "/dest")
        #expect(!tar.isEmpty)
        let entries = parseTar(tar)
        #expect(entries.isEmpty)
    }

    @Test func throwsForNonExistentDirectoryPath() {
        let fakeDir = URL(fileURLWithPath: "/tmp/__non_existent_dir_\(Int.random(in: 1...99999))__/")
        #expect(throws: TransferableError.self) {
            _ = try buildTransferTar(.path(fakeDir), destination: "/dest")
        }
    }

    @Test func pathCaseStoresURL() throws {
        let url = URL(fileURLWithPath: "/tmp/some-path.txt")
        if case .path(let stored) = Transferable.path(url) {
            #expect(stored == url)
        } else {
            Issue.record("Expected .path case")
        }
    }

    @Test func bytesCaseStoresData() {
        let data = Data([1, 2, 3])
        if case .bytes(let stored) = Transferable.bytes(data) {
            #expect(stored == data)
        } else {
            Issue.record("Expected .bytes case")
        }
    }
}
