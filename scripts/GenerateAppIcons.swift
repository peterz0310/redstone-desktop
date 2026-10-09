import AppKit

/// Compile alongside AppIdentityArtwork.swift; writes only generated assets under the given repo root.
@main
struct GenerateAppIcons {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Usage: GenerateAppIcons <repository-root>") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("RedstoneDesktop/Resources/Assets.xcassets")
        guard let dust = NSImage(contentsOf: root.appendingPathComponent("RedstoneDust.imageset/redstone.png")) else {
            fatalError("Missing committed redstone item sprite; see THIRD_PARTY_NOTICES.md")
        }
        let manager = FileManager.default
        func writeJSON(_ object: [String: Any], at url: URL) throws {
            try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        }
        func png(_ pixels: Int, template: Bool, to url: URL) throws {
            let image = AppIdentityArtwork.image(pixels: pixels, template: template, dust: dust)
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let info: [String: Any] = ["author": "xcode", "version": 1]
        try writeJSON(["info": info], at: root.appendingPathComponent("Contents.json"))
        let app = root.appendingPathComponent("AppIcon.appiconset")
        try manager.createDirectory(at: app, withIntermediateDirectories: true)
        var images: [[String: String]] = []
        for size in [16, 32, 128, 256, 512] {
            for factor in [1, 2] {
                let pixels = size * factor, filename = "dust-\(pixels).png"
                try png(pixels, template: false, to: app.appendingPathComponent(filename))
                images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(factor)x", "filename": filename])
            }
        }
        try writeJSON(["info": info, "images": images], at: app.appendingPathComponent("Contents.json"))
        let menu = root.appendingPathComponent("MenuDust.imageset")
        try manager.createDirectory(at: menu, withIntermediateDirectories: true)
        for factor in [1, 2] { try png(18 * factor, template: true, to: menu.appendingPathComponent("dust-\(factor)x.png")) }
        try writeJSON(["info": info, "images": [1, 2].map { ["idiom": "mac", "scale": "\($0)x", "filename": "dust-\($0)x.png"] },
                       "properties": ["template-rendering-intent": "template"]], at: menu.appendingPathComponent("Contents.json"))
    }
}
