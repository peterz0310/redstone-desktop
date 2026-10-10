import SwiftUI

struct TerrainBrushControls: View {
    @Binding var brush: TerrainBrush
    @Binding var size: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Terrain brush").font(.headline)
                HelpButton(title: "Shaping your world", text: "Paint ground to make space for circuits, clear decorations without changing the surface, or restore the original terrain. Drag to preview and release to save one undo step. Circuit components are preserved; tiles that would no longer support them are skipped. Escape cancels an unfinished stroke.")
            }
            Picker("Paint", selection: $brush) {
                ForEach(TerrainBrush.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Brush size", selection: $size) {
                ForEach([1, 3, 5], id: \.self) { Text("\($0) × \($0)").tag($0) }
            }.pickerStyle(.segmented)
            Text("Drag to paint. Orange tiles protect existing circuits.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
