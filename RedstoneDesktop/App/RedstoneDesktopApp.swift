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
                    appState.setDesktopRunning(!appState.isDesktopWorldEnabled)
                }
                .disabled(appState.isDesktopBuildMode)
            }
        }
        Settings { AppSettingsView(appState: appState) }
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
            Image("MenuDust").renderingMode(.template)
                .accessibilityLabel("Redstone Desktop, \(appState.desktopMenu.status)")
                .help("Redstone Desktop · \(appState.desktopMenu.status)")
        }
        .menuBarExtraStyle(.menu)
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
        return AppState(desktopScriptAccess: testing ? nil : DesktopScriptAccess.applicationDefault(),
            libraryStore: testing ? nil : WorldLibraryStore.applicationDefault(), automaticallyRefreshFinder: !testing,
            preferences: testing ? nil : .standard,
            soundPlayer: testing ? SilentSoundPlayer() : (try? AudioEngine()) ?? SilentSoundPlayer(), assets: assets)
    }
}
