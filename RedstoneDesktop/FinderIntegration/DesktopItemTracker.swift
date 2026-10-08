import Foundation
import Combine

/// A single outstanding poll, sharing the same request gate as explicit diagnostic reads.
@MainActor
final class DesktopItemTracker: ObservableObject {
    @Published private(set) var isPolling = false
    let diagnostics: FinderDiagnosticsModel
    /// Explicit input/output reads take priority over the next periodic poll.
    var shouldPoll: () -> Bool = { true }
    private var timer: Timer?
    private var pollTask: Task<Void, Never>?

    init(diagnostics: FinderDiagnosticsModel) {
        self.diagnostics = diagnostics
    }

    func start() {
        guard !isPolling else { return }
        isPolling = true
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestPoll() }
        }
        timer.tolerance = 0.05
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        requestPoll()
    }

    func stop() {
        isPolling = false
        timer?.invalidate()
        timer = nil
        // Keep the request slot occupied until a provider that ignores cancellation returns.
        pollTask?.cancel()
    }

    func requestPoll() {
        guard isPolling, pollTask == nil, !diagnostics.isReading, shouldPoll() else { return }
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if self.shouldPoll(), !Task.isCancelled { await self.diagnostics.readItems() }
            if !Task.isCancelled, self.diagnostics.error != nil { self.stop() }
            self.pollTask = nil
        }
    }
}
