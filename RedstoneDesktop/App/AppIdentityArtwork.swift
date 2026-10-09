import AppKit

/// Icon framing is original code; the dust image is a separately owned Minecraft texture.
/// See THIRD_PARTY_NOTICES.md. The same item sprite supplies app and template icons.
@MainActor
enum AppIdentityArtwork {
    static func image(pixels: Int, template: Bool, dust: NSImage) -> NSImage {
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        // An explicit bitmap avoids inheriting the generator Mac's Retina backing scale.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }
        image.addRepresentation(bitmap)
        let scale = CGFloat(pixels) / 128
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()
        if !template {
            let plate = NSBezierPath(roundedRect: NSRect(x: 5, y: 5, width: 118, height: 118), xRadius: 26, yRadius: 26)
            NSGradient(starting: NSColor(calibratedRed: 0.18, green: 0.21, blue: 0.25, alpha: 1),
                       ending: NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.09, alpha: 1))!.draw(in: plate, angle: -90)
        }
        // Preserve the exact item's pixel art, with no filtering or invented branches.
        NSGraphicsContext.current?.imageInterpolation = .none
        let rect = template ? NSRect(x: 0, y: 0, width: 128, height: 128)
                            : NSRect(x: 16, y: 16, width: 96, height: 96)
        dust.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        if template {
            // Keep the sprite's alpha silhouette; macOS supplies the light/dark foreground.
            NSColor.black.setFill()
            NSGraphicsContext.current?.compositingOperation = .sourceAtop
            NSBezierPath(rect: rect).fill()
        }
        image.isTemplate = template
        return image
    }
}
