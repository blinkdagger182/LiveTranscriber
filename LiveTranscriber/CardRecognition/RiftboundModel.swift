import Foundation
import Observation

@MainActor
@Observable
final class RiftboundModel {
    var selectedCard: Card?
    private(set) var snapshot = CardTranscriptSnapshot()
    private(set) var catalogCount = 0
    private(set) var isRefreshing = false
    private(set) var catalogMessage: String?
    private(set) var hasLoaded = false
    let repository: any CardRepository
    @ObservationIgnored private var processor: TranscriptCardProcessor?
    @ObservationIgnored private var detectionTask: Task<Void, Never>?
    @ObservationIgnored private var segments: [CardTranscriptSegment] = []
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var catalog: [Card] = []

    init(repository: any CardRepository = RiftboundDependencies.repository()) {
        self.repository = repository
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            await install(try await repository.loadCards())
            await refresh(force: false)
        } catch {
            hasLoaded = false
            catalogMessage = "Card catalog unavailable: \(error.localizedDescription)"
        }
    }

    func refresh(force: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            await install(try await repository.refreshCards(force: force))
            catalogMessage = nil
        } catch is CancellationError {
            return
        } catch {
            catalogMessage = catalogCount > 0
                ? "Update unavailable. All \(catalogCount) saved card titles still work offline."
                : "Card catalog unavailable: \(error.localizedDescription)"
        }
    }

    private func install(_ cards: [Card]) async {
        guard cards != catalog else { return }
        if let processor { await processor.replaceCatalog(cards) }
        else {
            processor = await Task.detached(priority: .utility) { TranscriptCardProcessor(cards: cards) }.value
        }
        catalog = cards
        catalogCount = cards.count
        revision += 1
        scheduleDetection()
    }

    func update(finals: [TranscriptionLine], interim: TranscriptionLine?) {
        var lines = finals
        if let interim {
            if let index = lines.firstIndex(where: { abs($0.startSeconds - interim.startSeconds) < 0.1 }) {
                lines[index] = interim
            } else { lines.append(interim) }
        }
        segments = lines.sorted { $0.startSeconds < $1.startSeconds }.map {
            CardTranscriptSegment(id: $0.id, text: $0.text, startSeconds: $0.startSeconds, isFinal: $0.isFinal)
        }
        revision += 1
        if segments.isEmpty { snapshot = CardTranscriptSnapshot() }
        scheduleDetection()
    }

    private func scheduleDetection() {
        guard detectionTask == nil, let processor else { return }
        detectionTask = Task { [weak self] in
            defer { self?.detectionTask = nil }
            while !Task.isCancelled {
                // Throttle rather than starving detection while partial results keep arriving.
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                guard let self else { return }
                let version = self.revision
                do {
                    let result = try await processor.process(self.segments)
                    guard !Task.isCancelled else { return }
                    if self.revision == version {
                        self.snapshot = result
                        return
                    }
                } catch { return }
            }
        }
    }
}
