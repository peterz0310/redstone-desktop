import AppKit

// Original installer artwork; rendered without starting the app or reading user data.
let size = NSSize(width: 680, height: 440)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedRed: 0.94, green: 0.97, blue: 0.95, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
func text(_ value: String, y: CGFloat, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
    (value as NSString).draw(in: NSRect(x: 30, y: y, width: 620, height: 40), withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
}
text("Redstone Desktop", y: 347, font: .systemFont(ofSize: 30, weight: .semibold), color: NSColor(calibratedWhite: 0.14, alpha: 1))
text("Drag the app into Applications", y: 314, font: .systemFont(ofSize: 16), color: NSColor(calibratedWhite: 0.34, alpha: 1))
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 305, y: 200)); arrow.line(to: NSPoint(x: 370, y: 200))
arrow.move(to: NSPoint(x: 357, y: 212)); arrow.line(to: NSPoint(x: 370, y: 200)); arrow.line(to: NSPoint(x: 357, y: 188))
arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(calibratedRed: 0.25, green: 0.49, blue: 0.37, alpha: 1).setStroke(); arrow.stroke()
text("A redstone world beneath your files.", y: 44, font: .systemFont(ofSize: 14), color: NSColor(calibratedWhite: 0.34, alpha: 1))
image.unlockFocus()
guard CommandLine.arguments.count == 2,
      let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Usage: InstallerArtwork.swift <output.png>")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
