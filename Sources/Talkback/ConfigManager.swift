import Foundation

public struct ManualMIDIDestinationConfig: Codable, Equatable, Sendable {
    public var name: String
    public var address: String
    public var port: UInt16

    public init(name: String, address: String, port: UInt16) {
        self.name = name
        self.address = address
        self.port = port
    }
}

public struct ChannelConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var channelIndex: Int // 0-based
    public var isEnabled: Bool

    public init(id: UUID = UUID(), name: String, colorHex: String = "#F2994A", channelIndex: Int = 0, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.channelIndex = channelIndex
        self.isEnabled = isEnabled
    }
}

public struct AppConfig: Codable, Sendable {
    public var rules: [KeywordRule]
    public var manualMIDIDestinations: [ManualMIDIDestinationConfig]
    public var selectedMIDIDestinationIDs: [String]
    public var channels: [ChannelConfig]

    public static let maxChannelsLimit = 6

    public static var `default`: AppConfig {
        AppConfig(
            rules: [
                KeywordRule(
                    keyword: "standby",
                    matchMode: .contains,
                    action: .flashWindow,
                    cooldownSeconds: 2.0
                ),
                KeywordRule(
                    keyword: "go",
                    matchMode: .exact,
                    action: .midiNoteOn(channel: 0, note: 60, velocity: 127),
                    cooldownSeconds: 1.0
                ),
                KeywordRule(
                    keyword: "stop",
                    matchMode: .exact,
                    action: .midiNoteOff(channel: 0, note: 60, velocity: 0),
                    cooldownSeconds: 1.0
                ),
                KeywordRule(
                    keyword: "cue 1",
                    matchMode: .contains,
                    action: .midiMSC(deviceID: 1, commandFormat: 0x01, command: 0x01, cueNumber: "1", cueList: nil),
                    cooldownSeconds: 2.0
                )
            ],
            manualMIDIDestinations: [],
            selectedMIDIDestinationIDs: [],
            channels: [
                ChannelConfig(name: "FOH Comms", colorHex: "#00E575", channelIndex: 0, isEnabled: true),
                ChannelConfig(name: "Director Call", colorHex: "#FF7640", channelIndex: 1, isEnabled: true),
                ChannelConfig(name: "Stage Manager", colorHex: "#00D2FF", channelIndex: 2, isEnabled: true),
                ChannelConfig(name: "Music Director", colorHex: "#FFD600", channelIndex: 3, isEnabled: false)
            ]
        )
    }
}

public final class ConfigManager: Sendable {
    public static let shared = ConfigManager()

    private var fileManager: FileManager { FileManager.default }
    private var configURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let liveCueDir = appSupport.appendingPathComponent("LiveCue", isDirectory: true)
        let oldDir = appSupport.appendingPathComponent("Talkback", isDirectory: true)

        if !fileManager.fileExists(atPath: liveCueDir.path) {
            try? fileManager.createDirectory(at: liveCueDir, withIntermediateDirectories: true)
            let oldConfig = oldDir.appendingPathComponent("config.json")
            let newConfig = liveCueDir.appendingPathComponent("config.json")
            if fileManager.fileExists(atPath: oldConfig.path) && !fileManager.fileExists(atPath: newConfig.path) {
                try? fileManager.copyItem(at: oldConfig, to: newConfig)
            }
        }
        return liveCueDir.appendingPathComponent("config.json")
    }

    public func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL) else {
            return .default
        }
        let decoder = JSONDecoder()
        if let config = try? decoder.decode(AppConfig.self, from: data) {
            return config
        }
        return .default
    }

    public func save(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
    }
}
