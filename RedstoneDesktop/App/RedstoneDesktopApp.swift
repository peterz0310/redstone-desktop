import SwiftUI

@main
struct RedstoneDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppTerminationDelegate.self) private var terminationDelegate
    @State private var appState = AppStartup.state

    var body: some Scene {
        WindowGroup("Redstone Desktop", id: "editor") {
            EditorView(appState: appState)
        }
        .defaultSize(width: 1200, height: 820)
        .commands { DesktopAppCommands(appState: appState) }
        Settings { AppSettingsView(appState: appState) }
        Window("Redstone Desktop Help", id: "help") { AppHelpView() }.defaultSize(width: 680, height: 700)
        Window("Welcome to Redstone Desktop", id: "setup") { SetupWizardView(appState: appState) }
            .windowResizability(.contentSize)
        Window("Desktop Details", id: "desktop-controls") {
            DesktopDetailsView(appState: appState)
        }
        .defaultSize(width: 640, height: 740)
        Window("Appearance & Packs", id: "asset-settings") {
            AssetSettingsView(appState: appState, assets: appState.assets)
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

struct DesktopAppCommands: Commands {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var presentation: MenuPresentation
    init(appState: AppState) { self.appState = appState; presentation = appState.menuPresentation }
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Redstone Desktop Help") {
                appState.exitDesktopBuildMode()
                openWindow(id: "help")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
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
