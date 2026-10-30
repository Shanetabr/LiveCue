import Foundation

/// Older transcript lines live on disk; only a small tail is kept in the UI.
/// Each batch is atomic, so a failed write never discards the in-memory lines.
final class TranscriptArchive {
    private let directory: URL
    private var batches = 0
    private(set) var count = 0

    init(directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("LiveCue-" + UUID().uuidString)) {
        self.directory = directory
    }

    func append(_ lines: [Line]) throws {
        guard !lines.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(lines)
        try data.write(to: directory.appendingPathComponent("\(batches).json"), options: .atomic)
        batches += 1
        count += lines.count
    }

    func compact(_ recent: inout [Line]) throws {
        guard recent.count > 600 else { return }
        let excess = recent.count - 500
        try append(Array(recent.prefix(excess)))
        recent.removeFirst(excess)
    }

    func readAll() throws -> [Line] {
        var result: [Line] = []
        result.reserveCapacity(count)
        let decoder = JSONDecoder()
        for index in 0..<batches {
            let data = try Data(contentsOf: directory.appendingPathComponent("\(index).json"))
            result.append(contentsOf: try decoder.decode([Line].self, from: data))
        }
        return result
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
