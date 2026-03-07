import Foundation

public struct NvALTImporter: Sendable {

    public init() {}

    /// Check common nvALT data locations and return the first found.
    public static func detectNvALTInstallation() -> URL? {
        let fm = FileManager.default
        let paths = [
            NSString("~/Library/Application Support/Notational Data").expandingTildeInPath,
            NSString("~/Library/Application Support/nvALT").expandingTildeInPath,
        ]
        for path in paths {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Import all notes from an nvALT-style notes directory.
    public static func importNvALTNotes(from directory: URL, service: ImportExportService) async -> [ImportedNote] {
        let fm = FileManager.default
        let importExtensions: Set<String> = ["txt", "md", "rtf"]

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        var results: [ImportedNote] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            guard importExtensions.contains(ext) else { continue }

            if var imported = try? await service.importFile(at: fileURL) {
                // Migrate OpenMeta tags
                let openMetaTags = readOpenMetaTags(from: fileURL)
                if !openMetaTags.isEmpty {
                    let mergedTags = Array(Set(imported.tags + openMetaTags))
                    imported = ImportedNote(title: imported.title, body: imported.body, tags: mergedTags)
                }
                results.append(imported)
            }
        }
        return results
    }

    /// Read OpenMeta tags from a file's extended attributes.
    public static func readOpenMetaTags(from url: URL) -> [String] {
        let attrName = "com.apple.metadata:kMDItemOMUserTags"
        return url.withUnsafeFileSystemRepresentation { path -> [String] in
            guard let path else { return [] }

            // Get size of xattr
            let size = getxattr(path, attrName, nil, 0, 0, 0)
            guard size > 0 else { return [] }

            // Read xattr data
            var buffer = [UInt8](repeating: 0, count: size)
            let readSize = getxattr(path, attrName, &buffer, size, 0, 0)
            guard readSize > 0 else { return [] }

            let data = Data(buffer[0..<readSize])

            // OpenMeta tags are stored as a plist array of strings
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let tags = plist as? [String] else {
                return []
            }
            return tags
        }
    }
}
