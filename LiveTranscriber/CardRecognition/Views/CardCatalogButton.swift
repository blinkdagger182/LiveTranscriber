import SwiftUI

struct CardCatalogButton: View {
    @Environment(RiftboundModel.self) private var model
    @State private var showingCatalog = false

    var body: some View {
        Button("Riftbound Cards", systemImage: "rectangle.stack") { showingCatalog = true }
            .labelStyle(.iconOnly)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier("riftbound-catalog")
            .sheet(isPresented: $showingCatalog) {
                CardCatalogSettingsView(model: model)
            }
    }
}

private struct CardCatalogSettingsView: View {
    let model: RiftboundModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("riftbound.highlightNames") private var highlightNames = true
    @AppStorage("riftbound.showImages") private var showImages = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Game", value: "Riftbound")
                    LabeledContent("Cards available offline", value: "\(model.catalogCount)")
                    if model.isRefreshing {
                        HStack { ProgressView(); Text("Updating card catalog…") }
                    } else {
                        Button("Update Card Catalog") { Task { await model.refresh() } }
                    }
                    if let message = model.catalogMessage { Text(message).foregroundStyle(.secondary) }
                } footer: {
                    Text("The complete card-text library is saved on this device. Card recognition never sends your transcript to a server. Catalog updates are checked at most once a day unless you request an update.")
                }
                Section {
                    Toggle("Highlight Card Names", isOn: $highlightNames)
                    Toggle("Show Card Images", isOn: $showImages)
                } footer: {
                    Text("Images download only when you open a card, then stay cached for future visits. Single-word names need a nearby game action, such as ‘play’ or ‘cast’.")
                }
                Section {
                    Text("Card data: Riftcodex. Card names and artwork belong to Riot Games. This is an unofficial companion.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Riftbound Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
