import Foundation

struct ScriptActionOutcome {
    let message: String
    let result: ScriptExecutionResult?
    init(_ message: String, result: ScriptExecutionResult? = nil) { self.message = message; self.result = result }
}

/// Authorization and execution stay outside simulation and rendering.
@MainActor
struct ExecuteScriptAction {
    let executor: any ScriptExecuting
    let authorizer: any ScriptAuthorizing
    let store: ActionAuthorizationStore

    func perform(occupancy: DesktopOccupancyState,
                 isCurrent: @MainActor () -> Bool,
                 refresh: @MainActor () async -> DesktopOccupancyState) async -> ScriptActionOutcome {
        do {
            guard case let .occupied(item) = occupancy else {
                return ScriptActionOutcome("Execution requires exactly one current Finder occupant; nothing executed.")
            }
            let target = try await Task.detached(priority: .utility) { try ScriptTarget.resolve(item) }.value
            guard !Task.isCancelled, isCurrent() else { throw CancellationError() }
            var remember = false
            if !store.contains(target) {
                let approval = await authorizer.approve(target)
                guard !Task.isCancelled, isCurrent() else { throw CancellationError() }
                switch approval {
                case .deny: return ScriptActionOutcome("Script execution cancelled; nothing executed.")
                case .once: break
                case .always: remember = true
                }
            }
            let fresh = await refresh()
            guard !Task.isCancelled, isCurrent() else { throw CancellationError() }
            guard case let .occupied(current) = fresh, current.id == item.id, current.url == item.url else {
                return ScriptActionOutcome("Output occupant changed during authorization; nothing executed. Press the input again.")
            }
            let checked = try await Task.detached(priority: .utility) { try ScriptTarget.resolve(current) }.value
            guard checked == target else { return ScriptActionOutcome("Script changed during authorization; nothing executed. Press the input again.") }
            guard !Task.isCancelled, isCurrent() else { throw CancellationError() }
            if remember { store.allow(target) }
            let result = try await executor.execute(target)
            guard !Task.isCancelled, isCurrent() else { throw CancellationError() }
            return ScriptActionOutcome("Script exited \(result.exitCode) in \(String(format: "%.2f", result.duration)) s: \(target.url.lastPathComponent)", result: result)
        } catch is CancellationError {
            return ScriptActionOutcome("Script action cancelled.")
        } catch { return ScriptActionOutcome("Nothing executed or execution failed: \(error.localizedDescription)") }
    }
}
