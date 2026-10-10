/// Shared user-facing descriptions for editor and desktop build tools.
enum ToolDescriptions {
    static let move = "Click a component to inspect it, or drag to move around the map. Scroll or pinch to zoom."
    static let select = "Drag a box around components. Shift-click adds or removes one; copy, move or rotate the group."
    static let erase = "Remove a circuit component while keeping its ground and decorations. Undo brings it back."
    static let terrain = "Paint ground, clear decorations or restore original terrain. Drag to preview, release to save, Escape to cancel."
    static func component(_ kind: CircuitComponentKind) -> String {
        switch kind {
        case .button: "A press sends a brief power pulse. Connect it to dust or a repeater to trigger an Output."
        case .lever: "A switch that holds power until you turn it off. Useful for enabling circuits and clocks."
        case .dust: "Carries power between neighboring components. Longer wire runs gradually lose signal strength."
        case .repeater: "Delays the signal and restores full power. Its arrow points forward; it accepts power only from behind."
        case .torch: "An inverter: on when its rear input is off, and off when that input is powered. Its arrow points forward."
        case .output: "Opens or runs the desktop item on its tile when power first turns on. Choose Do Nothing for a visual-only circuit."
        case .pressurePlate: "Holds power while any Finder item occupies its tile. Move the item away to turn it off."
        case .fileSensor: "Holds power when a desktop item matches its name or extension filter. Configure it in the Inspector."
        case .empty: "Choose a component to build."
        }
    }
}
