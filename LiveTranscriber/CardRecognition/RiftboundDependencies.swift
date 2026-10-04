import Foundation

enum RiftboundDependencies {
    static func repository() -> any CardRepository {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return CachedCardRepository(
            seedURL: Bundle.main.bundleURL.appendingPathComponent("riftbound-catalog.json"),
            cacheURL: support.appendingPathComponent("Riftbound/catalog-v1.json")
        )
    }
}
