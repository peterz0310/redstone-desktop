import AVFoundation
import Combine

@MainActor
protocol SoundPlaying {
    var status: String { get }
    func configure(_ settings: AudioSettings)
    func play(_ id: SoundID)
    func stop()
}

@MainActor
final class SilentSoundPlayer: SoundPlaying {
    var status: String { "Audio disabled in test host." }
    func configure(_ settings: AudioSettings) {}
    func play(_ id: SoundID) {}
    func stop() {}
}

/// One persistent graph, cached original PCM buffers and eight bounded overlapping voices.
/// It never connects to the input node or requests microphone access.
@MainActor
final class AudioEngine: SoundPlaying {
    private let engine = AVAudioEngine()
    private let voices = (0..<8).map { _ in AVAudioPlayerNode() }
    private var buffers: [SoundID: AVAudioPCMBuffer] = [:]
    private var nextVoice = 0
    private var settings = AudioSettings()
    private var configurationObserver: AnyCancellable?
    private(set) var status = "Sound effects ready."

    init(offline: Bool = false) throws {
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

    func configure(_ settings: AudioSettings) {
        self.settings = settings
        engine.mainMixerNode.outputVolume = settings.gain
        if settings.gain == 0 { stop() }
    }

    func play(_ id: SoundID) {
        guard settings.gain > 0, let buffer = buffers[id] else { return }
        do {
            if !engine.isRunning { try engine.start() }
            let voice = voices[nextVoice]
            nextVoice = (nextVoice + 1) % voices.count
            voice.stop() // At saturation recycle the oldest voice; never queue an unbounded tail.
            voice.scheduleBuffer(buffer, at: nil)
            voice.play()
            status = "Sound effects ready."
        } catch {
            stop()
            status = "Audio unavailable: \(error.localizedDescription). Next effect will retry."
        }
    }

    func stop() {
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
