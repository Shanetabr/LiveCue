import Foundation

public struct TriggerLogItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let ruleKeyword: String
    public let description: String
    public let channelName: String?

    public init(id: UUID = UUID(), timestamp: Date = Date(), ruleKeyword: String, description: String, channelName: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.ruleKeyword = ruleKeyword
        self.description = description
        self.channelName = channelName
    }
}
