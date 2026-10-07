import Foundation

/// One pending snapshot; retries retain the newest failed save. Quit flushes synchronously.
@MainActor
final class WorldAutosaver {
    private let store: any WorldStoring
    private let delay: Duration
    private let report: (String) -> Void
    private var task: Task<Void, Never>?
    private(set) var pending: WorldDocument?

    init(store: any WorldStoring, delay: Duration = .milliseconds(750), report: @escaping (String) -> Void) {
        self.store = store
        self.delay = delay
        self.report = report
    }

    func schedule(_ document: WorldDocument) {
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

    func flush() {
        task?.cancel()
        task = nil
        guard let pending else { return }
        do {
            try store.save(pending)
            self.pending = nil
            report("Saved.")
        } catch { report("Save failed: \(error.localizedDescription) Changes remain in memory; use Save Now to retry.") }
    }
}
