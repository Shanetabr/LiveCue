import AVFoundation
import Speech
import Foundation
private func expect(_ condition: @autoclosure () -> Bool) {
    precondition(condition(), "Regression check failed")
}
private func require<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckFailure.missingValue }
    return value
}
private enum CheckFailure: Error { case missingValue }


func longTranscriptKeepsSmallWindowAndPreservesEveryLine() throws {
    let archive = TranscriptArchive()
    var recent: [Line] = []
    var ids: [UUID] = []
    for i in 0..<20_000 {
        let line = Line(text: "Front of House \(i)\nwith Unicode 🎙️")
        ids.append(line.id)
        recent.append(line)
        try archive.compact(&recent)
        expect(recent.count <= 600)
    }
    let restored = try archive.readAll() + recent
    expect(restored.map(\.id) == ids)
    expect(archive.count + recent.count == 20_000)
    expect(restored.last?.text == "Front of House 19999\nwith Unicode 🎙️")
    let reopened = try JSONDecoder().decode([Line].self, from: JSONEncoder().encode(restored))
    expect(reopened.map(\.id) == ids)
    expect(TranscriptExporter.export(lines: restored, format: .csv).contains("Front of House 0"))
}

func archiveFailureRetainsRecentLines() throws {
    let blocked = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: blocked) // a file cannot be used as an archive directory
    let archive = TranscriptArchive(directory: blocked)
    var recent = (0..<601).map { Line(text: "\($0)") }
    var failed = false
    do { try archive.compact(&recent) } catch { failed = true }
    expect(failed)
    expect(recent.count == 601)
    expect(archive.count == 0)
}

func liveAudioOverflowClosesQueueAndReportsFailure() async throws {
    let (stream, feed) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(32))
    let failures = OverflowCount()
    let sink = AudioSink(feed: feed, onOverflow: { failures.increment() })
    let format = try require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    for _ in 0..<1000 {
        let buffer = try require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        buffer.frameLength = 4096
        sink.send(buffer)
    }
    var received = 0
    for await _ in stream { received += 1 }
    expect(received == 32)
    expect(failures.count == 1)
}

private final class OverflowCount: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

func reusedMonoBufferDoesNotOverwriteQueuedAudio() throws {
    let format = try require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
    let target = try require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
    let feeder = ChannelFeeder(channel: 1, target: target)
    let input = try require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
    input.frameLength = 4096
    for i in 0..<4096 { input.floatChannelData![1][i] = 0.25 }
    let first = try require(feeder.feed(input))
    let samples = Array(UnsafeBufferPointer(start: first.floatChannelData![0], count: Int(first.frameLength)))
    for i in 0..<4096 { input.floatChannelData![1][i] = 0.75 }
    _ = try require(feeder.feed(input))
    expect(Array(UnsafeBufferPointer(start: first.floatChannelData![0], count: Int(first.frameLength))) == samples)
    expect(feeder.peak == 0.75)
}

func invalidInputDoesNotSilentlyReadAnotherChannel() throws {
    let format = try require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
    let buffer = try require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
    buffer.frameLength = 64
    let feeder = ChannelFeeder(channel: 2, target: format)
    expect(feeder.feed(buffer) == nil)
}

@main struct MemoryChecks {
    static func main() async throws {
        try longTranscriptKeepsSmallWindowAndPreservesEveryLine()
        try archiveFailureRetainsRecentLines()
        try await liveAudioOverflowClosesQueueAndReportsFailure()
        try reusedMonoBufferDoesNotOverwriteQueuedAudio()
        try invalidInputDoesNotSilentlyReadAnotherChannel()
        print("Passed: 20,000-line preservation and bounded window, archive failure, 1,000-buffer overload, audio buffer ownership")
    }
}
