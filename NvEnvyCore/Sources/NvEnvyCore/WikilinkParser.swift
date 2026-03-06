import Foundation

public enum WikilinkParser {
    public static let pattern = "\\[\\[([^\\]]+)\\]\\]"

    public static func findWikilinks(in text: String) -> [(range: Range<String.Index>, title: String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        return matches.compactMap { match -> (Range<String.Index>, String)? in
            guard let fullRange = Range(match.range, in: text),
                  let titleRange = Range(match.range(at: 1), in: text) else { return nil }
            return (fullRange, String(text[titleRange]))
        }
    }

    public static func findWikilinkNSRanges(in text: String) -> [(range: NSRange, title: String)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        return matches.compactMap { match -> (NSRange, String)? in
            let fullRange = match.range
            guard let titleRange = Range(match.range(at: 1), in: text) else { return nil }
            return (fullRange, String(text[titleRange]))
        }
    }
}
