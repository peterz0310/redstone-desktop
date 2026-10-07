import Combine
import Foundation

/// Editor interaction state is separate from the desktop camera and simulation.
@MainActor
final class EditorSession: ObservableObject {
    enum Tool: String, CaseIterable {
        case select = "Select", pan = "Pan", dust = "Dust", button = "Button"
        case lever = "Lever", repeater = "Repeater", output = "Output", erase = "Erase"

        var componentKind: CircuitComponentKind? {
            switch self {
            case .dust: return .dust
            case .button: return .button
            case .lever: return .lever
            case .repeater: return .repeater
            case .output: return .output
            case .select, .pan, .erase: return nil
            }
        }
        var editsWorld: Bool { componentKind != nil || self == .erase }
    }

    @Published private(set) var camera = CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 40)
    @Published var tool = Tool.select
    @Published var direction = Direction.east
    @Published var delay = RepeaterDelay.one
    @Published var selectedTile: WorldCoordinate?
    @Published var hoveredTile: WorldCoordinate?
    @Published private(set) var status = "Select a tool. Drag with Pan; use +/− or scroll to zoom."
    var viewport = CGSize(width: 800, height: 600)

    var proposedComponent: CircuitComponent? {
        tool.componentKind.map { CircuitComponent(kind: $0, direction: direction, repeaterDelay: delay) }
    }

    func mapper(size: CGSize) -> CoordinateMapper? {
        try? CoordinateMapper(canvasFrame: CGRect(origin: .zero, size: size), camera: camera)
    }

    func hover(at point: CGPoint, size: CGSize) {
        guard let mapper = mapper(size: size), mapper.canvasFrame.contains(point) else { hoveredTile = nil; return }
        hoveredTile = mapper.tile(atScreen: point)
    }

    func click(at point: CGPoint, size: CGSize, appState: AppState) {
        guard tool != .pan, let mapper = mapper(size: size), mapper.canvasFrame.contains(point),
              let tile = mapper.tile(atScreen: point) else { return }
        selectedTile = tile
        if tool == .select {
            if let component = appState.desktopWorld.circuit.components[tile], component.kind == .repeater {
                direction = component.direction
                delay = component.repeaterDelay
            }
            status = "Selected (\(tile.x), \(tile.y))."
        } else if tool == .erase {
            appState.eraseCircuitComponent(at: tile)
            status = appState.developerPlacementStatus
        } else if let component = proposedComponent {
            appState.placeCircuitComponent(component, at: tile)
            status = appState.developerPlacementStatus
        }
    }

    func pan(by delta: CGSize, size: CGSize) {
        guard let mapper = mapper(size: size), let next = mapper.camera(pannedByScreenDelta: delta),
              isRepresentable(next, size: size) else { return }
        camera = next
        hoveredTile = nil
    }

    func zoom(by factor: Double, anchor: CGPoint? = nil, size: CGSize? = nil) {
        guard factor.isFinite, factor > 0 else { return }
        let size = size ?? viewport
        let scale = min(128, max(16, camera.pointsPerTile * factor))
        guard let mapper = mapper(size: size),
              let next = mapper.camera(zoomedTo: scale, aroundScreen: anchor ?? CGPoint(x: size.width / 2, y: size.height / 2)),
              isRepresentable(next, size: size) else { return }
        camera = next
        hoveredTile = nil
    }

    func resetCamera() {
        camera = CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 40)
        hoveredTile = nil
    }

    private func isRepresentable(_ camera: CameraState, size: CGSize) -> Bool {
        guard let mapper = try? CoordinateMapper(canvasFrame: CGRect(origin: .zero, size: size), camera: camera) else { return false }
        return mapper.tile(atScreen: .zero) != nil && mapper.tile(atScreen: CGPoint(x: size.width, y: size.height)) != nil
    }
}
