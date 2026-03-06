import Foundation

public struct Bookmark: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var searchQuery: String
    public var noteID: UUID?

    public init(id: UUID = UUID(), name: String, searchQuery: String, noteID: UUID? = nil) {
        self.id = id
        self.name = name
        self.searchQuery = searchQuery
        self.noteID = noteID
    }
}

public final class BookmarkStore: @unchecked Sendable {
    private static let storageKey = "nvEnvyBookmarks"
    private(set) public var bookmarks: [Bookmark] = []

    public init() {
        load()
    }

    public func add(_ bookmark: Bookmark) {
        bookmarks.append(bookmark)
        save()
    }

    public func remove(at index: Int) {
        guard bookmarks.indices.contains(index) else { return }
        bookmarks.remove(at: index)
        save()
    }

    public func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save()
    }

    public func rename(id: UUID, to name: String) {
        guard let idx = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[idx].name = name
        save()
    }

    public func reorder(from sourceIndex: Int, to destinationIndex: Int) {
        guard bookmarks.indices.contains(sourceIndex) else { return }
        let item = bookmarks.remove(at: sourceIndex)
        let dest = min(destinationIndex, bookmarks.count)
        bookmarks.insert(item, at: dest)
        save()
    }

    public func bookmark(at index: Int) -> Bookmark? {
        guard bookmarks.indices.contains(index) else { return nil }
        return bookmarks[index]
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) else { return }
        bookmarks = decoded
    }
}
