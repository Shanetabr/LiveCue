import AVFoundation
import Speech

/// A thread-safe audio sink for delivering PCM buffers into the transcriber pipeline.
public struct AudioSink: Sendable {
    let feed: AsyncStream<AnalyzerInput>.Continuation
    let onOverflow: @Sendable () -> Void

    public func send(_ buffer: AVAudioPCMBuffer) {
        if case .dropped = feed.yield(AnalyzerInput(buffer: buffer)) {
            feed.finish()
            onOverflow()
        }
    }
}

/// Apple's on-device speech engine for one stream of sound.
/// Sound goes in through `send` or `audioSink`; `onResult` gets the text.
@MainActor
final class Transcriber {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// The format `send` expects.
    let format: AVAudioFormat

    private let module: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>
    private let feed: AsyncStream<AnalyzerInput>.Continuation
    private var reading: Task<Void, Never>?
    private var reportError: (@MainActor (Error) -> Void)?

    /// A thread-safe sink to feed audio into this transcriber from background taps.
    var audioSink: AudioSink {
        AudioSink(feed: feed, onOverflow: { [weak self] in
            Task { @MainActor in
                self?.reportError?(Failure(errorDescription: "Speech processing fell behind the bounded audio queue. Reduce enabled channels and restart."))
            }
        })
    }

    /// Gets the speech model if this Mac does not have it yet (needs internet once),
    /// then makes a transcriber ready to start.
    static func make(status: @escaping @MainActor (String) -> Void) async throws -> Transcriber {
        guard SpeechTranscriber.isAvailable else {
            throw Failure(errorDescription: "On-device speech is not available on this Mac.")
        }
        let wanted = Locale(identifier: "en-US")
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else {
            throw Failure(errorDescription: "English is not offered by the speech engine on this Mac.")
        }
        let module = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                       reportingOptions: [.volatileResults], attributeOptions: [])
        let state = await AssetInventory.status(forModules: [module])
        if state == .unsupported {
            throw Failure(errorDescription: "The speech model is not supported on this Mac.")
        }
        if state < .installed {
            status("Downloading the speech model from Apple (first time only)…")
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw Failure(errorDescription: "The speech engine did not offer an audio format.")
        }
        return Transcriber(module: module, format: format)
    }

    private init(module: SpeechTranscriber, format: AVAudioFormat) {
        self.module = module
        self.format = format
        self.analyzer = SpeechAnalyzer(modules: [module])
        (input, feed) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(32))
    }

    func start(
        onResult: @escaping @MainActor (_ text: String, _ final: Bool) -> Void,
        onError: @escaping @MainActor (Error) -> Void
    ) async throws {
        reportError = onError
        let module = self.module
        let feed = self.feed
        reading = Task { @MainActor in
            do {
                for try await result in module.results {
                    if Task.isCancelled { break }
                    onResult(String(result.text.characters), result.isFinal)
                }
            } catch {
                feed.finish()
                if !Task.isCancelled {
                    onError(error)
                }
            }
        }
        try await analyzer.start(inputSequence: input)
    }

    // Offline files can wait for capacity without dropping samples or blocking an audio thread.
    nonisolated func send(_ buffer: AVAudioPCMBuffer) async throws {
        while true {
            try Task.checkCancellation()
            switch feed.yield(AnalyzerInput(buffer: buffer)) {
            case .enqueued: return
            case .terminated: throw Failure(errorDescription: "Audio input is closed.")
            case .dropped: try await Task.sleep(for: .milliseconds(5))
            @unknown default: return
            }
        }
    }

    /// Lets the engine settle what it has heard, then ends cleanly without hanging.
    func finish() async {
        reportError = nil
        feed.finish()
        reading?.cancel()
        _ = await reading?.result
        reading = nil
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
    }
}
