import SwiftUI

@main
struct RedstoneDesktopApp: App {
    @StateObject private var appState = AppStartup.makeState()

    var body: some Scene {
        WindowGroup("Redstone Desktop") {
            EditorView(appState: appState)
        }
        .defaultSize(width: 1200, height: 820)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button(appState.isDesktopWorldEnabled ? "Disable Desktop World" : "Enable Desktop World") {
                    appState.toggleDesktopWorld()
                }
            }
        }
        Window("Desktop Details", id: "desktop-controls") {
            DesktopDetailsView(appState: appState)
        }
        .defaultSize(width: 640, height: 740)
        Window("Finder Diagnostics", id: "finder-diagnostics") {
            FinderDiagnosticsView(appState: appState)
        }
        .defaultSize(width: 1200, height: 550)
    }
}

/// Xcode's application test host must never migrate/save the owner's real library.
@MainActor
enum AppStartup {
    static func makeState() -> AppState {
        let environment = ProcessInfo.processInfo.environment
        let testing = NSClassFromString("XCTestCase") != nil
            || environment.keys.contains { $0.hasPrefix("XCTest") || $0 == "XCInjectBundleInto" }
        return AppState(libraryStore: testing ? nil : WorldLibraryStore.applicationDefault(), automaticallyRefreshFinder: !testing,
            preferences: testing ? nil : .standard,
            soundPlayer: testing ? SilentSoundPlayer() : (try? AudioEngine()) ?? SilentSoundPlayer())
    }
}
