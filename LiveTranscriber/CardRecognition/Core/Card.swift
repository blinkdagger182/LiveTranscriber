import Foundation

struct Card: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    var aliases: [String] = []
    var type: String? = nil
    var energy: Int? = nil
    var power: Int? = nil
    var domains: [String] = []
    var might: Int? = nil
    var rules: String? = nil
    var set: String? = nil
    var rarity: String? = nil
    var imageURL: URL? = nil
    var sourceURL: URL? = nil

}
