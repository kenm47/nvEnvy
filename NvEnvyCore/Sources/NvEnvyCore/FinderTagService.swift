import Foundation

public enum FinderTagService {
    /// Write note tags as Finder tags on the file URL
    public static func writeFinderTags(_ tags: [String], to fileURL: URL) {
        try? (fileURL as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }

    /// Read Finder tags from a file URL
    public static func readFinderTags(from fileURL: URL) -> [String] {
        guard let values = try? fileURL.resourceValues(forKeys: [.tagNamesKey]),
              let tags = values.tagNames else { return [] }
        return tags
    }

    /// Migrate Finder tags into a note's tags if it has no frontmatter tags
    public static func migrateFinderTagsIfNeeded(for note: Note, fileURL: URL) -> Bool {
        guard note.tags.isEmpty else { return false }
        let finderTags = readFinderTags(from: fileURL)
        guard !finderTags.isEmpty else { return false }
        note.tags = finderTags
        note.invalidateSearchCache()
        return true
    }
}
