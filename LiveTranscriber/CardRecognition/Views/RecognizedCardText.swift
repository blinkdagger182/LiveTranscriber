import SwiftUI

struct RecognizedCardText: View {
    @Environment(RiftboundModel.self) private var model
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @AppStorage("riftbound.highlightNames") private var highlightsEnabled = true
    let text: String
    let lineID: UUID

    var body: some View {
        renderedText
            .textRenderer(CardHighlightRenderer())
            .tint(.indigo)
            .accessibilityRepresentation {
                VStack(alignment: .leading) {
                    Text(text)
                    ForEach(accessibleCards) { card in
                        Button("View \(card.name)") { model.selectedCard = card }
                    }
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "riftbound-card", let annotation = model.snapshot.annotations[lineID],
                      annotation.text == text,
                      let card = annotation.highlights.first(where: { $0.card.id == url.lastPathComponent })?.card else {
                    return .discarded
                }
                model.selectedCard = card
                return .handled
            })
    }

    private var accessibleCards: [Card] {
        guard highlightsEnabled, let annotation = model.snapshot.annotations[lineID], annotation.text == text else { return [] }
        var seen = Set<String>()
        return annotation.highlights.map(\.card).filter { seen.insert($0.id).inserted }
    }

    private var renderedText: Text {
        guard highlightsEnabled, let annotation = model.snapshot.annotations[lineID], annotation.text == text else { return Text(text) }
        var output = Text("")
        var cursor = text.startIndex
        for highlight in annotation.highlights.sorted(by: { $0.range.location < $1.range.location }) {
            guard let range = Range(highlight.range, in: text), range.lowerBound >= cursor else { continue }
            let plain = Text(String(text[cursor..<range.lowerBound]))
            var attributed = AttributedString(String(text[range]))
            var components = URLComponents()
            components.scheme = "riftbound-card"
            components.host = "card"
            components.path = "/" + highlight.card.id
            attributed.link = components.url
            attributed.foregroundColor = .indigo
            let mention = Text(attributed)
                .underline(differentiateWithoutColor)
                .customAttribute(CardMentionAttribute())
            output = Text("\(output)\(plain)\(mention)")
            cursor = range.upperBound
        }
        return Text("\(output)\(Text(String(text[cursor...])))")
    }
}

private struct CardMentionAttribute: TextAttribute {}

private struct CardHighlightRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[CardMentionAttribute.self] != nil {
                    context.fill(
                        Path(roundedRect: run.typographicBounds.rect.insetBy(dx: -1, dy: 0), cornerRadius: 4),
                        with: .color(.indigo.opacity(0.13))
                    )
                }
                context.draw(run)
            }
        }
    }
}
