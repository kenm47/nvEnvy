import Foundation

public actor FileStorageService {
    private let fileManager = FileManager.default
    public let notesDirectory: URL

    public init(notesDirectory: URL) {
        self.notesDirectory = notesDirectory
    }

    // MARK: - Read

    public func readNote(at url: URL) throws -> ParsedNote {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw FileStorageError.encodingError
        }
        return FrontmatterParser.parse(content)
    }

    public func readAllNotes() throws -> [Note] {
        var results: [Note] = []

        guard let enumerator = fileManager.enumerator(
            at: notesDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let ignoredDirs: Set<String> = [".obsidian"]
        // Resolve the base path once, not per-file
        let basePath = notesDirectory.resolvingSymlinksInPath().path
        let basePrefix = basePath.hasSuffix("/") ? basePath : basePath + "/"

        while let url = enumerator.nextObject() as? URL {
            // Use pre-fetched resource values for directory check (no extra stat)
            if let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory, isDir {
                let dirName = url.lastPathComponent
                if dirName.hasPrefix(".") || ignoredDirs.contains(dirName) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard url.pathExtension == "md" else { continue }
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8) else { continue }

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

            let filename = String(relativePath.dropLast(3)) // remove .md
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
        try atomicWrite(content: content, to: url)
    }

    public func deleteNote(_ note: Note) throws {
        let url = fileURL(for: note)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func renameNote(_ note: Note, oldFilename: String) throws {
        let oldURL = notesDirectory.appendingPathComponent(oldFilename + ".md")
        let newURL = fileURL(for: note)
        if fileManager.fileExists(atPath: oldURL.path) && oldURL != newURL {
            try fileManager.moveItem(at: oldURL, to: newURL)
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

    private func atomicWrite(content: String, to url: URL) throws {
        guard let data = content.data(using: .utf8) else {
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
