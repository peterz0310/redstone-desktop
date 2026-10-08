import SwiftUI
import UniformTypeIdentifiers

struct AssetSettingsView: View {
    @ObservedObject var assets: AssetLibrary
    @State private var choosingPack = false
    @State private var choosingJava = false
    @State private var selectedVersion: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Appearance & Packs").font(.largeTitle)
                Text(assets.name).font(.headline)
                Text(assets.status).textSelection(.enabled)
                Text("Custom packs can replace individual textures or sounds. Everything else keeps the original built-in appearance. Changing packs does not change worlds, cameras or circuits.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Choose Pack Folder or ZIP…") { choosingPack = true }
                    Button("Reload") { if let source = assets.source { Task { await assets.load(source) } } }
                        .disabled(assets.source == nil || assets.isLoading)
                    Button("Use Built-In") { assets.useBuiltIn() }
                }
                if assets.isLoading { ProgressView() }
                if let source = assets.source { Text(source.path).font(.caption).textSelection(.enabled) }
                Text("Format: pack.json with formatVersion 1, name and an assets dictionary. Textures are PNG; short effects are WAV. Packs are data only.")
                    .font(.callout)
                Divider()
                Text("Local Minecraft Java textures").font(.headline)
                Text("Use an installed Java version JAR or Java texture-pack folder/ZIP. Only supported PNG textures are imported; game code and audio are ignored. Imported images stay on this Mac, outside the repository.")
                    .foregroundStyle(.secondary)
                Text(assets.discoveryStatus).font(.caption)
                HStack {
                    Picker("Installed version", selection: $selectedVersion) {
                        Text("Select a version").tag(Optional<URL>.none)
                        ForEach(assets.installedVersions) { version in Text(version.name).tag(Optional(version.url)) }
                    }
                    Button("Import Selected") { if let selectedVersion { Task { await assets.importJava(selectedVersion) } } }
                        .disabled(selectedVersion == nil || assets.isLoading)
                }
                HStack {
                    Button("Find Installed Versions") { Task { await assets.discoverJava() } }
                    Button("Choose Java JAR / Pack…") { choosingJava = true }
                        .disabled(assets.isLoading)
                }
                HStack {
                    Button("Re-import") { Task { await assets.reimportJava() } }.disabled(assets.importRecord == nil || assets.isLoading)
                    Button("Reveal Import Cache") {
                        if let folder = assets.importFolder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    }.disabled(assets.importFolder == nil)
                    Button("Remove Imported Assets", role: .destructive) { assets.removeImportedAssets() }
                        .disabled(assets.importFolder == nil || assets.isLoading)
                }
                if let record = assets.importRecord {
                    Text("Last import source: \(record.sourcePath)\n\(record.mappings.count) supported mappings · first-frame textures with fixed tint and 2D circuit art. Re-import updates older cached mappings.")
                        .font(.caption).textSelection(.enabled)
                }
                if !assets.warnings.isEmpty {
                    DisclosureGroup("Pack diagnostics (\(assets.warnings.count))") {
                        ForEach(Array(assets.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning).font(.caption).textSelection(.enabled)
                        }
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
        .task { await assets.discoverJava() }
        .frame(minWidth: 620, minHeight: 420)
    }
}
