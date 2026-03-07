import Foundation

public enum DoneLineDetector {
    /// Returns ranges of lines containing @done in the given text.
    public static func doneLineRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        let nsText = text as NSString

        nsText.enumerateSubstrings(
            in: NSRange(location: 0, length: nsText.length),
            options: .byLines
        ) { line, lineRange, _, _ in
            guard let line, line.contains("@done") else { return }
            if let range = Range(lineRange, in: text) {
                ranges.append(range)
            }
        }

        return ranges
    }

    /// Returns true if the given line contains @done.
    public static func lineContainsDone(_ line: String) -> Bool {
        line.contains("@done")
    }
}
