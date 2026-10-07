import SpriteKit

/// Reuses the action-free world renderer; overlays only select/preview feedback.
@MainActor
final class EditorCanvasRenderer {
    private(set) var scene: DesktopScene?
    private var lastWorld: World?
    private var lastOccupancy: DesktopOccupancySnapshot?
    private var lastPower: Set<WorldCoordinate> = []
    private let terrainRenderer = TerrainChunkRenderer()
    private let ghostRenderer = CircuitRenderer()

    func update(appState: AppState, editor: EditorSession, size: CGSize) -> DesktopScene? {
        guard let mapper = editor.mapper(size: size) else { return nil }
        if scene?.mapper.camera != editor.camera || scene?.size != size {
            let screen = ScreenDescriptor(id: "editor", frame: CGRect(origin: .zero, size: size), backingScale: 1)
            scene = DesktopScene(screen: screen, mapper: mapper, terrainRenderer: terrainRenderer)
            lastWorld = nil
            lastOccupancy = nil
        }
        guard let scene else { return nil }
        let world = editor.browsingWorld(appState)
        let power: Set<WorldCoordinate> = editor.isPreviewing(appState) ? [] : appState.editorPoweredTiles
        if lastWorld != world || lastPower != power {
            scene.updateWorld(world, poweredTiles: power)
            lastWorld = world
            lastPower = power
        }
        // Use already-resolved world occupancy; browsing never moves its targets or queries Finder.
        let occupancy = editor.isPreviewing(appState) ? DesktopOccupancySnapshot.unavailable("New world preview") : appState.editorOccupancy
        if lastOccupancy != occupancy {
            scene.updateOccupancy(occupancy)
            lastOccupancy = occupancy
        }
        let areas = overlay("editor-desktop-viewport", in: scene)
        areas.removeAllChildren()
        if let display = appState.desktopScreen {
            for (name, camera, color) in [("current-desktop", appState.desktopCamera, NSColor.systemBlue),
                                          ("chosen-desktop", editor.proposedDesktopCamera(appState), NSColor.systemOrange)] {
                if name == "current-desktop" && (!appState.isEditingActiveWorld || editor.isPreviewing(appState)) { continue }
                if let rect = mapper.desktopViewportRect(camera: camera, displaySize: display.frame.size, on: scene.screen) {
                    let node = SKShapeNode(rect: rect)
                    node.name = name; node.strokeColor = color; node.fillColor = .clear; node.lineWidth = 3
                    areas.addChild(node)
                }
            }
        }
        // Finder icon ghosts and proposed desktop-camera mapping remain a later slice.
        let selection = overlay("editor-selection", in: scene)
        selection.removeAllChildren()
        if let tile = editor.selectedTile {
            selection.addChild(outline(tile, color: .systemBlue, mapper: mapper, scene: scene))
        }
        let preview = overlay("editor-preview", in: scene)
        preview.removeAllChildren()
        if let tile = editor.hoveredTile {
            if let component = editor.proposedComponent {
                let result = PlacementRules().canPlace(component: component, at: tile, in: world)
                let ghost = SKNode()
                ghost.alpha = 0.45
                ghostRenderer.render(CircuitWorld(components: [tile: component]), poweredTiles: [],
                    occupancy: .unavailable("Editor preview"), mapper: mapper, screen: scene.screen,
                    viewport: CGRect(origin: .zero, size: size), into: ghost)
                preview.addChild(ghost)
                preview.addChild(outline(tile, color: (result.isAllowed && !editor.isPreviewing(appState) && !appState.isDesktopWorldEnabled) ? .systemGreen : .systemRed, mapper: mapper, scene: scene))
            } else {
                preview.addChild(outline(tile, color: editor.tool == .erase ? .systemOrange : .white, mapper: mapper, scene: scene))
            }
        }
        return scene
    }

    private func overlay(_ name: String, in scene: SKScene) -> SKNode {
        if let node = scene.childNode(withName: name) { return node }
        let node = SKNode()
        node.name = name
        node.zPosition = name == "editor-selection" ? 6 : (name == "editor-desktop-viewport" ? 3.5 : 5)
        scene.addChild(node)
        return node
    }

    private func outline(_ tile: WorldCoordinate, color: NSColor, mapper: CoordinateMapper, scene: DesktopScene) -> SKShapeNode {
        let node = SKShapeNode(rect: mapper.sceneRect(forTile: tile, on: scene.screen).insetBy(dx: 1, dy: 1))
        node.strokeColor = color
        node.fillColor = color.withAlphaComponent(0.15)
        node.lineWidth = 2
        return node
    }
}
