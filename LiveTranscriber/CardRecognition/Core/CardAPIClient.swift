import Foundation

protocol CardAPIClient: Sendable {
    func fetchCards() async throws -> [Card]
}

struct RiftcodexAPIClient: CardAPIClient {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func fetchCards() async throws -> [Card] {
        struct Page: Decodable {
            let items: [RiftcodexCard]
            let pages: Int
            let total: Int
            let page: Int
        }
        var cards: [Card] = []
        var page = 1
        var seenIDs = Set<String>()
        var totalRecords = 0
        while true {
            try Task.checkCancellation()
            guard let url = URL(string: "https://api.riftcodex.com/cards?size=100&page=\(page)&sort=collector_number") else {
                throw CardCatalogError.invalidURL
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw CardCatalogError.invalidResponse
            }
            let result = try JSONDecoder().decode(Page.self, from: data)
            guard (1...100).contains(result.pages), result.page == page, !result.items.isEmpty else { throw CardCatalogError.invalidResponse }
            for item in result.items {
                guard seenIDs.insert(item.id).inserted else { throw CardCatalogError.invalidResponse }
            }
            totalRecords += result.items.count
            cards.append(contentsOf: result.items.filter { !$0.isAlternate }.map(\.card))
            if page >= result.pages {
                guard totalRecords == result.total else { throw CardCatalogError.invalidResponse }
                break
            }
            page += 1
        }
        return cards
    }
}

/// DTO keeps API field names and symbol conventions out of the views.
struct RiftcodexCard: Decodable {
    struct Attributes: Decodable { let energy: Int?; let might: Int?; let power: Int? }
    struct Classification: Decodable { let type: String; let supertype: String?; let rarity: String?; let domain: [String] }
    struct Rules: Decodable { let plain: String; let rich: String? }
    struct CardSet: Decodable { let label: String }
    struct Media: Decodable { let image_url: URL? }
    struct Metadata: Decodable { let alternate_art: Bool?; let signature: Bool?; let overnumbered: Bool? }
    let id: String
    let name: String
    let riftbound_id: String
    let attributes: Attributes
    let classification: Classification
    let text: Rules
    let set: CardSet
    let media: Media
    let metadata: Metadata?
    var isAlternate: Bool { metadata?.alternate_art == true || metadata?.signature == true || metadata?.overnumbered == true }

    var card: Card {
        let name = name.replacingOccurrences(of: " - ", with: ", ")
        return Card(
            id: riftbound_id,
            name: name,
            aliases: riftbound_id == "unl-150-219" ? ["Vex Apathy", "Vex, Apathy"] : [],
            type: [classification.supertype, classification.type].compactMap { $0 }.joined(separator: " "),
            energy: attributes.energy,
            power: attributes.power,
            domains: classification.domain,
            might: attributes.might,
            rules: Self.readableRules(text.rich ?? text.plain),
            set: set.label,
            rarity: classification.rarity,
            imageURL: media.image_url,
            sourceURL: URL(string: "https://api.riftcodex.com/cards/\(id)")
        )
    }

    static func readableRules(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        for (symbol, word) in [("rainbow", "Any domain"), ("chaos", "Chaos"), ("calm", "Calm"), ("fury", "Fury"), ("body", "Body"), ("mind", "Mind"), ("order", "Order")] {
            text = text.replacingOccurrences(of: ":rb_rune_\(symbol):", with: "[\(word)]")
        }
        for value in 0...20 { text = text.replacingOccurrences(of: ":rb_energy_\(value):", with: "[\(value) energy]") }
        return text.replacingOccurrences(of: ":rb_might:", with: "Might")
            .replacingOccurrences(of: ":rb_exhaust:", with: "[Exhaust]")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
