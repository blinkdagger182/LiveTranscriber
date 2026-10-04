import Foundation

/// Immutable, Sendable index. Construct once per catalog; invoke off the main actor.
struct CardDetectionService: Sendable {
    struct Token: Sendable {
        let value: String
        let range: Range<String.Index>
    }
    private struct Entry: Sendable {
        let card: Card
        let words: [String]
        let isAlias: Bool
    }
    private let index: [String: [Entry]]
    let maximumNameWords: Int
    private static let actions: Set<String> = ["play", "playing", "cast", "casting", "equip", "equipping", "use", "using", "summon", "move", "tap", "draw", "discard"]

    init(cards: [Card]) {
        var index: [String: [Entry]] = [:]
        var maximum = 1
        for card in cards.sorted(by: { $0.id < $1.id }) {
            for (name, alias) in [(card.name, false)] + card.aliases.map({ ($0, true) }) {
                let words = Self.tokens(in: name).map(\.value)
                guard let first = words.first else { continue }
                maximum = max(maximum, words.count)
                index[first, default: []].append(Entry(card: card, words: words, isAlias: alias))
            }
        }
        self.index = index
        maximumNameWords = maximum
    }

    func detect(in transcript: String) -> [DetectedCard] {
        let tokens = Self.tokens(in: transcript)
        var candidates: [DetectedCard] = []
        for start in tokens.indices {
            guard !Task.isCancelled else { return [] }
            for entry in index[tokens[start].value] ?? [] {
                let end = start + entry.words.count
                guard end <= tokens.count else { continue }
                let window = tokens[start..<end]
                let range = tokens[start].range.lowerBound..<tokens[end - 1].range.upperBound
                let original = String(transcript[range])
                // Don't join unrelated sentences into a card name.
                guard !original.contains(where: { ".!?;".contains($0) }) else { continue }
                let contextual = tokens[max(0, start - 3)..<start].contains {
                    Self.actions.contains($0.value) && !transcript[$0.range.upperBound..<range.lowerBound].contains(where: { ".!?;".contains($0) })
                }
                // One-word names are common English. Require an explicit nearby game action even for exact matches.
                guard entry.words.count > 1 || contextual else { continue }
                let words = window.map(\.value)
                let type: DetectedCard.MatchType
                if words == entry.words {
                    if entry.isAlias {
                        type = .alias
                    } else if original.compare(entry.card.name, options: [.caseInsensitive]) == .orderedSame {
                        type = .exact
                    } else {
                        type = .normalized
                    }
                } else {
                    // Only a single typo in a long word, with an exact first word and explicit game context.
                    // No phonetic guessing, incomplete final words, or fuzzy one-word card names.
                    guard !entry.isAlias, contextual, words.count >= 2,
                          entry.words.joined().count >= 12 else { continue }
                    let differences = zip(words, entry.words).filter { $0 != $1 }
                    guard differences.count == 1, let difference = differences.first,
                          min(difference.0.count, difference.1.count) >= 5,
                          !difference.1.hasPrefix(difference.0),
                          Self.isOneEditApart(difference.0, difference.1) else { continue }
                    type = .fuzzy
                }
                candidates.append(DetectedCard(card: entry.card, text: original, range: range, matchType: type))
            }
        }
        // Priority first, longest match next. No overlapping or duplicate mentions.
        candidates.sort {
            let leftPriority = Self.priority($0.matchType)
            let rightPriority = Self.priority($1.matchType)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            if $0.text.count != $1.text.count { return $0.text.count > $1.text.count }
            return $0.card.id < $1.card.id
        }
        var accepted: [DetectedCard] = []
        for candidate in candidates where !accepted.contains(where: { $0.range.overlaps(candidate.range) }) {
            accepted.append(candidate)
        }
        return accepted.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private static func priority(_ type: DetectedCard.MatchType) -> Int {
        switch type {
        case .exact, .normalized: 0
        case .alias: 1
        case .fuzzy: 2
        }
    }

    static func tokens(in text: String) -> [Token] {
        var result: [Token] = []
        var start: String.Index?
        var value = ""
        for position in text.indices {
            let character = text[position]
            if character.isLetter || character.isNumber {
                if start == nil { start = position }
                value.append(character)
            } else if (character == "'" || character == "’"), start != nil {
                continue
            } else if let lower = start {
                result.append(Token(value: normalize(value), range: lower..<position))
                start = nil
                value = ""
            }
        }
        if let start { result.append(Token(value: normalize(value), range: start..<text.endIndex)) }
        return result
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func isOneEditApart(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs), b = Array(rhs)
        guard abs(a.count - b.count) <= 1 else { return false }
        var i = 0, j = 0, edits = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if a.count >= b.count { i += 1 }
            if b.count >= a.count { j += 1 }
        }
        return edits + (a.count - i) + (b.count - j) == 1
    }
}
