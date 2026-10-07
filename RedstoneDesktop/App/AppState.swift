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
    private(set) var desktopCamera = CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64)
    @Published private(set) var persistenceStatus = "Persistence is disabled for this session."
    private var document = WorldDocument()
    private var savedLevers: Set<WorldCoordinate> = []
    private var autosaver: WorldAutosaver?
    var canSaveWorld: Bool { autosaver != nil }
    let finderDiagnostics: FinderDiagnosticsModel
    let desktopItemTracker: DesktopItemTracker
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
    private var desktopController: DesktopWindowController?
    private var pointerMonitor: PointerMonitor?
    private var clickMonitor: DesktopClickMonitor?
    private var terminationObserver: AnyCancellable?
    private let screenProviding: () -> ScreenDescriptor?
    private let clickEventMonitoring: any GlobalMouseEventMonitoring
    private var finderItemsObserver: AnyCancellable?
    private var finderReferenceScreen: ScreenDescriptor?
    private let finderReferenceProviding: () -> ScreenDescriptor?

    init(screenProviding: @escaping () -> ScreenDescriptor? = {
        NSScreen.main.map { ScreenDescriptor(screen: $0) }
    }, clickEventMonitoring: any GlobalMouseEventMonitoring = AppKitGlobalMouseEventMonitor(),
       finderDiagnostics: FinderDiagnosticsModel = FinderDiagnosticsModel(),
       desktopInteractionAssessment: @escaping (MouseEventIdentity) -> DesktopInteractionAssessment = { DesktopInteractionGate.assess($0) },
       tickScheduler: any CircuitTickScheduling = CircuitTickScheduler(),
       itemOpener: any ItemOpening = WorkspaceItemOpener(),
       worldStore: (any WorldStoring)? = nil,
       automaticallyRefreshFinder: Bool = false,
       autosaveDelay: Duration = .milliseconds(750),
       finderReferenceProviding: @escaping () -> ScreenDescriptor? = {
           NSScreen.screens.first.map { ScreenDescriptor(screen: $0) }
       }) {
        self.automaticallyRefreshFinder = automaticallyRefreshFinder
        self.tickScheduler = tickScheduler
        self.desktopInteractionAssessment = desktopInteractionAssessment
        openItemAction = OpenItemAction(opener: itemOpener)
        self.screenProviding = screenProviding
        self.clickEventMonitoring = clickEventMonitoring
        self.finderDiagnostics = finderDiagnostics
        self.finderReferenceProviding = finderReferenceProviding
        desktopItemTracker = DesktopItemTracker(diagnostics: finderDiagnostics)
        finderItemsObserver = Publishers.CombineLatest3(finderDiagnostics.$items, finderDiagnostics.$error, finderDiagnostics.$hasRead).sink { [weak self] items, error, hasRead in
            MainActor.assumeIsolated { self?.updateFinderState(items, error: error, hasRead: hasRead) }
        }
        simulator = CircuitSimulator(world: desktopWorld.circuit)
        if let worldStore {
            do {
                if let restored = try worldStore.load() {
                    desktopWorld = try restored.restoredWorld()
                    desktopCamera = restored.camera
                    document = restored
                    savedLevers = restored.activeLevers
                    persistenceStatus = "World restored. Desktop World starts disabled."
                } else {
                    desktopWorld = try document.restoredWorld()
                    persistenceStatus = "New world. Edits will autosave."
                }
                simulator = CircuitSimulator(world: desktopWorld.circuit)
                autosaver = WorldAutosaver(store: worldStore, delay: autosaveDelay) { [weak self] in self?.persistenceStatus = $0 }
            } catch {
                persistenceStatus = "Could not restore world: \(error.localizedDescription) Saved file preserved; autosave disabled. Repair or move the file before reopening."
            }
        }
        terminationObserver = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.shutdown() }
            }
    }

    func developerPlacementPreview(_ component: CircuitComponent, at coordinate: WorldCoordinate) -> PlacementResult {
        guard !isDesktopWorldEnabled else { return .rejected(.reserved) }
        return circuitPlacement.rules.canPlace(component: component, at: coordinate, in: desktopWorld)
    }

    @discardableResult
    func placeDeveloperComponent(_ component: CircuitComponent, at coordinate: WorldCoordinate) -> PlacementResult {
        placeCircuitComponent(component, at: coordinate)
    }

    @discardableResult
    func placeCircuitComponent(_ component: CircuitComponent, at coordinate: WorldCoordinate) -> PlacementResult {
        guard !isDesktopWorldEnabled else {
            developerPlacementStatus = "Disable Desktop World before editing."
            return .rejected(.reserved)
        }
        var next = desktopWorld
        let result = circuitPlacement.place(component, at: coordinate, in: &next)
        if result.isAllowed {
            desktopWorld = next
            simulator = CircuitSimulator(world: next.circuit)
            worldDidChange()
            developerPlacementStatus = "Placed \(component.kind.rawValue) at (\(coordinate.x), \(coordinate.y)). Enable Desktop World to view it."
        } else { developerPlacementStatus = result.message }
        return result
    }

    @discardableResult
    func eraseCircuitComponent(at coordinate: WorldCoordinate) -> Bool {
        guard !isDesktopWorldEnabled else {
            developerPlacementStatus = "Disable Desktop World before editing."
            return false
        }
        guard desktopWorld.circuit.components[coordinate] != nil else {
            developerPlacementStatus = "No component at (\(coordinate.x), \(coordinate.y))."
            return false
        }
        var next = desktopWorld
        next.circuit.components.removeValue(forKey: coordinate)
        desktopWorld = next
        simulator = CircuitSimulator(world: next.circuit)
        worldDidChange()
        developerPlacementStatus = "Erased component at (\(coordinate.x), \(coordinate.y)); terrain preserved."
        return true
    }

    @discardableResult
    func configureRepeater(at coordinate: WorldCoordinate, direction: Direction, delay: RepeaterDelay) -> Bool {
        guard !isDesktopWorldEnabled else {
            developerPlacementStatus = "Disable Desktop World before editing."
            return false
        }
        guard var component = desktopWorld.circuit.components[coordinate], component.kind == .repeater else {
            developerPlacementStatus = "Select a repeater to change its direction or delay."
            return false
        }
        component.direction = direction
        component.repeaterDelay = delay
        var next = desktopWorld
        next.circuit.components[coordinate] = component
        desktopWorld = next
        simulator = CircuitSimulator(world: next.circuit)
        worldDidChange()
        developerPlacementStatus = "Repeater updated at (\(coordinate.x), \(coordinate.y))."
        return true
    }

    func resetDeveloperPlacements() {
        guard !isDesktopWorldEnabled else {
            developerPlacementStatus = "Disable Desktop World before editing."
            return
        }
        var next = desktopWorld
        for target in DeveloperPlacementFixture.targets { next.circuit.components.removeValue(forKey: target.coordinate) }
        desktopWorld = next
        simulator = CircuitSimulator(world: next.circuit)
        worldDidChange()
        developerPlacementStatus = "Test placements reset; original circuits and terrain preserved."
    }

    private func worldDidChange() {
        savedLevers = savedLevers.filter { desktopWorld.circuit.components[$0]?.kind == .lever }
        document.camera = desktopCamera
        document.circuit = desktopWorld.circuit
        document.activeLevers = savedLevers
        autosaver?.schedule(document)
    }

    func saveWorldNow() { autosaver?.flush() }

    /// Used by both disable and the app's termination notification.
    func shutdown() {
        saveWorldNow()
        desktopSession = UUID()
        activationTask?.cancel()
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
    }

    func toggleDesktopWorld() {
        if isDesktopWorldEnabled {
            shutdown()
        } else {
            guard let screen = screenProviding() else {
                desktopStatus = "No main display is available."
                return
            }
            do {
                let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: desktopCamera)
                let controller = DesktopWindowController(screen: screen, mapper: mapper)
                let monitor = PointerMonitor(screen: screen, mapper: mapper) { [weak self, weak controller] snapshot in
                    self?.pointer = snapshot
                    controller?.scene.updateHighlight(snapshot.tile)
                }
                desktopController = controller
                // Durable lever positions resume only after explicitly enabling the world.
                simulator = CircuitSimulator(world: desktopWorld.circuit)
                for lever in savedLevers { simulator.toggleLever(at: lever) }
                controller.scene.updateWorld(desktopWorld, poweredTiles: simulator.poweredTiles)
                finderReferenceScreen = finderReferenceProviding()
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
                isDesktopWorldEnabled = true
                if automaticallyRefreshFinder && finderDiagnostics.permission != .denied { desktopItemTracker.start() }
                startCircuitTimer()
                lastActionResult = "Place a harmless Finder item on OUTPUT (7, 3), then click PRESS (2, 3)."
                desktopStatus = clicks.start()
                    ? "Desktop checker is enabled. Click the desktop to flash a tile."
                    : "Desktop checker is enabled, but click observation could not start. Disable and re-enable to retry."
            } catch {
                desktopStatus = "Display geometry cannot be mapped. Desktop checker remains disabled."
            }
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
        let changedPower = next.power != simulator.power
        if next != simulator { simulator = next }
        if changedPower { desktopController?.scene.updateWorld(desktopWorld, poweredTiles: next.poweredTiles) }
        for case let .outputActivated(coordinate) in events {
            desktopController?.scene.flashOutput(at: coordinate)
            // Bound pending I/O independently of simulation, rather than accumulating requests.
            if pendingOutputs.count < 32 { pendingOutputs.append(coordinate) }
            else { lastActionResult = "Output action queue is full; activation skipped." }
        }
        drainOutputActions()
    }

    private func drainOutputActions() {
        guard isDesktopWorldEnabled, activationTask == nil, !finderDiagnostics.isReading,
              !pendingOutputs.isEmpty else { return }
        guard finderDiagnostics.permission == .allowed else {
            pendingOutputs = []
            lastActionResult = "Finder unavailable; output actions skipped."
            return
        }
        let coordinate = pendingOutputs.removeFirst()
        let session = desktopSession
        activationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.activationTask = nil }
            let succeeded = await self.finderDiagnostics.readItems()
            guard !Task.isCancelled, self.desktopSession == session, self.isDesktopWorldEnabled else { return }
            guard succeeded else {
                self.pendingOutputs = []
                self.lastActionResult = "Finder could not be refreshed; nothing opened."
                return
            }
            self.lastActionResult = self.openItemAction.perform(occupancy: self.desktopOccupancy.state(at: coordinate))
        }
    }

    func handleCircuitClick(_ tile: WorldCoordinate, identity: MouseEventIdentity = MouseEventIdentity()) {
        guard isDesktopWorldEnabled, desktopController != nil,
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
        activationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.activationTask = nil }
            let succeeded = await self.finderDiagnostics.readItems()
            guard !Task.isCancelled, self.desktopSession == session,
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
                self.lastActionResult = "Button pulse queued; repeats extend it without another rising activation."
            } else {
                self.simulator.toggleLever(at: tile)
                self.savedLevers = self.simulator.activeLevers
                self.worldDidChange()
                self.lastActionResult = self.simulator.activeLevers.contains(tile)
                    ? "Lever on; power updates on the next tick." : "Lever off; power updates on the next tick."
            }
        }
    }

    private func updateFinderState(_ items: [DesktopItem], error: String?, hasRead: Bool) {
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
            snapshot = .unavailable("Read Finder Items to resolve occupancy.")
        } else {
            snapshot = DesktopOccupancyResolver().resolve(items: items, mapper: controller.scene.mapper,
                finderReference: reference, activeScreen: controller.scene.screen)
        }
        if snapshot != desktopOccupancy {
            desktopOccupancy = snapshot
            controller.scene.updateOccupancy(snapshot)
        }
    }
}
