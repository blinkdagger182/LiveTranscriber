import SwiftUI

struct CardArtworkView: View {
    let card: Card
    @State private var image: UIImage?
    @State private var errorMessage: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel("\(card.name) card image")
                    .accessibilityIdentifier("card-image")
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Image unavailable", systemImage: "photo")
                } description: {
                    Text(errorMessage)
                } actions: {
                    if card.imageURL != nil { Button("Try Again") { attempt += 1 } }
                }
            } else {
                ProgressView("Loading card image…").frame(minHeight: 200)
            }
        }
        .frame(maxWidth: 340)
        .task(id: "\(card.id)-\(attempt)") { await load() }
    }

    private func load() async {
        errorMessage = nil
        guard let url = card.imageURL else {
            errorMessage = "The catalog does not provide an image for this card."
            return
        }
        do {
            let data = try await CardImageStore.shared.data(for: url)
            try Task.checkCancellation()
            guard let decoded = UIImage(data: data) else { throw CardCatalogError.invalidResponse }
            image = decoded
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "The image couldn’t be loaded. Card information is still available offline."
        }
    }
}
