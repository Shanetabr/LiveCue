@preconcurrency import AVFoundation
import Accelerate
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
    private var monoBuffer: AVAudioPCMBuffer?

    private var _peak: Float = 0
    private var _sourcePeak: Float = 0
    private var _gain: Float = 1
    private var lock = os_unfair_lock()

    init(channel: Int, target: AVAudioFormat, gainDB: Double = 0) {
        self.channel = channel
        self.target = target
        self._gain = Self.linear(gainDB)
    }

    static func linear(_ dB: Double) -> Float { Float(pow(10, dB / 20)) }

    /// The loudest sample of the last buffer after gain, 0 to 1 (what the speech engine hears).
    var peak: Float {
        os_unfair_lock_lock(&lock)
        let val = _peak
        os_unfair_lock_unlock(&lock)
        return val
    }

    /// The loudest sample of the last buffer before gain, straight from the device.
    var sourcePeak: Float {
        os_unfair_lock_lock(&lock)
        let val = _sourcePeak
        os_unfair_lock_unlock(&lock)
        return val
    }

    /// Changes the gain; safe to call while audio is running.
    func setGain(dB: Double) {
        os_unfair_lock_lock(&lock)
        _gain = Self.linear(dB)
        os_unfair_lock_unlock(&lock)
    }

    private var gain: Float {
        os_unfair_lock_lock(&lock)
        let val = _gain
        os_unfair_lock_unlock(&lock)
        return val
    }

    private func setPeaks(_ after: Float, _ before: Float) {
        os_unfair_lock_lock(&lock)
        _peak = after
        _sourcePeak = before
        os_unfair_lock_unlock(&lock)
    }

    func feed(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return nil }
        guard channel >= 0, channel < Int(buffer.format.channelCount) else { return nil }
        let ch = channel
        let frames = Int(buffer.frameLength)

        if mono == nil || mono!.sampleRate != buffer.format.sampleRate {
            mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: buffer.format.sampleRate,
                                 channels: 1, interleaved: false)
            converter = mono.flatMap { AVAudioConverter(from: $0, to: target) }
            converter?.primeMethod = .none
            monoBuffer = nil
        }
        guard let mono, let converter else { return nil }
        if monoBuffer == nil || monoBuffer!.frameCapacity < buffer.frameLength {
            monoBuffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength)
        }
        guard let one = monoBuffer else { return nil }

        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        let source = buffer.format.isInterleaved ? data[0] + ch : data[ch]
        let dest = one.floatChannelData![0]
        if stride == 1 {
            dest.update(from: source, count: frames)
        } else {
            for i in 0..<frames { dest[i] = source[i * stride] }
        }
        var before: Float = 0
        vDSP_maxmgv(source, vDSP_Stride(stride), &before, vDSP_Length(frames))
        var g = gain
        if g != 1 {
            // Apply gain, then clip at full scale like real hardware would.
            vDSP_vsmul(dest, 1, &g, dest, 1, vDSP_Length(frames))
            var low: Float = -1, high: Float = 1
            vDSP_vclip(dest, 1, &low, &high, dest, 1, vDSP_Length(frames))
        }
        var after: Float = 0
        vDSP_maxmgv(dest, 1, &after, vDSP_Length(frames))
        one.frameLength = buffer.frameLength
        setPeaks(after, before)

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
    public var gainDB: Double

    public init(id: UUID, channel: Int, target: AVAudioFormat, sink: AudioSink, gainDB: Double = 0) {
        self.id = id
        self.channel = channel
        self.target = target
        self.sink = sink
        self.gainDB = gainDB
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
    private var receivedBuffers: UInt64 = 0
    private var strongestInput = 0
    public private(set) var openedFormat = ""

    public func inputDiagnostics() -> (buffers: UInt64, strongestInput: Int, peak: Float) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return (receivedBuffers, strongestInput, hardwarePeak)
    }
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

        var actualDevice = AudioDeviceID(0)
        var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let query = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &actualDevice, &deviceSize)
        guard query == noErr, actualDevice == device else {
            throw Failure(errorDescription: "The audio engine did not open the selected device (error \(query), device \(actualDevice)).")
        }
        let hwFormat = input.inputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw Failure(errorDescription: "Selected device has no active audio format. Start Dante Virtual Soundcard before recording.")
        }
        // Configure the input node's output bus, which is where recording taps read.
        // Do not substitute a fabricated 48 kHz mono format for inactive hardware.
        // The channels: initializer returns nil above two channels, so devices with
        // more inputs (Dante Virtual Soundcard, larger interfaces) need an explicit
        // discrete channel layout.
        let channelCount = hwFormat.channelCount
        let candidateFormat: AVAudioFormat?
        if channelCount <= 2 {
            candidateFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: hwFormat.sampleRate,
                                            channels: channelCount,
                                            interleaved: false)
        } else if let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channelCount) {
            candidateFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: hwFormat.sampleRate,
                                            interleaved: false,
                                            channelLayout: layout)
        } else {
            candidateFormat = nil
        }
        guard let tapFormat = candidateFormat else {
            throw Failure(errorDescription: "Unable to create audio tap format for \(channelCount) inputs.")
        }
        for target in targets where target.channel < 0 || target.channel >= Int(hwFormat.channelCount) {
            throw Failure(errorDescription: "Input \(target.channel + 1) is unavailable on the selected device (\(hwFormat.channelCount) inputs).")
        }
        var streamFormat = tapFormat.streamDescription.pointee
        let formatStatus = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
                                                &streamFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard formatStatus == noErr else {
            throw Failure(errorDescription: "Could not configure selected device input format (error \(formatStatus)).")
        }
        openedFormat = "\(Int(hwFormat.sampleRate)) Hz / \(hwFormat.channelCount) inputs"

        struct FeederBinding: @unchecked Sendable {
            let feeder: ChannelFeeder
            let sink: AudioSink
        }

        var map: [UUID: ChannelFeeder] = [:]
        var bindings: [FeederBinding] = []

        for target in targets {
            let feeder = ChannelFeeder(channel: target.channel, target: target.target, gainDB: target.gainDB)
            map[target.id] = feeder
            bindings.append(FeederBinding(feeder: feeder, sink: target.sink))
        }

        os_unfair_lock_lock(&lock)
        self.feederMap = map
        self.hardwarePeak = 0
        self.receivedBuffers = 0
        self.strongestInput = 0
        os_unfair_lock_unlock(&lock)

        input.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Instant raw hardware peak calculation directly from the audio driver buffer
            if let data = buffer.floatChannelData, buffer.frameLength > 0 {
                let frames = Int(buffer.frameLength)
                let chCount = Int(buffer.format.channelCount)
                var rawPeak: Float = 0
                var strongest = 0
                for c in 0..<chCount {
                    let ptr = data[c]
                    var channelPeak: Float = 0
                    vDSP_maxmgv(ptr, 1, &channelPeak, vDSP_Length(frames))
                    if channelPeak > rawPeak { rawPeak = channelPeak; strongest = c }
                }
                os_unfair_lock_lock(&self.lock)
                self.hardwarePeak = rawPeak
                self.strongestInput = strongest
                self.receivedBuffers += 1
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

    /// The channel's level before gain (straight from the device), 0.0 to 1.0.
    public func sourcePeak(for channelID: UUID) -> Float {
        os_unfair_lock_lock(&lock)
        let feeder = feederMap[channelID]
        os_unfair_lock_unlock(&lock)
        return feeder?.sourcePeak ?? 0
    }

    /// Changes a running channel's gain immediately, and keeps it for restarts.
    public func setGain(dB: Double, for channelID: UUID) {
        os_unfair_lock_lock(&lock)
        let feeder = feederMap[channelID]
        os_unfair_lock_unlock(&lock)
        feeder?.setGain(dB: dB)
        if let i = currentTargets.firstIndex(where: { $0.id == channelID }) {
            currentTargets[i].gainDB = dB
        }
    }

    /// Reads the overall peak volume across all active channels.
    public func overallPeak() -> Float {
        os_unfair_lock_lock(&lock)
        let peak = hardwarePeak
        os_unfair_lock_unlock(&lock)
        return peak
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
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.engine = nil
        }
        currentTargets = []
        currentDevice = nil

        os_unfair_lock_lock(&lock)
        self.feederMap.removeAll()
        self.hardwarePeak = 0
        self.receivedBuffers = 0
        self.strongestInput = 0
        os_unfair_lock_unlock(&lock)
    }
}
