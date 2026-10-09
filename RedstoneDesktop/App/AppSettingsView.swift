import SwiftUI
import UniformTypeIdentifiers

struct AppSettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var confirmingReset = false
    @State private var exporting = false
    @State private var exportDocument: LibraryExportDocument?
    @State private var exportStatus = ""

    var body: some View {
        TabView {
            Form {
                Section("Setup and permissions") {
                    Button("Open Setup…") { openWindow(id: "setup") }
                    Text("Finder Automation reads desktop icon positions. Desktop-folder access reads chosen scripts. Script approval is separate; Accessibility is not required.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Finder Diagnostics…") { openWindow(id: "finder-diagnostics") }
                }
                Section("Optional Finder scale") {
                    Toggle("Synchronize desktop scale to Finder icon size", isOn: Binding(
                        get: { appState.finderScale.enabled }, set: { appState.setFinderScaleEnabled($0) }))
                    Text(appState.finderScaleStatus).font(.caption)
                    Text("Off by default. Enable after Finder connects. Uses the logical canvas center; saved areas and editor zoom remain independent. Turning off restores the saved camera.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }
            Form {
                Section("Sound effects") {
                    Toggle("Enable sound effects", isOn: audioBinding(\.effectsEnabled))
                    Toggle("Mute", isOn: audioBinding(\.muted))
                    Slider(value: audioBinding(\.volume), in: 0...1) { Text("Volume") }
                    Text("Volume: \(Int(appState.audioSettings.volume * 100))%")
                    HStack {
                        Button("Preview Left") { appState.previewSound(.buttonPress, pan: -1) }
                        Button("Center") { appState.previewSound(.buttonPress) }
                        Button("Right") { appState.previewSound(.buttonPress, pan: 1) }
                    }
                    Menu("Preview Effects") { ForEach(SoundID.allCases, id: \.self) { id in Button(id.rawValue) { appState.previewSound(id) } } }
                    Text(appState.audioStatus).font(.caption)
                    Text("Effects use one bounded audio engine. Mute stops active voices; offscreen events are silent.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            AssetSettingsView(assets: appState.assets).tabItem { Label("Appearance", systemImage: "paintpalette") }
            scriptSettings.tabItem { Label("Outputs", systemImage: "terminal") }
            Form {
                Section("Export and recovery") {
                    Button("Export Library…") {
                        exportDocument = LibraryExportDocument(library: appState.library); exporting = true
                    }
                    Text("Exports all worlds, bookmarks, circuits and lever positions as validated JSON. Finder data, scripts, approvals and imported art are excluded.").font(.caption).foregroundStyle(.secondary)
                    if !exportStatus.isEmpty { Text(exportStatus).font(.caption).textSelection(.enabled) }
                    if let backup = appState.lastBackup {
                        Button("Reveal Reset Backup") { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
                    } else {
                        Button("Reveal Backups Folder") { NSWorkspace.shared.open(URL.applicationSupportDirectory.appendingPathComponent("RedstoneDesktopBackups")) }
                    }
                }
                Section("Start over") {
                    Button("Start Over…", role: .destructive) { confirmingReset = true }
                    Text("Creates a timestamped recovery backup, resets app saves/settings/approvals/import caches, and restarts into Setup. Desktop files, source packs/JARs and macOS privacy permissions remain untouched.").font(.caption).foregroundStyle(.secondary)
                    Text(appState.maintenanceStatus).font(.caption).textSelection(.enabled)
                }
            }.formStyle(.grouped).tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .padding(12).frame(width: 700, height: 600)
        .disabled(appState.isMaintenanceLocked)
        .overlay(alignment: .bottom) {
            if appState.isMaintenanceLocked {
                VStack { Text(appState.maintenanceStatus).textSelection(.enabled); Button("Quit") { appState.shutdown(); NSApplication.shared.terminate(nil) } }
                    .padding().background(.regularMaterial)
            }
        }
        .alert("Start Over and Restart?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Back Up, Reset and Restart", role: .destructive) {
                Task { if await appState.startOver() { NSApplication.shared.terminate(nil) } }
            }
        } message: {
            Text("Back up all worlds/areas/circuits, the legacy save, app preferences/approvals and managed imported textures. Then replace app data with one empty world and default settings. macOS permissions and your Desktop files/source packs stay unchanged. Backup/staging failures abort the reset. See README recovery instructions to restore a backup.")
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "RedstoneDesktop-library") { result in
            switch result { case .success: exportStatus = "Library exported."; case .failure(let error): exportStatus = "Export failed: \(error.localizedDescription)" }
        }
    }
    private func audioBinding<Value>(_ key: WritableKeyPath<AudioSettings, Value>) -> Binding<Value> {
        Binding(get: { appState.audioSettings[keyPath: key] }, set: { value in
            var settings = appState.audioSettings; settings[keyPath: key] = value; appState.setAudioSettings(settings)
        })
    }
    private var scriptSettings: some View {
        Form {
            Section("Output behavior") {
                Toggle("Run supported scripts; open other items", isOn: Binding(
                    get: { appState.scriptOutputSettings.runScriptsOpenOtherItems }, set: { appState.setRunScriptsOpenOtherItems($0) }))
                Text("Applies to Default Outputs: .sh, .command and .zsh use exact-file approval; other items open. Explicit Execute stays script-only and None stays disabled. Remembering starts checked; changed files ask again.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Forget Script Approvals") { appState.actionAuthorizations.revokeAll() }
            }
            Section("Desktop-folder access") {
                Text(appState.desktopScriptAccessStatus).font(.callout).textSelection(.enabled)
                Button("Check Desktop Access…") { appState.requestDesktopScriptAccess(retry: true) }.disabled(appState.desktopScriptAccessTask != nil)
                Text("Only explicit script opt-in/checks request this access. macOS chooses prompt timing and remembers privacy decisions across Start Over. Finder Automation and per-script approval are separate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
