import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import RedstoneDesktop

private final class MenuStore: WorldLibraryStoring {
    var document: WorldLibraryDocument? = try! WorldLibraryDocument(legacy: LegacyWorldDocument())
    var fails = false
    var saves = 0
    func load() throws -> WorldLibraryDocument? { document }
    func save(_ document: WorldLibraryDocument) throws {
        if fails { throw WorldStoreError.invalidDocument("Fixture write failure") }
        try document.validate(); self.document = document; saves += 1
    }
}

@MainActor
private final class MenuProvider: DesktopItemProviding {
    var calls = 0
    var wait = false
    var continuation: CheckedContinuation<[DesktopItem], any Error>?
    func currentDesktopItems() async throws -> [DesktopItem] {
        calls += 1
        if wait { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return []
    }
}

@MainActor
private final class MenuBuildPresenter: DesktopBuildPresenting {
    var closes = 0
    func show() {}
    func update(world: World, levers: Set<WorldCoordinate>, assets: AssetLibrary) {}
    func close() { closes += 1 }
}

final class DesktopMenuTests: XCTestCase {
    @MainActor
    private func app(store: MenuStore = MenuStore(), provider: MenuProvider = MenuProvider(),
                     opener: FixtureItemOpener = FixtureItemOpener(), presenter: MenuBuildPresenter = MenuBuildPresenter(),
                     available: Bool = true) -> AppState {
        let screen = ScreenDescriptor(id: "menu", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backingScale: 1)
        return AppState(screenProviding: { available ? screen : nil }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "Fixture") },
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener, libraryStore: store,
            autosaveDelay: .seconds(3600), buildControllerFactory: { _, _, _ in presenter }, finderReferenceProviding: { screen })
    }

    @MainActor
    func testAssignedIdentityAndCheckmarksAreIndependentOfBrowsing() throws {
        let state = app(); defer { state.shutdown() }
        let active = state.library.activeAreaID, world = state.activeWorldName
        XCTAssertTrue(state.createWorld(name: "Elsewhere", generation: WorldGenerationSettings(seed: 42)))
        let menu = state.desktopMenu
        XCTAssertEqual(menu.assignedWorld, world)
        XCTAssertEqual(menu.assignedArea, state.library.activeArea?.name)
        XCTAssertNotEqual(state.selectedAreaID, active)
        XCTAssertEqual(menu.groups.flatMap(\.areas).filter(\.assigned).map(\.id), [active])
        XCTAssertEqual(menu.status, "Stopped")
        state.setDesktopRunning(true)
        XCTAssertEqual(state.desktopMenu.status, "Running")
        state.setSimulationPaused(true)
        XCTAssertEqual(state.desktopMenu.status, "Running · Simulation paused")
    }

    @MainActor
    func testDuplicateWorldAndAreaNamesHaveDistinctLabelsAndStableIDs() throws {
        let state = app(); defer { state.shutdown() }
        let name = state.selectedDocument.name
        XCTAssertTrue(state.saveArea(name: state.selectedArea.name, camera: SavedArea.homeCamera))
        XCTAssertTrue(state.createWorld(name: name, generation: WorldGenerationSettings(seed: 42)))
        let groups = state.desktopMenu.groups
        XCTAssertEqual(Set(groups.map(\.title)).count, 2)
        XCTAssertEqual(Set(groups[0].areas.map(\.title)).count, 2)
        XCTAssertEqual(groups.flatMap(\.areas).map(\.id), state.library.areas.map(\.id))
        XCTAssertEqual(groups.flatMap(\.areas).filter(\.assigned).count, 1)
    }

    @MainActor
    func testMenuAssignmentResumesAndPreservesEditorCameraAndWorldOwnership() throws {
        let state = app(), editor = EditorSession(); defer { state.shutdown() }
        let target = state.library.activeAreaID
        XCTAssertTrue(state.createWorld(name: "Editor", generation: WorldGenerationSettings(seed: 42)))
        editor.syncSelectedWorld(state)
        editor.pan(by: CGSize(width: -400, height: -100), size: editor.viewport)
        let camera = editor.camera, selected = state.selectedAreaID, world = state.editorWorld
        state.setDesktopRunning(true)
        XCTAssertTrue(state.assignDesktopAreaFromMenu(target))
        XCTAssertTrue(state.isDesktopWorldEnabled)
        XCTAssertEqual(state.selectedAreaID, selected)
        XCTAssertEqual(editor.camera, camera)
        XCTAssertEqual(state.editorWorld, world)
        XCTAssertEqual(state.library.activeAreaID, target)
        XCTAssertFalse(state.areaStatus.contains("Start Desktop"))
    }

    @MainActor
    func testAssignmentResumesTargetDocumentInsteadOfBrowsedDocumentAndRelaunchesStopped() throws {
        let store = MenuStore(), state = app(store: store); defer { state.shutdown() }
        let original = state.selectedAreaID
        XCTAssertTrue(state.createWorld(name: "Target", generation: WorldGenerationSettings(seed: 42)))
        let target = state.selectedAreaID, targetWorld = state.editorWorld
        XCTAssertTrue(state.selectArea(original))
        state.setDesktopRunning(true)
        XCTAssertTrue(state.assignDesktopAreaFromMenu(target))
        XCTAssertEqual(state.desktopWorld, targetWorld)
        XCTAssertEqual(state.selectedAreaID, original)
        XCTAssertTrue(state.isDesktopWorldEnabled)
        let restored = app(store: store); defer { restored.shutdown() }
        XCTAssertEqual(restored.library.activeAreaID, target)
        XCTAssertFalse(restored.isDesktopWorldEnabled)
    }

    @MainActor
    func testMenuAssignmentWhileStoppedDoesNotStartDesktop() {
        let state = app(); defer { state.shutdown() }
        XCTAssertTrue(state.saveArea(name: "East", camera: CameraState(worldOrigin: WorldPoint(x: 20, y: 0), pointsPerTile: 64)))
        let target = state.selectedAreaID
        XCTAssertTrue(state.assignDesktopAreaFromMenu(target))
        XCTAssertEqual(state.library.activeAreaID, target)
        XCTAssertFalse(state.isDesktopWorldEnabled)
    }

    @MainActor
    func testFailedSaveOrMissingAreaPreservesRunningAssignment() throws {
        let store = MenuStore(), state = app(store: store); defer { state.shutdown() }
        XCTAssertTrue(state.saveArea(name: "East", camera: CameraState(worldOrigin: WorldPoint(x: 20, y: 0), pointsPerTile: 64)))
        let target = state.selectedAreaID, original = state.library.activeAreaID
        state.setDesktopRunning(true)
        let simulator = state.simulator, camera = state.desktopCamera
        store.fails = true
        XCTAssertFalse(state.assignDesktopAreaFromMenu(target))
        XCTAssertFalse(state.assignDesktopAreaFromMenu(UUID()))
        XCTAssertEqual(state.library.activeAreaID, original)
        XCTAssertEqual(state.simulator, simulator)
        XCTAssertEqual(state.desktopCamera, camera)
        XCTAssertTrue(state.isDesktopWorldEnabled)
    }

    @MainActor
    func testBuildConflictsAndRevealExitUseExistingTeardown() throws {
        let presenter = MenuBuildPresenter(), state = app(presenter: presenter); defer { state.shutdown() }
        let area = state.library.activeAreaID
        XCTAssertTrue(state.enterDesktopBuildMode())
        XCTAssertEqual(state.desktopMenu.status, "Build Mode · Circuit stopped")
        XCTAssertFalse(state.canAssignDesktopArea)
        state.setDesktopRunning(true)
        XCTAssertFalse(state.isDesktopWorldEnabled)
        XCTAssertFalse(state.assignDesktopAreaFromMenu(area))
        state.requestAssignedAreaInEditor()
        XCTAssertFalse(state.isDesktopBuildMode)
        XCTAssertEqual(presenter.closes, 1)
        XCTAssertTrue(state.consumeEditorAreaRequest())
        XCTAssertFalse(state.consumeEditorAreaRequest())
        XCTAssertFalse(state.isDesktopWorldEnabled)
    }

    @MainActor
    func testLifecycleCommandsAreIdempotentAndUnavailableDisplayIsSafe() throws {
        let state = app(); defer { state.shutdown() }
        state.setDesktopRunning(true)
        let runtime = state.simulator
        state.setDesktopRunning(true)
        XCTAssertEqual(state.simulator, runtime)
        XCTAssertTrue(state.isDesktopWorldEnabled)
        state.setDesktopRunning(false); state.setDesktopRunning(false)
        XCTAssertFalse(state.isDesktopWorldEnabled)
        let unavailable = app(available: false); defer { unavailable.shutdown() }
        XCTAssertFalse(unavailable.canAssignDesktopArea)
        XCTAssertFalse(unavailable.assignDesktopAreaFromMenu(unavailable.library.activeAreaID))
        unavailable.setDesktopRunning(true)
        XCTAssertFalse(unavailable.isDesktopWorldEnabled)
    }

    @MainActor
    func testMuteSharesSettingsWithoutChangingVolumeOrEffects() {
        let state = app(); defer { state.shutdown() }
        let settings = AudioSettings(volume: 0.73, muted: false, effectsEnabled: false)
        state.setAudioSettings(settings)
        state.toggleAudioMute()
        XCTAssertEqual(state.audioSettings, AudioSettings(volume: 0.73, muted: true, effectsEnabled: false))
        state.toggleAudioMute()
        XCTAssertEqual(state.audioSettings, settings)
    }

    @MainActor
    func testNativeMenuConstructionAndSnapshotDoNotReadStartSaveOrOpen() async throws {
        let store = MenuStore(), provider = MenuProvider(), opener = FixtureItemOpener()
        let state = app(store: store, provider: provider, opener: opener); defer { state.shutdown() }
        let library = state.library, saves = store.saves
        let host = NSHostingView(rootView: DesktopMenuView(appState: state))
        host.frame = CGRect(x: 0, y: 0, width: 500, height: 900); host.layoutSubtreeIfNeeded()
        for _ in 0..<10 { _ = state.desktopMenu; await Task.yield() }
        XCTAssertEqual(provider.calls, 0)
        XCTAssertEqual(store.saves, saves)
        XCTAssertEqual(state.library, library)
        XCTAssertFalse(state.isDesktopWorldEnabled)
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertNil(state.desktopScriptAccessTask)
        XCTAssertEqual(state.finderDiagnostics.permission, .notRequested)
    }

    @MainActor
    func testAssignmentCancelsPendingFinderInputWithoutReplayingAfterRestart() async throws {
        let provider = MenuProvider(), opener = FixtureItemOpener(), state = app(provider: provider, opener: opener)
        defer { state.shutdown() }
        await state.finderDiagnostics.readItems()
        state.setDesktopRunning(true)
        provider.wait = true
        state.handleCircuitClick(DemoCircuit.button)
        let pending = state.activationTask
        for _ in 0..<1000 { if provider.continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(provider.continuation)
        guard let continuation = provider.continuation else { return }
        XCTAssertTrue(state.assignDesktopAreaFromMenu(state.library.activeAreaID))
        XCTAssertNil(state.activationTask)
        provider.wait = false; provider.continuation = nil; continuation.resume(returning: [])
        await pending?.value
        state.setDesktopRunning(true)
        for _ in 0..<8 { state.advanceCircuitTick() }
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertEqual(state.simulator.power(at: DemoCircuit.button), .off)
        XCTAssertEqual(state.simulator.power(at: DemoCircuit.output), .off)
    }

    @MainActor
    func testMenuIdentityRemainsExactlyEighteenPointsAcrossRuntimeStates() throws {
        let state = app(); defer { state.shutdown() }
        let host = NSHostingView(rootView: MenuBarIdentityLabel())
        func assertSize() {
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize, NSSize(width: 18, height: 18))
        }
        XCTAssertEqual(state.desktopMenu.status, "Stopped"); assertSize()
        state.setDesktopRunning(true)
        XCTAssertEqual(state.desktopMenu.status, "Running"); assertSize()
        state.setSimulationPaused(true)
        XCTAssertEqual(state.desktopMenu.status, "Running · Simulation paused"); assertSize()
        XCTAssertTrue(state.enterDesktopBuildMode())
        XCTAssertEqual(state.desktopMenu.status, "Build Mode · Circuit stopped"); assertSize()
        state.exitDesktopBuildMode(); assertSize()
    }

    @MainActor
    func testOwnerLogoIsPreservedAndTemplateFitsItsAlphaSilhouette() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("RedstoneDesktop/Resources/Assets.xcassets/Logo.imageset/logo.png")
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hash, "2e2cc646437e3d992546e5b32df44ac12d1908875c1d10a15e847febf321f533", "Owner-provided source must remain unchanged")
        let source = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(source.pixelsWide, 1254); XCTAssertEqual(source.pixelsHigh, 1254)
        let logo = try XCTUnwrap(NSImage(data: data))
        let cropped = AppIdentityArtwork.trimmedLogo(logo)
        XCTAssertEqual(cropped.size.width, 828); XCTAssertEqual(cropped.size.height, 491)
        let template = AppIdentityArtwork.image(pixels: 128, template: true, logo: logo)
        XCTAssertTrue(template.isTemplate)
        let rendered = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(template.tiffRepresentation)))
        var opaque = 0
        for y in 0..<128 { for x in 0..<128 {
            let color = try XCTUnwrap(rendered.colorAt(x: x, y: y))
            if color.alphaComponent > 0.01 {
                opaque += 1
                XCTAssertEqual(color.redComponent, 0); XCTAssertEqual(color.greenComponent, 0); XCTAssertEqual(color.blueComponent, 0)
            }
        } }
        XCTAssertGreaterThan(opaque, 2000); XCTAssertLessThan(opaque, 9000)
        XCTAssertEqual(rendered.colorAt(x: 0, y: 0)?.alphaComponent, 0)
        XCTAssertGreaterThan(rendered.colorAt(x: 64, y: 64)?.alphaComponent ?? 0, 0)
    }

    @MainActor
    func testNativeIconCatalogSizesTemplateAndCompiledBundleMetadata() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RedstoneDesktop/Resources/Assets.xcassets")
        let app = root.appendingPathComponent("AppLogo.imageset")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: app.appendingPathComponent("Contents.json"))) as? [String: Any])
        let entries = try XCTUnwrap(json["images"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries.filter { $0["appearances"] != nil }.count, 2)
        for entry in entries {
            let factor = try XCTUnwrap(Int(try XCTUnwrap(entry["scale"] as? String).dropLast()))
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: app.appendingPathComponent(try XCTUnwrap(entry["filename"] as? String)))))
            XCTAssertEqual(bitmap.pixelsWide, 256 * factor); XCTAssertEqual(bitmap.pixelsHigh, 256 * factor)
        }
        let native = root.deletingLastPathComponent().appendingPathComponent("AppIcon.icon")
        let composition = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: native.appendingPathComponent("icon.json"))) as? [String: Any])
        let fills = try XCTUnwrap(composition["fill-specializations"] as? [[String: String]])
        XCTAssertEqual(fills.first { $0["appearance"] == nil }?["value"], "system-light")
        XCTAssertEqual(fills.first { $0["appearance"] == "dark" }?["value"], "system-dark")
        XCTAssertEqual((composition["supported-platforms"] as? [String: [String]])?["squares"], ["macOS"])
        let foreground = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: native.appendingPathComponent("Assets/logo.png"))))
        XCTAssertEqual(foreground.pixelsWide, 1024); XCTAssertEqual(foreground.pixelsHigh, 1024)
        XCTAssertEqual(foreground.colorAt(x: 512, y: 32)?.alphaComponent, 0, "System supplies the icon background")
        let menu = root.appendingPathComponent("MenuLogo.imageset")
        let templateJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: menu.appendingPathComponent("Contents.json"))) as? [String: Any])
        XCTAssertEqual((templateJSON["properties"] as? [String: String])?["template-rendering-intent"], "template")
        for factor in [1, 2] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: menu.appendingPathComponent("logo-\(factor)x.png"))))
            XCTAssertEqual(bitmap.pixelsWide, 18 * factor); XCTAssertEqual(bitmap.pixelsHigh, 18 * factor)
            XCTAssertEqual(bitmap.colorAt(x: 0, y: 0)?.alphaComponent, 0)
            XCTAssertGreaterThan(bitmap.colorAt(x: 9 * factor, y: 9 * factor)?.alphaComponent ?? 0, 0)
        }
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIcon")
        XCTAssertNotNil(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
        XCTAssertNotNil(NSImage(named: "MenuLogo"))
    }
    @MainActor
    func testLightAndDarkIdentityChangeOnlyBackgroundAndKeepLogoCentered() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RedstoneDesktop/Resources/Assets.xcassets/Logo.imageset/logo.png")
        let logo = try XCTUnwrap(NSImage(contentsOf: source))
        func bitmap(_ appearance: AppIdentityArtwork.Appearance) throws -> NSBitmapImageRep {
            let image = AppIdentityArtwork.image(pixels: 128, template: false, logo: logo, appearance: appearance)
            return try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        }
        let light = try bitmap(.light), dark = try bitmap(.dark)
        XCTAssertGreaterThan(light.colorAt(x: 64, y: 15)!.redComponent, 0.9)
        XCTAssertLessThan(dark.colorAt(x: 64, y: 15)!.redComponent, 0.25)
        for image in [light, dark] {
            XCTAssertEqual(image.colorAt(x: 0, y: 0)?.alphaComponent, 0)
            XCTAssertGreaterThan(image.colorAt(x: 64, y: 64)!.redComponent, 0.5)
        }
        let lightCenter = try XCTUnwrap(light.colorAt(x: 64, y: 64))
        let darkCenter = try XCTUnwrap(dark.colorAt(x: 64, y: 64))
        // Resampling translucent source edges blends slightly with the plate beneath them.
        XCTAssertEqual(lightCenter.redComponent, darkCenter.redComponent, accuracy: 0.01)
        XCTAssertEqual(lightCenter.greenComponent, darkCenter.greenComponent, accuracy: 0.01)
        XCTAssertEqual(lightCenter.blueComponent, darkCenter.blueComponent, accuracy: 0.01)
    }

}
