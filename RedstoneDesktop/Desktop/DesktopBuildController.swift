import AppKit
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
        surface.click = { [weak appState, weak session] point, erase in
            guard let session else { return }
            appState?.buildClick(at: point, erase: erase, sessionID: session.id)
        }
        surface.rotate = { [weak appState] in appState?.rotateBuildRepeater() }
        surface.changeDelay = { [weak appState, weak session] in
            guard let session else { return }
            appState?.setBuildRepeaterDelay(RepeaterDelay(rawValue: session.delay.rawValue % 4 + 1)!)
        }
        surface.exit = exit

        palette = NSPanel(contentRect: CGRect(x: screen.frame.midX - 330, y: screen.frame.maxY - 220, width: 660, height: 160),
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
    var click: ((CGPoint, Bool) -> Void)?
    var rotate: (() -> Void)?
    var changeDelay: (() -> Void)?
    var exit: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var hoveredTile: WorldCoordinate?
    private let outline = SKShapeNode()
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
        presentScene(scene)
        preferredFramesPerSecond = 30
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

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
        hoveredTile = session.tile(at: point(event))
        refreshHighlight()
    }

    override func mouseExited(with event: NSEvent) { hoveredTile = nil; refreshHighlight() }

    func refreshHighlight() {
        if let tile = hoveredTile ?? session.selectedTile {
            outline.path = CGPath(rect: session.mapper.sceneRect(forTile: tile, on: screen).insetBy(dx: 2, dy: 2), transform: nil)
        } else { outline.path = nil }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        click?(point(event), false)
        refreshHighlight()
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        click?(point(event), true)
        refreshHighlight()
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.scrollingDeltaY != 0 else { return }
        session.cycleTool(forward: event.scrollingDeltaY < 0)
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "\u{1b}": exit?()
        case "r": rotate?()
        case "d": changeDelay?()
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
                Label("BUILD MODE", systemImage: "hammer.fill").font(.headline).foregroundStyle(.orange)
                Text(session.title).lineLimit(1)
                Spacer()
                Button("Exit Build Mode") { appState.exitDesktopBuildMode() }.keyboardShortcut(.cancelAction)
            }
            Picker("Tool", selection: $session.tool) {
                ForEach(Array(DesktopBuildSession.Tool.allCases.enumerated()), id: \.element) { index, tool in
                    Text("\(index + 1) \(tool.rawValue)").tag(tool)
                }
            }.pickerStyle(.segmented)
            HStack {
                Button("Rotate (R)") { appState.rotateBuildRepeater() }
                Text(session.direction.rawValue.capitalized).frame(width: 45)
                Picker("Delay", selection: Binding(get: { session.delay }, set: { appState.setBuildRepeaterDelay($0) })) {
                    ForEach(RepeaterDelay.allCases, id: \.self) { Text("\($0.rawValue) tick\($0 == .one ? "" : "s")").tag($0) }
                }.frame(width: 160)
                Text("Selected repeater or next placement").font(.caption).foregroundStyle(.secondary)
            }
            Text(session.status).font(.caption).lineLimit(2)
        }.padding(12).frame(width: 636)
    }
}
