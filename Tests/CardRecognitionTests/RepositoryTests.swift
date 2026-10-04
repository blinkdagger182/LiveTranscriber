import Foundation
import Testing
@testable import CardRecognitionCore

private final class StubState: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    func configure(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) {
        lock.lock(); defer { lock.unlock() }
        self.handler = handler; calls = 0
    }
    func respond(_ request: URLRequest) throws -> (Int, Data) {
        lock.lock(); calls += 1; let handler = handler; lock.unlock()
        guard let handler else { throw URLError(.notConnectedToInternet) }
        return try handler(request)
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static let state = StubState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.state.respond(request)
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { throw URLError(.badURL) }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private actor FakeAPI: CardAPIClient {
    var count = 0
    var fails = false
    let cards: [Card]
    init(cards: [Card]) { self.cards = cards }
    func fail() { fails = true }
    func fetchCards() async throws -> [Card] {
        count += 1
        try await Task.sleep(for: .milliseconds(10))
        if fails { throw URLError(.notConnectedToInternet) }
        return cards
    }
}

@Suite(.serialized)
struct RepositoryTests {
    private var seedURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LiveTranscriber/CardRecognition/Resources/riftbound-catalog.json")
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
    private func pageData(page: Int, totalPages: Int = 2, duplicate: Bool = false) throws -> Data {
        let source = try JSONSerialization.jsonObject(with: Data(contentsOf: seedURL)) as? [[String: Any]] ?? []
        return try JSONSerialization.data(withJSONObject: ["page": page, "pages": totalPages, "total": totalPages, "items": [source[duplicate ? 0 : page - 1]]])
    }

    @Test func bundledCatalogWorksWithoutNetwork() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let api = FakeAPI(cards: [])
        await api.fail()
        let repository = CachedCardRepository(api: api, seedURL: seedURL, cacheURL: directory.appendingPathComponent("catalog.json"))
        let cards = try await repository.loadCards()
        #expect(cards.count > 700)
        #expect(Set(cards.map(\.name)).count == cards.count)
        for id in ["unl-150-219", "sfd-133-221", "ogn-173-298", "ven-099-166"] {
            let card = try await repository.card(id: id)
            #expect(card?.imageURL?.scheme == "https")
            #expect(card?.rules?.isEmpty == false)
        }
        #expect(await api.count == 0)
        let hits = CardDetectionService(cards: cards).detect(in: "I'll play Boots of Swiftness and then move Vex Apathy.")
        #expect(hits.map(\.card.id) == ["sfd-133-221", "unl-150-219"])
        #expect(hits.last?.card.name == "Vex, Apathetic")
    }

    @Test func persistentCacheTTLRefreshAndOfflineFallback() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("catalog.json")
        let api = FakeAPI(cards: [Card(id: "test", name: "Test Card")])
        let repository = CachedCardRepository(api: api, seedURL: seedURL, cacheURL: file)
        _ = try await repository.refreshCards(force: false)
        #expect(await api.count == 1)
        _ = try await repository.refreshCards(force: false)
        #expect(await api.count == 1)
        // A new repository, with no seed available, must still load persisted cards offline.
        await api.fail()
        let offline = CachedCardRepository(api: api, seedURL: directory.appendingPathComponent("missing.json"), cacheURL: file)
        #expect(try await offline.loadCards().map(\.name) == ["Test Card"])
        await #expect(throws: (any Error).self) { try await offline.refreshCards(force: true) }
        #expect(try await offline.card(id: "test")?.name == "Test Card")
    }

    @Test func corruptCacheFallsBackAndEmptyRefreshDoesNotEraseCatalog() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("catalog.json")
        try Data("broken".utf8).write(to: file)
        let repository = CachedCardRepository(api: FakeAPI(cards: []), seedURL: seedURL, cacheURL: file)
        let before = try await repository.loadCards()
        await #expect(throws: (any Error).self) { try await repository.refreshCards(force: true) }
        #expect(try await repository.loadCards() == before)
    }

    @Test func simultaneousRefreshesShareNetworkWork() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let api = FakeAPI(cards: [Card(id: "test", name: "Test Card")])
        let repository = CachedCardRepository(api: api, seedURL: seedURL, cacheURL: directory.appendingPathComponent("catalog.json"))
        async let a = repository.refreshCards(force: true)
        async let b = repository.refreshCards(force: true)
        let results = try await (a, b)
        #expect(results.0 == results.1)
        #expect(await api.count == 1)
    }

    @Test func apiPaginatesAndNeverRequestsAnImage() async throws {
        let page1 = try pageData(page: 1), page2 = try pageData(page: 2)
        StubURLProtocol.state.configure { request in
            #expect(request.url?.path == "/cards")
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil)
            return (200, request.url?.query?.contains("page=1") == true ? page1 : page2)
        }
        let client = RiftcodexAPIClient(session: session())
        _ = try await client.fetchCards()
        #expect(StubURLProtocol.state.count == 2)
    }

    @Test func apiRejectsDuplicatePaginationAndFailures() async throws {
        let page1 = try pageData(page: 1), page2 = try pageData(page: 2, duplicate: true)
        StubURLProtocol.state.configure { request in (200, request.url?.query?.contains("page=1") == true ? page1 : page2) }
        await #expect(throws: (any Error).self) { try await RiftcodexAPIClient(session: session()).fetchCards() }
        StubURLProtocol.state.configure { _ in (503, Data()) }
        await #expect(throws: (any Error).self) { try await RiftcodexAPIClient(session: session()).fetchCards() }
        StubURLProtocol.state.configure { _ in (200, Data("not json".utf8)) }
        await #expect(throws: (any Error).self) { try await RiftcodexAPIClient(session: session()).fetchCards() }
    }

    @Test func imagesAreOnDemandAndPersistOffline() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))
        let url = try #require(URL(string: "https://example.com/card.png"))
        StubURLProtocol.state.configure { _ in (200, png) }
        let store = CardImageStore(directory: directory, session: session())
        #expect(StubURLProtocol.state.count == 0)
        #expect(try await store.data(for: url) == png)
        #expect(StubURLProtocol.state.count == 1)
        StubURLProtocol.state.configure { _ in throw URLError(.notConnectedToInternet) }
        let offline = CardImageStore(directory: directory, session: session())
        #expect(try await offline.data(for: url) == png)
        #expect(StubURLProtocol.state.count == 0)
    }

    @Test func invalidImagesAreNotCachedAndCanBeRetried() async throws {
        let directory = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let url = try #require(URL(string: "https://example.com/card.png"))
        let store = CardImageStore(directory: directory, session: session())
        StubURLProtocol.state.configure { _ in (200, Data("an HTML error".utf8)) }
        await #expect(throws: (any Error).self) { try await store.data(for: url) }
        await #expect(throws: (any Error).self) { try await store.data(for: url) }
        #expect(StubURLProtocol.state.count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
}
