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
    static func symbol(for name: String) -> String {
        switch name {
        case "Select": "rectangle.dashed"
        case "Move": "cursorarrow"
        case "Terrain": "paintbrush.pointed.fill"
        case "Lamp": "lightbulb.fill"
        case "R. Torch": "bolt.fill"
        case "Torch": "flame.fill"
        case "Plate": "square.stack.3d.down.right.fill"
        case "Sensor": "doc.text.magnifyingglass"
        case "Erase": "eraser.fill"
        case "Button": "circle.inset.filled"
        case "Lever": "switch.2"
        case "Repeater": "arrow.right"
        case "Output": "terminal"
        default: "square"
        }
    }
    var body: some View {
        Group {
            if name == "Dust" {
                Image("MenuLogo").renderingMode(.template).resizable().interpolation(.high).scaledToFit()
            } else { Image(systemName: Self.symbol(for: name)) }
        }.frame(width: 18, height: 18).accessibilityHidden(true)
    }
}
