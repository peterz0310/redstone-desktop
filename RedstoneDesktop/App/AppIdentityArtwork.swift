import AppKit

/// App/menu icons derive only from the owner-provided logo. No game assets are needed.
@MainActor
enum AppIdentityArtwork {
    enum Appearance { case light, dark }
    static func trimmedLogo(_ logo: NSImage) -> NSImage {
        guard let data = logo.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let cgImage = bitmap.cgImage else { return logo }
        var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
            if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
            }
        } }
        guard maxX >= minX, maxY >= minY,
              let cropped = cgImage.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { return logo }
        return NSImage(cgImage: cropped, size: .zero)
    }

    static func image(pixels: Int, template: Bool, logo: NSImage, appearance: Appearance = .dark, foregroundOnly: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        // Explicit dimensions avoid inheriting the generator Mac's Retina backing scale.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }
        image.addRepresentation(bitmap)
        let scale = CGFloat(pixels) / 128
        let transform = NSAffineTransform()
        transform.scale(by: scale); transform.concat()
        if !template && !foregroundOnly {
            let plate = NSBezierPath(roundedRect: NSRect(x: 5, y: 5, width: 118, height: 118), xRadius: 26, yRadius: 26)
            let light = appearance == .light
            NSGradient(starting: light ? NSColor(white: 1, alpha: 1) : NSColor(white: 0.192, alpha: 1),
                       ending: light ? NSColor(white: 0.925, alpha: 1) : NSColor(white: 0.078, alpha: 1))!.draw(in: plate, angle: -90)
        }
        let art = trimmedLogo(logo)
        let available: CGFloat = template ? 120 : 96
        let ratio = min(available / art.size.width, available / art.size.height)
        let size = CGSize(width: art.size.width * ratio, height: art.size.height * ratio)
        let rect = CGRect(x: (128 - size.width) / 2, y: (128 - size.height) / 2, width: size.width, height: size.height)
        NSGraphicsContext.current?.imageInterpolation = .high
        art.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        if template {
            // Retain the logo's alpha silhouette; macOS chooses light/dark foreground.
            NSColor.black.setFill()
            NSGraphicsContext.current?.compositingOperation = .sourceAtop
            NSBezierPath(rect: CGRect(x: 0, y: 0, width: 128, height: 128)).fill()
        }
        image.isTemplate = template
        return image
    }
}
