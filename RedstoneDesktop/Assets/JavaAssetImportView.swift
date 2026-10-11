import SwiftUI
import UniformTypeIdentifiers

/// The same optional, explicit import flow is available during setup and in Settings.
struct JavaAssetImportView: View {
    @ObservedObject var assets: AssetLibrary
    @State private var choosingJava = false
    @State private var selectedVersion: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Minecraft textures & sounds").font(.headline)
                HelpButton(title: "Textures from your game", text: "Choose an installed Minecraft Java Edition version or a Java texture pack. Redstone Desktop copies supported textures, particles and short sounds into its own cache. It never runs game code or changes your installation. Missing assets use the original look and sounds. Nothing is downloaded.")
            }
            Text("Have Minecraft Java Edition? Bring its look and sounds into your desktop. Or keep the original artwork — no game installation is needed.")
                .foregroundStyle(.secondary)
            Picker("Minecraft version", selection: $selectedVersion) {
                Text("Choose a version").tag(Optional<URL>.none)
                ForEach(assets.installedVersions) { version in Text(version.name).tag(Optional(version.url)) }
            }
            HStack {
                Button("Use Minecraft Assets") {
                    if let selectedVersion { Task { await assets.importJava(selectedVersion) } }
                }.buttonStyle(.borderedProminent).disabled(selectedVersion == nil || assets.isLoading)
                Button("Choose a Texture Pack or JAR…") { choosingJava = true }.disabled(assets.isLoading)
            }
            if assets.installedVersions.isEmpty {
                Text("No installed versions found. You can choose a Java texture pack or game JAR instead, or come back later.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if assets.isLoading { ProgressView("Getting your assets ready…") }
            Text(assets.status).font(.caption).textSelection(.enabled)
        }
        .fileImporter(isPresented: $choosingJava,
            allowedContentTypes: [UTType(filenameExtension: "jar") ?? .archive, .zip, .folder],
            allowsMultipleSelection: false) { result in
                if case let .success(urls) = result, let url = urls.first { Task { await assets.importJava(url) } }
            }
        .task { await assets.discoverJava(); selectAvailableVersion() }
        .onChange(of: assets.installedVersions.map(\.url)) { _, _ in selectAvailableVersion() }
    }

    private func selectAvailableVersion() {
        if !assets.installedVersions.contains(where: { $0.url == selectedVersion }) {
            selectedVersion = assets.installedVersions.first?.url
        }
    }
}
