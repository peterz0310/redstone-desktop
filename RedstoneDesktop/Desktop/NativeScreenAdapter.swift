import AppKit

extension ScreenDescriptor {
    @MainActor
    init(screen: NSScreen) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        self.init(id: number?.stringValue ?? "main", frame: screen.frame, backingScale: screen.backingScaleFactor)
    }
}
