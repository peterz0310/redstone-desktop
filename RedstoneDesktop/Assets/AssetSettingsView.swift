import SwiftUI
import UniformTypeIdentifiers

struct AssetSettingsView: View {
    @ObservedObject var assets: AssetLibrary
    @State private var choosingPack = false

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
        .frame(minWidth: 620, minHeight: 420)
    }
}
