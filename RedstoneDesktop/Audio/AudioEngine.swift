import AVFoundation
import Combine

@MainActor
protocol SoundPlaying {
    var status: String { get }
    func configure(_ settings: AudioSettings)
    func play(_ id: SoundID, pan: Float)
    func stop()
    func replaceSoundOverrides(_ samples: [SoundID: [Float]])
}

extension SoundPlaying {
    func replaceSoundOverrides(_ samples: [SoundID: [Float]]) {}
    func play(_ id: SoundID) { play(id, pan: 0) }
}

@MainActor
final class SilentSoundPlayer: SoundPlaying {
    var status: String { "Audio disabled in test host." }
    func configure(_ settings: AudioSettings) {}
    func play(_ id: SoundID, pan: Float) {}
    func stop() {}
}

/// One persistent graph, cached original PCM buffers and eight bounded overlapping voices.
/// It never connects to the input node or requests microphone access.
@MainActor
final class AudioEngine: SoundPlaying {
    private let engine = AVAudioEngine()
    private let voices = (0..<8).map { _ in AVAudioPlayerNode() }
    private var buffers: [SoundID: AVAudioPCMBuffer] = [:]
    private var builtInBuffers: [SoundID: AVAudioPCMBuffer] = [:]
    private var idleStopTask: Task<Void, Never>?
    private let idleDelay: Duration
    var isRunning: Bool { engine.isRunning }
    private var nextVoice = 0
    private var settings = AudioSettings()
    private var configurationObserver: AnyCancellable?
    private(set) var status = "Sound effects ready."

    init(offline: Bool = false, idleDelay: Duration = .seconds(2)) throws {
        self.idleDelay = idleDelay
        let mono = AVAudioFormat(standardFormatWithSampleRate: BuiltInSounds.sampleRate, channels: 1)!
        for voice in voices {
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: mono)
        }
        for id in SoundID.allCases {
            let samples = BuiltInSounds.samples(for: id)
            let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(samples.count))!
            buffer.frameLength = buffer.frameCapacity
            for (index, sample) in samples.enumerated() { buffer.floatChannelData![0][index] = sample }
            buffers[id] = buffer
        }
        builtInBuffers = buffers
        if offline {
            let stereo = AVAudioFormat(standardFormatWithSampleRate: BuiltInSounds.sampleRate, channels: 2)!
            try engine.enableManualRenderingMode(.offline, format: stereo, maximumFrameCount: 4096)
        }
        engine.mainMixerNode.outputVolume = settings.gain
        configurationObserver = NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange, object: engine)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stop()
                    self?.status = "Audio device changed; previous sounds cleared. Next effect retries playback."
                }
            }
    }

    func replaceSoundOverrides(_ samples: [SoundID: [Float]]) {
        stop()
        buffers = builtInBuffers
        let mono = AVAudioFormat(standardFormatWithSampleRate: BuiltInSounds.sampleRate, channels: 1)!
        for (id, values) in samples where !values.isEmpty && values.count <= 88200 {
            guard values.allSatisfy({ $0.isFinite && abs($0) <= 0.11 }),
                  let buffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(values.count)) else { continue }
            buffer.frameLength = buffer.frameCapacity
            for (index, value) in values.enumerated() { buffer.floatChannelData![0][index] = value }
            buffers[id] = buffer
        }
    }

    func configure(_ settings: AudioSettings) {
        self.settings = settings
        engine.mainMixerNode.outputVolume = settings.gain
        if settings.gain == 0 { stop() }
    }

    func play(_ id: SoundID, pan: Float) {
        guard settings.gain > 0, let buffer = buffers[id] else { return }
        do {
            if !engine.isRunning { try engine.start() }
            let voice = voices[nextVoice]
            nextVoice = (nextVoice + 1) % voices.count
            voice.stop() // At saturation recycle the oldest voice; never queue an unbounded tail.
            voice.pan = pan.isFinite ? min(1, max(-1, pan)) : 0
            voice.scheduleBuffer(buffer, at: nil)
            voice.play()
            status = "Sound effects ready."
            idleStopTask?.cancel()
            idleStopTask = Task { @MainActor [weak self, idleDelay] in
                do { try await Task.sleep(for: idleDelay) } catch { return }
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            stop()
            status = "Audio unavailable: \(error.localizedDescription). Next effect will retry."
        }
    }

    func stop() {
        idleStopTask?.cancel(); idleStopTask = nil
        for voice in voices { voice.stop() }
        engine.stop()
        nextVoice = 0
    }

    /// Offline verification exercises the actual audio graph without speaker output.
    func renderOffline(frames: AVAudioFrameCount) throws -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: frames)!
        if !engine.isRunning { try engine.start() }
        guard try engine.renderOffline(frames, to: buffer) == .success else {
            throw NSError(domain: "RedstoneDesktop.Audio", code: 1)
        }
        return buffer
    }
}
