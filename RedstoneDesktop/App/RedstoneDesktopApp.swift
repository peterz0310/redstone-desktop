import SwiftUI

@main
struct RedstoneDesktopApp: App {
    @StateObject private var appState = AppState(worldStore: WorldStore.applicationDefault(), automaticallyRefreshFinder: true)

    var body: some Scene {
        WindowGroup("Redstone Desktop") {
            EditorView(appState: appState)
        }
        .defaultSize(width: 1200, height: 760)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button(appState.isDesktopWorldEnabled ? "Disable Desktop World" : "Enable Desktop World") {
                    appState.toggleDesktopWorld()
                }
            }
        }
        Window("Desktop Controls", id: "desktop-controls") {
            EditorPlaceholderView(appState: appState)
        }
        .defaultSize(width: 640, height: 740)
        Window("Developer Placement", id: "developer-placement") {
            DeveloperPlacementView(appState: appState)
        }
        .defaultSize(width: 560, height: 660)
        Window("Finder Diagnostics", id: "finder-diagnostics") {
            FinderDiagnosticsView(appState: appState)
        }
        .defaultSize(width: 1200, height: 550)
    }
}
