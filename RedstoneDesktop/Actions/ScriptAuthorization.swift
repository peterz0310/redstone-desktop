import SwiftUI
import AppKit

@MainActor
enum ScriptApproval { case deny, once, always }

@MainActor
protocol ScriptAuthorizing {
    func approve(_ target: ScriptTarget) async -> ScriptApproval
}

@MainActor
final class ActionAuthorizationStore {
    private let preferences: UserDefaults?
    private var allowed: Set<String>
    init(preferences: UserDefaults? = nil) {
        self.preferences = preferences
        allowed = Set((preferences?.stringArray(forKey: "approvedScripts") ?? []).prefix(256))
    }
    func contains(_ target: ScriptTarget) -> Bool { allowed.contains(target.authorizationKey) }
    func allow(_ target: ScriptTarget) {
        guard allowed.count < 256 else { return }
        allowed.insert(target.authorizationKey)
        preferences?.set(allowed.sorted(), forKey: "approvedScripts")
    }
    func revokeAll() { allowed = []; preferences?.removeObject(forKey: "approvedScripts") }
}

/// A dedicated SwiftUI prompt works even when the editor is closed. Never blocks the main run loop.
@MainActor
final class ScriptAuthorizationPresenter: NSObject, ScriptAuthorizing, NSWindowDelegate {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<ScriptApproval, Never>?
    private var requestID: UUID?

    func approve(_ target: ScriptTarget) async -> ScriptApproval {
        let id = UUID()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled, continuation == nil else { return .deny }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                requestID = id
                let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 560, height: 310),
                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.title = "Execute Desktop Script"
                window.isReleasedWhenClosed = false
                window.delegate = self
                window.contentView = NSHostingView(rootView: ScriptConfirmationView(target: target) { [weak self] in self?.finish($0, id: id) })
                self.window = window
                window.center()
                NSApplication.shared.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(.deny, id: id) } }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let id = requestID { finish(.deny, id: id) }
        return false
    }
    private func finish(_ approval: ScriptApproval, id: UUID) {
        guard requestID == id, let continuation else { return }
        self.continuation = nil
        requestID = nil
        window?.delegate = nil
        window?.orderOut(nil); window?.close(); window = nil
        continuation.resume(returning: approval)
    }
}

struct ScriptConfirmationView: View {
    let target: ScriptTarget
    let complete: (ScriptApproval) -> Void
    @State private var remember = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Run this script?").font(.title2)
            Text("It runs with your account's access to files and applications.")
            ScrollView { Text(target.url.path).font(.callout.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(height: 70)
            Text("Interpreter: \(target.interpreter.path) · working folder: script's folder").font(.caption).foregroundStyle(.secondary)
            Toggle("Always allow this exact file", isOn: $remember)
            Text("Changing its contents or replacing the file requires approval again.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { complete(.deny) }.keyboardShortcut(.cancelAction)
                Button("Run Script") { complete(remember ? .always : .once) }
            }
        }.padding(22).frame(width: 560, height: 310)
    }
}
