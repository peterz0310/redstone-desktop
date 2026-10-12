import AVFoundation
import XCTest
@testable import RedstoneDesktop

@MainActor
final class RecordingSoundPlayer: SoundPlaying {
    var status = "Fixture"
    var sounds: [SoundID] = []
    var pans: [Float] = []
    var settings = AudioSettings()
    var stops = 0
    func configure(_ settings: AudioSettings) { self.settings = settings }
    func play(_ id: SoundID, pan: Float) { sounds.append(id); pans.append(pan) }
    func stop() { stops += 1 }
}

final class AudioTests: XCTestCase {
    func testEveryOriginalSoundIsFiniteBoundedDistinctAndFadesToSilence() {
        var fingerprints: Set<[Float]> = []
        for id in SoundID.allCases {
            let samples = BuiltInSounds.samples(for: id)
            XCTAssertTrue((1000...7000).contains(samples.count))
            XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 0.11 })
            XCTAssertEqual(samples.first, 0)
            XCTAssertEqual(samples.last, 0)
            XCTAssertTrue(samples.contains { abs($0) > 0.01 })
            fingerprints.insert(samples)
        }
        XCTAssertEqual(fingerprints.count, SoundID.allCases.count)
    }
    func testAudioSettingsClampAndMuteEffectsIndependently() {
        XCTAssertEqual(AudioSettings(volume: 2).gain, 1)
        XCTAssertEqual(AudioSettings(volume: -1).gain, 0)
        XCTAssertEqual(AudioSettings(volume: .nan).gain, 0)
        XCTAssertEqual(AudioSettings(muted: true).gain, 0)
        XCTAssertEqual(AudioSettings(effectsEnabled: false).gain, 0)
    }
    func testButtonReleaseAndRepeaterEdgesAreSemanticNotPerFrame() {
        var simulator = CircuitSimulator(world: DemoCircuit.makeWorld().circuit)
        simulator.pressButton(at: DemoCircuit.button)
        var release: [WorldCoordinate] = []
        for _ in 0..<30 {
            let before = simulator; simulator.advanceTick()
            release += CircuitSounds.transitions(before: before, after: simulator).filter { $0.0 == .buttonRelease }.map { $0.1 }
        }
        XCTAssertEqual(release, [DemoCircuit.button])
        var world = CircuitWorld()
        let button = WorldCoordinate(x: 0, y: 0), repeater = WorldCoordinate(x: 1, y: 0)
        world.components[button] = CircuitComponent(kind: .button)
        world.components[repeater] = CircuitComponent(kind: .repeater, direction: .east)
        var sim = CircuitSimulator(world: world); sim.pressButton(at: button)
        var ticks = 0
        for _ in 0..<30 {
            let before = sim; sim.advanceTick()
            ticks += CircuitSounds.transitions(before: before, after: sim).filter { $0.0 == .repeaterTick }.count
        }
        XCTAssertEqual(ticks, 2)
    }
    @MainActor
    func testOfflineEngineProducesOverlappingAudioAndMuteClearsIt() throws {
        let engine = try AudioEngine(offline: true)
        defer { engine.stop() }
        engine.configure(AudioSettings(volume: 1))
        engine.play(.buttonPress); engine.play(.leverToggleOn)
        let buffer = try engine.renderOffline(frames: 2048)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        XCTAssertTrue(samples.contains { abs($0) > 0.01 })
        XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) < 1 })
        engine.configure(AudioSettings(muted: true))
        engine.play(.outputActivate)
        let silent = try engine.renderOffline(frames: 2048)
        XCTAssertTrue(Array(UnsafeBufferPointer(start: silent.floatChannelData![0], count: Int(silent.frameLength))).allSatisfy { abs($0) < 0.0001 })
    }
    @MainActor
    func testBackgroundDeviceChangeStopsOfflineGraphAndNextEffectRecovers() async throws {
        let graph = AVAudioEngine()
        let audio = try AudioEngine(offline: true, idleDelay: .seconds(60), engine: graph)
        defer { audio.stop() }
        audio.play(.buttonPress)
        XCTAssertTrue(audio.isRunning)
        let reference = AudioNotificationObject(graph)
        await Task.detached {
            NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: reference.value)
        }.value
        for _ in 0..<100 {
            if audio.status.contains("Audio device changed") { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(audio.status.contains("Audio device changed"))
        XCTAssertFalse(audio.isRunning)
        audio.play(.leverToggleOn)
        let rendered = try audio.renderOffline(frames: 2048)
        XCTAssertTrue(Array(UnsafeBufferPointer(start: rendered.floatChannelData![0], count: Int(rendered.frameLength))).contains { abs($0) > 0.001 })
        XCTAssertEqual(audio.status, "Sound effects ready.")
    }

    @MainActor
    func testPlacementRemovalAndInvalidPlacementPlayOnlyCorrespondingEffects() {
        let player = RecordingSoundPlayer()
        let state = AppState(soundPlayer: player)
        defer { state.shutdown() }
        let tile = WorldCoordinate(x: 20, y: 9)
        XCTAssertTrue(state.placeCircuitComponent(CircuitComponent(kind: .dust), at: tile).isAllowed)
        XCTAssertFalse(state.placeCircuitComponent(CircuitComponent(kind: .dust), at: tile).isAllowed)
        XCTAssertTrue(state.eraseCircuitComponent(at: tile))
        XCTAssertFalse(state.eraseCircuitComponent(at: tile))
        XCTAssertEqual(player.sounds, [.placeCircuit, .invalidPlacement, .removeCircuit])
        state.setAudioSettings(AudioSettings(muted: true))
        state.previewSound(.buttonPress)
        XCTAssertEqual(player.sounds.count, 3)
    }
    @MainActor
    func testAcceptedInputsOutputsAndReleasePlayButRejectedInputIsSilent() async {
        let player = RecordingSoundPlayer()
        let model = FinderDiagnosticsModel(provider: EmptyAudioProvider())
        let screen = ScreenDescriptor(id: "test", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 2)
        let app = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(), finderDiagnostics: model,
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "Fixture") },
            tickScheduler: ManualCircuitTickScheduler(), soundPlayer: player, finderReferenceProviding: { screen })
        defer { app.shutdown() }
        app.toggleDesktopWorld(); app.handleCircuitClick(DemoCircuit.button)
        XCTAssertTrue(player.sounds.isEmpty, "No successful Finder read yet")
        await model.readItems()
        app.handleCircuitClick(DemoCircuit.button); await app.activationTask?.value
        XCTAssertEqual(player.sounds, [.buttonPress])
        for _ in 0..<22 { app.advanceCircuitTick(); await app.activationTask?.value }
        XCTAssertEqual(player.sounds.filter { $0 == .outputActivate }.count, 1)
        XCTAssertEqual(player.sounds.filter { $0 == .buttonRelease }.count, 1)
        app.handleCircuitClick(DemoCircuit.lever); await app.activationTask?.value
        app.handleCircuitClick(DemoCircuit.lever); await app.activationTask?.value
        XCTAssertEqual(Array(player.sounds.suffix(2)), [.leverToggleOn, .leverToggleOff])
    }
    @MainActor
    func testVolumeMutePersistenceDoesNotTouchLibraryOrStartPlayback() throws {
        let suite = "RedstoneDesktopTests.audio.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let player = RecordingSoundPlayer(), app = AppState(preferences: defaults, soundPlayer: player)
        let library = app.library
        app.setAudioSettings(AudioSettings(volume: 0.7, muted: true))
        let restored = AppState(preferences: defaults, soundPlayer: RecordingSoundPlayer())
        defer { app.shutdown(); restored.shutdown() }
        XCTAssertEqual(restored.audioSettings, app.audioSettings)
        XCTAssertEqual(app.library, library)
        XCTAssertTrue(player.sounds.isEmpty)
        XCTAssertFalse(restored.isDesktopWorldEnabled)
    }
}

@MainActor
private final class EmptyAudioProvider: DesktopItemProviding {
    func currentDesktopItems() async throws -> [DesktopItem] { [] }
}

/// Only the immutable notification identity crosses executors; graph operations stay on MainActor.
private final class AudioNotificationObject: @unchecked Sendable {
    let value: AVAudioEngine
    init(_ value: AVAudioEngine) { self.value = value }
}
