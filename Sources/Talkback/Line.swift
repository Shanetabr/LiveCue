import Foundation

public struct Line: Identifiable, Codable, Sendable {
    public let id: UUID
    public let time: Date
    public let text: String
    public let channelID: UUID?
    public let channelName: String?
    public let channelColorHex: String?

    public init(
        id: UUID = UUID(),
        time: Date = Date(),
        text: String,
        channelID: UUID? = nil,
        channelName: String? = nil,
        channelColorHex: String? = nil
    ) {
        self.id = id
        self.time = time
        self.text = text
        self.channelID = channelID
        self.channelName = channelName
        self.channelColorHex = channelColorHex
    }
}
