import AppKit

/// Original MIT-licensed artwork. No imported game textures or fonts.
/// One branched dust silhouette is used for the full-color app icon and template status item.
@MainActor
enum AppIdentityArtwork {
    static func image(pixels: Int, template: Bool) -> NSImage {
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
        let dust = NSBezierPath()
        // Staggered, pixel-like crumbs and branches; original geometry on a 128-point canvas.
        for rect in [NSRect(x: 48, y: 49, width: 31, height: 29),
                     NSRect(x: 30, y: 61, width: 27, height: 12), NSRect(x: 20, y: 71, width: 18, height: 14),
                     NSRect(x: 71, y: 64, width: 25, height: 12), NSRect(x: 91, y: 75, width: 16, height: 15),
                     NSRect(x: 57, y: 74, width: 12, height: 22), NSRect(x: 63, y: 91, width: 17, height: 14),
                     NSRect(x: 40, y: 36, width: 17, height: 20), NSRect(x: 28, y: 26, width: 19, height: 15),
                     NSRect(x: 71, y: 37, width: 14, height: 21), NSRect(x: 80, y: 26, width: 17, height: 16),
                     NSRect(x: 20, y: 48, width: 8, height: 8), NSRect(x: 94, y: 51, width: 9, height: 9)] {
            dust.appendRect(rect)
        }
        (template ? NSColor.black : NSColor(calibratedRed: 0.94, green: 0.12, blue: 0.17, alpha: 1)).setFill()
        dust.fill()
        if !template {
            NSColor(calibratedRed: 1, green: 0.38, blue: 0.39, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 51, y: 66, width: 19, height: 8)).fill()
        }
        image.isTemplate = template
        return image
    }
}
