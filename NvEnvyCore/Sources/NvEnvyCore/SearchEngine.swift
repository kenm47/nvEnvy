import Foundation

/// Serializes search filtering off the main actor. Owns the `SearchEngine`
/// (and thus its incremental-search state) so heavy `filter` calls run on a
/// background executor instead of blocking the UI. Stateless lookups
/// (`SearchEngine.exactTitleMatch` / `bestTitlePrefixMatch`) stay static and
/// are called directly from the main actor.
public actor SearchActor {
    private var engine = SearchEngine()

    public init() {}

    public func filter(notes: [Note], query: String) -> [Note] {
        PerformanceTelemetry.signposter.withIntervalSignpost("SearchActor.filter") {
            engine.filter(notes: notes, query: query)
        }
    }
}

public struct SearchEngine: Sendable {
    private var previousQuery: String = ""
    private var previousResults: [Note] = []

    public init() {}

    public mutating func filter(notes: [Note], query: String) -> [Note] {
        guard !query.isEmpty else {
            previousQuery = ""
            previousResults = []
            return notes
        }

        let lowercaseQuery = query.lowercased()

        // Incremental optimization: if new query extends previous, filter from subset
        let workingSet: [Note]
        if !previousQuery.isEmpty &&
            lowercaseQuery.hasPrefix(previousQuery) &&
            !previousResults.isEmpty {
            workingSet = previousResults
        } else {
            workingSet = notes
        }

        let tokens = tokenize(lowercaseQuery)

        // Sort by relevance: exact title match first, then title prefix, then
        // title contains, then body/tag only. Bucket by tier during the single match pass
        // instead of recomputing each note's tier ~2 log N times inside a
        // sort comparator.
        var tier0Exact: [Note] = []
        var tier1Prefix: [Note] = []
        var tier1Title: [Note] = []
        var tier2Other: [Note] = []

        for note in workingSet {
            var matchesAllTokens = true
            var allTokensInTitle = true
            for token in tokens {
                let inTitle = note.cachedLowercaseTitle.contains(token)
                if !inTitle { allTokensInTitle = false }
                if !inTitle
                    && !note.cachedLowercaseBody.contains(token)
                    && !note.cachedLowercaseTags.contains(token) {
                    matchesAllTokens = false
                    break
                }
            }
            guard matchesAllTokens else { continue }

            if note.cachedLowercaseTitle == lowercaseQuery {
                tier0Exact.append(note)
            } else if allTokensInTitle && note.cachedLowercaseTitle.hasPrefix(lowercaseQuery) {
                tier1Prefix.append(note)
            } else if allTokensInTitle {
                tier1Title.append(note)
            } else {
                tier2Other.append(note)
            }
        }

        var sorted: [Note] = []
        sorted.reserveCapacity(tier0Exact.count + tier1Prefix.count + tier1Title.count + tier2Other.count)
        sorted.append(contentsOf: tier0Exact)
        sorted.append(contentsOf: tier1Prefix)
        sorted.append(contentsOf: tier1Title)
        sorted.append(contentsOf: tier2Other)

        previousQuery = lowercaseQuery
        previousResults = sorted
        return sorted
    }

    /// Stateless exact-title lookup. Does not use the incremental search state,
    /// so it is `static` and safe to call synchronously off the search actor.
    public static func exactTitleMatch(notes: [Note], query: String) -> Note? {
        let lowerQuery = query.lowercased()
        return notes.first { $0.cachedLowercaseTitle == lowerQuery }
    }

    /// Stateless best title-prefix lookup. See `exactTitleMatch`. Among notes
    /// whose title starts with the query, picks the shortest title (closest to
    /// exact), then the most recently modified, then alphabetical, then by id so
    /// the choice is total and deterministic.
    public static func bestTitlePrefixMatch(notes: [Note], query: String) -> Note? {
        guard !query.isEmpty else { return nil }
        let lowerQuery = query.lowercased()
        var best: Note?
        for note in notes where note.cachedLowercaseTitle.hasPrefix(lowerQuery) {
            if let current = best, !isBetterPrefixMatch(note, than: current) { continue }
            best = note
        }
        return best
    }

    private static func isBetterPrefixMatch(_ a: Note, than b: Note) -> Bool {
        let aTitle = a.cachedLowercaseTitle, bTitle = b.cachedLowercaseTitle
        if aTitle.count != bTitle.count { return aTitle.count < bTitle.count }
        if a.modifiedDate != b.modifiedDate { return a.modifiedDate > b.modifiedDate }
        if aTitle != bTitle { return aTitle < bTitle }
        return a.id.uuidString < b.id.uuidString
    }

    private func tokenize(_ query: String) -> [String] {
        var tokens: [String] = []
        var current = query[query.startIndex...]
        while !current.isEmpty {
            if current.first == "\"" {
                // Phrase search
                let rest = current.dropFirst()
                if let endQuote = rest.firstIndex(of: "\"") {
                    let phrase = String(rest[rest.startIndex..<endQuote])
                    if !phrase.isEmpty {
                        tokens.append(phrase)
                    }
                    current = rest[rest.index(after: endQuote)...]
                } else {
                    // No closing quote, treat rest as token
                    let remainder = String(rest).trimmingCharacters(in: .whitespaces)
                    if !remainder.isEmpty {
                        tokens.append(remainder)
                    }
                    break
                }
            } else if current.first == " " {
                current = current.drop(while: { $0 == " " })
            } else {
                // Regular word token
                let end = current.firstIndex(of: " ") ?? current.endIndex
                let token = String(current[current.startIndex..<end])
                if !token.isEmpty {
                    tokens.append(token)
                }
                current = current[end...]
            }
        }
        return tokens
    }
}
