import Foundation

/// One pending snapshot; retries retain the newest failed save. Quit flushes synchronously.
@MainActor
final class WorldAutosaver {
    private let store: any WorldLibraryStoring
    private let delay: Duration
    private let report: (String) -> Void
    private var task: Task<Void, Never>?
    private(set) var pending: WorldLibraryDocument?

    init(store: any WorldLibraryStoring, delay: Duration = .milliseconds(750), report: @escaping (String) -> Void) {
        self.store = store
        self.delay = delay
        self.report = report
    }

    func schedule(_ document: WorldLibraryDocument) {
        pending = document
        task?.cancel()
        report("Unsaved changes…")
        let delay = delay
        task = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func discard() { task?.cancel(); task = nil; pending = nil }

    /// Commit a proposed selection without leaving a failed selection queued for autosave.
    func commit(_ document: WorldLibraryDocument, operation: String = "Activation") -> Bool {
        guard flush() else { return false }
        do {
            try store.save(document)
            report("Saved.")
            return true
        } catch {
            report("\(operation) save failed: \(error.localizedDescription) Current library and desktop preserved; retry the operation.")
            return false
        }
    }

    @discardableResult
    func flush() -> Bool {
        task?.cancel()
        task = nil
        guard let pending else { return true }
        do {
            try store.save(pending)
            self.pending = nil
            report("Saved.")
            return true
        } catch { report("Save failed: \(error.localizedDescription) Changes remain in memory; use Save Now to retry."); return false }
    }
}
