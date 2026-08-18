import Foundation
#if canImport(zlib)
import zlib
#endif

public struct RecoveredNote: Sendable {
    public let noteID: UUID
    public let title: String
    public let body: String
    public let tags: [String]
    public let timestamp: Date
}

public actor CrashRecoveryService {
    private let walURL: URL
    private let fileManager = FileManager.default
    private static let encoder = JSONEncoder()

    /// Kept open across `appendRecord` calls instead of open/seek/write/close
    /// per call. `FileHandle.write` is an unbuffered `write(2)`, so durability
    /// is unchanged by keeping it open -- writes still land immediately, just
    /// without the per-call open/close syscalls.
    private var activeHandle: FileHandle?

    public init(cacheDirectory: URL? = nil) {
        let cacheDir = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("com.nvenvy.app")
        self.walURL = cacheDir.appendingPathComponent("wal.bin")
    }

    deinit {
        try? activeHandle?.close()
    }

    private func ensureDirectory() throws {
        let dir = walURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Write

    public func appendRecord(note: Note) throws {
        try ensureDirectory()

        let payload = WALPayload(
            noteID: note.id,
            title: note.title,
            body: note.body,
            tags: note.tags,
            timestamp: Date()
        )

        let jsonData = try Self.encoder.encode(payload)
        let compressed = try Self.compress(jsonData)
        let crc = Self.crc32Checksum(compressed)

        var record = Data()
        var originalLen = UInt32(jsonData.count)
        var compressedLen = UInt32(compressed.count)
        var checksum = crc
        record.append(Data(bytes: &originalLen, count: 4))
        record.append(Data(bytes: &compressedLen, count: 4))
        record.append(Data(bytes: &checksum, count: 4))
        record.append(compressed)

        let handle = try activeWriteHandle()
        handle.write(record)
    }

    /// Returns the persistent write handle, opening (and creating the file
    /// and seeking to its end) on first use or after `truncate()` closed it.
    private func activeWriteHandle() throws -> FileHandle {
        if let activeHandle { return activeHandle }
        if !fileManager.fileExists(atPath: walURL.path) {
            fileManager.createFile(atPath: walURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: walURL)
        handle.seekToEndOfFile()
        activeHandle = handle
        return handle
    }

    // MARK: - Recovery

    public func recoverPendingNotes() throws -> [RecoveredNote] {
        guard fileManager.fileExists(atPath: walURL.path) else { return [] }

        let data = try Data(contentsOf: walURL)
        var offset = 0
        var notesByID: [UUID: RecoveredNote] = [:]

        while offset + 12 <= data.count {
            let originalLen = readUInt32(from: data, at: offset)
            let compressedLen = readUInt32(from: data, at: offset + 4)
            let storedCRC = readUInt32(from: data, at: offset + 8)

            let headerSize = 12
            let compressedStart = offset + headerSize
            let compressedEnd = compressedStart + Int(compressedLen)

            guard compressedEnd <= data.count else { break }

            let compressed = data[compressedStart..<compressedEnd]

            // Validate CRC
            let computedCRC = Self.crc32Checksum(compressed)
            guard computedCRC == storedCRC else {
                offset = compressedEnd
                continue
            }

            // Decompress and decode
            if let decompressed = try? Self.decompress(compressed, originalSize: Int(originalLen)),
               let payload = try? JSONDecoder().decode(WALPayload.self, from: decompressed) {
                let recovered = RecoveredNote(
                    noteID: payload.noteID,
                    title: payload.title,
                    body: payload.body,
                    tags: payload.tags,
                    timestamp: payload.timestamp
                )
                // Deduplicate: latest timestamp wins
                if let existing = notesByID[payload.noteID] {
                    if payload.timestamp > existing.timestamp {
                        notesByID[payload.noteID] = recovered
                    }
                } else {
                    notesByID[payload.noteID] = recovered
                }
            }

            offset = compressedEnd
        }

        return Array(notesByID.values)
    }

    // MARK: - Cleanup

    public func truncate() throws {
        // Close the persistent handle before replacing the file -- an open
        // handle after `Data().write(to:)` swaps the inode out from under it
        // would keep appending into an unlinked file instead of the new one.
        try activeHandle?.close()
        activeHandle = nil
        guard fileManager.fileExists(atPath: walURL.path) else { return }
        try Data().write(to: walURL)
    }

    // MARK: - Compression

    static func compress(_ data: Data) throws -> Data {
        let sourceSize = data.count
        var destSize = Int(compressBound(uLong(sourceSize)))
        var dest = Data(count: destSize)

        let result = dest.withUnsafeMutableBytes { destBuf in
            data.withUnsafeBytes { srcBuf in
                zlib.compress(
                    destBuf.bindMemory(to: UInt8.self).baseAddress!,
                    &destSize,
                    srcBuf.bindMemory(to: UInt8.self).baseAddress!,
                    uLong(sourceSize)
                )
            }
        }

        guard result == Z_OK else {
            throw CrashRecoveryError.compressionFailed
        }

        return dest.prefix(destSize)
    }

    static func decompress(_ data: Data, originalSize: Int) throws -> Data {
        var destSize = uLong(originalSize)
        var dest = Data(count: originalSize)

        let result = dest.withUnsafeMutableBytes { destBuf in
            data.withUnsafeBytes { srcBuf in
                uncompress(
                    destBuf.bindMemory(to: UInt8.self).baseAddress!,
                    &destSize,
                    srcBuf.bindMemory(to: UInt8.self).baseAddress!,
                    uLong(data.count)
                )
            }
        }

        guard result == Z_OK else {
            throw CrashRecoveryError.decompressionFailed
        }

        return dest.prefix(Int(destSize))
    }

    // MARK: - Byte Helpers

    private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest.bindMemory(to: UInt8.self), from: offset..<(offset + 4))
        }
        return value
    }

    // MARK: - CRC32

    static func crc32Checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buf in
            UInt32(zlib.crc32(0, buf.bindMemory(to: UInt8.self).baseAddress!, uInt(data.count)))
        }
    }
}

// MARK: - Types

private struct WALPayload: Codable {
    let noteID: UUID
    let title: String
    let body: String
    let tags: [String]
    let timestamp: Date
}

public enum CrashRecoveryError: Error {
    case compressionFailed
    case decompressionFailed
}
