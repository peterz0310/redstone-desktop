import AppKit
import Foundation

// Sources are extracted from the owner-provided local JAR; see tool-icon-sources.json.
// Usage: swift scripts/generate-tool-icons.swift SOURCE_DIRECTORY ASSET_CATALOG
let args = CommandLine.arguments
guard args.count == 3 else { fatalError("Provide source directory and output catalog") }
for name in ["Dust", "Button", "Lever", "Repeater", "Output", "Torch"] {
    let source = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: args[1]).appendingPathComponent(name + ".png")))!
    let side = 16
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32)!
    for y in 0..<side { for x in 0..<side {
        let c = source.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        var alpha = c.alphaComponent
        if name == "Lever" {
            // Rotate the game's narrow handle and add its stone mounting base.
            let angle = Double.pi / 6, dx = Double(x) - 8, dy = Double(y) - 8
            let sx = Int((8 + dx * cos(angle) + dy * sin(angle)).rounded())
            let sy = Int((8 - dx * sin(angle) + dy * cos(angle)).rounded())
            alpha = (0..<16).contains(sx) && (0..<16).contains(sy) ? source.colorAt(x: sx, y: sy)!.alphaComponent : 0
            if (11...14).contains(y) && abs(x - 7) <= (y == 11 || y == 14 ? 3 : 5) { alpha = 1 }
        }
        if name == "Button" { alpha = (2...13).contains(x) && (5...10).contains(y) && !((x == 2 || x == 13) && (y == 5 || y == 10)) ? 1 : 0 }
        if name == "Output" {
            let edge = x == 0 || y == 0 || x == 15 || y == 15
            alpha = edge || (c.redComponent + c.greenComponent + c.blueComponent) / 3 < 0.48 ? 1 : 0
        }
        image.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: alpha), atX: x, y: y)
    } }
    let folder = URL(fileURLWithPath: args[2]).appendingPathComponent("Tool" + name + ".imageset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try image.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon.png"))
    try Data("""
    {"images":[{"filename":"icon.png","idiom":"universal"}],"info":{"author":"xcode","version":1},"properties":{"template-rendering-intent":"template"}}
    """.utf8).write(to: folder.appendingPathComponent("Contents.json"))
}
