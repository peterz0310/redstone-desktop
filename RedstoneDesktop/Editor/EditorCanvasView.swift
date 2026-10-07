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
        editor?.hover(at: convert(event.locationInWindow, from: nil), size: bounds.size)
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
        draggingPan = editor?.tool == .pan
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if draggingPan, let last = lastDragPoint {
            editor?.pan(by: CGSize(width: point.x - last.x, height: point.y - last.y), size: bounds.size)
        } else { editor?.hover(at: point, size: bounds.size) }
        lastDragPoint = point
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil; lastDragPoint = nil; draggingPan = false }
        let point = convert(event.locationInWindow, from: nil)
        if !draggingPan, let downPoint, hypot(point.x - downPoint.x, point.y - downPoint.y) < 4,
           let editor, let appState { editor.click(at: point, size: bounds.size, appState: appState) }
        editor?.hover(at: point, size: bounds.size)
        refresh()
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.scrollingDeltaY != 0 else { return }
        editor?.zoom(by: exp(Double(event.scrollingDeltaY) * 0.02),
                     anchor: convert(event.locationInWindow, from: nil), size: bounds.size)
        refresh()
    }
}
