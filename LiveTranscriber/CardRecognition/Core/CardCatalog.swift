import Foundation

enum CardCatalog {
    /// Pick one printing per spoken name. Prefer main-set printings to promos.
    static func canonicalCards(_ cards: [Card]) -> [Card] {
        let mainSets: Set<String> = ["ogn", "sfd", "unl", "ven"]
        var seen = Set<String>()
        return cards.sorted {
            let lhs = mainSets.contains(String($0.id.prefix(3)))
            let rhs = mainSets.contains(String($1.id.prefix(3)))
            if lhs != rhs { return lhs }
            return $0.id < $1.id
        }.filter {
            seen.insert(CardDetectionService.tokens(in: $0.name).map(\.value).joined(separator: " ")).inserted
        }.sorted { $0.name < $1.name }
    }
}
