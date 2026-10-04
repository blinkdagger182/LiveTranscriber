import SwiftUI

struct CardDetailSheet: View {
    let card: Card
    @Environment(\.dismiss) private var dismiss
    @AppStorage("riftbound.showImages") private var showImages = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(card.name).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    if showImages {
                        CardArtworkView(card: card)
                            .frame(maxWidth: .infinity)
                    }
                    VStack(spacing: 12) {
                        if let type = card.type { LabeledContent("Type", value: type) }
                        if let energy = card.energy { LabeledContent("Energy", value: "\(energy)") }
                        LabeledContent("Power requirement", value: card.power.map(String.init) ?? "None")
                        if !card.domains.isEmpty { LabeledContent("Domains", value: card.domains.joined(separator: ", ")) }
                        if let might = card.might { LabeledContent("Might", value: "\(might)") }
                        if let set = card.set { LabeledContent("Set", value: set) }
                        if let rarity = card.rarity { LabeledContent("Rarity", value: rarity) }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rules").font(.headline)
                        Text(card.rules?.isEmpty == false ? (card.rules ?? "") : "No rules text supplied by the card catalog.")
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(card.id.uppercased()) · Riftcodex\nCard text may be incomplete; consult the card image for the printed wording.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Card Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("dismiss-card") } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
