import Foundation

// What happens when a keyword is detected
public enum TriggerAction: Codable, Equatable, Sendable {
    case midiNoteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case midiNoteOff(channel: UInt8, note: UInt8, velocity: UInt8)
    case midiCC(channel: UInt8, controller: UInt8, value: UInt8)
    case midiProgramChange(channel: UInt8, program: UInt8)
    case midiMSC(deviceID: UInt8, commandFormat: UInt8, command: UInt8, cueNumber: String?, cueList: String?)
    case flashWindow  // visual alert
}

public enum MatchMode: String, Codable, CaseIterable, Sendable {
    case exact      // entire transcript line matches keyword
    case contains   // keyword found anywhere in text
    case prefix     // transcript line starts with keyword
}

// A rule that maps a spoken keyword/phrase to an action
public struct KeywordRule: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var keyword: String          // the word or phrase to match
    public var enabled: Bool
    public var caseSensitive: Bool
    public var matchMode: MatchMode     // exact, contains, prefix
    public var action: TriggerAction    // what to do when matched
    public var cooldownSeconds: Double  // minimum time between triggers (prevent jitter)
    public var channelFilter: UUID?     // nil = all channels, or specific channel ID
    public var followAudioChannel: Bool // when true, outgoing MIDI channel matches the spoken audio input channel (1..16)

    enum CodingKeys: String, CodingKey {
        case id, keyword, enabled, caseSensitive, matchMode, action, cooldownSeconds, channelFilter, followAudioChannel
    }

    public init(
        id: UUID = UUID(),
        keyword: String,
        enabled: Bool = true,
        caseSensitive: Bool = false,
        matchMode: MatchMode = .contains,
        action: TriggerAction,
        cooldownSeconds: Double = 1.0,
        channelFilter: UUID? = nil,
        followAudioChannel: Bool = false
    ) {
        self.id = id
        self.keyword = keyword
        self.enabled = enabled
        self.caseSensitive = caseSensitive
        self.matchMode = matchMode
        self.action = action
        self.cooldownSeconds = cooldownSeconds
        self.channelFilter = channelFilter
        self.followAudioChannel = followAudioChannel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        keyword = try container.decode(String.self, forKey: .keyword)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        caseSensitive = try container.decode(Bool.self, forKey: .caseSensitive)
        matchMode = try container.decode(MatchMode.self, forKey: .matchMode)
        action = try container.decode(TriggerAction.self, forKey: .action)
        cooldownSeconds = try container.decode(Double.self, forKey: .cooldownSeconds)
        channelFilter = try container.decodeIfPresent(UUID.self, forKey: .channelFilter)
        followAudioChannel = try container.decodeIfPresent(Bool.self, forKey: .followAudioChannel) ?? false
    }
}
