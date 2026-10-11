import Combine
import Foundation

/// Editor interaction state is separate from the desktop camera and simulation.
@MainActor
final class EditorSession: ObservableObject {
    enum Tool: String, CaseIterable {
        case select = "Move", region = "Select", erase = "Erase", terrain = "Terrain"
        case dust = "Dust", button = "Button"
        case lever = "Lever", repeater = "Repeater", output = "Output", torch = "Torch", pressurePlate = "Plate", fileSensor = "Sensor"

        var componentKind: CircuitComponentKind? {
            switch self {
            case .dust: return .dust
            case .button: return .button
            case .lever: return .lever
            case .pressurePlate: return .pressurePlate
            case .fileSensor: return .fileSensor
            case .torch: return .torch
            case .repeater: return .repeater
            case .output: return .output
            case .select, .region, .erase, .terrain: return nil
            }
        }
        var description: String {
            if let componentKind { return ToolDescriptions.component(componentKind) }
            switch self { case .select: return ToolDescriptions.move; case .region: return ToolDescriptions.select; case .terrain: return ToolDescriptions.terrain; default: return ToolDescriptions.erase }
        }
        var editsWorld: Bool { componentKind != nil || self == .erase || self == .terrain }
    }

    enum SidebarTab: String, CaseIterable { case build = "Build", blueprints = "Blueprints", inspector = "Inspector" }
    @Published var sidebarTab = SidebarTab.build
    @Published var isSavingBlueprint = false
    func selectSidebar(_ tab: SidebarTab) {
        sidebarTab = tab
        if tab == .inspector {
            tool = .select
            cancelPlacement()
            cancelTerrainStroke()
        }
    }
    func requestBlueprintSave() { sidebarTab = .blueprints; isSavingBlueprint = true }
    @Published private(set) var camera = CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 40)
    @Published var tool = Tool.select
    @Published var terrainBrush = TerrainBrush.grass
    @Published var terrainBrushSize = 3
    @Published private(set) var terrainStroke: TerrainStroke?
    func cancelTerrainStroke() { terrainStroke = nil }
    func terrainInput(at point: CGPoint, size: CGSize, phase: TerrainStrokePhase, appState: AppState) {
        guard phase != .cancel else { cancelTerrainStroke(); status = "Terrain stroke cancelled."; return }
        if appState.isEditorConfigurationLocked { cancelTerrainStroke(); status = appState.editorConfigurationLockMessage; return }
        guard circuitTest == nil, !isPreviewing(appState),
              let mapper = mapper(size: size), mapper.canvasFrame.contains(point),
              let tile = mapper.tile(atScreen: point) else { cancelTerrainStroke(); return }
        if phase == .begin { cancelPlacement(); terrainStroke = TerrainStroke(document: appState.selectedDocument, brush: terrainBrush, size: terrainBrushSize) }
        guard var stroke = terrainStroke else { return }
        guard stroke.document == appState.selectedDocument else { cancelTerrainStroke(); status = "World changed. Terrain stroke cancelled."; return }
        do {
            try stroke.extend(to: tile); terrainStroke = stroke
            status = "Preview: \(stroke.plan!.changed.count) tiles; \(stroke.plan!.protected.count) circuit tiles protected. Release to save."
            if phase == .end {
                cancelTerrainStroke()
                _ = appState.applyTerrain(brush: stroke.brush, tiles: stroke.tiles)
                status = appState.developerPlacementStatus
            }
        } catch { cancelTerrainStroke(); status = "Nothing changed: \(error.localizedDescription)" }
    }
    @Published var sensorFilter = FileSensorFilter()
    @Published var direction = Direction.east
    @Published var delay = RepeaterDelay.one
    @Published var selectedTile: WorldCoordinate?
    @Published var hoveredTile: WorldCoordinate?
    @Published private(set) var selectedTiles: Set<WorldCoordinate> = []
    @Published private(set) var regionStart: WorldCoordinate?
    @Published private(set) var regionEnd: WorldCoordinate?
    private var selectionBeforeDrag: Set<WorldCoordinate> = []
    @Published private(set) var clipboard: CircuitBlueprint?
    struct PendingPlacement: Equatable {
        var blueprint: CircuitBlueprint
        let worldID: UUID
        let original: [WorldCoordinate: CircuitComponent]
        var removing: Set<WorldCoordinate> { Set(original.keys) }
    }
    @Published private(set) var pendingPlacement: PendingPlacement?

    func setContextStatus(_ text: String) { status = text }
    func selectContextTile(_ tile: WorldCoordinate, appState: AppState) {
        selectedTile = tile
        if !selectedTiles.contains(tile) { selectedTiles = browsingWorld(appState).circuit.components[tile] == nil ? [] : [tile] }
        if let component = browsingWorld(appState).circuit.components[tile] {
            direction = component.direction; delay = component.repeaterDelay; sensorFilter = component.sensorFilter
        }
    }
    func selection(_ appState: AppState) -> Set<WorldCoordinate> {
        let valid = selectedTiles.filter { appState.editorWorld.circuit.components[$0] != nil }
        if valid.isEmpty, let selectedTile, appState.editorWorld.circuit.components[selectedTile] != nil { return [selectedTile] }
        return valid
    }
    func selectAll(_ appState: AppState) {
        let cells = Set(appState.editorWorld.circuit.components.keys)
        guard cells.count <= CircuitBlueprint.maximumComponents else { status = "Select a smaller group (4096 components maximum)."; return }
        selectedTiles = cells; selectedTile = cells.count == 1 ? cells.first : nil
        status = "Selected \(cells.count) components."
    }
    func beginRegion(at point: CGPoint, size: CGSize, additive: Bool) {
        guard let tile = mapper(size: size)?.tile(atScreen: point) else { return }
        regionStart = tile; regionEnd = tile
        selectionBeforeDrag = additive ? selectedTiles : []
    }
    func dragRegion(to point: CGPoint, size: CGSize, appState: AppState) {
        guard let start = regionStart, let end = mapper(size: size)?.tile(atScreen: point) else { return }
        regionEnd = end
        let found = Set(appState.editorWorld.circuit.components.keys.filter {
            (min(start.x, end.x)...max(start.x, end.x)).contains($0.x) && (min(start.y, end.y)...max(start.y, end.y)).contains($0.y)
        }).union(selectionBeforeDrag)
        guard found.count <= CircuitBlueprint.maximumComponents else { status = "Select a smaller group (4096 components maximum)."; return }
        selectedTiles = found; selectedTile = found.count == 1 ? found.first : nil
        status = "Selected \(found.count) components."
    }
    func endRegion() { regionStart = nil; regionEnd = nil; selectionBeforeDrag = [] }
    func cancelPlacement() { pendingPlacement = nil }
    func clearSelection() { isSavingBlueprint = false; selectedTiles = []; selectedTile = nil; endRegion(); cancelPlacement(); cancelTerrainStroke() }
    private func selectedBlueprint(_ appState: AppState, name: String = "Copied Circuit") throws -> CircuitBlueprint {
        let coordinates = selection(appState)
        return try CircuitBlueprint.capture(name: name, components: appState.editorWorld.circuit.components.filter { coordinates.contains($0.key) }, levers: appState.editorLeverPositions)
    }
    @discardableResult func copySelection(_ appState: AppState) -> Bool {
        do { clipboard = try selectedBlueprint(appState); status = "Copied \(clipboard!.circuit.components.count) components. Choose Paste, then click a destination."; return true }
        catch { status = error.localizedDescription; return false }
    }
    func copyToClipboard(_ appState: AppState) {
        guard copySelection(appState), let clipboard else { return }
        do { try EditorCircuitClipboard.write(clipboard) } catch { status = error.localizedDescription }
    }
    func pasteFromClipboard(_ appState: AppState) {
        do { beginPaste(appState, blueprint: try EditorCircuitClipboard.read()) }
        catch { status = error.localizedDescription }
    }
    @discardableResult func saveBlueprint(_ appState: AppState, name: String) -> Bool {
        do {
            let blueprint = try selectedBlueprint(appState, name: name)
            let result = appState.blueprints.save(blueprint); status = appState.blueprints.status; return result
        } catch { status = error.localizedDescription; return false }
    }
    func beginPaste(_ appState: AppState, blueprint: CircuitBlueprint? = nil) {
        guard circuitTest == nil, !isPreviewing(appState), !appState.isEditorConfigurationLocked else { return }
        guard let source = blueprint ?? clipboard else { status = "Copy a circuit or choose a blueprint first."; return }
        do { try source.validate() } catch { status = error.localizedDescription; return }
        pendingPlacement = PendingPlacement(blueprint: source, worldID: appState.selectedWorldID, original: [:])
        tool = .select; status = "Click a clear destination to place \(source.name). R rotates; Escape cancels."
    }
    func beginMove(_ appState: AppState) {
        guard circuitTest == nil, !isPreviewing(appState), !appState.isEditorConfigurationLocked else { return }
        do {
            let blueprint = try selectedBlueprint(appState)
            let cells = selection(appState)
            pendingPlacement = PendingPlacement(blueprint: blueprint, worldID: appState.selectedWorldID,
                original: appState.editorWorld.circuit.components.filter { cells.contains($0.key) })
            tool = .select; status = "Click a destination to move the selection. R rotates; Escape cancels."
        } catch { status = error.localizedDescription }
    }
    func rotatePending() {
        guard let pending = pendingPlacement else { return }
        do { pendingPlacement?.blueprint = try pending.blueprint.rotatedClockwise() }
        catch { status = error.localizedDescription }
    }
    func placementPreview(at anchor: WorldCoordinate, appState: AppState) -> (CircuitWorld, Bool)? {
        guard let pending = pendingPlacement, pending.worldID == appState.selectedWorldID,
              let (circuit, _) = try? pending.blueprint.positioned(at: anchor) else { return nil }
        return (circuit, (try? BlueprintPlacement.applying(pending.blueprint, at: anchor, to: appState.editorWorld, removing: pending.removing)) != nil)
    }
    @discardableResult private func placePending(at anchor: WorldCoordinate, appState: AppState) -> Bool {
        guard let pending = pendingPlacement, pending.worldID == appState.selectedWorldID,
              circuitTest == nil, !isPreviewing(appState), !appState.isEditorConfigurationLocked else { return false }
        do {
            guard pending.original.allSatisfy({ appState.editorWorld.circuit.components[$0.key] == $0.value }) else {
                throw BlueprintError("The original selection changed. Cancel and select it again.")
            }
            let world = try BlueprintPlacement.applying(pending.blueprint, at: anchor, to: appState.editorWorld, removing: pending.removing)
            let (placed, levers) = try pending.blueprint.positioned(at: anchor)
            let savedLevers = appState.editorLeverPositions.subtracting(pending.removing).union(levers)
            guard appState.replaceEditorCircuit(world.circuit, levers: savedLevers) else { status = appState.developerPlacementStatus; return false }
            selectedTiles = Set(placed.components.keys); selectedTile = selectedTiles.count == 1 ? selectedTiles.first : nil
            pendingPlacement = nil; status = "Placed \(placed.components.count) components. Undo reverses the whole operation."
            return true
        } catch { status = "Nothing changed: \(error.localizedDescription)"; return false }
    }
    func rotateSelection(_ appState: AppState) {
        guard circuitTest == nil, !isPreviewing(appState), !appState.isEditorConfigurationLocked else { return }
        let cells = selection(appState)
        guard let x = cells.map(\.x).min(), let y = cells.map(\.y).min() else { return }
        beginMove(appState)
        guard pendingPlacement != nil else { return }
        rotatePending()
        if !placePending(at: WorldCoordinate(x: x, y: y), appState: appState) { cancelPlacement() }
    }
    func deleteSelection(_ appState: AppState) {
        guard circuitTest == nil, !isPreviewing(appState) else { return }
        let cells = selection(appState); guard !cells.isEmpty else { return }
        var circuit = appState.editorWorld.circuit
        for point in cells { circuit.components.removeValue(forKey: point) }
        if appState.replaceEditorCircuit(circuit) { clearSelection(); status = "Selection erased. Terrain preserved." }
        else { status = appState.developerPlacementStatus }
    }
    func undo(_ appState: AppState, redo: Bool = false) {
        guard circuitTest == nil, !isPreviewing(appState) else { return }
        if appState.undoCircuit(redo: redo) { clearSelection() }
        status = appState.developerPlacementStatus
    }

    @Published private(set) var status = "Move: click to inspect, drag to pan. Pinch or scroll to zoom."
    @Published var seedText = "2026"
    @Published var newWorldName = "New World"
    @Published private(set) var previewGeneration: WorldGenerationSettings?
    @Published var terrainMetrics = TerrainRenderMetrics()
    var viewport = CGSize(width: 800, height: 600)
    @Published private(set) var circuitTest: EditorCircuitTest?
    private let testScheduler: any CircuitTickScheduling

    init(testScheduler: any CircuitTickScheduling = CircuitTickScheduler()) { self.testScheduler = testScheduler }

    func startTesting(_ appState: AppState) {
        guard !isPreviewing(appState), !appState.isMaintenanceLocked else { return }
        stopTesting(); cancelPlacement(); cancelTerrainStroke()
        circuitTest = EditorCircuitTest(worldID: appState.selectedWorldID, circuit: appState.editorWorld.circuit, levers: appState.editorLeverPositions)
        tool = .select
        status = "Test mode: click buttons and levers. Outputs only flash here; files never open."
        scheduleTest(appState)
    }
    func stopTesting() {
        testScheduler.stop(); circuitTest = nil
    }
    func toggleTestPlayback(_ appState: AppState) {
        guard circuitTest != nil else { return }
        circuitTest!.isPlaying.toggle()
        if circuitTest!.isPlaying { scheduleTest(appState) } else { testScheduler.stop() }
    }
    func stepTest(_ appState: AppState) {
        guard circuitTest?.isPlaying == false else { return }
        advanceTest(appState)
    }
    func resetTest(_ appState: AppState) {
        guard let current = circuitTest else { return }
        var fresh = EditorCircuitTest(worldID: current.worldID, circuit: current.source, levers: current.initialLevers)
        fresh.isPlaying = current.isPlaying; circuitTest = fresh
        invalidateTestIfNeeded(appState)
    }
    func invalidateTestIfNeeded(_ appState: AppState) {
        guard let test = circuitTest else { return }
        if test.worldID != appState.selectedWorldID || test.source != appState.editorWorld.circuit || appState.isMaintenanceLocked { stopTesting() }
    }
    private func scheduleTest(_ appState: AppState) {
        testScheduler.start { [weak self, weak appState] in
            guard let self, let appState else { return }
            self.advanceTest(appState)
        }
    }
    private func advanceTest(_ appState: AppState) {
        invalidateTestIfNeeded(appState)
        circuitTest?.advance()
    }
    func displayedPower(at tile: WorldCoordinate, appState: AppState) -> PowerLevel {
        circuitTest?.simulator.power(at: tile) ?? (isPreviewing(appState) ? .off : appState.editorPower(at: tile))
    }


    func isPreviewing(_ appState: AppState) -> Bool {
        previewGeneration != nil
    }

    func browsingWorld(_ appState: AppState) -> World {
        if let previewGeneration { return World(generation: previewGeneration) }
        return terrainStroke?.plan?.world ?? appState.editorWorld
    }

    func proposedDesktopCamera(_ appState: AppState) -> CameraState {
        CameraState(worldOrigin: camera.worldOrigin, pointsPerTile: appState.selectedAreaCamera.pointsPerTile)
    }

    @discardableResult
    func previewSeed() -> Bool {
        stopTesting(); clearSelection()
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

    @Published var areaName = "New Area"

    @discardableResult
    func saveArea(_ appState: AppState) -> Bool {
        guard !isPreviewing(appState) else { status = "Create or cancel the preview before saving an area."; return false }
        let result = appState.saveArea(name: areaName, camera: proposedDesktopCamera(appState))
        status = appState.areaStatus
        if result { fitSavedArea(appState) }
        return result
    }

    @discardableResult
    func updateArea(_ appState: AppState) -> Bool {
        guard !isPreviewing(appState) else { status = "Create or cancel the preview before updating an area."; return false }
        let result = appState.updateSelectedArea(camera: proposedDesktopCamera(appState))
        status = appState.areaStatus
        return result
    }

    @discardableResult
    func activateArea(_ appState: AppState) -> Bool {
        guard !isPreviewing(appState) else { status = "Create or cancel the preview before activating an area."; return false }
        let result = appState.activateSelectedArea()
        status = appState.areaStatus
        return result
    }

    @discardableResult
    func selectArea(_ id: UUID, appState: AppState) -> Bool {
        guard appState.selectArea(id) else { return false }
        syncSelectedWorld(appState)
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
        fitSavedArea(appState)
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
        stopTesting(); clearSelection()
        previewGeneration = nil
        seedText = String(appState.selectedDocument.generation.seed)
        camera = CameraState(worldOrigin: appState.selectedAreaCamera.worldOrigin, pointsPerTile: camera.pointsPerTile)
        hoveredTile = nil
        selectedTile = nil
    }

    func fitSavedArea(_ appState: AppState) {
        let area = appState.selectedAreaCamera
        let display = appState.desktopScreen?.frame.size ?? CGSize(width: 1440, height: 900)
        let worldWidth = display.width / area.pointsPerTile, worldHeight = display.height / area.pointsPerTile
        let scale = min(128, max(16, min((viewport.width - 32) / worldWidth, (viewport.height - 32) / worldHeight)))
        camera = CameraState(worldOrigin: area.worldOrigin, pointsPerTile: scale)
        hoveredTile = nil
    }
    /// Picker setters commit immediately; loading a selection never edits it.
    func setDirection(_ value: Direction, appState: AppState) {
        direction = value; saveSelectedConfiguration(appState, direction: value)
    }
    func setDelay(_ value: RepeaterDelay, appState: AppState) {
        delay = value; saveSelectedConfiguration(appState, delay: value)
    }
    private func saveSelectedConfiguration(_ appState: AppState, direction: Direction? = nil, delay: RepeaterDelay? = nil) {
        if appState.isEditorConfigurationLocked { cancelTerrainStroke(); status = appState.editorConfigurationLockMessage; return }
        guard circuitTest == nil, !isPreviewing(appState),
              let selectedTile, let component = browsingWorld(appState).circuit.components[selectedTile] else { return }
        if component.kind == .repeater { appState.configureRepeater(at: selectedTile, direction: direction ?? component.direction, delay: delay ?? component.repeaterDelay) }
        if component.kind == .torch { appState.configureTorch(at: selectedTile, direction: direction ?? component.direction) }
    }

    func showDesktopArea(_ appState: AppState) {
        guard appState.selectArea(appState.library.activeAreaID) else { return }
        syncSelectedWorld(appState)
        camera = CameraState(worldOrigin: appState.desktopCamera.worldOrigin, pointsPerTile: camera.pointsPerTile)
    }

    var proposedComponent: CircuitComponent? {
        tool.componentKind.map { CircuitComponent(kind: $0, direction: direction, repeaterDelay: delay, sensorFilter: $0 == .fileSensor ? sensorFilter : FileSensorFilter()) }
    }

    func mapper(size: CGSize) -> CoordinateMapper? {
        try? CoordinateMapper(canvasFrame: CGRect(origin: .zero, size: size), camera: camera)
    }

    func hover(at point: CGPoint, size: CGSize, appState: AppState? = nil) {
        guard let mapper = mapper(size: size), mapper.canvasFrame.contains(point) else { hoveredTile = nil; return }
        hoveredTile = appState.flatMap { placementTile(at: point, mapper: mapper, appState: $0) } ?? mapper.tile(atScreen: point)
    }

    func click(at point: CGPoint, size: CGSize, appState: AppState, additive: Bool = false) {
        guard let mapper = mapper(size: size), mapper.canvasFrame.contains(point),
              let tile = placementTile(at: point, mapper: mapper, appState: appState) else { return }
        if tool == .terrain {
            terrainInput(at: point, size: size, phase: .begin, appState: appState)
            terrainInput(at: point, size: size, phase: .end, appState: appState)
            return
        }
        if pendingPlacement != nil { _ = placePending(at: tile, appState: appState); return }
        if circuitTest != nil {
            invalidateTestIfNeeded(appState)
            selectedTile = tile
            let activated = circuitTest?.click(tile) ?? false
            status = activated ? "Test input received. Outputs flash without opening files." : "Test mode: click a button, lever, plate or sensor. Pause to inspect one tick at a time."
            return
        }
        if tool.editsWorld && isPreviewing(appState) {
            status = "Create the new world or cancel its preview before editing the circuit."
            return
        }
        selectedTile = tile
        if tool == .select || tool == .region {
            if additive {
                if !selectedTiles.insert(tile).inserted { selectedTiles.remove(tile) }
                selectedTile = selectedTiles.count == 1 ? selectedTiles.first : nil
            } else { selectedTiles = browsingWorld(appState).circuit.components[tile] == nil ? [] : [tile] }
            if let component = browsingWorld(appState).circuit.components[tile], [.repeater, .torch].contains(component.kind) {
                direction = component.direction
                delay = component.repeaterDelay
            }
            if let component = browsingWorld(appState).circuit.components[tile], component.kind == .fileSensor { sensorFilter = component.sensorFilter }
            status = "Selected (\(tile.x), \(tile.y))."
        } else if tool == .erase {
            selectedTiles = []
            appState.eraseCircuitComponent(at: tile, audioMapper: mapper)
            status = appState.developerPlacementStatus
        } else if let component = proposedComponent {
            selectedTiles = [tile]
            appState.placeCircuitComponent(component, at: tile, audioMapper: mapper)
            status = appState.developerPlacementStatus
        }
    }

    func finderProjection(_ appState: AppState) -> EditorFinderProjection {
        appState.editorFinderProjection(camera: proposedDesktopCamera(appState), preview: isPreviewing(appState))
    }

    private func placementTile(at point: CGPoint, mapper: CoordinateMapper, appState: AppState) -> WorldCoordinate? {
        if tool == .output, let snapped = finderProjection(appState).snappedTile(near: point, mapper: mapper) { return snapped }
        return mapper.tile(atScreen: point)
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

    func magnify(by delta: Double, anchor: CGPoint, size: CGSize) {
        guard delta.isFinite, delta > -1 else { return }
        zoom(by: 1 + delta, anchor: anchor, size: size)
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
