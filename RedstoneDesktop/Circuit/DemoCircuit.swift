/// Explicit feasibility fixture; rendering and simulation consume its model data.
enum DemoCircuit {
    static let button = WorldCoordinate(x: 2, y: 3)
    static let dust = (3...6).map { WorldCoordinate(x: $0, y: 3) }
    static let output = WorldCoordinate(x: 7, y: 3)
    static let lever = WorldCoordinate(x: 2, y: 5)
    static let leverDust = (3...6).map { WorldCoordinate(x: $0, y: 5) }
    static let leverOutput = WorldCoordinate(x: 7, y: 5)

    static let repeaterButton = WorldCoordinate(x: 2, y: 7)
    static let repeaterDust = [WorldCoordinate(x: 3, y: 7), WorldCoordinate(x: 4, y: 7), WorldCoordinate(x: 6, y: 7)]
    static let repeater = WorldCoordinate(x: 5, y: 7)
    static let repeaterOutput = WorldCoordinate(x: 7, y: 7)

    static func makeWorld() -> World {
        var components = Dictionary(uniqueKeysWithValues: (dust + leverDust + repeaterDust).map { ($0, CircuitComponent(kind: .dust)) })
        components[button] = CircuitComponent(kind: .button)
        components[output] = CircuitComponent(kind: .output)
        components[lever] = CircuitComponent(kind: .lever)
        components[leverOutput] = CircuitComponent(kind: .output)
        components[repeaterButton] = CircuitComponent(kind: .button)
        components[repeater] = CircuitComponent(kind: .repeater, direction: .east, repeaterDelay: .four)
        components[repeaterOutput] = CircuitComponent(kind: .output)
        return World(tiles: Dictionary(uniqueKeysWithValues: components.keys.map { ($0, Tile(terrain: .grass)) }),
                     circuit: CircuitWorld(components: components))
    }
}
