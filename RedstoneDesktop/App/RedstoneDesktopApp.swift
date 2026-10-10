import SwiftUI

@main
struct RedstoneDesktopApp: App {
    @State private var appState = AppStartup.makeState()

    var body: some Scene {
        WindowGroup("Redstone Desktop", id: "editor") {
            EditorView(appState: appState)
        }
        .defaultSize(width: 1200, height: 820)
        .commands { DesktopAppCommands(appState: appState) }
        Settings { AppSettingsView(appState: appState) }
        Window("Welcome to Redstone Desktop", id: "setup") { SetupWizardView(appState: appState) }
            .windowResizability(.contentSize)
        Window("Desktop Details", id: "desktop-controls") {
            DesktopDetailsView(appState: appState)
        }
        .defaultSize(width: 640, height: 740)
        Window("Appearance & Packs", id: "asset-settings") {
            AssetSettingsView(assets: appState.assets)
        }.defaultSize(width: 660, height: 650)
        Window("Finder Diagnostics", id: "finder-diagnostics") {
            FinderDiagnosticsView(appState: appState)
        }
        .defaultSize(width: 1200, height: 550)
        MenuBarExtra {
            DesktopMenuView(appState: appState)
        } label: {
            MenuBarIdentityLabel()
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Xcode's application test host must never migrate/save the owner's real library.
@MainActor
enum AppStartup {
    static func makeState() -> AppState {
        let environment = ProcessInfo.processInfo.environment
        if environment["REDSTONE_DESKTOP_DATA_ROOT"] != nil || environment["REDSTONE_DESKTOP_PREFERENCES_SUITE"] != nil {
            precondition(MaintenanceSmokeConfiguration.settings != nil, "Invalid smoke isolation configuration; owner store will not be opened.")
        }
        let testing = NSClassFromString("XCTestCase") != nil
            || environment.keys.contains { $0.hasPrefix("XCTest") || $0 == "XCInjectBundleInto" }
        if !testing, let smoke = MaintenanceSmokeConfiguration.settings, let prefs = UserDefaults(suiteName: smoke.domain) {
            let store = WorldLibraryStore(fileURL: smoke.root.appendingPathComponent("library.json"), legacyFileURL: smoke.root.appendingPathComponent("world.json"))
            let state = AppState(libraryStore: store, preferences: prefs, soundPlayer: SilentSoundPlayer(),
                assets: AssetLibrary(preferences: prefs, importCacheRoot: smoke.root.appendingPathComponent("ImportedTextures")),
                blueprintStore: CircuitBlueprintStore(fileURL: smoke.root.appendingPathComponent("blueprints.json")),
                maintenanceStore: LibraryMaintenanceStore(root: smoke.root, backups: smoke.root.deletingLastPathComponent().appendingPathComponent("Backups")),
                preferencesDomain: smoke.domain)
            MaintenanceSmokeConfiguration.report("startup", state: state)
            return state
        }
        let assets = AssetLibrary(preferences: testing ? nil : .standard, importCacheRoot: testing ? nil : JavaTextureImporter.applicationCacheRoot)
        if !testing { Task { await assets.restoreSelection() } }
        return AppState(desktopScriptAccess: testing ? nil : DesktopScriptAccess.applicationDefault(),
            libraryStore: testing ? nil : WorldLibraryStore.applicationDefault(), automaticallyRefreshFinder: !testing,
            preferences: testing ? nil : .standard,
            soundPlayer: testing ? SilentSoundPlayer() : (try? AudioEngine()) ?? SilentSoundPlayer(), assets: assets,
            blueprintStore: testing ? nil : CircuitBlueprintStore.applicationDefault(),
            maintenanceStore: testing ? nil : .applicationDefault(),
            preferencesDomain: testing ? nil : Bundle.main.bundleIdentifier,
            screensProviding: testing ? nil : { NSScreen.screens.map { ScreenDescriptor(screen: $0) } })
    }
}


struct DesktopAppCommands: Commands {
    let appState: AppState
    @ObservedObject private var presentation: MenuPresentation
    init(appState: AppState) { self.appState = appState; presentation = appState.menuPresentation }
    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button(presentation.snapshot.building ? "Exit Build Mode" : "Build on Desktop") {
                if presentation.snapshot.building { appState.exitDesktopBuildMode() } else { appState.enterDesktopBuildMode() }
            }.disabled(presentation.snapshot.locked)
            Button(presentation.snapshot.running ? "Stop Desktop" : "Start Desktop") {
                appState.setDesktopRunning(!presentation.snapshot.running)
            }.disabled(presentation.snapshot.building || presentation.snapshot.locked)
        }
    }
}
