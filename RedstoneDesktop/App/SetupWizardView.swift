import SwiftUI

struct SetupWizardView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var finder: FinderDiagnosticsModel
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    init(appState: AppState, initialPage: Int = 0) {
        self.appState = appState; finder = appState.finderDiagnostics
        _page = State(initialValue: min(Self.pageTitles.count - 1, max(0, initialPage)))
    }
    static let pageTitles = ["Welcome to Redstone Desktop", "Connect your desktop", "Choose your look", "Want to run scripts?", "You’re ready to build"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image("AppLogo").resizable().frame(width: 48, height: 48).accessibilityHidden(true)
                Text(Self.pageTitles[page]).font(.largeTitle)
            }
            Text("Step \(page + 1) of \(Self.pageTitles.count)").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
            switch page {
            case 0:
                Text("Build circuits underneath your desktop files. A button can open a folder, launch a file, or run a script you choose.")
                Text("Keep different builds in separate worlds. Save your favorite places as areas, then choose which area appears on your desktop.")
            case 1:
                Text("Your files stay right where they are. Connect to Finder so a circuit can find the file or folder sitting on its Output block.")
                Button("Connect to Finder…") { Task { await finder.readItems() } }.disabled(finder.isReading)
                Text("Finder: \(finder.permission.rawValue)\(finder.error.map { " · " + $0 } ?? "")").font(.callout)
                Text("Your Mac may ask for permission to connect to Finder. You can skip this for now and connect when you start Desktop.").font(.caption).foregroundStyle(.secondary)
            case 2:
                JavaAssetImportView(assets: appState.assets)
                Text("This step is optional. You can change your look anytime in Settings → Appearance.").font(.caption).foregroundStyle(.secondary)
            case 3:
                Text("Outputs open files and folders by default. If you also want to run shell scripts, you can enable that later in Settings → Outputs.")
                Text("Only run scripts you trust. The app asks before running a new or changed script, and can remember your choice.")
                Button("Allow Access to Desktop Scripts…") { appState.requestDesktopScriptAccess(retry: true) }
                    .disabled(appState.desktopScriptAccessTask != nil)
                Text(appState.desktopScriptAccessStatus).font(.caption)
                Text("This step is optional. Allowing access here won’t run anything.").font(.caption).foregroundStyle(.secondary)
            default:
                Text("Try a simple circuit: place a button, connect it to an Output with dust, and put a folder on the Output. Start Desktop, then press your button!")
                Text("You can change textures, sounds and visual effects in Settings → Appearance. Your worlds and circuits stay the same.")
            }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("You can revisit setup anytime from Settings. Your Mac’s permissions are managed in System Settings.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Skip Setup") { finish() }
                Spacer()
                if page > 0 { Button("Back") { page -= 1 } }
                Button(page == Self.pageTitles.count - 1 ? "Let’s Build" : "Next") { if page == Self.pageTitles.count - 1 { finish() } else { page += 1 } }
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 600, height: 430)
        .disabled(appState.isMaintenanceLocked)
        .onAppear { MaintenanceSmokeConfiguration.report("wizard", state: appState) }
    }
    private func finish() { appState.finishSetup(); dismiss() }
}
