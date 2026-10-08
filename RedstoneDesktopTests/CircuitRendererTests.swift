import AppKit
import SpriteKit
import XCTest
@testable import RedstoneDesktop

final class CircuitRendererTests: XCTestCase {
    private func cell(_ x: Int, _ y: Int = 1) -> WorldCoordinate { WorldCoordinate(x: x, y: y) }
    @MainActor
    private func fixture() throws -> (DesktopScene, CoordinateMapper, ScreenDescriptor) {
        let screen = ScreenDescriptor(id: "negative", frame: CGRect(x: -640, y: -100, width: 640, height: 640), backingScale: 2)
        let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64))
        return (DesktopScene(screen: screen, mapper: mapper), mapper, screen)
    }

    @MainActor
    func testDustConnectsAtTileEdgesAndIgnoresDiagonalAndRepeaterSides() throws {
        let (scene, mapper, screen) = try fixture()
        let coordinate = cell(2, 2)
        var components = [coordinate: CircuitComponent(kind: .dust), cell(3, 2): CircuitComponent(kind: .dust),
            cell(2, 3): CircuitComponent(kind: .repeater, direction: .east),
            cell(3, 3): CircuitComponent(kind: .dust)]
        scene.updateWorld(World(circuit: CircuitWorld(components: components)))
        let layer = try XCTUnwrap(scene.childNode(withName: "circuit"))
        let dust = try XCTUnwrap(layer.children.first as? SKShapeNode)
        let rect = mapper.sceneRect(forTile: coordinate, on: screen)
        let bounds = try XCTUnwrap(dust.path?.boundingBoxOfPath)
        XCTAssertEqual(bounds.minX, rect.midX - 6.4, accuracy: 0.000001)
        XCTAssertEqual(bounds.minY, rect.midY - 6.4, accuracy: 0.000001)
        XCTAssertEqual(bounds.width, rect.width / 2 + 6.4, accuracy: 0.000001)
        XCTAssertEqual(bounds.height, 12.8, accuracy: 0.000001)
        XCTAssertNotNil(dust.fillTexture)
        XCTAssertEqual(dust.fillTexture?.filteringMode, .nearest)
        components[cell(2, 3)]?.direction = .north // its rear port now faces this dust
        scene.updateWorld(World(circuit: CircuitWorld(components: components)))
        let connected = try XCTUnwrap(layer.children.first as? SKShapeNode)
        XCTAssertEqual(connected.path?.boundingBoxOfPath.maxY, rect.midY + 40)
    }

    @MainActor
    func testCornerTeeCrossAndIsolatedDustHaveBoundedLocalGeometry() throws {
        let (scene, mapper, screen) = try fixture()
        let origin = cell(3, 3)
        let rect = mapper.sceneRect(forTile: origin, on: screen)
        for directions in [[], [Direction.north, .east], [.north, .east, .west], Direction.allCases] {
            var components = [origin: CircuitComponent(kind: .dust)]
            for direction in directions { components[direction.neighbor(of: origin)!] = CircuitComponent(kind: .dust) }
            scene.updateWorld(World(circuit: CircuitWorld(components: components)))
            let paths = try XCTUnwrap(scene.childNode(withName: "circuit")).children.compactMap { $0 as? SKShapeNode }
            let originPath = try XCTUnwrap(paths.first { $0.path?.contains(CGPoint(x: rect.midX, y: rect.midY)) == true })
            let bounds = try XCTUnwrap(originPath.path?.boundingBoxOfPath)
            XCTAssertEqual(bounds.minX, directions.contains(.west) ? rect.minX : rect.midX - 6.4)
            XCTAssertEqual(bounds.maxX, directions.contains(.east) ? rect.maxX : rect.midX + 6.4)
            XCTAssertEqual(bounds.minY, directions.contains(.south) ? rect.minY : rect.midY - 6.4)
            XCTAssertEqual(bounds.maxY, directions.contains(.north) ? rect.maxY : rect.midY + 6.4)
            // Verify filled coverage under the even-odd rule used by SpriteKit, including joins.
            for direction in directions {
                for distance in [CGFloat(4), 9, 24, 31] {
                    let dx: CGFloat = direction == .east ? distance : (direction == .west ? -distance : 0)
                    let dy: CGFloat = direction == .north ? distance : (direction == .south ? -distance : 0)
                    XCTAssertTrue(originPath.path?.contains(CGPoint(x: rect.midX + dx, y: rect.midY + dy), using: .evenOdd) == true)
                }
            }
        }
    }

    @MainActor
    func testButtonAndLeverImagesAndLabelsFollowCommittedPower() throws {
        let (scene, _, _) = try fixture()
        let button = cell(1), lever = cell(2)
        let world = World(circuit: CircuitWorld(components: [button: CircuitComponent(kind: .button), lever: CircuitComponent(kind: .lever)]))
        let layer = try XCTUnwrap(scene.childNode(withName: "circuit"))
        func label(_ coordinate: WorldCoordinate) -> String? {
            (layer.childNode(withName: "state-label:\(coordinate.x),\(coordinate.y)") as? SKLabelNode)?.text
        }
        func icon(_ coordinate: WorldCoordinate) -> SKSpriteNode? {
            layer.children.flatMap(\.children).first { $0.name == "component-icon:\(coordinate.x),\(coordinate.y)" } as? SKSpriteNode
        }
        scene.updateWorld(world)
        XCTAssertEqual(label(button), "PRESS")
        XCTAssertEqual(label(lever), "OFF")
        let buttonUp = try XCTUnwrap(icon(button)?.texture), leverOff = try XCTUnwrap(icon(lever)?.texture)
        scene.updateWorld(world, poweredTiles: [button, lever])
        XCTAssertEqual(label(button), "DOWN")
        XCTAssertEqual(label(lever), "ON")
        XCTAssertFalse(icon(button)?.texture === buttonUp)
        XCTAssertFalse(icon(lever)?.texture === leverOff)
        scene.updateWorld(world)
        XCTAssertTrue(icon(button)?.texture === buttonUp, "Cached off texture is reused")
        XCTAssertTrue(icon(lever)?.texture === leverOff)
    }

    @MainActor
    func testOutputGlowsTrackAllOccupancyStatesWithoutLabelsOrChangingPower() throws {
        let (scene, mapper, screen) = try fixture()
        let output = cell(2)
        let world = World(circuit: CircuitWorld(components: [output: CircuitComponent(kind: .output)]))
        let item = DesktopItem(id: "one", url: URL(fileURLWithPath: "/tmp/one"), displayName: "one", position: .zero, estimatedIconSize: nil, kind: .file)
        let other = DesktopItem(id: "two", url: URL(fileURLWithPath: "/tmp/two"), displayName: "two", position: .zero, estimatedIconSize: nil, kind: .file)
        let layer = try XCTUnwrap(scene.childNode(withName: "circuit"))
        scene.updateWorld(world, poweredTiles: [output])
        let icon = try XCTUnwrap(layer.children.flatMap(\.children).first { $0 is SKSpriteNode } as? SKSpriteNode)
        let poweredTexture = icon.texture
        for (snapshot, color) in [(DesktopOccupancySnapshot.available([:]), NSColor.systemRed),
            (.available([output: DesktopOccupancy(coordinate: output, items: [item])]), .systemGreen),
            (.available([output: DesktopOccupancy(coordinate: output, items: [item, other])]), .systemOrange),
            (.unavailable("Denied"), .gray)] {
            scene.updateOccupancy(snapshot)
            let outputNode = try XCTUnwrap(layer.childNode(withName: "OUTPUT") as? SKShapeNode)
            let badge = try XCTUnwrap(outputNode.childNode(withName: "output-occupancy:2,1") as? SKShapeNode)
            XCTAssertFalse(outputNode.children.contains { $0 is SKLabelNode })
            XCTAssertNil(layer.childNode(withName: "state-label:2,1"))
            XCTAssertEqual(outputNode.path?.boundingBoxOfPath, mapper.sceneRect(forTile: output, on: screen))
            XCTAssertEqual((outputNode.childNode(withName: "component-icon:2,1") as? SKSpriteNode)?.size, CGSize(width: 64, height: 64))
            XCTAssertEqual(badge.fillColor.alphaComponent, 0)
            XCTAssertGreaterThan(badge.glowWidth, 0)
            let actualColor = try XCTUnwrap(badge.strokeColor.usingColorSpace(.sRGB))
            let expectedColor = try XCTUnwrap(color.usingColorSpace(.sRGB))
            XCTAssertEqual(actualColor.redComponent, expectedColor.redComponent, accuracy: 0.00001)
            XCTAssertEqual(actualColor.greenComponent, expectedColor.greenComponent, accuracy: 0.00001)
            XCTAssertEqual(actualColor.blueComponent, expectedColor.blueComponent, accuracy: 0.00001)
            XCTAssertTrue((outputNode.childNode(withName: "component-icon:2,1") as? SKSpriteNode)?.texture === poweredTexture)
            scene.size = CGSize(width: 600, height: 600)
            XCTAssertEqual((layer.childNode(withName: "OUTPUT")?.childNode(withName: "output-occupancy:2,1") as? SKShapeNode)?.strokeColor, badge.strokeColor)
        }
    }

    @MainActor
    func testIndependentOutputFlashesStayBoundedAndRemovedOutputsClearEffects() throws {
        let (scene, mapper, screen) = try fixture()
        let a = cell(1), b = cell(3)
        let world = World(circuit: CircuitWorld(components: [a: CircuitComponent(kind: .output), b: CircuitComponent(kind: .output)]))
        scene.updateWorld(world)
        let flashes = try XCTUnwrap(scene.childNode(withName: "output-flash"))
        for _ in 0..<20 { scene.flashOutput(at: a); scene.flashOutput(at: b) }
        XCTAssertEqual(flashes.children.count, 2)
        for coordinate in [a, b] {
            let node = try XCTUnwrap(flashes.childNode(withName: "output-flash:\(coordinate.x),\(coordinate.y)") as? SKShapeNode)
            XCTAssertEqual(node.path?.boundingBoxOfPath, mapper.sceneRect(forTile: coordinate, on: screen).insetBy(dx: 3, dy: 3))
            XCTAssertTrue(node.hasActions())
        }
        scene.updateWorld(world, poweredTiles: [a, b])
        scene.updateOccupancy(.available([:]))
        XCTAssertEqual(flashes.children.count, 2, "Snapshot refresh does not erase a live activation flash")
        scene.flashOutput(at: cell(8))
        XCTAssertEqual(flashes.children.count, 2, "Missing outputs never acquire effects")
        scene.updateWorld(World())
        XCTAssertTrue(flashes.children.isEmpty)
    }

    @MainActor
    func testOriginalTexturesAreDistinctCachedAndNearestFiltered() throws {
        let textures = CircuitTextures()
        for id in CircuitTextureID.allCases {
            let first = textures.texture(for: id)
            XCTAssertTrue(first === textures.texture(for: id))
            XCTAssertEqual(first.filteringMode, .nearest)
            XCTAssertEqual(first.size(), CGSize(width: 32, height: 32))
        }
        XCTAssertEqual(textures.cachedTextureCount, CircuitTextureID.allCases.count)
        let pairs: [(CircuitTextureID, CircuitTextureID)] = [(.dustOff, .dustOn), (.buttonUp, .buttonDown),
            (.leverOff, .leverOn), (.repeaterOff, .repeaterOn), (.outputOff, .outputOn), (.torchOff, .torchOn)]
        for (off, on) in pairs {
            let offData = try XCTUnwrap(CircuitTextures.image(for: off).tiffRepresentation)
            let onData = try XCTUnwrap(CircuitTextures.image(for: on).tiffRepresentation)
            XCTAssertNotEqual(offData, onData)
        }
        // Export the actual code-drawn art for visual inspection, using native image drawing.
        let sheet = NSImage(size: CGSize(width: 320, height: 64), flipped: false) { _ in
            NSColor.darkGray.setFill()
            NSBezierPath(rect: CGRect(x: 0, y: 0, width: 320, height: 64)).fill()
            for (index, id) in CircuitTextureID.allCases.enumerated() {
                CircuitTextures.image(for: id).draw(in: CGRect(x: index * 32, y: 16, width: 32, height: 32))
            }
            return true
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(sheet.tiffRepresentation)))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/redstone-circuit-textures.png"))
    }
}
