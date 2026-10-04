import Foundation

struct CardTranscriptSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let startSeconds: Double
    let isFinal: Bool
}

struct CardHighlight: Equatable, Sendable {
    let card: Card
    let range: NSRange
}

struct CardTranscriptAnnotation: Equatable, Sendable {
    let text: String
    var highlights: [CardHighlight]
}

struct MentionedCard: Identifiable, Equatable, Sendable {
    var id: String { card.id }
    let card: Card
    let firstMentionSeconds: Double
    var isFinal: Bool
}

struct CardTranscriptSnapshot: Sendable {
    var annotations: [UUID: CardTranscriptAnnotation] = [:]
    var mentions: [MentionedCard] = []
}

/// Scans only changed segments and the small preceding name-length context.
/// All tokenization, matching and history reconciliation happens on this actor.
actor TranscriptCardProcessor {
    private struct CachedMatch: Sendable {
        let card: Card
        let range: NSRange
    }
    private struct CachedScan {
        let input: String
        let matches: [CachedMatch]
        let trailingContext: String
    }
    private var detector: CardDetectionService
    private var cache: [UUID: CachedScan] = [:]
    private(set) var scanCount = 0

    init(cards: [Card]) { detector = CardDetectionService(cards: cards) }

    func replaceCatalog(_ cards: [Card]) {
        detector = CardDetectionService(cards: cards)
        cache.removeAll()
    }

    func process(_ segments: [CardTranscriptSegment]) throws -> CardTranscriptSnapshot {
        var snapshot = CardTranscriptSnapshot()
        var mentions: [String: MentionedCard] = [:]
        var placements: [(segment: CardTranscriptSegment, offset: Int, length: Int)] = []
        var offset = 0
        var context = ""
        let liveIDs = Set(segments.map(\.id))
        cache = cache.filter { liveIDs.contains($0.key) }
        for segment in segments {
            try Task.checkCancellation()
            let length = segment.text.utf16.count
            placements.append((segment, offset, length))
            snapshot.annotations[segment.id] = CardTranscriptAnnotation(text: segment.text, highlights: [])
            let prefix = context.isEmpty ? "" : context + "\n"
            let input = prefix + segment.text
            let prefixLength = prefix.utf16.count
            let matches: [CachedMatch]
            let trailingContext: String
            if let cached = cache[segment.id], cached.input == input {
                matches = cached.matches
                trailingContext = cached.trailingContext
            } else {
                scanCount += 1
                matches = detector.detect(in: input).map {
                    CachedMatch(card: $0.card, range: NSRange($0.range, in: input))
                }
                let retained = max(detector.maximumNameWords - 1, 0)
                let tokens = CardDetectionService.tokens(in: input)
                if retained > 0, let first = tokens.suffix(retained).first {
                    trailingContext = String(input[first.range.lowerBound...])
                } else { trailingContext = "" }
                cache[segment.id] = CachedScan(input: input, matches: matches, trailingContext: trailingContext)
            }
            for match in matches where NSMaxRange(match.range) > prefixLength {
                let global = NSRange(location: offset - prefixLength + match.range.location, length: match.range.length)
                var firstSeconds = segment.startSeconds
                var finalized = segment.isFinal
                for placement in placements.reversed() {
                    if placement.offset + placement.length <= global.location { break }
                    let intersection = NSIntersectionRange(global, NSRange(location: placement.offset, length: placement.length))
                    guard intersection.length > 0 else { continue }
                    firstSeconds = placement.segment.startSeconds
                    finalized = finalized && placement.segment.isFinal
                    snapshot.annotations[placement.segment.id]?.highlights.append(CardHighlight(
                        card: match.card,
                        range: NSRange(location: intersection.location - placement.offset, length: intersection.length)
                    ))
                }
                if var existing = mentions[match.card.id] {
                    existing.isFinal = existing.isFinal || finalized
                    mentions[match.card.id] = existing
                } else {
                    mentions[match.card.id] = MentionedCard(card: match.card, firstMentionSeconds: firstSeconds, isFinal: finalized)
                }
            }
            context = trailingContext
            offset += length + 1
        }
        snapshot.mentions = mentions.values.sorted {
            if $0.firstMentionSeconds == $1.firstMentionSeconds { return $0.card.name < $1.card.name }
            return $0.firstMentionSeconds < $1.firstMentionSeconds
        }
        return snapshot
    }
}
