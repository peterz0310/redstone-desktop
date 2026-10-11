import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    lazy var menuPresentation = MenuPresentation(self)
    @Published private(set) var isDesktopWorldEnabled = false
    @Published private(set) var isMaintenanceLocked = false
    @Published private(set) var maintenanceStatus = ""
    @Published private(set) var lastBackup: URL?
    @Published private(set) var backupRevealStatus = ""
    @Published private(set) var setupCompleted = false
    var needsSetup: Bool { preferences != nil && !setupCompleted }
    private let maintenanceStore: LibraryMaintenanceStore?
    private let preferencesDomain: String?
    private let relauncher: any AppRelaunching
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
    @Published private(set) var requestedEditorArea: UUID?
    @Published private(set) var selectedAreaID: UUID
    @Published private(set) var editorWorld: World
    @Published private(set) var libraryStatus = "Select a saved world, or preview a seed to create one."
    var selectedDocument: WorldDocument { library.world(id: selectedWorldID)! }
    var activeWorldID: UUID { library.activeArea!.worldID }
    var activeWorldName: String { library.world(id: activeWorldID)!.name }
    var selectedArea: SavedArea { library.areas.first { $0.id == selectedAreaID }! }
    var selectedAreaCamera: CameraState { selectedArea.camera }
    var isEditorConfigurationLocked: Bool { persistenceBlocked || isMaintenanceLocked || ((isDesktopWorldEnabled || isDesktopBuildMode) && isEditingActiveWorld) }
    var editorConfigurationLockMessage: String {
        persistenceBlocked ? "Editing is unavailable because the saved library could not be restored. Check the save message below."
            : isDesktopBuildMode ? "Exit Build Mode before editing this world in the editor." : "Disable Desktop World before editing."
    }
    @Published private(set) var buildSession: DesktopBuildSession?
    var isDesktopBuildMode: Bool { buildSession != nil }
    private(set) var buildController: (any DesktopBuildPresenting)?
    private let buildControllerFactory: (DesktopBuildSession, ScreenDescriptor, AppState) -> any DesktopBuildPresenting
    private var buildExitObservers: [AnyCancellable] = []
    let editorWindows = EditorWindowVisibility()
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
    let blueprints: BlueprintLibrary
    @Published private(set) var editHistoryRevision = 0
    private var editHistories: [UUID: CircuitEditHistory] = [:]
    var canUndoCircuit: Bool { !isEditorConfigurationLocked && !persistenceBlocked && !(editHistories[selectedWorldID]?.undo.isEmpty ?? true) }
    var canRedoCircuit: Bool { !isEditorConfigurationLocked && !persistenceBlocked && !(editHistories[selectedWorldID]?.redo.isEmpty ?? true) }

    @discardableResult
    func replaceEditorCircuit(_ circuit: CircuitWorld, levers: Set<WorldCoordinate>? = nil, recordUndo: Bool = true, terrainOverrides: [WorldCoordinate: Tile]? = nil) -> Bool {
        guard !isEditorConfigurationLocked, !persistenceBlocked else { developerPlacementStatus = editorConfigurationLockMessage; return false }
        var document = selectedDocument
        if let terrainOverrides { document.terrainOverrides = terrainOverrides }
        document.circuit = circuit
        document.activeLevers = (levers ?? document.activeLevers).filter { circuit.components[$0]?.kind == .lever }
        do {
            let world = try document.restoredWorld()
            if terrainOverrides != nil { try validateTerrainLibrarySize(document) }
            commitCircuit(world, worldID: document.id, recordUndo: recordUndo, leverPositions: document.activeLevers, terrainOverrides: document.terrainOverrides)
            return true
        } catch { developerPlacementStatus = "Nothing changed: \(error.localizedDescription)"; return false }
    }
    private func validateTerrainLibrarySize(_ document: WorldDocument) throws {
        var candidate = library
        guard let index = candidate.worlds.firstIndex(where: { $0.id == document.id }) else { throw BlueprintError("World no longer exists.") }
        candidate.worlds[index] = document
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard try encoder.encode(candidate).count <= WorldLibraryStore.maximumBytes else {
            throw BlueprintError("Nothing changed: this edit would exceed the 2 MB library limit. Restore terrain or remove unused worlds first.")
        }
    }

    @discardableResult
    func applyTerrain(brush: TerrainBrush, tiles: Set<WorldCoordinate>, buildSessionID: UUID? = nil) -> Bool {
        if let buildSessionID {
            guard let session = buildSession, session.id == buildSessionID, session.worldID == activeWorldID,
                  session.areaID == library.activeAreaID, !isMaintenanceLocked, !persistenceBlocked,
                  let document = library.world(id: session.worldID) else { return false }
            do {
                let plan = try TerrainEditing.plan(document: document, brush: brush, tiles: tiles)
                var nextDocument = document; nextDocument.terrainOverrides = plan.overrides
                try validateTerrainLibrarySize(nextDocument)
                commitCircuit(plan.world, worldID: session.worldID, terrainOverrides: plan.overrides)
                session.status = "Changed \(plan.changed.count) tiles; protected \(plan.protected.count) circuit tiles."
                refreshBuildRenderer(); return true
            } catch { session.status = error.localizedDescription; return false }
        }
        guard !isEditorConfigurationLocked else { return false }
        do {
            let plan = try TerrainEditing.plan(document: selectedDocument, brush: brush, tiles: tiles)
            guard replaceEditorCircuit(selectedDocument.circuit, terrainOverrides: plan.overrides) else { return false }
            developerPlacementStatus = "Changed \(plan.changed.count) tiles; protected \(plan.protected.count) circuit tiles."
            return true
        } catch { developerPlacementStatus = error.localizedDescription; return false }
    }

    @discardableResult
    func undoCircuit(redo: Bool = false) -> Bool {
        guard redo ? canRedoCircuit : canUndoCircuit,
              let change = redo ? editHistories[selectedWorldID]?.redo.last : editHistories[selectedWorldID]?.undo.last else { return false }
        do {
            let (circuit, levers) = try change.applying(to: selectedDocument.circuit, levers: selectedDocument.activeLevers, undo: !redo)
            let terrain = try change.applyingTerrain(to: selectedDocument.terrainOverrides, undo: !redo)
            guard replaceEditorCircuit(circuit, levers: levers, recordUndo: false, terrainOverrides: terrain) else { return false }
            if redo { editHistories[selectedWorldID]?.didRedo() } else { editHistories[selectedWorldID]?.didUndo() }
            editHistoryRevision += 1
            developerPlacementStatus = redo ? "Edit redone." : "Edit undone."
            return true
        } catch { developerPlacementStatus = error.localizedDescription; return false }
    }

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
    @Published private(set) var lastScriptResult: ScriptExecutionResult?
    @Published private(set) var scriptOutputSettings = ScriptOutputSettings()
    @Published private(set) var desktopScriptAccessStatus = "Desktop access has not been requested in this session."
    private let desktopScriptAccess: (any DesktopScriptAccessChecking)?
    private var desktopScriptAccessAttempted = false
    private var desktopScriptAccessGeneration = UUID()
    private(set) var desktopScriptAccessTask: Task<Void, Never>?
    private var outputPolicyGeneration = UUID()
    let actionAuthorizations: ActionAuthorizationStore
    private let executeScriptAction: ExecuteScriptAction
    private let openItemAction: OpenItemAction
    private let tickScheduler: any CircuitTickScheduling
    @Published private(set) var diagnosticOverlays = DiagnosticOverlaySettings()
    @Published private(set) var isSimulationPaused = false
    @Published private(set) var isFinderPollingFrozen = false
    @Published private(set) var lastOutputActivation: OutputActivationDiagnostic?
    private(set) var simulationRate = DiagnosticRateMeter()
    private(set) var simulationTick = 0
    weak var editorDiagnosticScene: DesktopScene?
    let libraryLocation: String
    let legacyLibraryLocation: String?
    var hasPendingSave: Bool { autosaver?.pending != nil }
    private var resumePollingAfterFreeze = false
    private var pendingOutputs: [WorldCoordinate] = []
    private(set) var activationTask: Task<Void, Never>?
    private enum ActivationPhase { case inputRead, outputRead, script }
    private var activationPhase: ActivationPhase?
    private struct PendingInput {
        let tile: WorldCoordinate
        let kind: CircuitComponentKind
        let session: UUID
        let worldID: UUID
        let layoutGeneration: UUID
    }
    private var pendingInput: PendingInput?
    private let desktopInteractionAssessment: (MouseEventIdentity) -> DesktopInteractionAssessment
    private var desktopSession = UUID()
    private(set) var desktopController: DesktopWindowController?
    private(set) var desktopControllers: [DesktopWindowController] = []
    private let screensProviding: (() -> [ScreenDescriptor])?
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
       scriptExecutor: any ScriptExecuting = ScriptProcess(),
       scriptAuthorizer: any ScriptAuthorizing = ScriptAuthorizationPresenter(),
       desktopScriptAccess: (any DesktopScriptAccessChecking)? = nil,
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
       blueprintStore: (any CircuitBlueprintStoring)? = nil,
       maintenanceStore: LibraryMaintenanceStore? = nil,
       preferencesDomain: String? = nil,
       relauncher: any AppRelaunching = NativeAppRelauncher(),
       screensProviding: (() -> [ScreenDescriptor])? = nil,
       finderReferenceProviding: @escaping () -> ScreenDescriptor? = {
           NSScreen.screens.first.map { ScreenDescriptor(screen: $0) }
       }) {
        var recoveryError: String?
        if let maintenanceStore, let preferences, let preferencesDomain {
            do {
                try maintenanceStore.recoverInterruptedReset { saved in
                    preferences.setPersistentDomain(saved, forName: preferencesDomain)
                    guard preferences.synchronize() else { throw MaintenanceError(message: "Recovered preferences could not be synchronized.") }
                }
            } catch { recoveryError = error.localizedDescription }
        }
        // No-store construction is an isolated prototype fixture for integration tests.
        // Normal app startup injects a library store and creates procedural worlds when absent.
        let initial = libraryStore == nil
            ? try! WorldLibraryDocument(legacy: LegacyWorldDocument()) : WorldLibraryDocument()
        legacyLibraryLocation = (libraryStore as? WorldLibraryStore)?.legacyFileURL.path
        libraryLocation = (libraryStore as? WorldLibraryStore)?.fileURL.path ?? "In-memory/custom store"
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
        let authorizations = ActionAuthorizationStore(preferences: preferences)
        actionAuthorizations = authorizations
        executeScriptAction = ExecuteScriptAction(executor: scriptExecutor, authorizer: scriptAuthorizer, store: authorizations)
        self.displaySettleDelay = displaySettleDelay
        self.preferences = preferences
        blueprints = BlueprintLibrary(store: blueprintStore)
        self.maintenanceStore = maintenanceStore
        self.preferencesDomain = preferencesDomain
        self.relauncher = relauncher
        setupCompleted = preferences?.bool(forKey: "setupCompleted") ?? false
        self.desktopScriptAccess = desktopScriptAccess
        if let data = preferences?.data(forKey: "scriptOutputSettings"),
           let stored = try? JSONDecoder().decode(ScriptOutputSettings.self, from: data) { scriptOutputSettings = stored }
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
        self.screensProviding = screensProviding
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
                for controller in self.desktopControllers { controller.scene.setAssets(self.assets) }
                self.refreshBuildRenderer()
                self.objectWillChange.send()
            }
        }
        if finderScale.enabled { finderScaleStatus = "Experimental sync waiting for a stable Finder icon size." }
        desktopItemTracker.shouldPoll = { [weak self] in
            guard let self else { return false }
            return !self.isFinderPollingFrozen && self.pendingInput == nil && (self.activationPhase == nil || self.activationPhase == .script)
        }
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
                    self.pendingInput = nil
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
                if let recoveryError { throw MaintenanceError(message: recoveryError) }
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
        lastObservedGeometry = DisplayGeometry(target: screenProviding(), finderReference: finderReferenceProviding(), screens: screensProviding?() ?? [])
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

    var desktopScreens: [ScreenDescriptor] {
        let reported = displayGeometry?.screens ?? screensProviding?() ?? []
        if !reported.isEmpty { return (try? DesktopCanvas(screens: reported))?.screens ?? [] }
        return (displayGeometry?.target ?? screenProviding()).map { [$0] } ?? []
    }
    var desktopScreen: ScreenDescriptor? { (try? DesktopCanvas(screens: desktopScreens))?.descriptor }

    var diagnosticFinderReferenceScreen: ScreenDescriptor? {
        displayGeometry == nil ? finderReferenceProviding() : displayGeometry?.finderReference
    }
    var diagnosticFinderMappings: [FinderItemMapping] {
        guard finderDiagnostics.hasRead, finderDiagnostics.error == nil, !isDisplaySettling,
              let screen = desktopScreen, let reference = diagnosticFinderReferenceScreen,
              let mapper = try? CoordinateMapper(canvasFrame: screen.frame, camera: desktopCamera) else { return [] }
        return finderDiagnostics.items.map { mapper.finderMapping(for: $0, referenceScreen: reference) }
    }

    func setEditorFinderItemsVisible(_ visible: Bool) {
        editorFinderItemsVisible = visible
        if visible { displayChangeMonitor?.start(); startEditorFinderTrackingIfNeeded() }
        else if !isDesktopWorldEnabled || !automaticallyRefreshFinder { desktopItemTracker.stop() }
    }

    private func startEditorFinderTrackingIfNeeded() {
        if editorFinderItemsVisible && !isDisplaySettling && !isFinderPollingFrozen && finderDiagnostics.permission != .denied { desktopItemTracker.start() }
    }

    func editorFinderProjection(camera: CameraState, preview: Bool = false) -> EditorFinderProjection {
        EditorFinderProjection(worldID: selectedWorldID, camera: camera, snapshot: FinderReadSnapshot(items: finderReadSnapshot.items.filter { item in
                guard let reference = diagnosticFinderReferenceScreen, let screen = desktopScreen,
                      let mapper = try? CoordinateMapper(canvasFrame: screen.frame, camera: camera) else { return false }
                let center = mapper.finderMapping(for: item, referenceScreen: reference).screenCenter
                return desktopScreens.contains { $0.contains(center) }
            }, error: finderReadSnapshot.error, hasRead: finderReadSnapshot.hasRead),
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
        guard !isMaintenanceLocked, !persistenceBlocked else { libraryStatus = editorConfigurationLockMessage; return false }
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
        guard !isMaintenanceLocked else { return false }
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
        guard !isMaintenanceLocked else { return false }
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
        guard !isMaintenanceLocked else { return false }
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
        guard !isMaintenanceLocked else { return false }
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
            guard let screen = desktopScreen,
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
        return activateArea(selectedAreaID, resetRuntime: false)
    }

    /// Menu assignment preserves editor browsing and resumes a previously running desktop.
    @discardableResult
    func assignDesktopAreaFromMenu(_ id: UUID) -> Bool {
        activateArea(id, resetRuntime: true)
    }

    var canAssignDesktopArea: Bool { !isMaintenanceLocked && !isDesktopBuildMode && !persistenceBlocked && desktopScreen != nil }

    private func activateArea(_ id: UUID, resetRuntime: Bool) -> Bool {
        guard !isMaintenanceLocked else { return false }
        guard !persistenceBlocked else { areaStatus = "Desktop assignment is unavailable because the saved library could not be restored. Check the save message below."; return false }
        guard !isDesktopBuildMode else { areaStatus = "Exit Build Mode before changing the desktop assignment."; return false }
        guard let area = library.areas.first(where: { $0.id == id }),
              let document = library.world(id: area.worldID) else {
            areaStatus = "That saved area is no longer available. Current desktop preserved."
            return false
        }
        guard !persistenceBlocked, let world = try? document.restoredWorld(),
              (try? area.validate()) != nil, let screen = desktopScreen,
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
        if !sameView || resetRuntime { shutdown(preserveEditorTracking: true) }
        library = next
        if !sameView || resetRuntime {
            desktopCamera = area.camera
            desktopWorld = world
            savedLevers = document.activeLevers
            simulator = CircuitSimulator(world: world.circuit)
            if running { setDesktopRunning(true) }
            else { refreshFinderScale() }
        }
        areaStatus = running && !isDesktopWorldEnabled
            ? "Area saved, but rendering could not start. Desktop World is disabled. \(desktopStatus)"
            : "Desktop assigned to \(document.name) / \(area.name), saved origin (\(area.camera.worldOrigin.x), \(area.camera.worldOrigin.y))."
        return !running || isDesktopWorldEnabled
    }

    /// Explicit, idempotent command shared by editor, application menu and status menu.
    func setDesktopRunning(_ running: Bool) {
        guard !isMaintenanceLocked, !isDesktopBuildMode, running != isDesktopWorldEnabled else { return }
        toggleDesktopWorld()
    }

    func toggleAudioMute() {
        var settings = audioSettings
        settings.muted.toggle()
        setAudioSettings(settings)
    }

    func requestAssignedAreaInEditor() {
        exitDesktopBuildMode()
        guard selectArea(library.activeAreaID) else { return }
        requestedEditorArea = library.activeAreaID
    }

    func consumeEditorAreaRequest() -> Bool {
        guard let id = requestedEditorArea else { return false }
        requestedEditorArea = nil
        return id == selectedAreaID
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
        guard !isMaintenanceLocked else { return false }
        guard !persistenceBlocked, autosaver?.commit(next, operation: "Deletion") ?? true else {
            libraryStatus = "Could not save deletion. Nothing deleted; check save/recovery status and retry."
            return false
        }
        let remaining = next.areas.first { $0.id == selectedAreaID }
            ?? next.areas.first { $0.worldID == selectedWorldID }
            ?? next.activeArea!
        library = next
        let remainingWorlds = Set(next.worlds.map(\.id))
        editHistories = editHistories.filter { remainingWorlds.contains($0.key) }
        editHistoryRevision += 1
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
    func configureTorch(at coordinate: WorldCoordinate, direction: Direction) -> Bool {
        guard !isEditorConfigurationLocked else {
            developerPlacementStatus = editorConfigurationLockMessage
            return false
        }
        guard var component = editorWorld.circuit.components[coordinate], component.kind == .torch else { return false }
        component.direction = direction
        var next = editorWorld
        next.circuit.components[coordinate] = component
        editorWorld = next
        worldDidChange()
        developerPlacementStatus = "Torch direction updated at (\(coordinate.x), \(coordinate.y))."
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

    @discardableResult
    func configureOutput(at coordinate: WorldCoordinate, mode: OutputActionMode) -> Bool {
        guard !isEditorConfigurationLocked,
              var component = editorWorld.circuit.components[coordinate], component.kind == .output else { return false }
        component.outputAction = mode
        var next = editorWorld
        next.circuit.components[coordinate] = component
        editorWorld = next
        worldDidChange()
        developerPlacementStatus = "Output action updated. Execution requires separate file approval."
        if mode == .executeOccupant { requestDesktopScriptAccess() }
        return true
    }

    @discardableResult
    func configureFileSensor(at coordinate: WorldCoordinate, filter: FileSensorFilter) -> Bool {
        guard filter.isValid, var component = editorWorld.circuit.components[coordinate], component.kind == .fileSensor else { return false }
        component.sensorFilter = filter
        var circuit = editorWorld.circuit; circuit.components[coordinate] = component
        return replaceEditorCircuit(circuit)
    }

    /// Fail off when Finder positions are stale, frozen, unavailable or being recalibrated.
    var desktopSensorOccupancy: DesktopOccupancySnapshot {
        guard !isDisplaySettling, !isFinderLayoutSettling, !isFinderPollingFrozen,
              finderDiagnostics.hasRead, finderDiagnostics.error == nil,
              DesktopSensorInputs.isFresh(lastRead: finderDiagnostics.lastSuccessfulRead) else {
            return .unavailable("Sensors need a recent, stable Finder read.")
        }
        return desktopOccupancy
    }

    func setRunScriptsOpenOtherItems(_ enabled: Bool) {
        guard !isMaintenanceLocked else { return }
        guard enabled != scriptOutputSettings.runScriptsOpenOtherItems else { return }
        scriptOutputSettings.runScriptsOpenOtherItems = enabled
        if let data = try? JSONEncoder().encode(scriptOutputSettings) { preferences?.set(data, forKey: "scriptOutputSettings") }
        outputPolicyGeneration = UUID()
        // Leave the task slot occupied until cancellation finishes; no old cleanup can clear a new action.
        activationTask?.cancel()
        pendingOutputs = []
        pendingInput = nil
        if enabled { requestDesktopScriptAccess() }
    }

    func requestDesktopScriptAccess(retry: Bool = false) {
        guard !isMaintenanceLocked else { return }
        guard let desktopScriptAccess, desktopScriptAccessTask == nil,
              retry || !desktopScriptAccessAttempted else { return }
        desktopScriptAccessAttempted = true
        desktopScriptAccessStatus = "Checking Desktop-folder access…"
        let generation = desktopScriptAccessGeneration
        desktopScriptAccessTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.desktopScriptAccessGeneration == generation { self.desktopScriptAccessTask = nil } }
            do {
                guard !Task.isCancelled, self.desktopScriptAccessGeneration == generation else { return }
                try await desktopScriptAccess.checkAccess()
                guard !Task.isCancelled, self.desktopScriptAccessGeneration == generation else { return }
                self.desktopScriptAccessStatus = "Desktop-folder access succeeded. Script approval is separate."
            } catch {
                guard !Task.isCancelled, self.desktopScriptAccessGeneration == generation else { return }
                self.desktopScriptAccessStatus = "Desktop access failed: \(error.localizedDescription) Check System Settings → Privacy & Security → Files & Folders."
            }
        }
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

    private func commitCircuit(_ world: World, worldID: UUID, recordUndo: Bool = true, leverPositions: Set<WorldCoordinate>? = nil, terrainOverrides: [WorldCoordinate: Tile]? = nil) {
        guard let index = library.worlds.firstIndex(where: { $0.id == worldID }) else { return }
        let before = library.worlds[index]
        let nextLevers = (leverPositions ?? before.activeLevers).filter { world.circuit.components[$0]?.kind == .lever }
        if recordUndo {
            let change = CircuitChange(before: before.circuit, after: world.circuit, leversBefore: before.activeLevers, leversAfter: nextLevers, terrainBefore: before.terrainOverrides, terrainAfter: terrainOverrides ?? before.terrainOverrides)
            editHistories[worldID, default: CircuitEditHistory()].record(change)
            editHistoryRevision += 1
        }
        if let terrainOverrides { library.worlds[index].terrainOverrides = terrainOverrides }
        library.worlds[index].circuit = world.circuit
        library.worlds[index].activeLevers = nextLevers
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
        guard !isMaintenanceLocked else { return false }
        if isDesktopBuildMode { return true }
        guard !persistenceBlocked, !isDisplaySettling, !isFinderLayoutSettling,
              let screen = screenProviding(),
              let mapper = try? CoordinateMapper(canvasFrame: desktopScreen?.frame ?? screen.frame, camera: desktopCamera),
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
        editorWindows.beginBuild()
        desktopStatus = "BUILD MODE — editing \(session.title). Circuit stopped. Exit before using Finder."
        return true
    }

    func exitDesktopBuildMode(restoreEditor: Bool = true) {
        guard isDesktopBuildMode || buildController != nil else { return }
        buildSession = nil // invalidate captured input before closing native windows
        let controller = buildController
        buildController = nil
        controller?.close()
        editorWindows.endBuild(restore: restoreEditor)
        saveWorldNow()
        desktopStatus = "Build Mode exited. Desktop stopped; Start Desktop to run your circuit."
    }

    private func refreshBuildRenderer() {
        guard buildSession != nil else { return }
        buildController?.update(world: buildSession?.terrainStroke?.plan?.world ?? desktopWorld, levers: savedLevers, assets: assets)
    }

    func buildTerrain(at point: CGPoint, phase: TerrainStrokePhase, sessionID: UUID) {
        guard let session = buildSession, session.id == sessionID else { return }
        if phase == .cancel { session.terrainStroke = nil; session.status = "Terrain stroke cancelled."; refreshBuildRenderer(); return }
        guard session.worldID == activeWorldID, session.areaID == library.activeAreaID,
              !isMaintenanceLocked, !persistenceBlocked, let tile = session.tile(at: point),
              let document = library.world(id: session.worldID) else { session.terrainStroke = nil; refreshBuildRenderer(); return }
        if phase == .begin { session.terrainStroke = TerrainStroke(document: document, brush: session.terrainBrush, size: session.terrainBrushSize) }
        guard var stroke = session.terrainStroke else { return }
        guard stroke.document == document else { session.terrainStroke = nil; session.status = "World changed; stroke cancelled."; refreshBuildRenderer(); return }
        do {
            try stroke.extend(to: tile); session.terrainStroke = stroke
            session.status = "Preview: \(stroke.plan!.changed.count) tiles; \(stroke.plan!.protected.count) circuit tiles protected. Release to save."
            if phase == .end {
                session.terrainStroke = nil
                _ = applyTerrain(brush: stroke.brush, tiles: stroke.tiles, buildSessionID: session.id)
            }
        } catch { session.terrainStroke = nil; session.status = "Nothing changed: \(error.localizedDescription)" }
        refreshBuildRenderer()
    }

    func buildClick(at point: CGPoint, erase: Bool = false, sessionID: UUID) {
        guard let session = buildSession, session.id == sessionID,
              session.worldID == activeWorldID, session.areaID == library.activeAreaID,
              let tile = session.tile(at: point) else { return }
        session.selectedTile = tile
        if let existing = desktopWorld.circuit.components[tile], [.repeater, .torch].contains(existing.kind) {
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
                session.status = result.message + (next.circuit.components[tile]?.kind == .repeater ? " Use Rotate or Delay to edit this repeater." : (next.circuit.components[tile]?.kind == .torch ? " Use Rotate to edit this torch." : ""))
                playSound(.invalidPlacement, at: tile, mapper: session.mapper)
                return
            }
            session.status = "Placed \(session.tool.rawValue) at (\(tile.x), \(tile.y)). Circuit stopped."
            playSound(.placeCircuit, at: tile, mapper: session.mapper)
        } else { return }
        commitCircuit(next, worldID: session.worldID)
        refreshBuildRenderer()
    }

    func configureBuildFileSensor(at tile: WorldCoordinate, filter: FileSensorFilter) {
        guard let session = buildSession, session.worldID == activeWorldID, session.areaID == library.activeAreaID,
              filter.isValid, desktopWorld.circuit.components[tile]?.kind == .fileSensor else { return }
        var next = desktopWorld; next.circuit.components[tile]?.sensorFilter = filter
        commitCircuit(next, worldID: session.worldID); refreshBuildRenderer()
        session.status = "Sensor filter saved. Circuit stopped."
    }

    func rotateBuildRepeater() {
        guard let session = buildSession else { return }
        session.rotateDirection()
        configureBuildRepeater()
    }

    func setBuildRepeaterDelay(_ delay: RepeaterDelay) {
        guard let session = buildSession else { return }
        if session.selectedTile.flatMap({ desktopWorld.circuit.components[$0]?.kind }) == .torch {
            session.status = "Torch inversion has a fixed 1-redstone-tick delay; Rotate changes its direction."
            return
        }
        session.delay = delay
        configureBuildRepeater()
    }

    /// Keyboard editing targets hover only; never falls back to a previously
    /// selected directional component when the pointer leaves it or moves over another tile.
    func editHoveredBuildRepeater(at tile: WorldCoordinate?, rotate: Bool) {
        guard let session = buildSession else { return }
        guard let tile, tile == session.hoveredTile,
              let component = desktopWorld.circuit.components[tile], [.repeater, .torch].contains(component.kind) else {
            session.status = "Hover a torch/repeater and press R to rotate; T cycles repeater delay."
            return
        }
        guard rotate || component.kind == .repeater else {
            session.status = "Torch inversion has a fixed 1-redstone-tick delay; R rotates it."
            return
        }
        session.selectedTile = tile
        session.direction = component.direction
        session.delay = component.repeaterDelay
        if rotate { session.rotateDirection() }
        else { session.delay = RepeaterDelay(rawValue: component.repeaterDelay.rawValue % 4 + 1)! }
        configureBuildRepeater()
    }

    private func configureBuildRepeater() {
        guard let session = buildSession else { return }
        guard let tile = session.selectedTile, var component = desktopWorld.circuit.components[tile], [.repeater, .torch].contains(component.kind) else {
            session.status = "Next direction: \(session.direction.rawValue), delay \(session.delay.rawValue)."; return
        }
        component.direction = session.direction
        if component.kind == .repeater { component.repeaterDelay = session.delay }
        var next = desktopWorld
        next.circuit.components[tile] = component
        commitCircuit(next, worldID: session.worldID)
        refreshBuildRenderer()
        session.status = component.kind == .torch
            ? "Torch (\(tile.x), \(tile.y)): \(session.direction.rawValue), fixed 1-tick inversion."
            : "Repeater (\(tile.x), \(tile.y)): \(session.direction.rawValue), delay \(session.delay.rawValue)."
    }

    private func desktopLeversDidChange() {
        guard let index = library.worlds.firstIndex(where: { $0.id == activeWorldID }) else { return }
        library.worlds[index].activeLevers = savedLevers
        autosaver?.schedule(library)
    }

    func setDiagnosticOverlays(_ settings: DiagnosticOverlaySettings) {
        diagnosticOverlays = settings
        for controller in desktopControllers { controller.scene.setDiagnosticOverlays(settings) }
        editorDiagnosticScene?.setDiagnosticOverlays(settings)
    }

    /// Freeze only automatic polling. Explicit reads/input/action freshness checks remain authoritative.
    func setFinderPollingFrozen(_ frozen: Bool) {
        guard frozen != isFinderPollingFrozen else { return }
        isFinderPollingFrozen = frozen
        if frozen {
            resumePollingAfterFreeze = desktopItemTracker.isPolling
            desktopItemTracker.stop()
        } else if resumePollingAfterFreeze, (isDesktopWorldEnabled || editorFinderItemsVisible),
                  !isDisplaySettling, finderDiagnostics.permission == .allowed {
            desktopItemTracker.start()
        }
        if !frozen { resumePollingAfterFreeze = false }
    }

    /// Pause retains signal/history but invalidates action work; resuming cannot replay old Output edges.
    func setSimulationPaused(_ paused: Bool) {
        guard isDesktopWorldEnabled, paused != isSimulationPaused else { return }
        isSimulationPaused = paused
        simulationRate = DiagnosticRateMeter()
        if paused {
            desktopSession = UUID()
            activationTask?.cancel(); activationTask = nil; activationPhase = nil
            pendingOutputs = []; pendingInput = nil
        }
        lastActionResult = paused ? "Simulation paused; pending actions cancelled. Inputs wait until Resume." : "Simulation resumed; held Output power is not replayed."
    }

    func finishSetup() {
        guard !isMaintenanceLocked else { return }
        setupCompleted = true; preferences?.set(true, forKey: "setupCompleted")
    }

    func revealBackupsFolder(openFolder: (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        guard !isMaintenanceLocked, let maintenanceStore else {
            backupRevealStatus = "Backups aren’t available in this session."
            return
        }
        do {
            let folder = try maintenanceStore.prepareBackupsFolder()
            guard openFolder(folder) else {
                backupRevealStatus = "Couldn’t open Finder. Your backups folder is at \(folder.path)."
                return
            }
            backupRevealStatus = ""
        } catch {
            backupRevealStatus = "Couldn’t open the backups folder: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func startOver() async -> Bool {
        guard !isMaintenanceLocked, !persistenceBlocked, let maintenanceStore,
              let preferences, let preferencesDomain else {
            maintenanceStatus = "Start Over is unavailable; check library recovery/save status."; return false
        }
        guard autosaver?.flush() ?? true else {
            maintenanceStatus = "Save failed. Nothing reset; use Save Now and retry."; return false
        }
        isMaintenanceLocked = true
        let pendingAction = activationTask
        shutdown()
        await finderDiagnostics.suspendReads()
        await assets.suspendForMaintenance()
        await pendingAction?.value
        let savedPreferences = preferences.persistentDomain(forName: preferencesDomain) ?? [:]
        do {
            let backup = try maintenanceStore.reset(library: library, preferences: savedPreferences,
                clearPreferences: {
                    preferences.removePersistentDomain(forName: preferencesDomain)
                    guard preferences.synchronize() else { throw MaintenanceError(message: "Preference reset could not be synchronized.") }
                }, restorePreferences: {
                    preferences.setPersistentDomain(savedPreferences, forName: preferencesDomain); _ = preferences.synchronize()
                })
            lastBackup = backup
            autosaver?.discard(); autosaver = nil // termination cannot resurrect the old library
            persistenceBlocked = true
            maintenanceStatus = "Reset saved. Backup: \(backup.path). Relaunching stopped into Setup…"
        } catch {
            if FileManager.default.fileExists(atPath: maintenanceStore.backups.appendingPathComponent("reset-in-progress.json").path) {
                persistenceBlocked = true
                autosaver?.discard(); autosaver = nil
                // Interrupted rollback is fail-closed; next startup recovers before any write.
            } else {
                isMaintenanceLocked = false; assets.resumeAfterMaintenance(); finderDiagnostics.resumeReads()
            }
            maintenanceStatus = error.localizedDescription
            return false
        }
        do {
            try await relauncher.relaunch()
            return true // UI terminates this instance only after the new process launches.
        } catch {
            maintenanceStatus = "Reset succeeded; relaunch failed: \(error.localizedDescription) Quit and reopen the app. Backup: \(lastBackup!.path)"
            return false // keep old instance locked and its writer permanently discarded
        }
    }

    @discardableResult
    func importLibrary(_ document: WorldLibraryDocument) -> Bool {
        guard !isMaintenanceLocked, !persistenceBlocked else { return false }
        do {
            let next = try LibraryImport.adding(document, to: library)
            guard autosaver?.commit(next, operation: "Import") ?? true else { libraryStatus = persistenceStatus; return false }
            library = next
            libraryStatus = "Added \(document.worlds.count) world(s). Choose one in the sidebar to explore it."
            return true
        } catch { libraryStatus = "Couldn’t import this library: \(error.localizedDescription)"; return false }
    }

    func saveWorldNow() { autosaver?.flush() }

    /// Used by both disable and the app's termination notification.
    func shutdown(preserveEditorTracking: Bool = false) {
        if !preserveEditorTracking {
            desktopScriptAccessGeneration = UUID()
            if desktopScriptAccessTask != nil { desktopScriptAccessStatus = "Desktop access check cancelled." }
            desktopScriptAccessTask?.cancel(); desktopScriptAccessTask = nil
        }
        exitDesktopBuildMode(restoreEditor: preserveEditorTracking)
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
        activationPhase = nil
        tickScheduler.stop()
        simulationRate = DiagnosticRateMeter()
        simulationTick = 0
        isSimulationPaused = false
        pendingOutputs = []
        pendingInput = nil
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
        closeDesktopRenderers()
        isDesktopWorldEnabled = false
        desktopStatus = "Desktop checker is disabled."
        if preserveEditorTracking { startEditorFinderTrackingIfNeeded() }
        else { editorFinderItemsVisible = false }
    }

    func toggleDesktopWorld() {
        guard !isMaintenanceLocked else { return }
        exitDesktopBuildMode()
        displayChangeMonitor?.start()
        if isDesktopWorldEnabled {
            shutdown(preserveEditorTracking: true)
        } else {
            guard let screen = desktopScreen else {
                desktopStatus = "No main display is available."
                return
            }
            do {
                isSimulationPaused = false
                simulationRate = DiagnosticRateMeter()
                simulationTick = 0
                lastOutputActivation = nil
                simulator = CircuitSimulator(world: desktopWorld.circuit)
                for lever in savedLevers { simulator.toggleLever(at: lever) }
                try installDesktopRenderer(on: screen)
                isDesktopWorldEnabled = true
                if automaticallyRefreshFinder && !isDisplaySettling && !isFinderPollingFrozen && finderDiagnostics.permission != .denied { desktopItemTracker.start() }
                startCircuitTimer()
                lastActionResult = "Desktop running. Use a visible button/lever to power an Output; its current occupant is refreshed before action."
            } catch {
                desktopStatus = "Display geometry cannot be mapped. Desktop checker remains disabled."
            }
        }
    }

    private func closeDesktopRenderers() {
        for controller in desktopControllers { controller.disable(); controller.close() }
        desktopControllers = []; desktopController = nil
    }

    private func installDesktopRenderer(on screen: ScreenDescriptor) throws {
        let canvas = try DesktopCanvas(screens: desktopScreens)
        if let effective = finderScale.camera(saved: library.activeArea!.camera,
            current: finderDiagnostics.viewSettings, frame: canvas.frame), finderScale.enabled { desktopCamera = effective }
        let mapper = try CoordinateMapper(canvasFrame: canvas.frame, camera: desktopCamera)
        for physical in canvas.screens {
            guard !mapper.visibleChunks(on: physical, viewport: CGRect(origin: .zero, size: physical.frame.size)).isEmpty else {
                throw CoordinateMapper.ValidationError.invalidCanvas
            }
        }
        desktopControllers = canvas.screens.map { physical in
            let controller = DesktopWindowController(screen: physical, mapper: mapper)
            controller.scene.setDiagnosticOverlays(diagnosticOverlays)
            controller.scene.setAssets(assets)
            controller.scene.updateWorld(desktopWorld, poweredTiles: simulator.poweredTiles,
                leverPositions: simulator.activeLevers, powerLevels: simulator.power)
            return controller
        }
        desktopController = desktopControllers.first
        finderReferenceScreen = finderReferenceProviding()
        lastObservedGeometry = DisplayGeometry(target: screenProviding(), finderReference: finderReferenceScreen,
            screens: screensProviding?() ?? [])
        if displayGeometry != nil { displayGeometry = lastObservedGeometry }
        updateFinderState(finderDiagnostics.items, error: finderDiagnostics.error, hasRead: finderDiagnostics.hasRead)
        let monitor = PointerMonitor(screens: canvas.screens, mapper: mapper) { [weak self] snapshot in
            guard let self else { return }
            self.pointer = snapshot
            for controller in self.desktopControllers {
                controller.scene.updateHighlight(controller.scene.screen.id == snapshot.screenID ? snapshot.tile : nil)
            }
        }
        pointerMonitor = monitor
        let clicks = DesktopClickMonitor(screens: canvas.screens, mapper: mapper, eventMonitoring: clickEventMonitoring) { [weak self] snapshot in
            guard let self else { return }
            self.lastClick = snapshot; self.observedClickCount += 1
            for controller in self.desktopControllers where controller.scene.screen.contains(snapshot.screenPoint) {
                controller.scene.flashTile(snapshot.tile)
            }
            self.handleCircuitClick(snapshot.tile, identity: snapshot.identity)
        }
        clickMonitor = clicks
        for controller in desktopControllers { controller.enable() }
        monitor.start()
        desktopStatus = clicks.start()
            ? "Desktop enabled on \(canvas.screens.count) display(s), one continuous world."
            : "Desktop enabled, but click observation could not start. Stop and Start to retry."
    }

    /// Geometry changes preserve saved cameras/configuration and the current simulator.
    func displayParametersDidChange() {
        guard !isMaintenanceLocked else { return }
        let next = DisplayGeometry(target: screenProviding(), finderReference: finderReferenceProviding(), screens: screensProviding?() ?? [])
        guard next != lastObservedGeometry else { return }
        exitDesktopBuildMode()
        lastObservedGeometry = next
        displayGeometry = next
        displayRefreshGeneration = UUID()
        let generation = displayRefreshGeneration
        displayRefreshTask?.cancel()
        desktopSession = UUID()
        activationTask?.cancel(); activationTask = nil
        activationPhase = nil
        pendingOutputs = []
        pendingInput = nil
        desktopItemTracker.stop()
        isDisplaySettling = true
        finderDiagnostics.invalidateDisplayPositions()
        finderMappings = []
        desktopOccupancy = .unavailable("Display changed; waiting for fresh Finder positions.")
        pointerMonitor?.stop(); pointerMonitor = nil
        clickMonitor?.stop(); clickMonitor = nil
        pointer = nil; lastClick = nil
        closeDesktopRenderers()
        tickScheduler.stop()
        if isDesktopWorldEnabled {
            do {
                guard next.target != nil, let screen = self.desktopScreen else { throw CoordinateMapper.ValidationError.invalidCanvas }
                let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: desktopCamera)
                guard !mapper.visibleChunks(on: screen, viewport: CGRect(origin: .zero, size: screen.frame.size)).isEmpty else {
                    throw CoordinateMapper.ValidationError.invalidCanvas
                }
                try installDesktopRenderer(on: screen)
                for controller in desktopControllers { controller.scene.updateOccupancy(desktopOccupancy) }
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
                if !self.isFinderPollingFrozen { self.desktopItemTracker.start() }
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
        guard isDesktopWorldEnabled, !isSimulationPaused else { return }
        simulationTick += 1
        simulationRate.record(at: ProcessInfo.processInfo.systemUptime)
        var next = simulator
        next.setDesktopSensors(DesktopSensorInputs.active(in: next.world, occupancy: desktopSensorOccupancy))
        let events = next.advanceTick()
        if !isDisplaySettling && !isFinderLayoutSettling {
            for (id, tile) in CircuitSounds.transitions(before: simulator, after: next) where outputIsVisible(tile) {
                playSound(id, at: tile, mapper: desktopController?.scene.mapper)
            }
        }
        let changedPower = next.power != simulator.power
        if next != simulator { simulator = next }
        if changedPower { for controller in desktopControllers { controller.scene.updateWorld(desktopWorld, poweredTiles: next.poweredTiles, leverPositions: next.activeLevers, powerLevels: next.power) } }
        for case let .outputActivated(coordinate) in events {
            lastOutputActivation = OutputActivationDiagnostic(worldID: activeWorldID, areaID: library.activeAreaID,
                tile: coordinate, power: next.power(at: coordinate), tick: simulationTick)
            guard !isDisplaySettling, !isFinderLayoutSettling, outputIsVisible(coordinate) else { continue }
            for controller in desktopControllers { controller.scene.flashOutput(at: coordinate) }
            playSound(.outputActivate, at: coordinate, mapper: desktopController?.scene.mapper)
            // Bound pending I/O independently of simulation, rather than accumulating requests.
            if pendingOutputs.count < 32 { pendingOutputs.append(coordinate) }
            else { lastActionResult = "Output action queue is full; activation skipped." }
        }
        drainPendingInput()
        drainOutputActions()
    }

    private func outputIsVisible(_ coordinate: WorldCoordinate) -> Bool {
        guard let mapper = desktopController?.scene.mapper else { return false }
        let rect = mapper.screenRect(forTile: coordinate)
        return desktopControllers.contains { $0.scene.screen.contains(CGPoint(x: rect.midX, y: rect.midY)) }
    }

    private func drainOutputActions() {
        guard isDesktopWorldEnabled, !isDisplaySettling, !isFinderLayoutSettling, activationTask == nil, !finderDiagnostics.isReading,
              !pendingOutputs.isEmpty else { return }
        guard finderDiagnostics.permission == .allowed else {
            pendingOutputs = []
            pendingInput = nil
            lastActionResult = "Finder unavailable; output actions skipped."
            return
        }
        let coordinate = pendingOutputs.removeFirst()
        let session = desktopSession
        let worldID = activeWorldID
        let layoutGeneration = finderDiagnostics.layoutGeneration
        let policyGeneration = outputPolicyGeneration
        activationPhase = .outputRead
        activationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.desktopSession == session { self.activationTask = nil; self.activationPhase = nil } }
            let succeeded = await self.finderDiagnostics.readItems()
            guard !Task.isCancelled, self.desktopSession == session, self.finderDiagnostics.layoutGeneration == layoutGeneration, self.activeWorldID == worldID, self.isDesktopWorldEnabled, self.outputPolicyGeneration == policyGeneration else { return }
            guard succeeded else {
                self.pendingOutputs = []
                self.pendingInput = nil
                self.lastActionResult = "Finder could not be refreshed; nothing opened."
                return
            }
            guard self.outputIsVisible(coordinate) else { return }
            let configured = self.desktopWorld.circuit.components[coordinate]?.outputAction ?? .openOccupant
            let mode = self.scriptOutputSettings.action(configured: configured, occupancy: self.desktopOccupancy.state(at: coordinate))
            switch mode {
            case .none: self.lastActionResult = "Output action is disabled."
            case .openOccupant:
                self.lastActionResult = self.openItemAction.perform(occupancy: self.desktopOccupancy.state(at: coordinate))
            case .executeOccupant:
                self.activationPhase = .script
                // Never retain an input to run unexpectedly after a potentially long approval/process.
                self.pendingInput = nil
                self.lastActionResult = "Checking script and waiting for approval…"
                let outcome = await self.executeScriptAction.perform(occupancy: self.desktopOccupancy.state(at: coordinate), isCurrent: {
                    self.desktopSession == session && self.activeWorldID == worldID && self.isDesktopWorldEnabled
                        && self.outputPolicyGeneration == policyGeneration
                        && !self.isDisplaySettling && !self.isFinderLayoutSettling
                        && self.finderDiagnostics.layoutGeneration == layoutGeneration && self.outputIsVisible(coordinate)
                }, refresh: {
                    // A confirmation may remain open while a background poll runs; use the shared read gate.
                    while self.finderDiagnostics.isReading && !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(10))
                    }
                    guard !Task.isCancelled, await self.finderDiagnostics.readItems() else { return .unavailable("Finder refresh failed.") }
                    return self.desktopOccupancy.state(at: coordinate)
                })
                guard !Task.isCancelled, self.desktopSession == session, self.activeWorldID == worldID, self.outputPolicyGeneration == policyGeneration else { return }
                self.lastActionResult = outcome.message
                if let result = outcome.result { self.lastScriptResult = result }
            }
        }
    }

    func handleCircuitClick(_ tile: WorldCoordinate, identity: MouseEventIdentity = MouseEventIdentity()) {
        guard isDesktopWorldEnabled, !isDisplaySettling, !isFinderLayoutSettling, desktopController != nil,
              let kind = desktopWorld.circuit.components[tile]?.kind,
              kind == .button || kind == .lever else { return }
        observedPressCount += 1
        guard !isSimulationPaused else { lastActionResult = "Simulation paused; Resume before using an input."; return }
        let inputTitle = kind == .button ? "PRESS" : "LEVER"
        let assessment = desktopInteractionAssessment(identity)
        lastPressMetadata = assessment.details
        if let reason = assessment.rejectionReason {
            lastActionResult = "\(inputTitle) click received; not activated: \(reason)"
            return
        }
        guard finderDiagnostics.hasRead, finderDiagnostics.permission == .allowed else {
            lastActionResult = automaticallyRefreshFinder
                ? "Finder is connecting or unavailable; wait for refresh, or inspect Finder Diagnostics."
                : "Read Finder Items in Finder Diagnostics before using \(inputTitle)."
            return
        }
        if pendingInput != nil {
            lastActionResult = "An input click is already queued behind the Output refresh."
            return
        }
        if activationTask != nil {
            switch activationPhase {
            case .outputRead:
                if pendingInput == nil {
                    pendingInput = PendingInput(tile: tile, kind: kind, session: desktopSession,
                        worldID: activeWorldID, layoutGeneration: finderDiagnostics.layoutGeneration)
                }
                lastActionResult = "\(inputTitle) click received; waiting for the current Output refresh. One input is queued."
            case .inputRead:
                lastActionResult = "An input click is already being checked; waiting for Finder."
            case .script, .none:
                lastActionResult = "Script approval or execution is busy; use \(inputTitle) again after it finishes."
            }
            return
        }
        startCircuitInput(tile, kind: kind)
    }

    private func drainPendingInput() {
        guard activationTask == nil, let input = pendingInput else { return }
        pendingInput = nil
        guard input.session == desktopSession, input.worldID == activeWorldID,
              input.layoutGeneration == finderDiagnostics.layoutGeneration,
              isDesktopWorldEnabled, !isDisplaySettling, !isFinderLayoutSettling,
              finderDiagnostics.hasRead, finderDiagnostics.permission == .allowed else { return }
        startCircuitInput(input.tile, kind: input.kind)
    }

    private func startCircuitInput(_ tile: WorldCoordinate, kind: CircuitComponentKind) {
        let inputTitle = kind == .button ? "PRESS" : "LEVER"
        lastActionResult = finderDiagnostics.isReading
            ? "\(inputTitle) click received; waiting for Finder refresh…"
            : "\(inputTitle) click received; refreshing Finder items…"
        let session = desktopSession
        let worldID = activeWorldID
        let layoutGeneration = finderDiagnostics.layoutGeneration
        activationPhase = .inputRead
        activationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.desktopSession == session { self.activationTask = nil; self.activationPhase = nil } }
            // Background polling holds the shared read gate for hundreds of milliseconds.
            // Reserve one input task instead of discarding a valid click during that read.
            while self.finderDiagnostics.isReading && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
            }
            guard !Task.isCancelled, self.desktopSession == session,
                  self.activeWorldID == worldID, self.isDesktopWorldEnabled,
                  self.finderDiagnostics.layoutGeneration == layoutGeneration else { return }
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
            for view in desktopControllers { view.scene.updateOccupancy(desktopOccupancy) }
            return
        }
        let mappings = items.map { controller.scene.mapper.finderMapping(for: $0, referenceScreen: reference) }
        if mappings != finderMappings {
            finderMappings = mappings
            for view in desktopControllers { view.scene.updateFinderMarkers(mappings) }
        }
        let snapshot: DesktopOccupancySnapshot
        if let error {
            snapshot = .unavailable(error)
        } else if !hasRead {
            snapshot = .unavailable(isDisplaySettling ? "Display changed; waiting for fresh Finder positions." : "Read Finder Items to resolve occupancy.")
        } else {
            snapshot = DesktopOccupancyResolver().resolve(items: items, mapper: controller.scene.mapper,
                finderReference: reference, activeScreens: desktopControllers.map { $0.scene.screen })
        }
        if snapshot != desktopOccupancy {
            desktopOccupancy = snapshot
            for view in desktopControllers { view.scene.updateOccupancy(snapshot) }
        }
    }

    func setFinderScaleEnabled(_ enabled: Bool) {
        guard !isMaintenanceLocked else { return }
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
        guard !isMaintenanceLocked else { return }
        audioSettings = AudioSettings(volume: settings.volume.isFinite ? min(1, max(0, settings.volume)) : 0,
            muted: settings.muted, effectsEnabled: settings.effectsEnabled)
        soundPlayer.configure(audioSettings)
        if let data = try? JSONEncoder().encode(audioSettings) { preferences?.set(data, forKey: "audioSettings") }
    }

    func previewSound(_ id: SoundID, pan: Float = 0) { guard !isMaintenanceLocked else { return }; playSound(id, pan: pan) }

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
        activationPhase = nil
        pendingOutputs = []
        pendingInput = nil
        tickScheduler.stop()
        pointerMonitor?.stop(); clickMonitor?.stop()
        closeDesktopRenderers()
        do { try installDesktopRenderer(on: screen); startCircuitTimer() }
        catch { isDesktopWorldEnabled = false; desktopStatus = "Scale mapping failed; desktop stopped." }
        lastActionResult = "Desktop scale refreshed; old activations skipped. Use the input again."
    }
}
