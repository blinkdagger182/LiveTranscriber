import Foundation

protocol CardRepository: Sendable {
    func loadCards() async throws -> [Card]
    func card(id: String) async throws -> Card?
    func refreshCards(force: Bool) async throws -> [Card]
}

extension CardRepository {
    func refreshCards(force: Bool) async throws -> [Card] { try await loadCards() }
}

actor CachedCardRepository: CardRepository {
    private struct Cache: Codable {
        let version: Int
        let fetchedAt: Date
        let cards: [Card]
    }
    private let api: any CardAPIClient
    private let seedURL: URL
    private let cacheURL: URL
    private var loaded: [Card]?
    private var fetchedAt: Date?
    private var refreshTask: Task<[Card], Error>?

    init(api: any CardAPIClient = RiftcodexAPIClient(), seedURL: URL, cacheURL: URL) {
        self.api = api
        self.seedURL = seedURL
        self.cacheURL = cacheURL
    }

    func loadCards() async throws -> [Card] {
        if let loaded { return loaded }
        if let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(Cache.self, from: data),
           cache.version == 1, !cache.cards.isEmpty {
            loaded = cache.cards
            fetchedAt = cache.fetchedAt
            return cache.cards
        }
        let data = try Data(contentsOf: seedURL)
        let seed = CardCatalog.canonicalCards(try JSONDecoder().decode([RiftcodexCard].self, from: data).filter { !$0.isAlternate }.map(\.card))
        guard !seed.isEmpty else { throw CardCatalogError.emptyCatalog }
        loaded = seed
        return seed
    }

    func card(id: String) async throws -> Card? {
        try await loadCards().first { $0.id == id }
    }

    func refreshCards(force: Bool) async throws -> [Card] {
        let current = try await loadCards()
        if !force, let fetchedAt, Date().timeIntervalSince(fetchedAt) < 86_400 { return current }
        if let refreshTask { return try await refreshTask.value }
        let api = self.api
        let task = Task { CardCatalog.canonicalCards(try await api.fetchCards()) }
        refreshTask = task
        defer { refreshTask = nil }
        let cards = try await task.value
        guard !cards.isEmpty else { throw CardCatalogError.emptyCatalog }
        let now = Date()
        let data = try JSONEncoder().encode(Cache(version: 1, fetchedAt: now, cards: cards))
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cacheURL, options: .atomic)
        fetchedAt = now
        loaded = cards
        return cards
    }
}

enum CardCatalogError: LocalizedError {
    case invalidURL, invalidResponse, emptyCatalog
    var errorDescription: String? {
        switch self {
        case .invalidURL: "The card catalog address is invalid."
        case .invalidResponse: "The card service returned an unexpected response."
        case .emptyCatalog: "The card service returned an empty catalog."
        }
    }
}
