import Foundation

public enum ExportFormat: String, CaseIterable, Identifiable {
    case txt = "Plain Text (.txt)"
    case csv = "Comma-Separated Values (.csv)"
    case srt = "SubRip Subtitles (.srt)"

    public var id: String { rawValue }
    public var fileExtension: String {
        switch self {
        case .txt: return "txt"
        case .csv: return "csv"
        case .srt: return "srt"
        }
    }
}

public struct TranscriptExporter {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let srtFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss,SSS"
        return f
    }()

    public static func export(lines: [Line], format: ExportFormat, defaultChannel: String? = nil) -> String {
        switch format {
        case .txt:
            return exportText(lines: lines, defaultChannel: defaultChannel)
        case .csv:
            return exportCSV(lines: lines, defaultChannel: defaultChannel)
        case .srt:
            return exportSRT(lines: lines, defaultChannel: defaultChannel)
        }
    }

    private static func exportText(lines: [Line], defaultChannel: String?) -> String {
        var output = ""
        for line in lines {
            let timeStr = timeFormatter.string(from: line.time)
            let ch = line.channelName ?? defaultChannel
            let prefix = ch.map { "[\($0)] " } ?? ""
            output += "[\(timeStr)] \(prefix)\(line.text)\n"
        }
        return output
    }

    private static func exportCSV(lines: [Line], defaultChannel: String?) -> String {
        var output = "Timestamp,Channel,Text\n"
        for line in lines {
            let ch = line.channelName ?? defaultChannel ?? "Default"
            let timeStr = ISO8601DateFormatter().string(from: line.time)
            let escapedText = "\"" + line.text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let escapedCh = "\"" + ch.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            output += "\(timeStr),\(escapedCh),\(escapedText)\n"
        }
        return output
    }

    private static func exportSRT(lines: [Line], defaultChannel: String?) -> String {
        var output = ""
        for (index, line) in lines.enumerated() {
            let start = line.time
            let nextTime = (index + 1 < lines.count) ? lines[index + 1].time : start.addingTimeInterval(3.0)
            let end = min(start.addingTimeInterval(5.0), max(start.addingTimeInterval(1.5), nextTime))

            output += "\(index + 1)\n"
            output += "\(srtFormatter.string(from: start)) --> \(srtFormatter.string(from: end))\n"
            let ch = line.channelName ?? defaultChannel
            if let ch = ch {
                output += "[\(ch)] \(line.text)\n\n"
            } else {
                output += "\(line.text)\n\n"
            }
        }
        return output
    }
}
