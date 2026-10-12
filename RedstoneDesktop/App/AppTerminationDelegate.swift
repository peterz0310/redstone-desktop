import AppKit

enum QuitSaveDecision { case cancel, retry, recoveryCopy }

/// Testable quit policy. A cancelled quit leaves the runtime and pending save intact.
@MainActor
final class QuitSaveCoordinator {
    private(set) var isDeciding = false
    func resolve(save: () -> Bool, decide: () async -> QuitSaveDecision,
                 saveRecovery: () async -> Bool) async -> Bool {
        guard !isDeciding else { return false }
        isDeciding = true
        defer { isDeciding = false }
        while !save() {
            switch await decide() {
            case .cancel: return false
            case .retry: continue
            case .recoveryCopy: return await saveRecovery()
            }
        }
        return true
    }
}

/// All quit entry points, including Command-Q, use AppKit's deferred termination contract.
@MainActor
final class AppTerminationDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = QuitSaveCoordinator()
    private var terminationTask: Task<Void, Never>?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        let state = AppStartup.state
        guard !state.saveWorldNow() else { return .terminateNow }
        terminationTask = Task { @MainActor [weak self] in
            guard let self else { sender.reply(toApplicationShouldTerminate: false); return }
            let shouldQuit = await coordinator.resolve(save: { state.saveWorldNow() }, decide: {
                let alert = NSAlert()
                alert.messageText = "Your latest changes couldn’t be saved"
                alert.informativeText = "Your worlds are still open. You can stay here, retry saving, or save a recovery copy somewhere else before quitting.\n\n\(state.persistenceStatus)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Stay Open")
                alert.addButton(withTitle: "Retry Save")
                alert.addButton(withTitle: "Save Copy and Quit…")
                switch await Self.present(alert) {
                case .alertSecondButtonReturn: return .retry
                case .alertThirdButtonReturn: return .recoveryCopy
                default: return .cancel
                }
            }, saveRecovery: {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                panel.nameFieldStringValue = "RedstoneDesktop-Recovery.json"
                panel.message = "Choose another folder or drive for a copy of all your worlds and areas."
                let response = await withCheckedContinuation { continuation in
                    panel.begin { continuation.resume(returning: $0) }
                }
                guard response == .OK, let url = panel.url else { return false }
                do {
                    try state.saveRecoveryCopy(to: url)
                    // No suspension between capturing the latest library and stopping new inputs.
                    state.shutdown()
                    return true
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "The recovery copy couldn’t be saved"
                    alert.informativeText = "The app will stay open so your changes are still here. Try another folder or drive.\n\n\(error.localizedDescription)"
                    await Self.present(alert)
                    return false
                }
            })
            terminationTask = nil
            sender.reply(toApplicationShouldTerminate: shouldQuit)
        }
        return .terminateLater
    }

    @discardableResult
    private static func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.keyWindow, window.attachedSheet == nil {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            }
        }
        // A menu-bar session may have no editor window for a sheet.
        return alert.runModal()
    }
}
