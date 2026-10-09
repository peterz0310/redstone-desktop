import SwiftUI

struct HelpButton: View {
    let title: String
    let text: String
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: { Image(systemName: "questionmark.circle").foregroundStyle(.secondary) }
            .buttonStyle(.plain).help(title).accessibilityLabel("Help: " + title)
            .popover(isPresented: $showing) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(.headline)
                    Text(text).fixedSize(horizontal: false, vertical: true)
                }.padding(20).frame(width: 300)
            }
    }
}

struct ToolIcon: View {
    let name: String
    var body: some View {
        Group {
            if name == "Select" || name == "Navigate" { Image(systemName: "cursorarrow") }
            else if name == "Erase" { Image(systemName: "eraser.fill") }
            else { Image("Tool" + name).renderingMode(.template).resizable().interpolation(.none).scaledToFit() }
        }.frame(width: 18, height: 18).accessibilityHidden(true)
    }
}
