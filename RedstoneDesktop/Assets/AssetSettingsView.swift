import SwiftUI
import UniformTypeIdentifiers

struct AssetSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var assets: AssetLibrary
    @State private var choosingPack = false

    private func visualBinding(_ key: WritableKeyPath<VisualSettings, Bool>) -> Binding<Bool> {
        Binding(get: { appState.visualSettings[keyPath: key] }, set: { value in
            var settings = appState.visualSettings
            settings[keyPath: key] = value
            appState.setVisualSettings(settings)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Make it yours").font(.largeTitle)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Animation & effects").font(.headline)
                    Toggle("Animate water and lava", isOn: visualBinding(\.liquidAnimations))
                    Toggle("Subtle scenery shimmer", isOn: visualBinding(\.sceneryAnimations))
                    Toggle("Show particles", isOn: visualBinding(\.particles))
                    Text("Particles add tiny flames, smoke, lava pops and redstone sparks. These settings apply to every world, in the editor and on your Desktop.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Your Mac’s Reduce Motion setting pauses these effects. Daylight and local lighting are controlled separately in World Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    VStack(alignment: .leading) { Text("Current appearance").font(.caption).foregroundStyle(.secondary); Text(assets.name).font(.headline) }
                    Spacer()
                    Button("Use Original Look") { assets.useBuiltIn() }
                }
                Divider()
                JavaAssetImportView(assets: assets)
                DisclosureGroup("More options & custom packs") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Redstone Desktop packs").font(.headline)
                            HelpButton(title: "Custom packs", text: "These are packs made specifically for Redstone Desktop, with a pack.json file, PNG textures and optional WAV effects. For normal Minecraft packs, use Choose a Texture Pack above. Use Original Look to return to the built-in textures and sounds.")
                        }
                        Button("Choose Custom Pack Folder or ZIP…") { choosingPack = true }
                        Button("Reload Current Pack") { if let source = assets.source { Task { await assets.load(source) } } }.disabled(assets.source == nil || assets.isLoading)
                        Button("Refresh Imported Minecraft Assets") { Task { await assets.reimportJava() } }.disabled(assets.importRecord == nil || assets.isLoading)
                        Button("Show Imported Textures in Finder") { if let folder = assets.importFolder { NSWorkspace.shared.activateFileViewerSelecting([folder]) } }.disabled(assets.importFolder == nil)
                        Button("Remove Imported Textures", role: .destructive) { assets.removeImportedAssets() }.disabled(assets.importFolder == nil || assets.isLoading)
                        if let source = assets.source { Text(source.path).font(.caption).textSelection(.enabled) }
                        if let record = assets.importRecord { Text("Imported from: \(record.sourcePath)").font(.caption).textSelection(.enabled) }
                    }.padding(.top, 10)
                }
                if !assets.warnings.isEmpty {
                    DisclosureGroup("Import details (\(assets.warnings.count))") {
                        ForEach(Array(assets.warnings.enumerated()), id: \.offset) { _, warning in Text(warning).font(.caption).textSelection(.enabled) }
                    }
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileImporter(isPresented: $choosingPack, allowedContentTypes: [.folder, .zip], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first { Task { await assets.load(url) } }
        }
        .frame(minWidth: 620, minHeight: 420)
    }
}
