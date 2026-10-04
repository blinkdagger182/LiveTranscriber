import Foundation

struct DetectedCard: Sendable, Equatable {
    enum MatchType: Int, Codable, Sendable {
        case exact, alias, normalized, fuzzy
        var confidence: Double {
            switch self {
            case .exact: 1
            case .alias: 0.99
            case .normalized: 0.98
            case .fuzzy: 0.90
            }
        }
    }

    let card: Card
    let text: String
    /// Always refers to the original input string, never the normalized copy.
    let range: Range<String.Index>
    let matchType: MatchType
    var confidence: Double { matchType.confidence }
}
