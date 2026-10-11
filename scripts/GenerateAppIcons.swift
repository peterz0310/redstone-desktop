import AppKit

/// Compile alongside AppIdentityArtwork.swift; writes only generated assets under the given repo root.
@main
struct GenerateAppIcons {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Usage: GenerateAppIcons <repository-root>") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("RedstoneDesktop/Resources/Assets.xcassets")
        guard let logo = NSImage(contentsOf: root.appendingPathComponent("Logo.imageset/logo.png")) else {
            fatalError("Missing owner-provided logo; see THIRD_PARTY_NOTICES.md")
        }
        let manager = FileManager.default
        func writeJSON(_ object: [String: Any], at url: URL) throws {
            try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
        }
        func png(_ pixels: Int, template: Bool, appearance: AppIdentityArtwork.Appearance = .dark, foregroundOnly: Bool = false, to url: URL) throws {
            let image = AppIdentityArtwork.image(pixels: pixels, template: template, logo: logo, appearance: appearance, foregroundOnly: foregroundOnly)
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let info: [String: Any] = ["author": "xcode", "version": 1]
        try writeJSON(["info": info], at: root.appendingPathComponent("Contents.json"))
        let app = root.appendingPathComponent("AppLogo.imageset")
        try manager.createDirectory(at: app, withIntermediateDirectories: true)
        var images: [[String: Any]] = []
        for (name, appearance) in [("light", AppIdentityArtwork.Appearance.light), ("dark", .dark)] {
            for factor in [1, 2] {
                let filename = "logo-\(name)-\(factor)x.png"
                try png(256 * factor, template: false, appearance: appearance, to: app.appendingPathComponent(filename))
                var entry: [String: Any] = ["idiom": "mac", "scale": "\(factor)x", "filename": filename]
                if name == "dark" { entry["appearances"] = [["appearance": "luminosity", "value": "dark"]] }
                images.append(entry)
            }
        }
        try writeJSON(["info": info, "images": images], at: app.appendingPathComponent("Contents.json"))
        let foreground = root.deletingLastPathComponent().appendingPathComponent("AppIcon.icon/Assets/logo.png")
        try manager.createDirectory(at: foreground.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png(1024, template: false, foregroundOnly: true, to: foreground)
        let menu = root.appendingPathComponent("MenuLogo.imageset")
        try manager.createDirectory(at: menu, withIntermediateDirectories: true)
        for factor in [1, 2] { try png(18 * factor, template: true, to: menu.appendingPathComponent("logo-\(factor)x.png")) }
        try writeJSON(["info": info, "images": [1, 2].map { ["idiom": "mac", "scale": "\($0)x", "filename": "logo-\($0)x.png"] },
                       "properties": ["template-rendering-intent": "template"]], at: menu.appendingPathComponent("Contents.json"))
    }
}
