import Combine
import Foundation

/// Local editing state. No simulator, Finder provider, renderer or action executor.
@MainActor
final class DesktopBuildSession: ObservableObject {
    enum Tool: String, CaseIterable {
        case dust = "Dust", button = "Button", lever = "Lever"
        case repeater = "Repeater", output = "Output", erase = "Erase", torch = "R. Torch", pressurePlate = "Plate", fileSensor = "Sensor", terrain = "Terrain", lamp = "Lamp", lightTorch = "Torch"

        var description: String { kind.map(ToolDescriptions.component) ?? (self == .terrain ? ToolDescriptions.terrain : ToolDescriptions.erase) }
        var kind: CircuitComponentKind? {
            switch self {
            case .dust: .dust
            case .button: .button
            case .lever: .lever
            case .pressurePlate: .pressurePlate
            case .fileSensor: .fileSensor
            case .lamp: .lamp
            case .lightTorch: .lightTorch
            case .torch: .torch
            case .repeater: .repeater
            case .output: .output
            case .erase, .terrain: nil
            }
        }
    }

    let id = UUID()
    let worldID: UUID
    let areaID: UUID
    let mapper: CoordinateMapper
    let title: String
    @Published var tool = Tool.dust { didSet { if tool != oldValue { dustStroke = nil } } }
    @Published var terrainBrush = TerrainBrush.grass
    @Published var terrainBrushSize = 3
    @Published var dustStroke: DustStroke?
    @Published var terrainStroke: TerrainStroke?
    @Published var sensorFilter = FileSensorFilter()
    @Published var direction = Direction.east
    @Published var delay = RepeaterDelay.one
    struct SensorEditRequest {
        let id = UUID()
        let tile: WorldCoordinate
        let match: FileSensorMatch
    }
    @Published var sensorEditRequest: SensorEditRequest?
    @Published var selectedTile: WorldCoordinate? {
        didSet { if selectedTile != oldValue { sensorEditRequest = nil } }
    }
    @Published var hoveredTile: WorldCoordinate?
    @Published var status = "Left-click places; right-click erases. Edits save to this world. Circuit stopped."

    init(worldID: UUID, areaID: UUID, mapper: CoordinateMapper, title: String) {
        self.worldID = worldID
        self.areaID = areaID
        self.mapper = mapper
        self.title = title
    }

    var component: CircuitComponent? {
        tool.kind.map { CircuitComponent(kind: $0, direction: direction, repeaterDelay: delay, sensorFilter: $0 == .fileSensor ? sensorFilter : FileSensorFilter()) }
    }

    func tile(at point: CGPoint) -> WorldCoordinate? {
        guard mapper.canvasFrame.contains(point) else { return nil }
        return mapper.tile(atScreen: point)
    }

    func selectTool(number: Int) {
        guard (1...Tool.allCases.count).contains(number) else { return }
        tool = Tool.allCases[number - 1]
    }

    func cycleTool(forward: Bool) {
        let tools = Tool.allCases
        let index = tools.firstIndex(of: tool)!
        tool = tools[(index + (forward ? 1 : tools.count - 1)) % tools.count]
    }

    func rotateDirection() {
        switch direction {
        case .north: direction = .east
        case .east: direction = .south
        case .south: direction = .west
        case .west: direction = .north
        }
    }
}
