import SwiftUI
import UniformTypeIdentifiers

struct AssetSettingsView: View {
    @ObservedObject var assets: AssetLibrary
    @State private var choosingPack = false
    @State private var choosingJava = false
    @State private var selectedVersion: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Make it yours").font(.largeTitle)
                HStack {
                    VStack(alignment: .leading) { Text("Current appearance").font(.caption).foregroundStyle(.secondary); Text(assets.name).font(.headline) }
                    Spacer()
                    Button("Use Original Look") { assets.useBuiltIn() }
                }
                Divider()
                HStack {
                    Text("Minecraft textures & sounds").font(.headline)
                    HelpButton(title: "Textures from your game", text: "If Minecraft Java Edition is installed on this Mac, choose a version below. The app copies supported images and short sound effects to its own cache. Sounds come from the selected version’s local asset cache or the chosen pack. It never runs game code or changes your installation. Missing textures use the original look. Missing sounds use original effects. No downloads are required. Your worlds and circuits stay the same.")
                }
                Text("Bring Minecraft’s textures, particles and supported sound effects into your desktop.").foregroundStyle(.secondary)
                Picker("Minecraft version", selection: $selectedVersion) {
                    Text("Choose a version").tag(Optional<URL>.none)
                    ForEach(assets.installedVersions) { version in Text(version.name).tag(Optional(version.url)) }
                }
                HStack {
                    Button("Use Minecraft Assets") { if let selectedVersion { Task { await assets.importJava(selectedVersion) } } }
                        .buttonStyle(.borderedProminent).disabled(selectedVersion == nil || assets.isLoading)
                    Button("Choose a Texture Pack…") { choosingJava = true }.disabled(assets.isLoading)
                }
                if assets.installedVersions.isEmpty { Text("No installed versions found. You can choose a Java texture pack or game JAR instead.").font(.caption).foregroundStyle(.secondary) }
                if assets.isLoading { ProgressView("Getting your assets ready…") }
                Text(assets.status).font(.caption).textSelection(.enabled)
                DisclosureGroup("More options & custom packs") {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Look for Installed Versions Again") { Task { await discover() } }
                        Text(assets.discoveryStatus).font(.caption)
                        Divider()
                        HStack {
                            Text("Redstone Desktop packs").font(.headline)
                            HelpButton(title: "Custom packs", text: "These are packs made specifically for Redstone Desktop, with a pack.json file, PNG textures and optional WAV effects. For normal Minecraft packs, use Choose a Texture Pack above. See docs/RESOURCE_PACKS.md in the source repository if you want to make your own.")
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
        .fileImporter(isPresented: $choosingJava, allowedContentTypes: [UTType(filenameExtension: "jar") ?? .archive, .zip, .folder], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first { Task { await assets.importJava(url) } }
        }
        .task { await discover() }
        .frame(minWidth: 620, minHeight: 420)
    }
    private func discover() async {
        await assets.discoverJava()
        if selectedVersion == nil || !assets.installedVersions.contains(where: { $0.url == selectedVersion }) { selectedVersion = assets.installedVersions.first?.url }
    }
}
