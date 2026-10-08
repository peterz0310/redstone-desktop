import SwiftUI

@main
struct RedstoneDesktopApp: App {
    @StateObject private var appState = AppStartup.makeState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Redstone Desktop", id: "editor") {
            EditorView(appState: appState)
        }
        .defaultSize(width: 1200, height: 820)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button(appState.isDesktopBuildMode ? "Exit Desktop Build Mode" : "Enter Desktop Build Mode") {
                    if appState.isDesktopBuildMode { appState.exitDesktopBuildMode() }
                    else { appState.enterDesktopBuildMode() }
                }
                Button(appState.isDesktopWorldEnabled ? "Disable Desktop World" : "Enable Desktop World") {
                    appState.toggleDesktopWorld()
                }
                .disabled(appState.isDesktopBuildMode)
            }
        }
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
        MenuBarExtra("Redstone Desktop", systemImage: appState.isDesktopBuildMode ? "hammer.fill" : "square.grid.3x3.fill") {
            Text(appState.isDesktopBuildMode ? "BUILD MODE · Circuit stopped" : "Redstone Desktop")
            Button("Open Editor") { openWindow(id: "editor") }
            Button(appState.isDesktopBuildMode ? "Exit Build Mode" : "Build on Desktop") {
                if appState.isDesktopBuildMode { appState.exitDesktopBuildMode() }
                else { appState.enterDesktopBuildMode() }
            }
            Button("Quit Redstone Desktop") { appState.shutdown(); NSApplication.shared.terminate(nil) }
        }
    }
}

/// Xcode's application test host must never migrate/save the owner's real library.
@MainActor
enum AppStartup {
    static func makeState() -> AppState {
        let environment = ProcessInfo.processInfo.environment
        let testing = NSClassFromString("XCTestCase") != nil
            || environment.keys.contains { $0.hasPrefix("XCTest") || $0 == "XCInjectBundleInto" }
        let assets = AssetLibrary(preferences: testing ? nil : .standard, importCacheRoot: testing ? nil : JavaTextureImporter.applicationCacheRoot)
        if !testing { Task { await assets.restoreSelection() } }
        return AppState(libraryStore: testing ? nil : WorldLibraryStore.applicationDefault(), automaticallyRefreshFinder: !testing,
            preferences: testing ? nil : .standard,
            soundPlayer: testing ? SilentSoundPlayer() : (try? AudioEngine()) ?? SilentSoundPlayer(), assets: assets)
    }
}
