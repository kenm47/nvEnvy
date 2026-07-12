import Foundation

/// Builds the `nvenvy://find/<title>` deep link used by "Copy Note Link" on
/// both platforms, so the URL-encoding rules can't drift between them.
public enum NoteLinkBuilder {
    public static func link(for note: Note) -> String {
        let encoded = note.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? note.title
        return "nvenvy://find/\(encoded)"
    }
}
