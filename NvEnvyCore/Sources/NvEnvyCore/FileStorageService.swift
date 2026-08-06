import Foundation

/// Wraps file I/O so iOS can adopt `NSFileCoordinator` for iCloud safety while
/// macOS stays on direct I/O (preserves read-perf wins). The Phase 4 iOS
/// adapter will replace `PassthroughFileAccessCoordinator` with one that calls
/// `NSFileCoordinator.coordinate(readingItemAt:...)` / `coordinate(writingItemAt:...)`.
public protocol FileAccessCoordinator: Sendable {
    func coordinate<T>(readingItemAt url: URL, _ work: (URL) throws -> T) throws -> T
    func coordinate<T>(writingItemAt url: URL, _ work: (URL) throws -> T) throws -> T
}

public struct PassthroughFileAccessCoordinator: FileAccessCoordinator {
    public init() {}
    public func coordinate<T>(readingItemAt url: URL, _ work: (URL) throws -> T) throws -> T {
        try work(url)
    }
    public func coordinate<T>(writingItemAt url: URL, _ work: (URL) throws -> T) throws -> T {
        try work(url)
    }
}

public actor FileStorageService {
    private let fileManager = FileManager.default
    public let notesDirectory: URL
    private let coordinator: FileAccessCoordinator

    public init(
        notesDirectory: URL,
        allowedExtensions: Set<String>? = nil,
        coordinator: FileAccessCoordinator = PassthroughFileAccessCoordinator()
    ) {
        self.notesDirectory = notesDirectory
        self.allowedExtensions = allowedExtensions ?? Self.defaultAllowedExtensions
        self.coordinator = coordinator
    }

    // MARK: - Read

    public func readNote(at url: URL) throws -> (parsed: ParsedNote, encoding: String.Encoding) {
        try coordinator.coordinate(readingItemAt: url) { resolvedURL in
            let data = try Data(contentsOf: resolvedURL)
            let (content, encoding) = Self.decodeWithFallback(data)
            guard let content else {
                throw FileStorageError.encodingError
            }
            return (FrontmatterParser.parse(content), encoding)
        }
    }

    /// Try UTF-8, then UTF-16, then ISO Latin-1 / MacRoman.
    public static func decodeWithFallback(_ data: Data) -> (String?, String.Encoding) {
        if let str = String(data: data, encoding: .utf8) {
            return (str, .utf8)
        }
        if let str = String(data: data, encoding: .utf16) {
            return (str, .utf16)
        }
        if let str = String(data: data, encoding: .isoLatin1) {
            return (str, .isoLatin1)
        }
        if let str = String(data: data, encoding: .macOSRoman) {
            return (str, .macOSRoman)
        }
        return (nil, .utf8)
    }

    public static let defaultAllowedExtensions: Set<String> = ["md", "markdown", "mmd", "txt", "text"]

    public var allowedExtensions: Set<String>

    private var basePrefix: String {
        let basePath = notesDirectory.resolvingSymlinksInPath().path
        return basePath.hasSuffix("/") ? basePath : basePath + "/"
    }

    /// Relative "filename" (no extension) nvEnvy uses as a note's stable key,
    /// derived from an absolute file URL. Pure path arithmetic — doesn't touch disk.
    /// `static` (not actor-isolated) so it can run concurrently from parallel load tasks.
    private static func relativeFilename(for url: URL, basePrefix: String) -> String {
        let filePath = url.path
        let relativePath: String
        if filePath.hasPrefix(basePrefix) {
            relativePath = String(filePath.dropFirst(basePrefix.count))
        } else {
            // Fallback: resolve this one URL if prefix doesn't match
            let resolved = url.resolvingSymlinksInPath().path
            if resolved.hasPrefix(basePrefix) {
                relativePath = String(resolved.dropFirst(basePrefix.count))
            } else {
                relativePath = url.lastPathComponent
            }
        }
        let ext = url.pathExtension
        return String(relativePath.dropLast(ext.count + 1)) // remove .ext
    }

    /// Filename key for an absolute path, without touching disk. Returns nil if
    /// the path's extension isn't one nvEnvy reads. Used to map raw FSEvents
    /// paths (which may point at now-deleted files) back to a note key.
    public func filename(forPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard allowedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return Self.relativeFilename(for: url, basePrefix: basePrefix)
    }

    public func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    public func statFile(at url: URL) -> (modDate: Date, size: UInt64)? {
        guard let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modDate = rv.contentModificationDate,
              let size = rv.fileSize else { return nil }
        return (modDate, UInt64(size))
    }

    /// Reads and parses a single note file. `static`/non-isolated (takes its
    /// inputs as plain values) so it can run concurrently across `Task`s
    /// without hopping back onto the `FileStorageService` actor per file.
    /// Shared by the full-vault scan (`readAllNotes`) and the incremental
    /// FSEvents reconciliation path so the two never drift.
    private static func parseNoteFile(at url: URL, allowedExtensions: Set<String>, basePrefix: String) -> Note? {
        guard allowedExtensions.contains(url.pathExtension.lowercased()) else { return nil }

        // A plain `Data(contentsOf:)` on a not-yet-downloaded iCloud item blocks
        // until the download completes. Across a large external vault (e.g. an
        // Obsidian iCloud folder with thousands of notes) that can make the
        // parallel scan hang for a very long time — or effectively forever if a
        // single file's download stalls, since it blocks the whole chunk it's
        // in. Skip anything not already local; `IOSFolderMonitor` kicks off the
        // download and `reconcileFilesystem` picks the note up once it lands.
        if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
           status != .current {
            return nil
        }

        // Not `.mappedIfSafe`: memory-mapping chokes with "Unknown compression
        // scheme encountered" on files under iCloud sync engines (observed with
        // an Obsidian iCloud vault on iOS) whose on-disk extents use APFS
        // compression the mapper can't handle. A normal read is negligibly
        // slower for note-sized text files and works everywhere.
        guard let data = try? Data(contentsOf: url) else { return nil }
        let (content, encoding) = Self.decodeWithFallback(data)
        guard let content else { return nil }

        let parsed = FrontmatterParser.parse(content)
        let filename = relativeFilename(for: url, basePrefix: basePrefix)
        let title = url.deletingPathExtension().lastPathComponent
        let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modDate = resourceValues?.contentModificationDate ?? Date()
        let fileSize = resourceValues?.fileSize.map { UInt64($0) }

        let note = Note(
            title: title,
            body: parsed.body,
            tags: parsed.frontmatter?.tags ?? [],
            filename: filename,
            createdDate: parsed.frontmatter?.created ?? modDate,
            modifiedDate: parsed.frontmatter?.modified ?? modDate
        )
        note.fileModifiedDate = modDate
        note.fileSize = fileSize
        note.fileEncoding = encoding
        note.unknownFrontmatterFields = parsed.frontmatter?.unknownFields ?? []
        return note
    }

    /// Reads and parses a single note by absolute file URL, for incremental
    /// reconciliation of one changed path. Returns nil for directories,
    /// disallowed extensions, or unreadable files.
    public func loadSingleNote(at url: URL) -> Note? {
        Self.parseNoteFile(at: url, allowedExtensions: allowedExtensions, basePrefix: basePrefix)
    }

    public func readAllNotes() async throws -> [Note] {
        let exts = allowedExtensions
        let urls: [URL] = try coordinator.coordinate(readingItemAt: notesDirectory) { dir in
            guard let enumerator = self.fileManager.enumerator(
                at: dir,
                includingPropertiesForKeys: [
                    .contentModificationDateKey, .fileSizeKey, .isDirectoryKey,
                    .ubiquitousItemDownloadingStatusKey,
                ],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            let ignoredDirs: Set<String> = [".obsidian"]
            var collected: [URL] = []

            while let url = enumerator.nextObject() as? URL {
                if let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory, isDir {
                    let dirName = url.lastPathComponent
                    if dirName.hasPrefix(".") || ignoredDirs.contains(dirName) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard exts.contains(url.pathExtension.lowercased()) else { continue }
                collected.append(url)
            }
            return collected
        }

        guard !urls.isEmpty else { return [] }

        // Enumeration must stay serial (NSDirectoryEnumerator isn't concurrency-safe),
        // but per-file read/decode/parse is pure and independent, so fan it out.
        let prefix = basePrefix
        let chunkCount = max(1, min(urls.count, ProcessInfo.processInfo.activeProcessorCount))
        let chunkSize = max(1, (urls.count + chunkCount - 1) / chunkCount)
        let chunks = stride(from: 0, to: urls.count, by: chunkSize).map {
            Array(urls[$0..<min($0 + chunkSize, urls.count)])
        }

        return await withTaskGroup(of: [Note].self) { group in
            for chunk in chunks {
                group.addTask {
                    chunk.compactMap { Self.parseNoteFile(at: $0, allowedExtensions: exts, basePrefix: prefix) }
                }
            }
            var all: [Note] = []
            all.reserveCapacity(urls.count)
            for await partial in group {
                all.append(contentsOf: partial)
            }
            return all
        }
    }

    // MARK: - Write

    public func writeNote(_ note: Note) throws {
        let frontmatter = FrontmatterBlock(
            tags: note.tags,
            created: note.createdDate,
            modified: note.modifiedDate,
            unknownFields: note.unknownFrontmatterFields
        )
        let content = FrontmatterParser.serialize(
            frontmatter: frontmatter.isEmpty ? nil : frontmatter,
            body: note.body
        )

        let url = fileURL(for: note)
        try coordinator.coordinate(writingItemAt: url) { resolvedURL in
            try self.atomicWrite(content: content, to: resolvedURL, encoding: note.fileEncoding)
        }
    }

    public func deleteNote(_ note: Note) throws {
        let url = fileURL(for: note)
        try coordinator.coordinate(writingItemAt: url) { resolvedURL in
            if self.fileManager.fileExists(atPath: resolvedURL.path) {
                try self.fileManager.removeItem(at: resolvedURL)
            }
        }
    }

    public func renameNote(_ note: Note, oldFilename: String) throws {
        let oldURL = notesDirectory.appendingPathComponent(oldFilename + ".md")
        let newURL = fileURL(for: note)
        try coordinator.coordinate(writingItemAt: oldURL) { resolvedOld in
            if self.fileManager.fileExists(atPath: resolvedOld.path) && resolvedOld != newURL {
                try self.fileManager.moveItem(at: resolvedOld, to: newURL)
            }
        }
    }

    // MARK: - Helpers

    public func fileURL(for note: Note) -> URL {
        notesDirectory.appendingPathComponent(note.filename + ".md")
    }

    public func ensureUniqueFilename(_ baseName: String) -> String {
        var name = baseName
        var counter = 2
        while fileManager.fileExists(atPath: notesDirectory.appendingPathComponent(name + ".md").path) {
            name = "\(baseName) \(counter)"
            counter += 1
        }
        return name
    }

    private func atomicWrite(content: String, to url: URL, encoding: String.Encoding = .utf8) throws {
        guard let data = content.data(using: encoding) ?? content.data(using: .utf8) else {
            throw FileStorageError.encodingError
        }
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp")
        // No `.atomic` here: `replaceItemAt` below is already the atomicity
        // boundary, so `.atomic` on the temp file would just add a second
        // temp-write-and-rename for no benefit.
        try data.write(to: tempURL)
        _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
        recordSelfWrite(at: url)
    }

    // MARK: - Self-write suppression

    /// Stat recorded immediately after nvEnvy writes a file itself, keyed by
    /// path. Lets the FSEvents reconciliation path recognize "this event is our
    /// own autosave" and skip re-reading/re-parsing a file we just wrote.
    private var lastWrittenStat: [String: (modDate: Date, size: UInt64)] = [:]

    private func recordSelfWrite(at url: URL) {
        guard let stat = statFile(at: url) else { return }
        lastWrittenStat[url.path] = stat
    }

    /// True if the file at `path` currently matches the stat nvEnvy recorded
    /// for its own most recent write to that path. Consumes (clears) the
    /// recorded stat on a match, so a genuine subsequent external edit isn't
    /// silently ignored.
    public func wasSelfWrite(path: String) -> Bool {
        guard let recorded = lastWrittenStat[path] else { return false }
        guard let current = statFile(at: URL(fileURLWithPath: path)) else { return false }
        guard current.modDate == recorded.modDate, current.size == recorded.size else { return false }
        lastWrittenStat.removeValue(forKey: path)
        return true
    }
}

public enum FileStorageError: Error, LocalizedError {
    case encodingError
    case fileNotFound
    case writeError(String)

    public var errorDescription: String? {
        switch self {
        case .encodingError: return "Failed to encode/decode file content"
        case .fileNotFound: return "File not found"
        case .writeError(let msg): return "Write error: \(msg)"
        }
    }
}
