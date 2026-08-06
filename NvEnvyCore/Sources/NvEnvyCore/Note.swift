import Foundation

public enum SyncStatus: Int, Sendable {
    case local = 0
    case uploading = 1
    case downloading = 2
    case current = 3
    case conflict = 4
}

@Observable
public final class Note: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var title: String
    public var body: String
    public var tags: [String]
    public var filename: String
    public var createdDate: Date
    public var modifiedDate: Date
    @ObservationIgnored public var fileModifiedDate: Date?
    @ObservationIgnored public var fileSize: UInt64?
    @ObservationIgnored public var fileEncoding: String.Encoding
    @ObservationIgnored public var selectedRange: NSRange?
    public var syncStatus: SyncStatus = .local

    /// Frontmatter keys nvEnvy doesn't model, carried from read to write so a
    /// save doesn't strip them. External tools keep identity here — Joplin's
    /// two-way sync stores the note's `id`, and losing it makes the file look
    /// like a brand-new note on the next sync.
    @ObservationIgnored public var unknownFrontmatterFields: [(key: String, value: Any)] = []

    // Search optimization: cached lowercase strings (not displayed; not observed)
    @ObservationIgnored public var cachedLowercaseTitle: String
    @ObservationIgnored public var cachedLowercaseBody: String
    @ObservationIgnored public var cachedLowercaseTags: String

    // List-render optimization: first non-empty line of the body, shown in
    // preview rows. Cached so each row render avoids splitting the whole body.
    @ObservationIgnored public var cachedFirstLine: String

    public init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        tags: [String] = [],
        filename: String = "",
        createdDate: Date = Date(),
        modifiedDate: Date = Date(),
        fileEncoding: String.Encoding = .utf8
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
        self.filename = filename.isEmpty ? Note.sanitizedFilename(from: title) : filename
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.fileEncoding = fileEncoding
        self.cachedLowercaseTitle = title.lowercased()
        self.cachedLowercaseBody = body.lowercased()
        self.cachedLowercaseTags = tags.joined(separator: " ").lowercased()
        self.cachedFirstLine = Note.firstLine(of: body)
    }

    public func invalidateSearchCache() {
        cachedLowercaseTitle = title.lowercased()
        cachedLowercaseBody = body.lowercased()
        cachedLowercaseTags = tags.joined(separator: " ").lowercased()
        cachedFirstLine = Note.firstLine(of: body)
    }

    /// First non-empty line of `body` (leading/trailing whitespace and blank
    /// lines trimmed). Avoids splitting the entire body into components.
    public static func firstLine(of body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nl = trimmed.firstIndex(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) {
            return String(trimmed[trimmed.startIndex..<nl])
        }
        return trimmed
    }

    public static func sanitizedFilename(from title: String) -> String {
        let forbidden = CharacterSet(charactersIn: ":/\\?\"|*<>\0")
        var name = title.components(separatedBy: forbidden).joined(separator: "-")
        // Truncate to 255 bytes UTF-8
        while name.utf8.count > 250 {
            name = String(name.dropLast())
        }
        if name.isEmpty {
            name = "Untitled"
        }
        return name
    }
}

extension Note: Equatable {
    public static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id
    }
}

extension Note: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
