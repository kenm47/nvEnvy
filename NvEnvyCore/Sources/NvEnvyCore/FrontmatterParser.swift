import Foundation
import Yams

public struct FrontmatterBlock: Equatable, Sendable {
    public var tags: [String]
    public var created: Date?
    public var modified: Date?
    public var unknownFields: [(key: String, value: Any)]
    public var rawYAML: String?

    public init(
        tags: [String] = [],
        created: Date? = nil,
        modified: Date? = nil,
        unknownFields: [(key: String, value: Any)] = [],
        rawYAML: String? = nil
    ) {
        self.tags = tags
        self.created = created
        self.modified = modified
        self.unknownFields = unknownFields
        self.rawYAML = rawYAML
    }

    public var isEmpty: Bool {
        tags.isEmpty && created == nil && modified == nil && unknownFields.isEmpty
    }

    public static func == (lhs: FrontmatterBlock, rhs: FrontmatterBlock) -> Bool {
        lhs.tags == rhs.tags &&
        lhs.created == rhs.created &&
        lhs.modified == rhs.modified &&
        lhs.rawYAML == rhs.rawYAML
    }
}

public struct ParsedNote: Equatable, Sendable {
    public var frontmatter: FrontmatterBlock?
    public var body: String

    public init(frontmatter: FrontmatterBlock? = nil, body: String) {
        self.frontmatter = frontmatter
        self.body = body
    }
}

public enum FrontmatterParser {

    // MARK: - Parse

    public static func parse(_ content: String) -> ParsedNote {
        let lines = content.components(separatedBy: "\n")

        guard !lines.isEmpty, lines[0].trimmingCharacters(in: .whitespaces) == "---" else {
            return ParsedNote(body: content)
        }

        // Find closing ---
        var closingIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = i
                break
            }
        }

        guard let closing = closingIndex else {
            return ParsedNote(body: content)
        }

        let yamlLines = lines[1..<closing]
        let rawYAML = yamlLines.joined(separator: "\n")

        // Body is everything after closing --- (skip one newline)
        let bodyStartIndex = closing + 1
        let body: String
        if bodyStartIndex < lines.count {
            body = lines[bodyStartIndex...].joined(separator: "\n")
        } else {
            body = ""
        }

        let frontmatter = parseYAML(rawYAML)
        return ParsedNote(frontmatter: frontmatter, body: body)
    }

    private static func parseYAML(_ yaml: String) -> FrontmatterBlock {
        guard let node = try? Yams.compose(yaml: yaml) else {
            return FrontmatterBlock(rawYAML: yaml)
        }

        guard let mapping = node.mapping else {
            return FrontmatterBlock(rawYAML: yaml)
        }

        var tags: [String] = []
        var created: Date?
        var modified: Date?
        var unknownFields: [(key: String, value: Any)] = []

        let knownKeys: Set<String> = ["tags", "created", "modified"]

        for (keyNode, valueNode) in mapping {
            guard let key = keyNode.string else { continue }

            if key == "tags" {
                tags = parseTags(valueNode)
            } else if key == "created" {
                created = parseDate(valueNode)
            } else if key == "modified" {
                modified = parseDate(valueNode)
            } else if !knownKeys.contains(key) {
                unknownFields.append((key: key, value: nodeToAny(valueNode)))
            }
        }

        return FrontmatterBlock(
            tags: tags,
            created: created,
            modified: modified,
            unknownFields: unknownFields,
            rawYAML: yaml
        )
    }

    private static func parseTags(_ node: Node) -> [String] {
        if let sequence = node.sequence {
            return sequence.compactMap { $0.string }
        }
        if let scalar = node.string {
            // Handle comma-separated or single tag
            return scalar.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return []
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let yamlDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static let yamlDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static func parseDate(_ node: Node) -> Date? {
        guard let str = node.string else { return nil }
        if let date = isoFormatter.date(from: str) { return date }
        if let date = yamlDateFormatter.date(from: str) { return date }
        if let date = yamlDateTimeFormatter.date(from: str) { return date }
        return nil
    }

    private static func nodeToAny(_ node: Node) -> Any {
        switch node {
        case .scalar(let s):
            return s.string
        case .sequence(let seq):
            return seq.map { nodeToAny($0) }
        case .mapping(let map):
            var dict: [(String, Any)] = []
            for (k, v) in map {
                dict.append((k.string ?? "", nodeToAny(v)))
            }
            return dict
        case .alias(let alias):
            return alias.anchor
        }
    }

    // MARK: - Serialize

    public static func serialize(frontmatter: FrontmatterBlock?, body: String) -> String {
        guard let fm = frontmatter, !fm.isEmpty else {
            return body
        }

        var yamlLines: [String] = []

        // Tags
        if !fm.tags.isEmpty {
            yamlLines.append("tags:")
            for tag in fm.tags {
                yamlLines.append("  - \(tag)")
            }
        }

        // Created
        if let created = fm.created {
            yamlLines.append("created: \(formatDate(created))")
        }

        // Modified
        if let modified = fm.modified {
            yamlLines.append("modified: \(formatDate(modified))")
        }

        // Unknown fields - preserve in original order
        for (key, value) in fm.unknownFields {
            yamlLines.append(serializeField(key: key, value: value))
        }

        if yamlLines.isEmpty {
            return body
        }

        return "---\n" + yamlLines.joined(separator: "\n") + "\n---\n" + body
    }

    private static func formatDate(_ date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.string(from: date)
    }

    private static func serializeField(key: String, value: Any) -> String {
        if let str = value as? String {
            return "\(key): \(str)"
        }
        if let arr = value as? [Any] {
            var lines = ["\(key):"]
            for item in arr {
                if let s = item as? String {
                    lines.append("  - \(s)")
                } else {
                    lines.append("  - \(item)")
                }
            }
            return lines.joined(separator: "\n")
        }
        if let pairs = value as? [(String, Any)] {
            var lines = ["\(key):"]
            for (k, v) in pairs {
                lines.append("  \(serializeField(key: k, value: v))")
            }
            return lines.joined(separator: "\n")
        }
        return "\(key): \(value)"
    }
}
