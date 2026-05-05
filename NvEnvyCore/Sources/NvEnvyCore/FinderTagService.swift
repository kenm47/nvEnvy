import Foundation

public enum FinderTagService {
    /// Write note tags as Finder tags on the file URL
    public static func writeFinderTags(_ tags: [String], to fileURL: URL) {
        #if os(macOS)
        try? (fileURL as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
        #endif
    }

    /// Read Finder tags from a file URL
    public static func readFinderTags(from fileURL: URL) -> [String] {
        #if os(macOS)
        guard let values = try? fileURL.resourceValues(forKeys: [.tagNamesKey]),
              let tags = values.tagNames else { return [] }
        return tags
        #else
        return []
        #endif
    }

    /// Migrate Finder tags into a note's tags if it has no frontmatter tags
    public static func migrateFinderTagsIfNeeded(for note: Note, fileURL: URL) -> Bool {
        #if os(macOS)
        guard note.tags.isEmpty else { return false }
        let finderTags = readFinderTags(from: fileURL)
        guard !finderTags.isEmpty else { return false }
        note.tags = finderTags
        note.invalidateSearchCache()
        return true
        #else
        return false
        #endif
    }
}
