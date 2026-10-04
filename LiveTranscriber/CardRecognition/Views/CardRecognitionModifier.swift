import Combine
import SwiftUI

struct CardRecognitionModifier: ViewModifier {
    let transcriber: LiveTranscriptionManager
    @State private var model = RiftboundModel()

    func body(content: Content) -> some View {
        @Bindable var model = model
        content
            .environment(model)
            .task { await model.load() }
            #if DEBUG
            .task { await verifyWithProgressiveResultsIfRequested() }
            #endif
            .onReceive(transcriber.finalTranscriptStore.$lines.combineLatest(transcriber.interimTranscriptStore.$line)) { finals, interim in
                model.update(finals: finals, interim: interim)
            }
            .sheet(item: $model.selectedCard) { card in
                CardDetailSheet(card: card)
            }
    }
    #if DEBUG
    /// Repeatable UI verification through the real transcript publishers; never enabled in normal launches.
    @MainActor
    private func verifyWithProgressiveResultsIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--verify-riftbound") else { return }
        var first = TranscriptionLine(startSeconds: 0, text: "I'll play Boots of", isFinal: false)
        transcriber.interimTranscriptStore.publish(first)
        do {
            try await Task.sleep(for: .milliseconds(600))
            first.text = "I'll play Boots of Swiftness and then move Vex Apathy."
            transcriber.interimTranscriptStore.publish(first)
            try await Task.sleep(for: .seconds(2))
            first.isFinal = true
            var finals = [first]
            transcriber.finalTranscriptStore.publish(finals, incrementsRevision: true)
            transcriber.interimTranscriptStore.publish(nil)
            for index in 1...2 {
                try await Task.sleep(for: .seconds(6))
                let line = TranscriptionLine(startSeconds: Double(index * 6), text: "Use Ride the Wind, then play Tornado Warrior. Update \(index).", isFinal: true)
                finals.append(line)
                transcriber.finalTranscriptStore.publish(finals, incrementsRevision: true)
            }
        } catch { return }
    }
    #endif
}
