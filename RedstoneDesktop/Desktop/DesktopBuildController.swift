import AppKit
import Combine
import SpriteKit
import SwiftUI

@MainActor
protocol DesktopBuildPresenting: AnyObject {
    func show()
    func update(world: World, levers: Set<WorldCoordinate>, assets: AssetLibrary)
    func close()
}

private final class BuildInputWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Only the temporary transparent input window sits above Finder icons. The existing
/// SpriteKit world remains below them. Ordinary windows and the Dock stay above input.
@MainActor
final class DesktopBuildController: NSObject, DesktopBuildPresenting, NSWindowDelegate {
    let inputWindow: NSWindow
    let palette: NSPanel
    let renderer: DesktopWindowController
    let surface: DesktopBuildSurface
    private let exit: () -> Void

    init(session: DesktopBuildSession, screen: ScreenDescriptor, appState: AppState) {
        exit = { [weak appState] in appState?.exitDesktopBuildMode() }
        renderer = DesktopWindowController(screen: screen, mapper: session.mapper)
        surface = DesktopBuildSurface(session: session, screen: screen)
        inputWindow = BuildInputWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        inputWindow.title = "Desktop Build Mode Input"
        inputWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        inputWindow.isOpaque = false
        inputWindow.backgroundColor = .clear
        inputWindow.hasShadow = false
        inputWindow.isReleasedWhenClosed = false
        inputWindow.hidesOnDeactivate = true
        inputWindow.collectionBehavior = [.stationary, .ignoresCycle]
        inputWindow.contentView = surface
        inputWindow.acceptsMouseMovedEvents = true
        surface.click = { [weak appState, weak session] point, erase in
            guard let session else { return }
            appState?.buildClick(at: point, erase: erase, sessionID: session.id)
        }
        surface.terrainInput = { [weak appState, weak session] point, phase in
            guard let session else { return }
            appState?.buildTerrain(at: point, phase: phase, sessionID: session.id)
        }
        surface.rotate = { [weak appState] tile in appState?.editHoveredBuildRepeater(at: tile, rotate: true) }
        surface.changeDelay = { [weak appState] tile in appState?.editHoveredBuildRepeater(at: tile, rotate: false) }
        surface.exit = exit

        palette = NSPanel(contentRect: CGRect(x: screen.frame.midX - min(760, screen.frame.width - 32) / 2, y: screen.frame.maxY - 460, width: min(760, screen.frame.width - 32), height: 400),
                          styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        palette.title = "Desktop Build Mode — Circuit stopped"
        palette.level = .floating
        palette.isReleasedWhenClosed = false
        palette.hidesOnDeactivate = true
        palette.contentView = NSHostingView(rootView: DesktopBuildHotbar(session: session, appState: appState))
        super.init()
        palette.delegate = self
    }

    func show() {
        NSApplication.shared.activate()
        renderer.enable()
        inputWindow.makeKeyAndOrderFront(nil)
        inputWindow.makeFirstResponder(surface)
        palette.orderFront(nil)
    }

    func update(world: World, levers: Set<WorldCoordinate>, assets: AssetLibrary) {
        renderer.scene.setAssets(assets)
        renderer.scene.updateWorld(world, poweredTiles: [], leverPositions: levers)
        surface.refreshHighlight()
    }

    func close() {
        // Remove capture before any rendering/palette teardown. Safe to repeat.
        inputWindow.ignoresMouseEvents = true
        inputWindow.orderOut(nil)
        surface.stopFeedback()
        surface.click = nil; surface.rotate = nil; surface.changeDelay = nil; surface.exit = nil
        inputWindow.close()
        palette.delegate = nil
        palette.orderOut(nil)
        palette.close()
        renderer.disable()
        renderer.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        exit()
        return false // exit closes all windows together, without a second close.
    }
}

@MainActor
final class DesktopBuildSurface: SKView {
    let session: DesktopBuildSession
    let screen: ScreenDescriptor
    var terrainInput: ((CGPoint, TerrainStrokePhase) -> Void)?
    var click: ((CGPoint, Bool) -> Void)?
    var rotate: ((WorldCoordinate?) -> Void)?
    var changeDelay: ((WorldCoordinate?) -> Void)?
    var exit: (() -> Void)?
    private var tracking: NSTrackingArea?
    private let outline = SKShapeNode()
    private let boundary = SKShapeNode()
    private var motionObserver: AnyCancellable?
    override var acceptsFirstResponder: Bool { true }

    init(session: DesktopBuildSession, screen: ScreenDescriptor) {
        self.session = session
        self.screen = screen
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        allowsTransparency = true
        let scene = SKScene(size: screen.frame.size)
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        outline.strokeColor = .cyan
        outline.lineWidth = 3
        outline.fillColor = .clear
        scene.addChild(outline)
        boundary.name = "build-mode-boundary"
        boundary.strokeColor = .systemOrange
        boundary.fillColor = .clear
        boundary.lineWidth = 8
        boundary.zPosition = 10
        scene.addChild(boundary)
        presentScene(scene)
        updateBoundaryGeometry()
        setReducedMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        motionObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.setReducedMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
            }
        preferredFramesPerSecond = 30
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        scene?.size = bounds.size
        updateBoundaryGeometry()
    }

    private func updateBoundaryGeometry() {
        boundary.path = CGPath(roundedRect: bounds.insetBy(dx: 5, dy: 5), cornerWidth: 12, cornerHeight: 12, transform: nil)
    }

    func setReducedMotion(_ reduced: Bool) {
        boundary.removeAllActions()
        boundary.alpha = reduced ? 0.7 : 0.5
        guard !reduced else { return }
        let brighten = SKAction.fadeAlpha(to: 0.9, duration: 1.4)
        let dim = SKAction.fadeAlpha(to: 0.5, duration: 1.4)
        brighten.timingMode = .easeInEaseOut
        dim.timingMode = .easeInEaseOut
        boundary.run(.repeatForever(.sequence([brighten, dim])), withKey: "build-pulse")
    }

    func stopFeedback() {
        boundary.removeAllActions()
        motionObserver?.cancel(); motionObserver = nil
        session.hoveredTile = nil; session.terrainStroke = nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        tracking = next
        addTrackingArea(next)
    }

    private func point(_ event: NSEvent) -> CGPoint {
        session.mapper.screenPoint(fromScene: convert(event.locationInWindow, from: nil), on: screen)
    }

    override func mouseMoved(with event: NSEvent) {
        session.hoveredTile = session.tile(at: point(event))
        // Returning to the canvas after a hotbar click makes hover shortcuts usable
        // without clicking (and inadvertently placing) a component first.
        window?.makeKey()
        window?.makeFirstResponder(self)
        refreshHighlight()
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { session.hoveredTile = nil; refreshHighlight() }

    func refreshHighlight() {
        if let tile = session.hoveredTile ?? session.selectedTile {
            var rect = session.mapper.sceneRect(forTile: tile, on: screen)
            if session.tool == .terrain, let cells = try? TerrainEditing.footprint(center: tile, size: session.terrainBrushSize) {
                for cell in cells { rect = rect.union(session.mapper.sceneRect(forTile: cell, on: screen)) }
            }
            outline.strokeColor = session.tool == .terrain ? .systemGreen : .cyan
            outline.path = CGPath(rect: rect.insetBy(dx: 2, dy: 2), transform: nil)
        } else { outline.path = nil }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if session.tool == .terrain { terrainInput?(point(event), .begin) }
        else { click?(point(event), false) }
        refreshHighlight()
    }

    override func mouseDragged(with event: NSEvent) {
        if session.terrainStroke != nil { terrainInput?(point(event), .drag) }
        session.hoveredTile = session.tile(at: point(event)); refreshHighlight()
    }
    override func mouseUp(with event: NSEvent) {
        if session.terrainStroke != nil { terrainInput?(point(event), .end) }
        refreshHighlight()
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if session.tool == .terrain { terrainInput?(point(event), .cancel) }
        else { click?(point(event), true) }
        refreshHighlight()
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.scrollingDeltaY != 0 else { return }
        session.cycleTool(forward: event.scrollingDeltaY < 0)
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "\u{1b}":
            if session.terrainStroke != nil { terrainInput?(point(event), .cancel) } else { exit?() }
        case "0": session.selectTool(number: 10)
        case "r": rotate?(session.hoveredTile)
        case "t", "d": changeDelay?(session.hoveredTile)
        default:
            if let text = event.charactersIgnoringModifiers, let number = Int(text) {
                session.selectTool(number: number)
            } else { super.keyDown(with: event) }
        }
    }
}

private struct DesktopBuildHotbar: View {
    @ObservedObject var session: DesktopBuildSession
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Build on Desktop", systemImage: "hammer.fill").font(.headline).foregroundStyle(.orange)
                Text(session.title).lineLimit(1)
                Spacer()
                Button("Exit Build Mode") { appState.exitDesktopBuildMode() }.keyboardShortcut(.cancelAction)
            }
            ForEach(0..<((DesktopBuildSession.Tool.allCases.count + 4) / 5), id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(Array(DesktopBuildSession.Tool.allCases.enumerated()).filter { $0.offset / 5 == row }, id: \.element) { index, tool in
                        Button { session.tool = tool } label: {
                            Label { Text((index < 10 ? "\(index == 9 ? 0 : index + 1) " : "") + tool.rawValue) } icon: { ToolIcon(name: tool.rawValue) }
                        }.tint(session.tool == tool ? .accentColor : .secondary).help(tool.description)
                    }
                }
            }
            Text(session.tool.description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if session.tool == .terrain {
                TerrainBrushControls(brush: $session.terrainBrush, size: $session.terrainBrushSize)
            } else if let tile = session.selectedTile, let component = appState.desktopWorld.circuit.components[tile], component.kind == .fileSensor {
                FileSensorConfigurationView(filter: component.sensorFilter) { filter in
                    appState.configureBuildFileSensor(at: tile, filter: filter)
                }.id("sensor:\(tile)")
            } else if session.tool == .fileSensor {
                FileSensorConfigurationView(filter: session.sensorFilter) { session.sensorFilter = $0 }
            }
            HStack {
                Button("Rotate") { appState.rotateBuildRepeater() }
                Text(session.direction.rawValue.capitalized).frame(width: 45)
                Picker("Delay", selection: Binding(get: { session.delay }, set: { appState.setBuildRepeaterDelay($0) })) {
                    ForEach(RepeaterDelay.allCases, id: \.self) { Text("\($0.rawValue) tick\($0 == .one ? "" : "s")").tag($0) }
                }.frame(width: 160)
                Text("Hover a component: R rotates · T changes delay").font(.caption).foregroundStyle(.secondary)
            }
            Text(session.status).font(.caption).lineLimit(2)
        }.onChange(of: session.tool) { _, _ in
            appState.buildTerrain(at: .zero, phase: .cancel, sessionID: session.id)
        }.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity)
    }
}
