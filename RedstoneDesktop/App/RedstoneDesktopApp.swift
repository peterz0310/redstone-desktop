import SwiftUI

@main
struct RedstoneDesktopApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Redstone Desktop") {
            EditorPlaceholderView(appState: appState)
        }
        .defaultSize(width: 640, height: 420)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button(appState.isDesktopWorldEnabled ? "Disable Desktop World" : "Enable Desktop World") {
                    appState.toggleDesktopWorld()
                }
            }
        }
    }
}
