@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Takes one channel out of a buffer and converts it to the format the
/// speech engine wants. Used for the live input and for the file check.
final class ChannelFeeder: @unchecked Sendable {
    private let channel: Int
    private let target: AVAudioFormat
    private var mono: AVAudioFormat?
    private var converter: AVAudioConverter?

    private var _peak: Float = 0
    private var lock = os_unfair_lock()

    init(channel: Int, target: AVAudioFormat) {
        self.channel = channel
        self.target = target
    }

    /// The loudest sample of the last buffer, 0 to 1.
    var peak: Float {
        os_unfair_lock_lock(&lock)
        let val = _peak
        os_unfair_lock_unlock(&lock)
        return val
    }

    private func setPeak(_ val: Float) {
        os_unfair_lock_lock(&lock)
        _peak = val
        os_unfair_lock_unlock(&lock)
    }

    func feed(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return nil }
        let ch = max(0, min(channel, Int(buffer.format.channelCount) - 1))
        let frames = Int(buffer.frameLength)

        if mono == nil || mono!.sampleRate != buffer.format.sampleRate {
            mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: buffer.format.sampleRate,
                                 channels: 1, interleaved: false)
            converter = mono.flatMap { AVAudioConverter(from: $0, to: target) }
            converter?.primeMethod = .none
        }
        guard let mono, let converter,
              let one = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength) else { return nil }

        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        let source = buffer.format.isInterleaved ? data[0] + ch : data[ch]
        let dest = one.floatChannelData![0]
        var top: Float = 0
        for i in 0..<frames {
            let v = source[i * stride]
            dest[i] = v
            top = max(top, abs(v))
        }
        one.frameLength = buffer.frameLength
        setPeak(top)

        let capacity = AVAudioFrameCount(Double(frames) * target.sampleRate / mono.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        final class InputState: @unchecked Sendable {
            var fed = false
            let buffer: AVAudioPCMBuffer
            init(buffer: AVAudioPCMBuffer) {
                self.buffer = buffer
            }
        }
        let inputState = InputState(buffer: one)
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if inputState.fed {
                status.pointee = .noDataNow
                return nil
            }
            inputState.fed = true
            status.pointee = .haveData
            return inputState.buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }
}

/// Target channel specification for multi-channel audio tap.
public struct ChannelTarget: @unchecked Sendable {
    public let id: UUID
    public let channel: Int
    public let target: AVAudioFormat
    public let sink: AudioSink

    public init(id: UUID, channel: Int, target: AVAudioFormat, sink: AudioSink) {
        self.id = id
        self.channel = channel
        self.target = target
        self.sink = sink
    }
}

/// One input device, live. Can feed multiple channels simultaneously from a single tap.
public final class AudioCapture: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private var configObserver: NSObjectProtocol?
    private var currentDevice: AudioDeviceID?
    private var currentTargets: [ChannelTarget] = []

    private var feederMap: [UUID: ChannelFeeder] = [:]
    private var hardwarePeak: Float = 0
    private var lock = os_unfair_lock()

    public var onConfigurationChange: (@Sendable () -> Void)?

    public struct Failure: LocalizedError {
        public let errorDescription: String?
        public init(errorDescription: String?) {
            self.errorDescription = errorDescription
        }
    }

    public init() {}

    /// Multi-channel capture method. Feeds multiple channels from a single AVAudioEngine tap.
    public func startMulti(device: AudioDeviceID, targets: [ChannelTarget]) throws {
        stop()
        guard !targets.isEmpty else { return }

        self.currentDevice = device
        self.currentTargets = targets

        let engine = AVAudioEngine()
        let input = engine.inputNode
        guard let unit = input.audioUnit else {
            throw Failure(errorDescription: "The audio input could not be opened.")
        }
        var id = device
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            throw Failure(errorDescription: "That input device could not be selected (error \(status)).")
        }

        let hwFormat = input.inputFormat(forBus: 0)
        let tapSampleRate = hwFormat.sampleRate > 0 ? hwFormat.sampleRate : 48000
        let tapChannels = max(1, hwFormat.channelCount)
        guard let tapFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: tapSampleRate,
                                            channels: tapChannels,
                                            interleaved: false) else {
            throw Failure(errorDescription: "Unable to create 32-bit float audio tap format.")
        }

        struct FeederBinding: @unchecked Sendable {
            let feeder: ChannelFeeder
            let sink: AudioSink
        }

        var map: [UUID: ChannelFeeder] = [:]
        var bindings: [FeederBinding] = []

        for target in targets {
            let feeder = ChannelFeeder(channel: target.channel, target: target.target)
            map[target.id] = feeder
            bindings.append(FeederBinding(feeder: feeder, sink: target.sink))
        }

        os_unfair_lock_lock(&lock)
        self.feederMap = map
        self.hardwarePeak = 0
        os_unfair_lock_unlock(&lock)

        input.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Instant raw hardware peak calculation directly from the audio driver buffer
            if let data = buffer.floatChannelData, buffer.frameLength > 0 {
                let frames = Int(buffer.frameLength)
                let chCount = Int(buffer.format.channelCount)
                var rawPeak: Float = 0
                for c in 0..<chCount {
                    let ptr = data[c]
                    for i in 0..<frames {
                        rawPeak = max(rawPeak, abs(ptr[i]))
                    }
                }
                os_unfair_lock_lock(&self.lock)
                self.hardwarePeak = rawPeak
                os_unfair_lock_unlock(&self.lock)
            }

            for binding in bindings {
                if let out = binding.feeder.feed(buffer) {
                    binding.sink.send(out)
                }
            }
        }

        // Only react to configuration changes if the engine has actually stopped running unexpectedly
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self, let eng = self.engine, !eng.isRunning else { return }
            self.onConfigurationChange?()
        }

        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    /// Reads the current peak volume for a given channel ID (0.0 to 1.0).
    public func peak(for channelID: UUID) -> Float {
        os_unfair_lock_lock(&lock)
        let feeder = feederMap[channelID]
        os_unfair_lock_unlock(&lock)
        return feeder?.peak ?? 0
    }

    /// Reads the overall peak volume across all active channels.
    public func overallPeak() -> Float {
        os_unfair_lock_lock(&lock)
        let hw = hardwarePeak
        let feeders = Array(feederMap.values)
        os_unfair_lock_unlock(&lock)
        let feederPeak = feeders.reduce(Float(0)) { max($0, $1.peak) }
        return max(hw, feederPeak)
    }

    /// Attempts to restart the engine with the current device and targets (e.g. after sample rate change)
    public func restart() throws {
        guard let device = currentDevice, !currentTargets.isEmpty else { return }
        if let eng = engine, eng.isRunning { return }
        try startMulti(device: device, targets: currentTargets)
    }

    public func stop() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil

        os_unfair_lock_lock(&lock)
        self.feederMap.removeAll()
        self.hardwarePeak = 0
        os_unfair_lock_unlock(&lock)
    }
}
