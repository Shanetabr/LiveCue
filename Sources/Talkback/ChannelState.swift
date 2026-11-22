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
    /// When the signal after gain last hit full scale (shown as CLIP).
    public var lastClip: Date? = nil
    /// When the signal was already at full scale before gain (gain can't fix this).
    public var lastInputClip: Date? = nil

    /// Clipped within the last 1.5 seconds.
    public func clipping(at now: Date = Date()) -> Bool {
        lastClip.map { now.timeIntervalSince($0) < 1.5 } ?? false
    }
    public func inputClipping(at now: Date = Date()) -> Bool {
        lastInputClip.map { now.timeIntervalSince($0) < 1.5 } ?? false
    }

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
