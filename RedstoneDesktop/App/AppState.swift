import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var isDesktopWorldEnabled = false
    @Published private(set) var desktopStatus = "Desktop checker is disabled."
    @Published private(set) var pointer: PointerSnapshot?
    @Published private(set) var lastClick: DesktopClickSnapshot?
    @Published private(set) var observedClickCount = 0
    let desktopCamera = CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64)
    let finderDiagnostics: FinderDiagnosticsModel
    let desktopItemTracker: DesktopItemTracker
    @Published private(set) var finderMappings: [FinderItemMapping] = []
    @Published private(set) var desktopOccupancy: DesktopOccupancySnapshot = .unavailable("Enable Desktop World to resolve occupancy.")
    @Published private(set) var observedPressCount = 0
    @Published private(set) var testCircuit = FixedTestCircuit()
    @Published private(set) var lastActionResult = "Place a harmless Finder item on OUTPUT, then click PRESS on the desktop."
    private let openItemAction: OpenItemAction
    private var circuitTimer: Timer?
    private(set) var activationTask: Task<Void, Never>?
    private let desktopInteractionRejection: (CGPoint) -> String?
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
       desktopInteractionRejection: @escaping (CGPoint) -> String? = { DesktopInteractionGate.rejectionReason($0) },
       itemOpener: any ItemOpening = WorkspaceItemOpener(),
       finderReferenceProviding: @escaping () -> ScreenDescriptor? = {
           NSScreen.screens.first.map { ScreenDescriptor(screen: $0) }
       }) {
        self.desktopInteractionRejection = desktopInteractionRejection
        openItemAction = OpenItemAction(opener: itemOpener)
        self.screenProviding = screenProviding
        self.clickEventMonitoring = clickEventMonitoring
        self.finderDiagnostics = finderDiagnostics
        self.finderReferenceProviding = finderReferenceProviding
        desktopItemTracker = DesktopItemTracker(diagnostics: finderDiagnostics)
        finderItemsObserver = Publishers.CombineLatest3(finderDiagnostics.$items, finderDiagnostics.$error, finderDiagnostics.$hasRead).sink { [weak self] items, error, hasRead in
            MainActor.assumeIsolated { self?.updateFinderState(items, error: error, hasRead: hasRead) }
        }
        terminationObserver = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.shutdown() }
            }
    }

    /// Used by both disable and the app's termination notification.
    func shutdown() {
        desktopSession = UUID()
        activationTask?.cancel()
        circuitTimer?.invalidate()
        circuitTimer = nil
        observedPressCount = 0
        testCircuit = FixedTestCircuit()
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
                controller.scene.updateTestCircuit(testCircuit)
                finderReferenceScreen = finderReferenceProviding()
                updateFinderState(finderDiagnostics.items, error: finderDiagnostics.error, hasRead: finderDiagnostics.hasRead)
                pointerMonitor = monitor
                let clicks = DesktopClickMonitor(screen: screen, mapper: mapper, eventMonitoring: clickEventMonitoring) { [weak self, weak controller] snapshot in
                    guard let self else { return }
                    self.lastClick = snapshot
                    self.observedClickCount += 1
                    controller?.scene.flashTile(snapshot.tile)
                    self.handleCircuitClick(snapshot.tile, atScreen: snapshot.screenPoint)
                }
                clickMonitor = clicks
                controller.enable()
                monitor.start()
                isDesktopWorldEnabled = true
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
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.desktopSession == session else { return }
                self.advanceCircuitTick()
            }
        }
        circuitTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // Internal for deterministic integration tests; production cadence is the timer above.
    func advanceCircuitTick() {
        guard testCircuit.isPowered else { return }
        var next = testCircuit
        next.advanceTick()
        let changedPower = next.isPowered != testCircuit.isPowered
        testCircuit = next
        if changedPower { desktopController?.scene.updateTestCircuit(next) }
    }

    func handleCircuitClick(_ tile: WorldCoordinate, atScreen point: CGPoint? = nil) {
        guard isDesktopWorldEnabled, tile == FixedTestCircuit.button, let controller = desktopController else { return }
        let rect = controller.scene.mapper.screenRect(forTile: tile)
        let clickPoint = point ?? CGPoint(x: rect.midX, y: rect.midY)
        observedPressCount += 1
        if let reason = desktopInteractionRejection(clickPoint) {
            lastActionResult = "PRESS click received; not activated: \(reason)"
            return
        }
        guard activationTask == nil, !finderDiagnostics.isReading else {
            lastActionResult = "Finder is busy; click PRESS again after the read finishes."
            return
        }
        guard finderDiagnostics.hasRead, finderDiagnostics.permission == .allowed else {
            lastActionResult = "Read Finder Items in Finder Diagnostics before using PRESS."
            return
        }
        lastActionResult = "PRESS click received; refreshing Finder items…"
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
                self.lastActionResult = "Finder item is on or near PRESS; move it away to use the circuit."
                return
            }
            let events = self.testCircuit.press(at: tile)
            controller.scene.updateTestCircuit(self.testCircuit)
            guard !events.isEmpty else {
                self.lastActionResult = "Pulse extended; output opens once per rising activation."
                return
            }
            controller.scene.flashOutput()
            self.lastActionResult = self.openItemAction.perform(
                occupancy: self.desktopOccupancy.state(at: FixedTestCircuit.output))
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
