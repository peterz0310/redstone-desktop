import SpriteKit

/// Original placeholder art, addressed by semantic IDs rather than file paths.
enum CircuitTextureID: String, CaseIterable {
    case dustOff, dustOn, buttonUp, buttonDown, leverOff, leverOn
    case repeaterOff, repeaterOn, outputOff, outputOn, torchOff, torchOn

    case plateOff, plateOn, sensorOff, sensorOn

    var assetID: TextureAssetID {
        switch self {
        case .plateOff: .redstonePlateOff
        case .plateOn: .redstonePlateOn
        case .sensorOff: .redstoneSensorOff
        case .sensorOn: .redstoneSensorOn
        case .dustOff: .redstoneDustOff
        case .dustOn: .redstoneDustOn
        case .buttonUp: .redstoneButtonUp
        case .buttonDown: .redstoneButtonDown
        case .leverOff: .redstoneLeverOff
        case .leverOn: .redstoneLeverOn
        case .repeaterOff: .redstoneRepeaterOff
        case .repeaterOn: .redstoneRepeaterOn
        case .torchOff: .redstoneTorchOff
        case .torchOn: .redstoneTorchOn
        case .outputOff: .redstoneOutputOff
        case .outputOn: .redstoneOutputOn
        }
    }

    static func id(for kind: CircuitComponentKind, powered: Bool) -> CircuitTextureID? {
        switch kind {
        case .pressurePlate: return powered ? .plateOn : .plateOff
        case .fileSensor: return powered ? .sensorOn : .sensorOff
        case .dust: return powered ? .dustOn : .dustOff
        case .button: return powered ? .buttonDown : .buttonUp
        case .lever: return powered ? .leverOn : .leverOff
        case .repeater: return powered ? .repeaterOn : .repeaterOff
        case .torch: return powered ? .torchOn : .torchOff
        case .output: return powered ? .outputOn : .outputOff
        case .empty: return nil
        }
    }
}

/// Small code-drawn images, cached once per scene. No external assets or pack code.
@MainActor
final class CircuitTextures {
    var assets: any AssetProvider = BuiltInAssetProvider()
    private var revision: UUID?
    private var cache: [CircuitTextureID: SKTexture] = [:]
    var cachedTextureCount: Int { cache.count }

    func texture(for id: CircuitTextureID) -> SKTexture {
        if revision != assets.revision { cache = [:]; revision = assets.revision }
        if let texture = cache[id] { return texture }
        let texture = assets.texture(for: id.assetID) ?? SKTexture(image: Self.image(for: id))
        texture.filteringMode = .nearest
        cache[id] = texture
        return texture
    }

    static func image(for id: CircuitTextureID) -> NSImage {
        NSImage(size: CGSize(width: 32, height: 32), flipped: false) { _ in
            NSGraphicsContext.current?.imageInterpolation = .none
            func fill(_ rect: CGRect, _ color: NSColor) {
                color.setFill()
                NSBezierPath(rect: rect).fill()
            }
            let dark = NSColor(calibratedWhite: 0.14, alpha: 1)
            let rim = NSColor(calibratedWhite: 0.65, alpha: 1)
            let hot = NSColor(calibratedRed: 1, green: 0.09, blue: 0.12, alpha: 1)
            let red = NSColor(calibratedRed: 0.42, green: 0.05, blue: 0.07, alpha: 1)
            switch id {
            case .plateOff, .plateOn:
                fill(CGRect(x: 2, y: 5, width: 28, height: 22), dark)
                fill(CGRect(x: 4, y: 7, width: 24, height: 18), id == .plateOn ? hot : rim)
                fill(CGRect(x: 7, y: 10, width: 18, height: 12), .gray)
            case .sensorOff, .sensorOn:
                fill(CGRect(x: 3, y: 3, width: 26, height: 26), dark)
                fill(CGRect(x: 9, y: 7, width: 14, height: 20), rim)
                for y in [12, 17, 22] { fill(CGRect(x: 12, y: y, width: 8, height: 2), dark) }
                fill(CGRect(x: 3, y: 3, width: 5, height: 5), id == .sensorOn ? hot : red)
            case .dustOff, .dustOn:
                let color = id == .dustOn ? hot : red
                fill(CGRect(x: 0, y: 0, width: 32, height: 32), color)
                fill(CGRect(x: 0, y: 0, width: 32, height: 4), color.blended(withFraction: 0.3, of: dark)!)
                fill(CGRect(x: 4, y: 20, width: 4, height: 4), color)
                fill(CGRect(x: 20, y: 8, width: 4, height: 4), color)
            case .buttonUp, .buttonDown:
                fill(CGRect(x: 4, y: 4, width: 24, height: 24), dark)
                fill(CGRect(x: 6, y: 6, width: 20, height: 20), rim)
                let down = id == .buttonDown
                fill(CGRect(x: down ? 9 : 8, y: down ? 9 : 11, width: down ? 14 : 16, height: down ? 12 : 15), down ? hot : .lightGray)
                fill(CGRect(x: 8, y: 7, width: 16, height: 3), down ? .brown : .black)
            case .leverOff, .leverOn:
                fill(CGRect(x: 5, y: 4, width: 22, height: 8), rim)
                let on = id == .leverOn
                let path = NSBezierPath()
                path.move(to: CGPoint(x: 16, y: 8))
                path.line(to: CGPoint(x: on ? 24 : 8, y: 26))
                path.lineWidth = 5
                (on ? hot : NSColor.lightGray).setStroke()
                path.stroke()
                fill(CGRect(x: on ? 21 : 5, y: 23, width: 6, height: 6), dark)
            case .repeaterOff, .repeaterOn:
                fill(CGRect(x: 2, y: 5, width: 28, height: 22), dark)
                let path = NSBezierPath()
                path.move(to: CGPoint(x: 5, y: 13))
                path.line(to: CGPoint(x: 19, y: 13))
                path.line(to: CGPoint(x: 19, y: 8))
                path.line(to: CGPoint(x: 28, y: 16))
                path.line(to: CGPoint(x: 19, y: 24))
                path.line(to: CGPoint(x: 19, y: 19))
                path.line(to: CGPoint(x: 5, y: 19))
                path.close()
                (id == .repeaterOn ? hot : rim).setFill()
                path.fill()
            case .torchOff, .torchOn:
                fill(CGRect(x: 13, y: 4, width: 6, height: 19), .brown)
                fill(CGRect(x: 14, y: 6, width: 2, height: 14), rim)
                fill(CGRect(x: 10, y: 20, width: 12, height: 9), id == .torchOn ? hot : red)
                fill(CGRect(x: 13, y: 24, width: 6, height: 3), id == .torchOn ? .white : dark)
            case .outputOff, .outputOn:
                // Original terminal block motif; Java importing supplies the real command-block face.
                fill(CGRect(x: 1, y: 1, width: 30, height: 30), .brown)
                fill(CGRect(x: 4, y: 4, width: 24, height: 24), NSColor(calibratedRed: 0.8, green: 0.57, blue: 0.34, alpha: 1))
                fill(CGRect(x: 7, y: 7, width: 18, height: 18), dark)
                for row in 0..<3 { for column in 0..<3 {
                    fill(CGRect(x: 9 + column * 5, y: 9 + row * 5, width: 3, height: 3), (row + column) % 2 == 0 ? rim : .gray)
                } }
                fill(CGRect(x: 23, y: 23, width: 4, height: 4), id == .outputOn ? hot : .darkGray)
            }
            return true
        }
    }
}
