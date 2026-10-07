import Foundation

public struct ChannelState: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var colorHex: String
    public var channelIndex: Int // 0-based
    public var isEnabled: Bool
    public var level: Float
    public var partial: String
    public var partialTime: Date

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#3498DB",
        channelIndex: Int = 0,
        isEnabled: Bool = true,
        level: Float = 0,
        partial: String = "",
        partialTime: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.channelIndex = channelIndex
        self.isEnabled = isEnabled
        self.level = level
        self.partial = partial
        self.partialTime = partialTime
    }
}
