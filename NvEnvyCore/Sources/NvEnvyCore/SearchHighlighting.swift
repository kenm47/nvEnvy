import Foundation

/// Shared match-range computation for search-term highlighting in the macOS
/// and iOS editor coordinators. Extracted so it is unit-testable independent
/// of `NSTextView`/`UITextView`, and so both platforms can't drift.
public enum SearchHighlighting {
    /// Returns the non-overlapping ranges of `query` within `text`, searched
    /// case-insensitively against the *original* string (not a lowercased
    /// copy — `lowercased()` is not length-preserving in Unicode, e.g. `İ`
    /// expands to two scalars, which would shift every subsequent range).
    public static func matchRanges(in text: NSString, query: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }

        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.location < text.length {
            let foundRange = text.range(of: query, options: .caseInsensitive, range: searchRange)
            guard foundRange.location != NSNotFound else { break }
            ranges.append(foundRange)
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = text.length - searchRange.location
        }
        return ranges
    }
}
