import CryptoKit
import Foundation
import ImageIO

/// On-demand image downloads, coalesced across sheets and persisted independently of the catalog.
actor CardImageStore {
    static let shared = CardImageStore()
    private let directory: URL
    private let session: URLSession
    private var pending: [URL: Task<Data, Error>] = [:]

    init(directory: URL? = nil, session: URLSession = .shared) {
        self.directory = directory ?? (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory).appendingPathComponent("Riftbound/Images")
        self.session = session
    }

    func data(for url: URL) async throws -> Data {
        guard url.scheme == "https" else { throw CardCatalogError.invalidURL }
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent(name)
        if let data = try? Data(contentsOf: file), Self.isImage(data) { return data }
        if let task = pending[url] { return try await task.value }
        let session = self.session
        let task = Task<Data, Error> {
            var request = URLRequest(url: url)
            request.timeoutInterval = 25
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  data.count < 20_000_000, Self.isImage(data) else { throw CardCatalogError.invalidResponse }
            return data
        }
        pending[url] = task
        defer { pending[url] = nil }
        let data = try await task.value
        // Failure to persist must not prevent viewing a successfully downloaded image.
        if (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil {
            try? data.write(to: file, options: .atomic)
        }
        return data
    }

    private static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }
}
