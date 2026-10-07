import Foundation

/// A complete, persistent LiveCue show session document.
public struct LiveCueSession: Codable, Sendable {
    public var version: String
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var lines: [Line]
    public var channels: [ChannelConfig]
    public var rules: [KeywordRule]
    public var triggerLogs: [TriggerLogItem]
    public var deviceName: String?

    public init(
        version: String = "1.0",
        title: String = "Untitled Session",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        lines: [Line] = [],
        channels: [ChannelConfig] = [],
        rules: [KeywordRule] = [],
        triggerLogs: [TriggerLogItem] = [],
        deviceName: String? = nil
    ) {
        self.version = version
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lines = lines
        self.channels = channels
        self.rules = rules
        self.triggerLogs = triggerLogs
        self.deviceName = deviceName
    }
}
