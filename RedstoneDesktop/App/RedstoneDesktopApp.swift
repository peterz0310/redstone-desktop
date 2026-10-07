import SwiftUI

@main
struct RedstoneDesktopApp: App {
    var body: some Scene {
        WindowGroup("Redstone Desktop") {
            EditorPlaceholderView()
        }
        .defaultSize(width: 640, height: 420)
    }
}
