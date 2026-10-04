import Foundation
import Testing
@testable import CardRecognitionCore

private let vex = Card(id: "vex", name: "Vex, Apathetic", aliases: ["Vex Apathy"])
private let boots = Card(id: "boots", name: "Boots of Swiftness")
private let wind = Card(id: "wind", name: "Ride the Wind")
private let tornado = Card(id: "tornado", name: "Tornado Warrior")
private let cards = [vex, boots, wind, tornado, Card(id: "recall", name: "Recall"), Card(id: "charm", name: "Charm"), Card(id: "barrier", name: "Barrier")]

struct CardDetectionTests {
    @Test(arguments: ["play Vex, Apathy", "play vex apathy", "play Vex, Apathetic", "play VEX APATHETIC"])
    func vexNames(text: String) {
        let hits = CardDetectionService(cards: cards).detect(in: text)
        #expect(hits.map(\.card.id) == ["vex"])
        #expect(hits.first.map { String(text[$0.range]) == $0.text } == true)
    }

    @Test(arguments: ["equip Boots of Swiftness", "(Boots, of   Swiftness)!", "🎲 Boots of Swiftness — ready", "boots of swiftness"])
    func bootsNames(text: String) {
        #expect(CardDetectionService(cards: cards).detect(in: text).map(\.card.id) == ["boots"])
    }

    @Test func multipleAndRepeated() {
        let text = "I'll play Boots of Swiftness, then move Vex Apathy and use ride the wind. Boots of Swiftness!"
        #expect(CardDetectionService(cards: cards).detect(in: text).map(\.card.id) == ["boots", "vex", "wind", "boots"])
    }

    @Test(arguments: ["play Vex Apa", "Boots of Swift", "play Boots of Swiftnes", "ride the", "Tornado Warr", "Boots of Swiftnessness", "the recall has charm and a barrier", "play chasm and carrier", "use recalll", "I lost my boots. Of swiftness we spoke."])
    func avoidsFalsePositives(text: String) {
        #expect(CardDetectionService(cards: cards).detect(in: text).isEmpty)
    }

    @Test func conservativeFuzzy() {
        let detector = CardDetectionService(cards: cards)
        #expect(detector.detect(in: "equip Boots of Swiftnass").first?.matchType == .fuzzy)
        #expect(detector.detect(in: "Boots of Swiftnass are comfortable").isEmpty)
        #expect(detector.detect(in: "play Boots of Slowness").isEmpty)
        #expect(detector.detect(in: "play Recall").first?.card.id == "recall")
    }

    @Test func unicodeAndApostrophes() {
        let card = Card(id: "zhonya", name: "Zhonya’s Hourglass")
        let text = "🎲 use ZHONYAS   HOURGLASS, then go."
        let hit = CardDetectionService(cards: [card]).detect(in: text).first
        #expect(hit?.text == "ZHONYAS   HOURGLASS")
        #expect(hit?.matchType == .normalized)
    }

    @Test func longestAndCanonicalPriority() {
        let detector = CardDetectionService(cards: [wind, Card(id: "short", name: "Ride"), Card(id: "other", name: "Other Card", aliases: ["Ride the Wind"])])
        let hits = detector.detect(in: "play Ride the Wind")
        #expect(hits.count == 1)
        #expect(hits.first?.card.id == wind.id)
    }

    @Test func partialCorrectionAndSplitName() async throws {
        let processor = TranscriptCardProcessor(cards: cards)
        let a = UUID(), b = UUID(), c = UUID()
        var segments = [CardTranscriptSegment(id: a, text: "I'll play Boots of", startSeconds: 4, isFinal: true), CardTranscriptSegment(id: b, text: "Swiftness and Vex Apathy", startSeconds: 7, isFinal: false)]
        let first = try await processor.process(segments)
        #expect(first.mentions.count == 2)
        #expect(first.mentions.first(where: { $0.id == "boots" })?.firstMentionSeconds == 4)
        #expect(first.annotations[a]?.highlights.first?.card.id == "boots")
        #expect(first.annotations[b]?.highlights.count == 2)
        let count = await processor.scanCount
        _ = try await processor.process(segments)
        #expect(await processor.scanCount == count)
        segments[1] = CardTranscriptSegment(id: b, text: "Swiftness and Vex", startSeconds: 7, isFinal: false)
        let correction = try await processor.process(segments)
        #expect(correction.mentions.map(\.id) == ["boots"])
        #expect(await processor.scanCount == count + 1)
        segments.append(CardTranscriptSegment(id: c, text: "Apathy", startSeconds: 8, isFinal: true))
        let split = try await processor.process(segments)
        #expect(split.mentions.count == 2)
        let reset = try await processor.process([])
        #expect(reset.mentions.isEmpty)
    }

    @Test func normalizedFullNameBeatsShortExactNameAndAlias() {
        let detector = CardDetectionService(cards: [wind, Card(id: "short", name: "Ride"), Card(id: "other", name: "Other Card", aliases: ["Ride the Wind"])])
        #expect(detector.detect(in: "play Ride, the Wind").map(\.card.id) == [wind.id])
        #expect(detector.detect(in: "We play. Recall what happened.").isEmpty)
    }

    @Test func threeSegmentsAndFinalization() async throws {
        let processor = TranscriptCardProcessor(cards: cards)
        let segments = [
            CardTranscriptSegment(id: UUID(), text: "Boots", startSeconds: 1, isFinal: true),
            CardTranscriptSegment(id: UUID(), text: "of", startSeconds: 2, isFinal: true),
            CardTranscriptSegment(id: UUID(), text: "Swiftness", startSeconds: 3, isFinal: true)
        ]
        let result = try await processor.process(segments)
        #expect(result.mentions.count == 1)
        #expect(result.mentions.first?.firstMentionSeconds == 1)
        #expect(result.mentions.first?.isFinal == true)
        #expect(segments.allSatisfy { result.annotations[$0.id]?.highlights.count == 1 })
    }

    @Test func longSessionDoesNotRescanUnchangedSegments() async throws {
        let processor = TranscriptCardProcessor(cards: cards)
        var segments = (0..<1000).map { CardTranscriptSegment(id: UUID(), text: "We talk about the next turn and play Boots of Swiftness.", startSeconds: Double($0), isFinal: true) }
        _ = try await processor.process(segments)
        let before = await processor.scanCount
        let last = try #require(segments.last)
        segments[999] = CardTranscriptSegment(id: last.id, text: last.text + " Use Ride the Wind.", startSeconds: 999, isFinal: false)
        let result = try await processor.process(segments)
        #expect(await processor.scanCount == before + 1)
        #expect(result.mentions.map(\.card.id) == ["boots", "wind"])
    }

    @Test func catalogScale() {
        let catalog = (0..<2000).map { Card(id: "\($0)", name: "Distinct\($0) Card Name") } + cards
        #expect(CardDetectionService(cards: catalog).detect(in: "play Boots of Swiftness and Vex Apathy").count == 2)
    }
}
