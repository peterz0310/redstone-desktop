import SwiftUI
import SpriteKit

struct EditorCanvasView: NSViewRepresentable {
    @ObservedObject var appState: AppState
    @ObservedObject var editor: EditorSession

    func makeNSView(context: Context) -> EditorCanvasSurface {
        let view = EditorCanvasSurface()
        view.preferredFramesPerSecond = 30
        view.appState = appState
        view.editor = editor
        return view
    }

    func updateNSView(_ view: EditorCanvasSurface, context: Context) {
        view.appState = appState
        view.editor = editor
        view.refresh()
    }
}

/// Local editor input only. Desktop global monitoring remains unchanged.
@MainActor
final class EditorCanvasSurface: SKView {
    var appState: AppState?
    var editor: EditorSession?
    let renderer = EditorCanvasRenderer()
    private var tracking: NSTrackingArea?
    private var downPoint: CGPoint?
    private var lastDragPoint: CGPoint?
    private var draggingPan = false
    private var navigating = false
    private var selectingRegion = false
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        editor?.viewport = bounds.size
        refresh()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
    }

    func refresh() {
        guard let appState, let editor, let next = renderer.update(appState: appState, editor: editor, size: bounds.size) else { return }
        if scene !== next { presentScene(next) }
        let metrics = next.terrainMetrics
        if editor.terrainMetrics != metrics {
            Task { @MainActor [weak editor] in
                if editor?.terrainMetrics != metrics { editor?.terrainMetrics = metrics }
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        editor?.hover(at: convert(event.locationInWindow, from: nil), size: bounds.size, appState: appState)
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        editor?.hoveredTile = nil
        refresh()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        downPoint = convert(event.locationInWindow, from: nil)
        lastDragPoint = downPoint
        navigating = editor?.tool == .select && editor?.pendingPlacement == nil
        selectingRegion = editor?.pendingPlacement == nil && (editor?.tool == .region || event.modifierFlags.contains(.shift)) && editor?.circuitTest == nil
        if selectingRegion, let downPoint { editor?.beginRegion(at: downPoint, size: bounds.size, additive: event.modifierFlags.contains(.shift)) }
        draggingPan = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if selectingRegion, let downPoint, draggingPan || hypot(point.x - downPoint.x, point.y - downPoint.y) >= 4 {
            if let appState { editor?.dragRegion(to: point, size: bounds.size, appState: appState) }
            draggingPan = true
        } else if navigating, let downPoint,
           draggingPan || hypot(point.x - downPoint.x, point.y - downPoint.y) >= 4,
           let last = draggingPan ? lastDragPoint : downPoint {
            editor?.pan(by: CGSize(width: point.x - last.x, height: point.y - last.y), size: bounds.size)
            draggingPan = true
        } else { editor?.hover(at: point, size: bounds.size, appState: appState) }
        lastDragPoint = point
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        defer { editor?.endRegion(); downPoint = nil; lastDragPoint = nil; draggingPan = false; navigating = false; selectingRegion = false }
        let point = convert(event.locationInWindow, from: nil)
        if !draggingPan, let downPoint, hypot(point.x - downPoint.x, point.y - downPoint.y) < 4,
           let editor, let appState { editor.click(at: point, size: bounds.size, appState: appState, additive: event.modifierFlags.contains(.shift)) }
        editor?.hover(at: point, size: bounds.size, appState: appState)
        refresh()
    }

    override func keyDown(with event: NSEvent) {
        if handleShortcut(event) { refresh() } else { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        if handleShortcut(event) { refresh(); return true }
        return super.performKeyEquivalent(with: event)
    }
    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard let editor, let appState else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option) {
            switch key {
            case "z": editor.undo(appState, redo: modifiers.contains(.shift))
            case "c": editor.copyToClipboard(appState)
            case "v": editor.pasteFromClipboard(appState)
            case "a": editor.selectAll(appState)
            default: return false
            }
            return true
        }
        guard modifiers.isEmpty else { return false }
        switch key {
        case "\u{1b}": editor.clearSelection()
        case "\u{7f}", "\u{8}": editor.deleteSelection(appState)
        case "r": if editor.pendingPlacement != nil { editor.rotatePending() } else { editor.rotateSelection(appState) }
        default: return false
        }
        return true
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.scrollingDeltaY != 0 else { return }
        editor?.zoom(by: exp(Double(event.scrollingDeltaY) * 0.02),
                     anchor: convert(event.locationInWindow, from: nil), size: bounds.size)
        refresh()
    }

    override func magnify(with event: NSEvent) {
        editor?.magnify(by: Double(event.magnification), anchor: convert(event.locationInWindow, from: nil), size: bounds.size)
        refresh()
    }
}
