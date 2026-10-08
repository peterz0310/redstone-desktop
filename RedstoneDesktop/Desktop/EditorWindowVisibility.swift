import AppKit
import Combine
import SwiftUI

/// Registers actual editor windows, rather than guessing from window titles or
/// hiding the whole app (which would also hide the build palette and input).
@MainActor
final class EditorWindowVisibility {
    private let registered = NSHashTable<NSWindow>.weakObjects()
    private let hidden = NSHashTable<NSWindow>.weakObjects()
    private(set) var isBuilding = false
    private var closeObserver: AnyCancellable?

    init() {
        closeObserver = NotificationCenter.default.publisher(for: NSWindow.willCloseNotification).sink { [weak self] notification in
            MainActor.assumeIsolated {
                if let window = notification.object as? NSWindow { self?.unregister(window) }
            }
        }
    }

    func register(_ window: NSWindow) { registered.add(window) }
    func unregister(_ window: NSWindow) { registered.remove(window); hidden.remove(window) }

    func beginBuild() {
        guard !isBuilding else { return }
        isBuilding = true
        for window in registered.allObjects where window.isVisible && !window.isMiniaturized {
            hidden.add(window)
            window.orderOut(nil)
        }
    }

    func endBuild(restore: Bool) {
        guard isBuilding else { return }
        isBuilding = false
        if restore {
            // Show only windows we hid, without activating the app or taking key
            // focus away from Finder when automatic deactivation caused the exit.
            for window in hidden.allObjects { window.orderFront(nil) }
        }
        hidden.removeAllObjects()
    }
}

struct EditorWindowRegistration: NSViewRepresentable {
    let windows: EditorWindowVisibility

    func makeNSView(context: Context) -> EditorWindowRegistrationView {
        let view = EditorWindowRegistrationView()
        view.windows = windows
        return view
    }

    func updateNSView(_ view: EditorWindowRegistrationView, context: Context) {
        view.windows = windows
        if let window = view.window { windows.register(window) }
    }
}

final class EditorWindowRegistrationView: NSView {
    weak var windows: EditorWindowVisibility?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window { windows?.unregister(window) }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { windows?.register(window) }
    }
}
