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

    public func readAllNotes() throws -> [Note] {
        var results: [Note] = []

        guard let enumerator = fileManager.enumerator(
            at: notesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let ignoredDirs: Set<String> = [".obsidian"]
        let basePath = notesDirectory.resolvingSymlinksInPath().path
        let basePrefix = basePath.hasSuffix("/") ? basePath : basePath + "/"

        while let url = enumerator.nextObject() as? URL {
            if let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory, isDir {
                let dirName = url.lastPathComponent
                if dirName.hasPrefix(".") || ignoredDirs.contains(dirName) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard allowedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            let (content, encoding) = Self.decodeWithFallback(data)
            guard let content else { continue }

            let parsed = FrontmatterParser.parse(content)

            // Compute relative path using string prefix (no per-file symlink resolution)
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
            let filename = String(relativePath.dropLast(ext.count + 1)) // remove .ext
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
            results.append(note)
        }

        return results
    }

    // MARK: - Write

    public func writeNote(_ note: Note) throws {
        let frontmatter = FrontmatterBlock(
            tags: note.tags,
            created: note.createdDate,
            modified: note.modifiedDate
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
        try data.write(to: tempURL, options: .atomic)
        _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
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
