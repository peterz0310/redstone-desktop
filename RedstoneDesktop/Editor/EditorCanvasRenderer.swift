import SpriteKit

/// Reuses the action-free world renderer; overlays only select/preview feedback.
@MainActor
final class EditorCanvasRenderer {
    private(set) var scene: DesktopScene?
    private var lastWorld: World?
    private var lastOccupancy: DesktopOccupancySnapshot?
    private var lastProjection: EditorFinderProjection?
    private var lastPower: [WorldCoordinate: PowerLevel] = [:]
    private var lastLevers: Set<WorldCoordinate> = []
    private let terrainRenderer = TerrainChunkRenderer()
    private let ghostRenderer = CircuitRenderer()

    func update(appState: AppState, editor: EditorSession, size: CGSize) -> DesktopScene? {
        guard let mapper = editor.mapper(size: size) else { return nil }
        if scene == nil {
            let screen = ScreenDescriptor(id: "editor", frame: CGRect(origin: .zero, size: size), backingScale: 1)
            scene = DesktopScene(screen: screen, mapper: mapper, terrainRenderer: terrainRenderer)
            lastWorld = nil
            lastOccupancy = nil
            lastProjection = nil
        } else if scene?.mapper.camera != editor.camera || scene?.size != size {
            let screen = ScreenDescriptor(id: "editor", frame: CGRect(origin: .zero, size: size), backingScale: 1)
            scene?.updateViewport(screen: screen, mapper: mapper)
            lastProjection = nil
        }
        guard let scene else { return nil }
        appState.editorDiagnosticScene = scene
        scene.setDiagnosticOverlays(appState.diagnosticOverlays)
        scene.setAssets(appState.assets)
        ghostRenderer.textures.assets = appState.assets
        let world = editor.browsingWorld(appState)
        let power: [WorldCoordinate: PowerLevel] = editor.isPreviewing(appState) || !appState.isEditingActiveWorld ? [:] : appState.simulator.power
        let levers: Set<WorldCoordinate> = editor.isPreviewing(appState) ? [] : appState.editorLeverPositions
        if lastWorld != world || lastPower != power || lastLevers != levers {
            scene.updateWorld(world, poweredTiles: Set(power.keys), leverPositions: levers, powerLevels: power)
            lastWorld = world
            lastPower = power
            lastLevers = levers
        }
        let projection = editor.finderProjection(appState)
        scene.updateFinderMarkers(projection.markers.map { marker in
            FinderItemMapping(item: marker.item, screenCenter: mapper.screenPoint(fromWorld: marker.worldCenter), tile: marker.tile)
        })
        let occupancy = projection.occupancy
        if lastOccupancy != occupancy {
            scene.updateOccupancy(occupancy)
            lastOccupancy = occupancy
        }
        let areas = overlay("editor-desktop-viewport", in: scene)
        areas.removeAllChildren()
        if let display = appState.desktopScreen {
            for (name, camera, color) in [("current-desktop", appState.isEditingActiveWorld ? appState.desktopCamera : appState.selectedAreaCamera, NSColor.systemBlue),
                                          ("chosen-desktop", editor.proposedDesktopCamera(appState), NSColor.systemOrange)] {
                if name == "current-desktop" && editor.isPreviewing(appState) { continue }
                if let rect = mapper.desktopViewportRect(camera: camera, displaySize: display.frame.size, on: scene.screen) {
                    let node = SKShapeNode(rect: rect)
                    node.name = name; node.strokeColor = color; node.fillColor = .clear; node.lineWidth = 3
                    areas.addChild(node)
                    let title = name == "current-desktop" ? (appState.isEditingActiveWorld ? "Desktop area" : "Saved area") : "Current view"
                    let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
                    label.name = name + "-label"; label.text = title; label.fontSize = 12; label.fontColor = color
                    label.horizontalAlignmentMode = .left; label.verticalAlignmentMode = .top
                    label.position = CGPoint(x: max(8, rect.minX + 8), y: min(scene.size.height - 60, rect.maxY - 8) - (name == "chosen-desktop" ? 20 : 0))
                    let background = SKShapeNode(rect: CGRect(x: -4, y: -18, width: label.frame.width + 8, height: 22), cornerRadius: 4)
                    background.fillColor = NSColor.black.withAlphaComponent(0.8); background.strokeColor = .clear; background.zPosition = -1
                    label.addChild(background); areas.addChild(label)
                }
            }
        }
        if projection != lastProjection {
            // Hidden ghosts add no scene layer; visible geometry is bounded by the canvas.
            scene.childNode(withName: "editor-finder")?.removeFromParent()
            if appState.editorFinderItemsVisible && !editor.isPreviewing(appState) {
                let layer = overlay("editor-finder", in: scene)
                layer.zPosition = 4
                for marker in projection.markers {
                    let point = mapper.screenPoint(fromWorld: marker.worldCenter)
                    guard mapper.canvasFrame.contains(point) else { continue }
                    let node = SKShapeNode(circleOfRadius: 10)
                    node.name = "finder:\(marker.item.id)"
                    node.position = mapper.scenePoint(fromScreen: point, on: scene.screen)
                    if case .ambiguous = projection.occupancy.state(at: marker.tile) { node.strokeColor = .systemRed }
                    else { node.strokeColor = .systemTeal }
                    node.fillColor = node.strokeColor.withAlphaComponent(0.25)
                    node.lineWidth = 2
                    let label = SKLabelNode(text: String(marker.item.displayName.prefix(32)))
                    label.fontName = "Menlo"; label.fontSize = 10; label.fontColor = .white
                    label.position = CGPoint(x: 0, y: 14)
                    node.addChild(label)
                    layer.addChild(node)
                }
            }
            lastProjection = projection
        }
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
                preview.addChild(outline(tile, color: (result.isAllowed && !editor.isPreviewing(appState) && !appState.isEditorConfigurationLocked) ? .systemGreen : .systemRed, mapper: mapper, scene: scene))
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
