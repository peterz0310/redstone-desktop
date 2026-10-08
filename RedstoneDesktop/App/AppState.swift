import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var isDesktopWorldEnabled = false
    @Published private(set) var desktopStatus = "Desktop checker is disabled."
    @Published private(set) var pointer: PointerSnapshot?
    @Published private(set) var lastClick: DesktopClickSnapshot?
    @Published private(set) var observedClickCount = 0
    @Published private(set) var desktopWorld = EditorConstructionArea.makeWorld()
    @Published private(set) var developerPlacementStatus = "Choose a component and test tile."
    private let automaticallyRefreshFinder: Bool
    private let circuitPlacement = CircuitPlacement()
    @Published private(set) var desktopCamera = CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64)
    @Published private(set) var persistenceStatus = "Persistence is disabled for this session."
    @Published private(set) var library: WorldLibraryDocument
    @Published private(set) var selectedWorldID: UUID
    @Published private(set) var selectedAreaID: UUID
    @Published private(set) var editorWorld: World
    @Published private(set) var libraryStatus = "Select a saved world, or preview a seed to create one."
    var selectedDocument: WorldDocument { library.world(id: selectedWorldID)! }
    var activeWorldID: UUID { library.activeArea!.worldID }
    var activeWorldName: String { library.world(id: activeWorldID)!.name }
    var selectedArea: SavedArea { library.areas.first { $0.id == selectedAreaID }! }
    var selectedAreaCamera: CameraState { selectedArea.camera }
    var isEditorConfigurationLocked: Bool { (isDesktopWorldEnabled || isDesktopBuildMode) && isEditingActiveWorld }
    var editorConfigurationLockMessage: String {
        isDesktopBuildMode ? "Exit Build Mode before editing this world in the editor." : "Disable Desktop World before editing."
    }
    @Published private(set) var buildSession: DesktopBuildSession?
    var isDesktopBuildMode: Bool { buildSession != nil }
    private(set) var buildController: (any DesktopBuildPresenting)?
    private let buildControllerFactory: (DesktopBuildSession, ScreenDescriptor, AppState) -> any DesktopBuildPresenting
    private var buildExitObservers: [AnyCancellable] = []
    var editorLeverPositions: Set<WorldCoordinate> { selectedDocument.activeLevers }
    var isEditingActiveWorld: Bool { selectedWorldID == activeWorldID }
    var editorOccupancy: DesktopOccupancySnapshot {
        isEditingActiveWorld ? desktopOccupancy : .unavailable("This world is not active on the desktop.")
    }
    var editorPoweredTiles: Set<WorldCoordinate> { isEditingActiveWorld ? simulator.poweredTiles : [] }
    func editorPower(at coordinate: WorldCoordinate) -> PowerLevel {
        isEditingActiveWorld ? simulator.power(at: coordinate) : .off
    }
    private var savedLevers: Set<WorldCoordinate> = []
    private var autosaver: WorldAutosaver?
    private var persistenceBlocked = false
    var canSaveWorld: Bool { autosaver != nil }
    let finderDiagnostics: FinderDiagnosticsModel
    let desktopItemTracker: DesktopItemTracker
    @Published private(set) var editorFinderItemsVisible = false
    @Published private(set) var finderReadSnapshot = FinderReadSnapshot()
    @Published private(set) var finderMappings: [FinderItemMapping] = []
    @Published private(set) var desktopOccupancy: DesktopOccupancySnapshot = .unavailable("Enable Desktop World to resolve occupancy.")
    @Published private(set) var lastPressMetadata = ""
    @Published private(set) var observedPressCount = 0
    @Published private(set) var simulator = CircuitSimulator(world: DemoCircuit.makeWorld().circuit)
    @Published private(set) var lastActionResult = "Place a harmless Finder item on OUTPUT, then click PRESS on the desktop."
    private let openItemAction: OpenItemAction
    private let tickScheduler: any CircuitTickScheduling
    private var pendingOutputs: [WorldCoordinate] = []
    private(set) var activationTask: Task<Void, Never>?
    private let desktopInteractionAssessment: (MouseEventIdentity) -> DesktopInteractionAssessment
    private var desktopSession = UUID()
    private(set) var desktopController: DesktopWindowController?
    private var pointerMonitor: PointerMonitor?
    private var clickMonitor: DesktopClickMonitor?
    private var terminationObserver: AnyCancellable?
    private let screenProviding: () -> ScreenDescriptor?
    private let clickEventMonitoring: any GlobalMouseEventMonitoring
    private var finderLayoutObserver: AnyCancellable?
    @Published private(set) var isFinderLayoutSettling = false
    private var finderItemsObserver: AnyCancellable?
    private var finderReferenceScreen: ScreenDescriptor?
    private let finderReferenceProviding: () -> ScreenDescriptor?
    @Published private(set) var displayGeometry: DisplayGeometry?
    @Published private(set) var isDisplaySettling = false
    private var lastObservedGeometry: DisplayGeometry?
    private var displayChangeMonitor: DisplayChangeMonitor?
    private var displayRefreshGeneration = UUID()
    private(set) var displayRefreshTask: Task<Void, Never>?
    private let displaySettleDelay: Duration
    @Published private(set) var finderScale = FinderScale()
    @Published private(set) var finderScaleStatus = "Independent: saved area scale."
    private let preferences: UserDefaults?
    @Published private(set) var audioSettings = AudioSettings()
    @Published private(set) var audioStatus = "Sound effects ready."
    let assets: AssetLibrary
    private var assetObserver: AnyCancellable?
    private let soundPlayer: any SoundPlaying

    init(screenProviding: @escaping () -> ScreenDescriptor? = {
        NSScreen.screens.first.map { ScreenDescriptor(screen: $0) }
    }, clickEventMonitoring: any GlobalMouseEventMonitoring = AppKitGlobalMouseEventMonitor(),
       finderDiagnostics: FinderDiagnosticsModel = FinderDiagnosticsModel(),
       desktopInteractionAssessment: @escaping (MouseEventIdentity) -> DesktopInteractionAssessment = { DesktopInteractionGate.assess($0) },
       tickScheduler: any CircuitTickScheduling = CircuitTickScheduler(),
       itemOpener: any ItemOpening = WorkspaceItemOpener(),
       libraryStore: (any WorldLibraryStoring)? = nil,
       automaticallyRefreshFinder: Bool = false,
       autosaveDelay: Duration = .milliseconds(750),
       displayNotificationCenter: NotificationCenter = .default,
       displaySettleDelay: Duration = .milliseconds(500),
       preferences: UserDefaults? = nil,
       soundPlayer: any SoundPlaying = SilentSoundPlayer(),
       assets: AssetLibrary = AssetLibrary(),
       buildControllerFactory: @escaping (DesktopBuildSession, ScreenDescriptor, AppState) -> any DesktopBuildPresenting = {
           DesktopBuildController(session: $0, screen: $1, appState: $2)
       },
       finderReferenceProviding: @escaping () -> ScreenDescriptor? = {
           NSScreen.screens.first.map { ScreenDescriptor(screen: $0) }
       }) {
        // No-store construction is an isolated prototype fixture for integration tests.
        // Normal app startup injects a library store and creates procedural worlds when absent.
        let initial = libraryStore == nil
            ? try! WorldLibraryDocument(legacy: LegacyWorldDocument()) : WorldLibraryDocument()
        library = initial
        let initialID = initial.activeArea!.worldID
        let initialWorld = try! initial.world(id: initialID)!.restoredWorld()
        selectedWorldID = initialID
        selectedAreaID = initial.activeAreaID
        editorWorld = initialWorld
        desktopWorld = initialWorld
        self.automaticallyRefreshFinder = automaticallyRefreshFinder
        self.tickScheduler = tickScheduler
        self.desktopInteractionAssessment = desktopInteractionAssessment
        openItemAction = OpenItemAction(opener: itemOpener)
        self.displaySettleDelay = displaySettleDelay
        self.preferences = preferences
        self.soundPlayer = soundPlayer
        self.assets = assets
        self.buildControllerFactory = buildControllerFactory
        if let data = preferences?.data(forKey: "audioSettings"),
           let stored = try? JSONDecoder().decode(AudioSettings.self, from: data) {
            audioSettings = AudioSettings(volume: stored.volume.isFinite ? min(1, max(0, stored.volume)) : 0,
                muted: stored.muted, effectsEnabled: stored.effectsEnabled)
        }
        if let data = preferences?.data(forKey: "finderScale"),
           let stored = try? JSONDecoder().decode(FinderScale.self, from: data),
           !stored.enabled || (stored.baselineIconSize.map { (1...4096).contains($0) } ?? false) {
            finderScale = stored
        }
        self.screenProviding = screenProviding
        self.clickEventMonitoring = clickEventMonitoring
        self.finderDiagnostics = finderDiagnostics
        self.finderReferenceProviding = finderReferenceProviding
        desktopItemTracker = DesktopItemTracker(diagnostics: finderDiagnostics)
        soundPlayer.configure(audioSettings)
        soundPlayer.replaceSoundOverrides(assets.soundOverrides)
        assetObserver = assets.$revision.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.soundPlayer.replaceSoundOverrides(self.assets.soundOverrides)
                self.desktopController?.scene.setAssets(self.assets)
                self.refreshBuildRenderer()
                self.objectWillChange.send()
            }
        }
        if finderScale.enabled { finderScaleStatus = "Experimental sync waiting for a stable Finder icon size." }
        finderItemsObserver = Publishers.CombineLatest3(finderDiagnostics.$items, finderDiagnostics.$error, finderDiagnostics.$hasRead).sink { [weak self] items, error, hasRead in
            MainActor.assumeIsolated { self?.updateFinderState(items, error: error, hasRead: hasRead) }
        }
        finderLayoutObserver = finderDiagnostics.$isLayoutSettling.sink { [weak self] settling in
            MainActor.assumeIsolated {
                guard let self else { return }
                let wasSettling = self.isFinderLayoutSettling
                self.isFinderLayoutSettling = settling
                if settling {
                    self.pendingOutputs = []
                    self.lastActionResult = "Finder icon size changed; waiting for fresh positions. Old activations skipped."
                } else if wasSettling {
                    self.lastActionResult = self.finderDiagnostics.hasRead && self.finderDiagnostics.error == nil
                        ? "Finder layout refreshed. Use the input again; old activations were skipped."
                        : "Finder layout refresh interrupted or unavailable; inspect Finder Diagnostics."
                }
            }
        }
        simulator = CircuitSimulator(world: desktopWorld.circuit)
        if let libraryStore {
            do {
                if let restored = try libraryStore.load() {
                    try restored.validate()
                    library = restored
                    persistenceStatus = "Library restored. Desktop World starts disabled."
                } else {
                    try libraryStore.save(library)
                    persistenceStatus = "New library saved. Desktop World starts disabled."
                }
                selectedWorldID = activeWorldID
                selectedAreaID = library.activeAreaID
                desktopCamera = library.activeArea!.camera
                desktopWorld = try library.world(id: activeWorldID)!.restoredWorld()
                editorWorld = desktopWorld
                savedLevers = library.world(id: activeWorldID)!.activeLevers
                simulator = CircuitSimulator(world: desktopWorld.circuit)
                autosaver = WorldAutosaver(store: libraryStore, delay: autosaveDelay) { [weak self] in self?.persistenceStatus = $0 }
            } catch {
                persistenceBlocked = true
                persistenceStatus = "Could not restore library: \(error.localizedDescription) Saved files preserved; autosave disabled. Repair or move library.json (or legacy world.json if no library exists) before reopening."
            }
        }
        lastObservedGeometry = DisplayGeometry(target: screenProviding(), finderReference: finderReferenceProviding())
        displayChangeMonitor = DisplayChangeMonitor(center: displayNotificationCenter) { [weak self] in self?.displayParametersDidChange() }
        displayChangeMonitor?.start()
        for name in [NSApplication.didResignActiveNotification, NSApplication.didHideNotification] {
            buildExitObservers.append(displayNotificationCenter.publisher(for: name).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.exitDesktopBuildMode() }
            })
        }
        terminationObserver = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.shutdown() }
            }
    }

    var desktopScreen: ScreenDescriptor? {
        if let displayGeometry { return displayGeometry.target }
        return desktopController?.scene.screen ?? screenProviding()
    }
    func setEditorFinderItemsVisible(_ visible: Bool) {
        editorFinderItemsVisible = visible
        if visible { displayChangeMonitor?.start(); startEditorFinderTrackingIfNeeded() }
        else if !isDesktopWorldEnabled || !automaticallyRefreshFinder { desktopItemTracker.stop() }
    }

    private func startEditorFinderTrackingIfNeeded() {
        if editorFinderItemsVisible && !isDisplaySettling && finderDiagnostics.permission != .denied { desktopItemTracker.start() }
    }

    func editorFinderProjection(camera: CameraState, preview: Bool = false) -> EditorFinderProjection {
        EditorFinderProjection(worldID: selectedWorldID, camera: camera, snapshot: finderReadSnapshot,
            screen: desktopScreen, reference: displayGeometry == nil ? finderReferenceProviding() : displayGeometry?.finderReference, enabled: editorFinderItemsVisible && !preview && !isDisplaySettling)
    }

    @Published private(set) var areaStatus = "Save Area bookmarks the proposed view. Activate on Desktop uses the selected saved view."

    @discardableResult
    func selectWorld(_ id: UUID) -> Bool {
        guard let document = library.world(id: id),
              let world = try? document.restoredWorld() else {
            libraryStatus = "The selected world is unavailable."
            return false
        }
        selectedWorldID = id
        selectedAreaID = library.areas.first { $0.worldID == id }!.id
        editorWorld = world
        libraryStatus = "Editing \(document.name). Desktop assignment remains \(activeWorldName)."
        return true
    }

    @discardableResult
    func createWorld(name: String, generation: WorldGenerationSettings) -> Bool {
        let document = WorldDocument(name: name, generation: generation)
        guard let world = try? document.restoredWorld() else { libraryStatus = "Enter a nonempty name and a supported seed."; return false }
        var next = library
        next.worlds.append(document)
        next.areas.append(SavedArea(name: "Home", worldID: document.id, camera: SavedArea.homeCamera))
        guard (try? next.validate()) != nil else { return false }
        library = next
        selectedWorldID = document.id
        selectedAreaID = next.areas.last!.id
        editorWorld = world
        autosaver?.schedule(library)
        libraryStatus = "Created \(document.name) with seed \(generation.seed). It is not activated."
        return true
    }

    @discardableResult
    func renameSelectedWorld(_ name: String) -> Bool {
        renameWorld(selectedWorldID, name: name)
    }

    @discardableResult
    func renameWorld(_ id: UUID, name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(isDesktopWorldEnabled && id == activeWorldID), !name.isEmpty,
              let index = library.worlds.firstIndex(where: { $0.id == id }) else {
            libraryStatus = "Disable Desktop World and enter a nonempty world name."
            return false
        }
        library.worlds[index].name = name
        autosaver?.schedule(library)
        libraryStatus = "World renamed."
        return true
    }

    @discardableResult
    func selectArea(_ id: UUID) -> Bool {
        guard let area = library.areas.first(where: { $0.id == id }), selectWorld(area.worldID) else { return false }
        selectedAreaID = id
        libraryStatus = "Browsing \(selectedDocument.name) / \(area.name). Desktop assignment is unchanged."
        return true
    }

    @discardableResult
    func saveArea(name: String, camera: CameraState) -> Bool {
        let area = SavedArea(name: name.trimmingCharacters(in: .whitespacesAndNewlines), worldID: selectedWorldID, camera: camera)
        guard (try? area.validate()) != nil else { areaStatus = "Enter an area name and a valid camera."; return false }
        library.areas.append(area)
        selectedAreaID = area.id
        autosaver?.schedule(library)
        areaStatus = "Saved \(area.name). Desktop assignment is unchanged."
        return true
    }

    @discardableResult
    func renameSelectedArea(_ name: String) -> Bool {
        renameArea(selectedAreaID, name: name)
    }

    @discardableResult
    func renameArea(_ id: UUID, name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = library.areas.firstIndex(where: { $0.id == id }) else {
            areaStatus = "Enter a nonempty name for an existing area."
            return false
        }
        library.areas[index].name = name
        autosaver?.schedule(library)
        areaStatus = "Area renamed; its saved camera is unchanged."
        return true
    }

    var isSelectedAreaRunning: Bool { (isDesktopWorldEnabled || isDesktopBuildMode) && selectedAreaID == library.activeAreaID }

    @discardableResult
    func updateSelectedArea(camera: CameraState) -> Bool {
        guard !isSelectedAreaRunning else {
            areaStatus = isDesktopBuildMode ? "Exit Build Mode before updating its active area's saved view." : "Stop Desktop before updating its active area's saved view."
            return false
        }
        guard !persistenceBlocked, let index = library.areas.firstIndex(where: { $0.id == selectedAreaID }) else {
            areaStatus = "Area update unavailable; check library recovery status."
            return false
        }
        guard camera.pointsPerTile == selectedAreaCamera.pointsPerTile else {
            areaStatus = "Updating an area keeps its desktop tile scale. Nothing changed."
            return false
        }
        if selectedAreaID == library.activeAreaID {
            guard let screen = screenProviding(),
                  let mapper = try? CoordinateMapper(canvasFrame: screen.frame, camera: camera),
                  mapper.tile(atScreen: screen.frame.origin) != nil,
                  mapper.tile(atScreen: CGPoint(x: screen.frame.maxX, y: screen.frame.maxY)) != nil,
                  !mapper.visibleChunks(on: screen, viewport: CGRect(origin: .zero, size: screen.frame.size)).isEmpty else {
                areaStatus = "The prepared desktop view or display is unavailable. Previous view preserved."
                return false
            }
        }
        var next = library
        next.areas[index].camera = camera
        do { try next.validate() }
        catch { areaStatus = "Invalid area view: \(error.localizedDescription) Nothing changed."; return false }
        guard autosaver?.commit(next, operation: "Area update") ?? true else {
            areaStatus = "Could not save area update. Previous view preserved; check save status and retry Update Current Area."
            return false
        }
        library = next
        if selectedAreaID == library.activeAreaID { desktopCamera = camera; refreshFinderScale() }
        areaStatus = selectedAreaID == library.activeAreaID
            ? "Area updated. This saved view is prepared for the next Start Desktop."
            : "Area updated in place. Desktop assignment is unchanged."
        return true
    }

    @discardableResult
    func activateSelectedArea() -> Bool {
        guard !isDesktopBuildMode else { areaStatus = "Exit Build Mode before changing the desktop assignment."; return false }
        let area = selectedArea
        guard !persistenceBlocked, let world = try? selectedDocument.restoredWorld(),
              (try? area.validate()) != nil, let screen = screenProviding(),
              let mapper = try? CoordinateMapper(canvasFrame: screen.frame, camera: area.camera),
              mapper.tile(atScreen: screen.frame.origin) != nil,
              mapper.tile(atScreen: CGPoint(x: screen.frame.maxX, y: screen.frame.maxY)) != nil,
              !mapper.visibleChunks(on: screen, viewport: CGRect(origin: .zero, size: screen.frame.size)).isEmpty else {
            areaStatus = "Activation unavailable: check the display, saved camera and library recovery status. Current desktop preserved."
            return false
        }
        var next = library
        next.activeAreaID = area.id
        guard (try? next.validate()) != nil, autosaver?.commit(next) ?? true else {
            areaStatus = "Activation could not be saved. Current desktop preserved; use Save Now, then retry Activate on Desktop."
            return false
        }
        let sameView = area.worldID == activeWorldID && area.camera == library.activeArea!.camera
        let running = isDesktopWorldEnabled
        // Save succeeds before cancelling the old runtime; shutdown has no pending selection to flush.
        if !sameView { shutdown(preserveEditorTracking: true) }
        library = next
        if !sameView {
            desktopCamera = area.camera
            desktopWorld = world
            savedLevers = selectedDocument.activeLevers
            simulator = CircuitSimulator(world: world.circuit)
            if running { toggleDesktopWorld() }
            else { refreshFinderScale() }
        }
        areaStatus = running && !isDesktopWorldEnabled
            ? "Area saved, but rendering could not start. Desktop World is disabled. \(desktopStatus)"
            : "Desktop assigned to \(selectedDocument.name) / \(area.name), saved origin (\(area.camera.worldOrigin.x), \(area.camera.worldOrigin.y))."
        return !running || isDesktopWorldEnabled
    }

    @discardableResult
    func deleteWorld(_ id: UUID) -> Bool {
        do { return commitDeletion(try library.deletingWorld(id)) }
        catch { libraryStatus = error.localizedDescription; return false }
    }

    @discardableResult
    func deleteArea(_ id: UUID) -> Bool {
        do { return commitDeletion(try library.deletingArea(id)) }
        catch { libraryStatus = error.localizedDescription; return false }
    }

    private func commitDeletion(_ next: WorldLibraryDocument) -> Bool {
        guard !persistenceBlocked, autosaver?.commit(next, operation: "Deletion") ?? true else {
            libraryStatus = "Could not save deletion. Nothing deleted; check save/recovery status and retry."
            return false
        }
        let remaining = next.areas.first { $0.id == selectedAreaID }
            ?? next.areas.first { $0.worldID == selectedWorldID }
            ?? next.activeArea!
        library = next
        selectedWorldID = remaining.worldID
        selectedAreaID = remaining.id
        editorWorld = try! selectedDocument.restoredWorld() // already validated before commit
        libraryStatus = "Deleted. Other builds and the desktop assignment are unchanged."
        return true
    }

    func developerPlacementPreview(_ component: CircuitComponent, at coordinate: WorldCoordinate) -> PlacementResult {
        guard !isEditorConfigurationLocked else { return .rejected(.reserved) }
        return circuitPlacement.rules.canPlace(component: component, at: coordinate, in: editorWorld)
    }

    @discardableResult
    func placeDeveloperComponent(_ component: CircuitComponent, at coordinate: WorldCoordinate) -> PlacementResult {
        placeCircuitComponent(component, at: coordinate)
    }

    @discardableResult
    func placeCircuitComponent(_ component: CircuitComponent, at coordinate: WorldCoordinate, audioMapper: CoordinateMapper? = nil) -> PlacementResult {
        guard !isEditorConfigurationLocked else {
            developerPlacementStatus = editorConfigurationLockMessage
            playSound(.invalidPlacement, at: coordinate, mapper: audioMapper)
            return .rejected(.reserved)
        }
        var next = editorWorld
        let result = circuitPlacement.place(component, at: coordinate, in: &next)
        if result.isAllowed {
            editorWorld = next
            worldDidChange()
            playSound(.placeCircuit, at: coordinate, mapper: audioMapper)
            developerPlacementStatus = "Placed \(component.kind.rawValue) at (\(coordinate.x), \(coordinate.y)). Saved in the selected world. Activate a saved area to run it."
        } else { developerPlacementStatus = result.message; playSound(.invalidPlacement, at: coordinate, mapper: audioMapper) }
        return result
    }

    @discardableResult
    func eraseCircuitComponent(at coordinate: WorldCoordinate, audioMapper: CoordinateMapper? = nil) -> Bool {
        guard !isEditorConfigurationLocked else {
            developerPlacementStatus = editorConfigurationLockMessage
            return false
        }
        guard editorWorld.circuit.components[coordinate] != nil else {
            developerPlacementStatus = "No component at (\(coordinate.x), \(coordinate.y))."
            return false
        }
        var next = editorWorld
        next.circuit.components.removeValue(forKey: coordinate)
        editorWorld = next
        worldDidChange()
        playSound(.removeCircuit, at: coordinate, mapper: audioMapper)
        developerPlacementStatus = "Erased component at (\(coordinate.x), \(coordinate.y)); terrain preserved."
        return true
    }

    @discardableResult
    func configureRepeater(at coordinate: WorldCoordinate, direction: Direction, delay: RepeaterDelay) -> Bool {
        guard !isEditorConfigurationLocked else {
            developerPlacementStatus = editorConfigurationLockMessage
            return false
        }
        guard var component = editorWorld.circuit.components[coordinate], component.kind == .repeater else {
            developerPlacementStatus = "Select a repeater to change its direction or delay."
            return false
        }
        component.direction = direction
        component.repeaterDelay = delay
        var next = editorWorld
        next.circuit.components[coordinate] = component
        editorWorld = next
        worldDidChange()
        developerPlacementStatus = "Repeater updated at (\(coordinate.x), \(coordinate.y))."
        return true
    }

    func resetDeveloperPlacements() {
        guard selectedDocument.terrainProfile == .legacyFixtureV1 else {
            developerPlacementStatus = "This procedural world has no developer test patch. Use Erase for its components."
            return
        }
        guard !isEditorConfigurationLocked else {
            developerPlacementStatus = editorConfigurationLockMessage
            return
        }
        var next = editorWorld
        for target in DeveloperPlacementFixture.targets { next.circuit.components.removeValue(forKey: target.coordinate) }
        editorWorld = next
        worldDidChange()
        developerPlacementStatus = "Test placements reset; original circuits and terrain preserved."
    }

    private func worldDidChange() {
        commitCircuit(editorWorld, worldID: selectedWorldID)
    }

    private func commitCircuit(_ world: World, worldID: UUID) {
        guard let index = library.worlds.firstIndex(where: { $0.id == worldID }) else { return }
        library.worlds[index].circuit = world.circuit
        library.worlds[index].activeLevers = library.worlds[index].activeLevers.filter { world.circuit.components[$0]?.kind == .lever }
        if selectedWorldID == worldID { editorWorld = world }
        if activeWorldID == worldID {
            desktopWorld = world
            savedLevers = library.worlds[index].activeLevers
            simulator = CircuitSimulator(world: desktopWorld.circuit)
        }
        autosaver?.schedule(library)
    }

    /// Explicit local editing. Normal simulation and its asynchronous action requests
    /// are stopped before the temporary capture window can be created.
    @discardableResult
    func enterDesktopBuildMode() -> Bool {
        if isDesktopBuildMode { return true }
        guard !persistenceBlocked, !isDisplaySettling, !isFinderLayoutSettling,
              let screen = screenProviding(),
              let mapper = try? CoordinateMapper(canvasFrame: screen.frame, camera: desktopCamera),
              !mapper.visibleChunks(on: screen, viewport: CGRect(origin: .zero, size: screen.frame.size)).isEmpty else {
            desktopStatus = "Build Mode unavailable: check display, settling and library recovery status."
            return false
        }
        shutdown(preserveEditorTracking: true)
        displayChangeMonitor?.start()
        let session = DesktopBuildSession(worldID: activeWorldID, areaID: library.activeAreaID, mapper: mapper,
            title: "\(activeWorldName) / \(library.activeArea!.name)")
        buildSession = session
        let controller = buildControllerFactory(session, screen, self)
        buildController = controller
        refreshBuildRenderer()
        controller.show()
        desktopStatus = "BUILD MODE — editing \(session.title). Circuit stopped. Exit before using Finder."
        return true
    }

    func exitDesktopBuildMode() {
        guard isDesktopBuildMode || buildController != nil else { return }
        buildSession = nil // invalidate captured input before closing native windows
        let controller = buildController
        buildController = nil
        controller?.close()
        saveWorldNow()
        desktopStatus = "Build Mode exited. Desktop stopped; Start Desktop to run your circuit."
    }

    private func refreshBuildRenderer() {
        guard buildSession != nil else { return }
        buildController?.update(world: desktopWorld, levers: savedLevers, assets: assets)
    }

    func buildClick(at point: CGPoint, erase: Bool = false, sessionID: UUID) {
        guard let session = buildSession, session.id == sessionID,
              session.worldID == activeWorldID, session.areaID == library.activeAreaID,
              let tile = session.tile(at: point) else { return }
        session.selectedTile = tile
        if let existing = desktopWorld.circuit.components[tile], existing.kind == .repeater {
            session.direction = existing.direction
            session.delay = existing.repeaterDelay
        }
        var next = desktopWorld
        if erase || session.tool == .erase {
            guard next.circuit.components.removeValue(forKey: tile) != nil else {
                session.status = "No circuit component here. Terrain is preserved."; return
            }
            session.status = "Erased (\(tile.x), \(tile.y)). Terrain preserved."
            playSound(.removeCircuit, at: tile, mapper: session.mapper)
        } else if let component = session.component {
            let result = circuitPlacement.place(component, at: tile, in: &next)
            guard result.isAllowed else {
                session.status = result.message + (next.circuit.components[tile]?.kind == .repeater ? " Use Rotate or Delay to edit this repeater." : "")
                playSound(.invalidPlacement, at: tile, mapper: session.mapper)
                return
            }
            session.status = "Placed \(session.tool.rawValue) at (\(tile.x), \(tile.y)). Circuit stopped."
            playSound(.placeCircuit, at: tile, mapper: session.mapper)
        } else { return }
        commitCircuit(next, worldID: session.worldID)
        refreshBuildRenderer()
    }

    func rotateBuildRepeater() {
        guard let session = buildSession else { return }
        session.rotateDirection()
        configureBuildRepeater()
    }

    func setBuildRepeaterDelay(_ delay: RepeaterDelay) {
        guard let session = buildSession else { return }
        session.delay = delay
        configureBuildRepeater()
    }

    private func configureBuildRepeater() {
        guard let session = buildSession else { return }
        guard let tile = session.selectedTile, var component = desktopWorld.circuit.components[tile], component.kind == .repeater else {
            session.status = "Next repeater: \(session.direction.rawValue), delay \(session.delay.rawValue)."; return
        }
        component.direction = session.direction
        component.repeaterDelay = session.delay
        var next = desktopWorld
        next.circuit.components[tile] = component
        commitCircuit(next, worldID: session.worldID)
        refreshBuildRenderer()
        session.status = "Repeater (\(tile.x), \(tile.y)): \(session.direction.rawValue), delay \(session.delay.rawValue)."
    }

    private func desktopLeversDidChange() {
        guard let index = library.worlds.firstIndex(where: { $0.id == activeWorldID }) else { return }
        library.worlds[index].activeLevers = savedLevers
        autosaver?.schedule(library)
    }

    func saveWorldNow() { autosaver?.flush() }

    /// Used by both disable and the app's termination notification.
    func shutdown(preserveEditorTracking: Bool = false) {
        exitDesktopBuildMode()
        soundPlayer.stop()
        if !preserveEditorTracking || !editorFinderItemsVisible {
            displayRefreshTask?.cancel()
            displayRefreshTask = nil
            displayRefreshGeneration = UUID()
            isDisplaySettling = false
        }
        if !preserveEditorTracking { displayChangeMonitor?.stop() }
        saveWorldNow()
        desktopSession = UUID()
        activationTask?.cancel()
        activationTask = nil
        tickScheduler.stop()
        pendingOutputs = []
        lastPressMetadata = ""
        observedPressCount = 0
        simulator = CircuitSimulator(world: desktopWorld.circuit)
        lastActionResult = "Desktop circuit is disabled."
        desktopItemTracker.stop()
        finderMappings = []
        desktopOccupancy = .unavailable("Enable Desktop World to resolve occupancy.")
        finderReferenceScreen = nil
        clickMonitor?.stop()
        clickMonitor = nil
        pointerMonitor?.stop()
        pointerMonitor = nil
        pointer = nil
        lastClick = nil
        observedClickCount = 0
        desktopController?.disable()
        desktopController?.close()
        desktopController = nil
        isDesktopWorldEnabled = false
        desktopStatus = "Desktop checker is disabled."
        if preserveEditorTracking { startEditorFinderTrackingIfNeeded() }
        else { editorFinderItemsVisible = false }
    }

    func toggleDesktopWorld() {
        exitDesktopBuildMode()
        displayChangeMonitor?.start()
        if isDesktopWorldEnabled {
            shutdown(preserveEditorTracking: true)
        } else {
            guard let screen = screenProviding() else {
                desktopStatus = "No main display is available."
                return
            }
            do {
                simulator = CircuitSimulator(world: desktopWorld.circuit)
                for lever in savedLevers { simulator.toggleLever(at: lever) }
                try installDesktopRenderer(on: screen)
                isDesktopWorldEnabled = true
                if automaticallyRefreshFinder && !isDisplaySettling && finderDiagnostics.permission != .denied { desktopItemTracker.start() }
                startCircuitTimer()
                lastActionResult = "Place a harmless Finder item on OUTPUT (7, 3), then click PRESS (2, 3)."
            } catch {
                desktopStatus = "Display geometry cannot be mapped. Desktop checker remains disabled."
            }
        }
    }

    private func installDesktopRenderer(on screen: ScreenDescriptor) throws {
        if let effective = finderScale.camera(saved: library.activeArea!.camera,
            current: finderDiagnostics.viewSettings, frame: screen.frame), finderScale.enabled {
            desktopCamera = effective
        }
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: desktopCamera)
        let controller = DesktopWindowController(screen: screen, mapper: mapper)
        let monitor = PointerMonitor(screen: screen, mapper: mapper) { [weak self, weak controller] snapshot in
            self?.pointer = snapshot
            controller?.scene.updateHighlight(snapshot.tile)
        }
        desktopController = controller
        controller.scene.setAssets(assets)
        controller.scene.updateWorld(desktopWorld, poweredTiles: simulator.poweredTiles, leverPositions: simulator.activeLevers)
        finderReferenceScreen = finderReferenceProviding()
        lastObservedGeometry = DisplayGeometry(target: screen, finderReference: finderReferenceScreen)
        if displayGeometry != nil { displayGeometry = lastObservedGeometry }
        updateFinderState(finderDiagnostics.items, error: finderDiagnostics.error, hasRead: finderDiagnostics.hasRead)
        pointerMonitor = monitor
        let clicks = DesktopClickMonitor(screen: screen, mapper: mapper, eventMonitoring: clickEventMonitoring) { [weak self, weak controller] snapshot in
            guard let self else { return }
            self.lastClick = snapshot
            self.observedClickCount += 1
            controller?.scene.flashTile(snapshot.tile)
            self.handleCircuitClick(snapshot.tile, identity: snapshot.identity)
        }
        clickMonitor = clicks
        controller.enable()
        monitor.start()
        desktopStatus = clicks.start()
            ? "Desktop checker is enabled. Click the desktop to flash a tile."
            : "Desktop checker is enabled, but click observation could not start. Disable and re-enable to retry."
    }

    /// Geometry changes preserve saved cameras/configuration and the current simulator.
    func displayParametersDidChange() {
        let next = DisplayGeometry(target: screenProviding(), finderReference: finderReferenceProviding())
        guard next != lastObservedGeometry else { return }
        exitDesktopBuildMode()
        lastObservedGeometry = next
        displayGeometry = next
        displayRefreshGeneration = UUID()
        let generation = displayRefreshGeneration
        displayRefreshTask?.cancel()
        desktopSession = UUID()
        activationTask?.cancel(); activationTask = nil
        pendingOutputs = []
        desktopItemTracker.stop()
        isDisplaySettling = true
        finderDiagnostics.invalidateDisplayPositions()
        finderMappings = []
        desktopOccupancy = .unavailable("Display changed; waiting for fresh Finder positions.")
        pointerMonitor?.stop(); pointerMonitor = nil
        clickMonitor?.stop(); clickMonitor = nil
        pointer = nil; lastClick = nil
        desktopController?.disable(); desktopController?.close(); desktopController = nil
        tickScheduler.stop()
        if isDesktopWorldEnabled {
            do {
                guard let screen = next.target else { throw CoordinateMapper.ValidationError.invalidCanvas }
                let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: desktopCamera)
                guard !mapper.visibleChunks(on: screen, viewport: CGRect(origin: .zero, size: screen.frame.size)).isEmpty else {
                    throw CoordinateMapper.ValidationError.invalidCanvas
                }
                try installDesktopRenderer(on: screen)
                desktopController?.scene.updateOccupancy(desktopOccupancy)
                startCircuitTimer()
            } catch {
                isDesktopWorldEnabled = false
                desktopStatus = "Display unavailable or invalid. Desktop stopped; Start Desktop after the display returns."
            }
        }
        lastActionResult = "Display changed; old input/output requests canceled. Waiting for Finder to settle."
        displayRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.displayRefreshGeneration == generation { self.displayRefreshTask = nil } }
            do {
                try await Task.sleep(for: self.displaySettleDelay)
                // Keep the shared read slot occupied if an old provider ignores cancellation.
                while self.finderDiagnostics.isReading {
                    try await Task.sleep(for: .milliseconds(50))
                }
            } catch { return }
            guard !Task.isCancelled, self.displayRefreshGeneration == generation else { return }
            let needsFinder = (self.isDesktopWorldEnabled || self.editorFinderItemsVisible)
                && next.target != nil && next.finderReference != nil && self.finderDiagnostics.permission != .denied
            let success = needsFinder ? await self.finderDiagnostics.readItems() : false
            guard !Task.isCancelled, self.displayRefreshGeneration == generation else { return }
            self.isDisplaySettling = false
            if success && ((self.isDesktopWorldEnabled && self.automaticallyRefreshFinder) || self.editorFinderItemsVisible) {
                self.desktopItemTracker.start()
            }
            self.lastActionResult = success ? "Display refreshed. Finder targets use the new geometry." : "Display refreshed; Finder unavailable or tracking not enabled."
        }
    }

    private func startCircuitTimer() {
        let session = desktopSession
        tickScheduler.start { [weak self] in
            guard let self, self.desktopSession == session else { return }
            self.advanceCircuitTick()
        }
    }

    func advanceCircuitTick() {
        guard isDesktopWorldEnabled else { return }
        var next = simulator
        let events = next.advanceTick()
        if !isDisplaySettling && !isFinderLayoutSettling {
            for (id, tile) in CircuitSounds.transitions(before: simulator, after: next) where outputIsVisible(tile) {
                playSound(id, at: tile, mapper: desktopController?.scene.mapper)
            }
        }
        let changedPower = next.power != simulator.power
        if next != simulator { simulator = next }
        if changedPower { desktopController?.scene.updateWorld(desktopWorld, poweredTiles: next.poweredTiles) }
        for case let .outputActivated(coordinate) in events {
            guard !isDisplaySettling, !isFinderLayoutSettling, outputIsVisible(coordinate) else { continue }
            desktopController?.scene.flashOutput(at: coordinate)
            playSound(.outputActivate, at: coordinate, mapper: desktopController?.scene.mapper)
            // Bound pending I/O independently of simulation, rather than accumulating requests.
            if pendingOutputs.count < 32 { pendingOutputs.append(coordinate) }
            else { lastActionResult = "Output action queue is full; activation skipped." }
        }
        drainOutputActions()
    }

    private func outputIsVisible(_ coordinate: WorldCoordinate) -> Bool {
        guard let mapper = desktopController?.scene.mapper else { return false }
        let rect = mapper.screenRect(forTile: coordinate)
        return mapper.canvasFrame.contains(CGPoint(x: rect.midX, y: rect.midY))
    }

    private func drainOutputActions() {
        guard isDesktopWorldEnabled, !isDisplaySettling, !isFinderLayoutSettling, activationTask == nil, !finderDiagnostics.isReading,
              !pendingOutputs.isEmpty else { return }
        guard finderDiagnostics.permission == .allowed else {
            pendingOutputs = []
            lastActionResult = "Finder unavailable; output actions skipped."
            return
        }
        let coordinate = pendingOutputs.removeFirst()
        let session = desktopSession
        let worldID = activeWorldID
        let layoutGeneration = finderDiagnostics.layoutGeneration
        activationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.desktopSession == session { self.activationTask = nil } }
            let succeeded = await self.finderDiagnostics.readItems()
            guard !Task.isCancelled, self.desktopSession == session, self.finderDiagnostics.layoutGeneration == layoutGeneration, self.activeWorldID == worldID, self.isDesktopWorldEnabled else { return }
            guard succeeded else {
                self.pendingOutputs = []
                self.lastActionResult = "Finder could not be refreshed; nothing opened."
                return
            }
            guard self.outputIsVisible(coordinate) else { return }
            self.lastActionResult = self.openItemAction.perform(occupancy: self.desktopOccupancy.state(at: coordinate))
        }
    }

    func handleCircuitClick(_ tile: WorldCoordinate, identity: MouseEventIdentity = MouseEventIdentity()) {
        guard isDesktopWorldEnabled, !isDisplaySettling, !isFinderLayoutSettling, desktopController != nil,
              let kind = desktopWorld.circuit.components[tile]?.kind,
              kind == .button || kind == .lever else { return }
        observedPressCount += 1
        let inputTitle = kind == .button ? "PRESS" : "LEVER"
        let assessment = desktopInteractionAssessment(identity)
        lastPressMetadata = assessment.details
        if let reason = assessment.rejectionReason {
            lastActionResult = "\(inputTitle) click received; not activated: \(reason)"
            return
        }
        guard activationTask == nil, !finderDiagnostics.isReading else {
            lastActionResult = "Finder is busy; click \(inputTitle) again after the read finishes."
            return
        }
        guard finderDiagnostics.hasRead, finderDiagnostics.permission == .allowed else {
            lastActionResult = automaticallyRefreshFinder
                ? "Finder is connecting or unavailable; wait for refresh, or inspect Finder Diagnostics."
                : "Read Finder Items in Finder Diagnostics before using \(inputTitle)."
            return
        }
        lastActionResult = "\(inputTitle) click received; refreshing Finder items…"
        let session = desktopSession
        let worldID = activeWorldID
        let layoutGeneration = finderDiagnostics.layoutGeneration
        activationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.desktopSession == session { self.activationTask = nil } }
            let succeeded = await self.finderDiagnostics.readItems()
            guard !Task.isCancelled, self.desktopSession == session, self.finderDiagnostics.layoutGeneration == layoutGeneration, self.activeWorldID == worldID,
                  self.isDesktopWorldEnabled, let controller = self.desktopController else { return }
            guard succeeded else {
                self.lastActionResult = "Finder could not be refreshed; nothing opened."
                return
            }
            // Conservative one-tile margin also protects nearby icon/label overlap.
            // Never claim exact Finder hit regions from center-only scripting data.
            let protectedRect = controller.scene.mapper.screenRect(forTile: tile)
                .insetBy(dx: -self.desktopCamera.pointsPerTile, dy: -self.desktopCamera.pointsPerTile)
            if self.finderMappings.contains(where: { protectedRect.contains($0.screenCenter) }) {
                self.lastActionResult = "Finder item is on or near \(inputTitle); move it away to use the circuit."
                return
            }
            if kind == .button {
                self.simulator.pressButton(at: tile)
                self.playSound(.buttonPress, at: tile, mapper: controller.scene.mapper)
                self.lastActionResult = "Button pulse queued; repeats extend it without another rising activation."
            } else {
                self.simulator.toggleLever(at: tile)
                self.playSound(self.simulator.activeLevers.contains(tile) ? .leverToggleOn : .leverToggleOff,
                    at: tile, mapper: controller.scene.mapper)
                self.savedLevers = self.simulator.activeLevers
                self.desktopLeversDidChange()
                self.lastActionResult = self.simulator.activeLevers.contains(tile)
                    ? "Lever on; power updates on the next tick." : "Lever off; power updates on the next tick."
            }
        }
    }

    private func updateFinderState(_ items: [DesktopItem], error: String?, hasRead: Bool) {
        let read = FinderReadSnapshot(items: items, error: error, hasRead: hasRead)
        if finderReadSnapshot != read { finderReadSnapshot = read }
        if hasRead, error == nil, !isDisplaySettling { refreshFinderScale() }
        guard let controller = desktopController else { return }
        guard let reference = finderReferenceScreen else {
            desktopOccupancy = .unavailable("The primary display reference is unavailable.")
            controller.scene.updateOccupancy(desktopOccupancy)
            return
        }
        let mappings = items.map { controller.scene.mapper.finderMapping(for: $0, referenceScreen: reference) }
        if mappings != finderMappings {
            finderMappings = mappings
            controller.scene.updateFinderMarkers(mappings)
        }
        let snapshot: DesktopOccupancySnapshot
        if let error {
            snapshot = .unavailable(error)
        } else if !hasRead {
            snapshot = .unavailable(isDisplaySettling ? "Display changed; waiting for fresh Finder positions." : "Read Finder Items to resolve occupancy.")
        } else {
            snapshot = DesktopOccupancyResolver().resolve(items: items, mapper: controller.scene.mapper,
                finderReference: reference, activeScreen: controller.scene.screen)
        }
        if snapshot != desktopOccupancy {
            desktopOccupancy = snapshot
            controller.scene.updateOccupancy(snapshot)
        }
    }

    func setFinderScaleEnabled(_ enabled: Bool) {
        if enabled {
            guard finderDiagnostics.hasRead, finderDiagnostics.error == nil else {
                finderScaleStatus = "Read Finder successfully first. Check Finder Diagnostics if access failed."
                return
            }
            guard !finderDiagnostics.isLayoutSettling, !isDisplaySettling else {
                finderScaleStatus = "Finder/display layout is settling. Try again when positions have refreshed."
                return
            }
            guard let setting = finderDiagnostics.viewSettings else {
                finderScaleStatus = "Finder items are connected, but desktop icon size is unavailable. Independent scale still works."
                return
            }
            // Ordinary polling may be in progress; use the last completed stable setting.
            finderScale = FinderScale(enabled: true, baselineIconSize: setting.iconSize)
        } else { finderScale = FinderScale() }
        if let data = try? JSONEncoder().encode(finderScale) { preferences?.set(data, forKey: "finderScale") }
        refreshFinderScale()
    }

    func setAudioSettings(_ settings: AudioSettings) {
        audioSettings = AudioSettings(volume: settings.volume.isFinite ? min(1, max(0, settings.volume)) : 0,
            muted: settings.muted, effectsEnabled: settings.effectsEnabled)
        soundPlayer.configure(audioSettings)
        if let data = try? JSONEncoder().encode(audioSettings) { preferences?.set(data, forKey: "audioSettings") }
    }

    func previewSound(_ id: SoundID, pan: Float = 0) { playSound(id, pan: pan) }

    private func playSound(_ id: SoundID, pan: Float = 0) {
        guard audioSettings.gain > 0 else { return }
        soundPlayer.play(id, pan: pan)
        audioStatus = soundPlayer.status
    }

    private func playSound(_ id: SoundID, at tile: WorldCoordinate, mapper: CoordinateMapper?) {
        guard let mapper else { playSound(id); return }
        guard let pan = AudioPanning.pan(tile: tile, mapper: mapper) else { return }
        playSound(id, pan: pan)
    }

    private func refreshFinderScale() {
        guard let screen = desktopScreen,
              let camera = finderScale.camera(saved: library.activeArea!.camera,
                current: finderDiagnostics.viewSettings, frame: screen.frame) else {
            finderScaleStatus = "Synchronization waiting for an available display and Finder icon size."
            return
        }
        finderScaleStatus = finderScale.enabled
            ? "Experimental sync · baseline \(finderScale.baselineIconSize!) · \(Int(camera.pointsPerTile)) pt/tile · center anchored."
            : "Independent: saved area scale."
        guard camera != desktopCamera else { return }
        guard let mapper = try? CoordinateMapper(canvasFrame: screen.frame, camera: camera),
              !mapper.visibleChunks(on: screen, viewport: CGRect(origin: .zero, size: screen.frame.size)).isEmpty else {
            finderScaleStatus = "Scale cannot be mapped safely; previous camera retained."
            return
        }
        desktopCamera = camera
        guard isDesktopWorldEnabled else { return }
        desktopSession = UUID()
        activationTask?.cancel(); activationTask = nil
        pendingOutputs = []
        tickScheduler.stop()
        pointerMonitor?.stop(); clickMonitor?.stop()
        desktopController?.disable(); desktopController?.close(); desktopController = nil
        do { try installDesktopRenderer(on: screen); startCircuitTimer() }
        catch { isDesktopWorldEnabled = false; desktopStatus = "Scale mapping failed; desktop stopped." }
        lastActionResult = "Desktop scale refreshed; old activations skipped. Use the input again."
    }
}
