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
    @Published var seedText = "2026"
    @Published var newWorldName = "New World"
    @Published private(set) var previewGeneration: WorldGenerationSettings?
    @Published var terrainMetrics = TerrainRenderMetrics()
    var viewport = CGSize(width: 800, height: 600)

    func isPreviewing(_ appState: AppState) -> Bool {
        previewGeneration != nil
    }

    func browsingWorld(_ appState: AppState) -> World {
        if let previewGeneration { return World(generation: previewGeneration) }
        return appState.editorWorld
    }

    func proposedDesktopCamera(_ appState: AppState) -> CameraState {
        CameraState(worldOrigin: camera.worldOrigin, pointsPerTile: appState.selectedAreaCamera.pointsPerTile)
    }

    @discardableResult
    func previewSeed() -> Bool {
        let text = seedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let seed = UInt64(text) else {
            status = "Enter a whole seed from 0 to 18446744073709551615."
            return false
        }
        previewGeneration = WorldGenerationSettings(seed: seed)
        seedText = String(seed)
        hoveredTile = nil
        status = "Previewing an empty world with seed \(seed). Create World saves it; existing worlds keep their seeds."
        return true
    }

    func randomSeed() { seedText = String(UInt64.random(in: .min ... .max)); previewSeed() }

    func cancelPreview(_ appState: AppState) {
        previewGeneration = nil
        seedText = String(appState.selectedDocument.generation.seed)
        status = "Seed preview cancelled."
    }

    @discardableResult
    func useThisArea(_ appState: AppState) -> Bool {
        guard !isPreviewing(appState) else { status = "Create or cancel the new-world preview before choosing a desktop area."; return false }
        guard appState.useDesktopArea(camera: proposedDesktopCamera(appState), generation: appState.selectedDocument.generation) else {
            status = appState.areaStatus
            return false
        }
        status = appState.areaStatus
        return true
    }

    @discardableResult
    func createWorld(_ appState: AppState) -> Bool {
        guard previewSeed(), let generation = previewGeneration else { return false }
        guard appState.createWorld(name: newWorldName, generation: generation) else {
            status = appState.libraryStatus
            return false
        }
        syncSelectedWorld(appState)
        status = appState.libraryStatus
        return true
    }

    @discardableResult
    func selectWorld(_ id: UUID, appState: AppState) -> Bool {
        guard appState.selectWorld(id) else { status = appState.libraryStatus; return false }
        syncSelectedWorld(appState)
        return true
    }

    func syncSelectedWorld(_ appState: AppState) {
        previewGeneration = nil
        seedText = String(appState.selectedDocument.generation.seed)
        camera = CameraState(worldOrigin: appState.selectedAreaCamera.worldOrigin, pointsPerTile: camera.pointsPerTile)
        hoveredTile = nil
        selectedTile = nil
    }

    func showDesktopArea(_ appState: AppState) {
        if !appState.isEditingActiveWorld {
            guard appState.selectWorld(appState.activeWorldID) else { status = appState.libraryStatus; return }
        }
        syncSelectedWorld(appState)
        camera = CameraState(worldOrigin: appState.desktopCamera.worldOrigin, pointsPerTile: camera.pointsPerTile)
    }

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
        if tool.editsWorld && isPreviewing(appState) {
            status = "Create the new world or cancel its preview before editing the circuit."
            return
        }
        selectedTile = tile
        if tool == .select {
            if let component = browsingWorld(appState).circuit.components[tile], component.kind == .repeater {
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
