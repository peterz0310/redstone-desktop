import SwiftUI

struct EditorPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Redstone Desktop")
                .font(.largeTitle)
            Text("Experimental macOS desktop world")
                .font(.title3)
                .foregroundStyle(.secondary)
            Divider()
            Text("Editor placeholder")
                .font(.headline)
            Text("The native app foundation is ready. Desktop rendering, Finder integration, and circuits will be added in roadmap order.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text("Slice 0 · Repository bootstrap")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 320)
    }
}
