import AppKit
import SpriteKit
import ImageIO
import UniformTypeIdentifiers
import Darwin

private struct ProfileLibrary: WorldLibraryStoring {
    func load() throws -> WorldLibraryDocument? { WorldLibraryDocument() }
    func save(_ document: WorldLibraryDocument) throws {}
}

@main struct PolishProfile {
    static func usage() -> (Double, Double) {
        var value = rusage(); getrusage(RUSAGE_SELF, &value)
        let cpu = Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec) + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
        return (cpu, Double(value.ru_maxrss) / 1_048_576)
    }
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let app = AppState(libraryStore: ProfileLibrary())
        defer { app.shutdown() }
        let editor = EditorSession(), renderer = EditorCanvasRenderer(), size = CGSize(width: 960, height: 640)
        _ = renderer.update(appState: app, editor: editor, size: size)
        let baseline = usage(), start = CFAbsoluteTimeGetCurrent()
        var worst = 0.0, maximumChunks = 0
        for _ in 0..<160 {
            editor.pan(by: CGSize(width: -256, height: 0), size: size)
            let t = CFAbsoluteTimeGetCurrent()
            autoreleasepool {
                let scene = renderer.update(appState: app, editor: editor, size: size)!
                worst = max(worst, (CFAbsoluteTimeGetCurrent() - t) * 1000)
                maximumChunks = max(maximumChunks, scene.terrainMetrics.retainedChunks)
            }
        }
        print("pan_steps=160 total_ms=\((CFAbsoluteTimeGetCurrent()-start)*1000) worst_step_ms=\(worst) max_retained_chunks=\(maximumChunks) peak_rss_before_mb=\(baseline.1) peak_rss_after_mb=\(usage().1)")
        let beforeIdle = usage().0, idleStart = CFAbsoluteTimeGetCurrent()
        try await Task.sleep(for: .seconds(4))
        print("stopped_idle_cpu_percent=\((usage().0-beforeIdle)/(CFAbsoluteTimeGetCurrent()-idleStart)*100)")
        var world = World()
        for x in 0..<9 { for y in 0..<3 { world.tiles[WorldCoordinate(x: x, y: y)] = Tile(terrain: .grass) } }
        for x in 1...7 {
            let kind: CircuitComponentKind = x == 1 ? .button : x == 5 ? .repeater : x == 7 ? .output : .dust
            world.circuit.components[WorldCoordinate(x: x, y: 1)] = CircuitComponent(kind: kind, direction: .east)
        }
        let screen = ScreenDescriptor(id: "synthetic-demo", frame: CGRect(x: 0, y: 0, width: 576, height: 192), backingScale: 1)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        let scene = DesktopScene(screen: screen, mapper: mapper)
        let view = SKView(frame: screen.frame); view.presentScene(scene)
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view // snapshot only; never ordered on screen
        var simulator = CircuitSimulator(world: world.circuit)
        let demoURL = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let destination = CGImageDestinationCreateWithURL(demoURL as CFURL, UTType.gif.identifier as CFString, 40, nil) else { throw MaintenanceError(message: "GIF destination failed") }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<40 {
            if frame == 5 || frame == 25 { simulator.pressButton(at: WorldCoordinate(x: 1, y: 1)) }
            for _ in 0..<4 { _ = simulator.advanceTick() }
            scene.updateWorld(world, poweredTiles: simulator.poweredTiles, powerLevels: simulator.power)
            guard let texture = view.texture(from: scene) else { throw MaintenanceError(message: "Native SpriteKit snapshot failed") }
            CGImageDestinationAddImage(destination, texture.cgImage(), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw MaintenanceError(message: "GIF finalization failed") }
        print("Native SpriteKit synthetic circuit demo: 40 frames, 576x192, original assets, no Finder/actions.")
        // Running pure 20 Hz tick cost, without desktop windows/Finder or speaker output.
        let beforeTicks = usage().0, tickStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<80 { _ = simulator.advanceTick(); try await Task.sleep(for: .milliseconds(50)) }
        print("isolated_20hz_cpu_percent=\((usage().0-beforeTicks)/(CFAbsoluteTimeGetCurrent()-tickStart)*100) peak_rss_final_mb=\(usage().1)")
    }
}
