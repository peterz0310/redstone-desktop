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
                HelpButton(title: "Textures from your game", text: "Downloaded Minecraft Java versions in the usual Minecraft folder appear automatically. Use Refresh after installing or launching a version. For another launcher location, use Choose a Texture Pack or JAR. Redstone Desktop copies supported textures and short sounds without changing your installation or running game code. Missing assets use the original look and sounds.")
            }
            Text("Have Minecraft Java Edition? Bring its look and sounds into your desktop. Or keep the original artwork — no game installation is needed.")
                .foregroundStyle(.secondary)
            HStack {
                Picker("Minecraft version", selection: $selectedVersion) {
                    Text("Choose a version").tag(Optional<URL>.none)
                    ForEach(assets.installedVersions) { version in Text(version.name).tag(Optional(version.url)) }
                }.disabled(assets.isDiscoveringJava || assets.isLoading)
                Button("Refresh") { Task { await assets.discoverJava() } }
                    .disabled(assets.isDiscoveringJava || assets.isLoading)
                    .help("Look again for downloaded Minecraft Java versions.")
            }
            HStack {
                Button("Use Minecraft Assets") {
                    if let selectedVersion { Task { await assets.importJava(selectedVersion) } }
                }.buttonStyle(.borderedProminent).disabled(selectedVersion == nil || assets.isLoading || assets.isDiscoveringJava)
                Button("Choose a Texture Pack or JAR…") { choosingJava = true }.disabled(assets.isLoading)
            }
            if assets.isDiscoveringJava {
                ProgressView("Looking for installed versions…").controlSize(.small)
            } else if !assets.discoveryStatus.isEmpty {
                Text(assets.discoveryStatus).font(.caption).foregroundStyle(.secondary)
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
