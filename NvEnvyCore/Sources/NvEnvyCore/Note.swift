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

    // Search optimization: cached lowercase strings (not displayed; not observed)
    @ObservationIgnored public var cachedLowercaseTitle: String
    @ObservationIgnored public var cachedLowercaseBody: String
    @ObservationIgnored public var cachedLowercaseTags: String

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
    }

    public func invalidateSearchCache() {
        cachedLowercaseTitle = title.lowercased()
        cachedLowercaseBody = body.lowercased()
        cachedLowercaseTags = tags.joined(separator: " ").lowercased()
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
