import Foundation

/// Serializes search filtering off the main actor. Owns the `SearchEngine`
/// (and thus its incremental-search state) so heavy `filter` calls run on a
/// background executor instead of blocking the UI. Stateless lookups
/// (`SearchEngine.exactTitleMatch` / `autocompleteTitlePrefix`) stay static and
/// are called directly from the main actor.
public actor SearchActor {
    private var engine = SearchEngine()

    public init() {}

    public func filter(notes: [Note], query: String) -> [Note] {
        engine.filter(notes: notes, query: query)
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

        let results = workingSet.filter { note in
            for token in tokens {
                let matchesTitle = note.cachedLowercaseTitle.contains(token)
                let matchesBody = note.cachedLowercaseBody.contains(token)
                let matchesTags = note.cachedLowercaseTags.contains(token)
                if !matchesTitle && !matchesBody && !matchesTags {
                    return false
                }
            }
            return true
        }

        // Sort by relevance: exact title match first, then title contains, then body/tag only
        let sorted = results.sorted { a, b in
            let tierA = relevanceTier(note: a, query: lowercaseQuery, tokens: tokens)
            let tierB = relevanceTier(note: b, query: lowercaseQuery, tokens: tokens)
            return tierA < tierB
        }

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

    /// Stateless title-prefix lookup. See `exactTitleMatch`.
    public static func autocompleteTitlePrefix(notes: [Note], query: String) -> Note? {
        guard !query.isEmpty else { return nil }
        let lowerQuery = query.lowercased()
        return notes.first { $0.cachedLowercaseTitle.hasPrefix(lowerQuery) }
    }

    /// Returns 0 for exact title match, 1 for title contains, 2 for body/tag only.
    private func relevanceTier(note: Note, query: String, tokens: [String]) -> Int {
        if note.cachedLowercaseTitle == query { return 0 }
        let allInTitle = tokens.allSatisfy { note.cachedLowercaseTitle.contains($0) }
        if allInTitle { return 1 }
        return 2
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
