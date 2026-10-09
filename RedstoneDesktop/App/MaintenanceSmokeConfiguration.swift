import AppKit

/// Debug-only, paired isolation settings used by the native reset/relaunch smoke harness.
/// Never falls back to the owner's store/preferences when smoke mode was requested.
@MainActor
enum MaintenanceSmokeConfiguration {
    static var settings: (root: URL, domain: String)? {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard let path = env["REDSTONE_DESKTOP_DATA_ROOT"], path.hasPrefix("/"),
              let domain = env["REDSTONE_DESKTOP_PREFERENCES_SUITE"], domain.hasPrefix("RedstoneDesktop.smoke.") else { return nil }
        return (URL(fileURLWithPath: path).resolvingSymlinksInPath(), domain)
        #else
        return nil
        #endif
    }
    static func report(_ phase: String, state: AppState) {
        guard let settings else { return }
        let report: [String: Any] = ["phase": phase, "pid": ProcessInfo.processInfo.processIdentifier,
            "needsSetup": state.needsSetup, "desktopRunning": state.isDesktopWorldEnabled,
            "worldCount": state.library.worlds.count, "components": state.editorWorld.circuit.components.count,
            "finderRead": state.finderDiagnostics.hasRead]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: settings.root.deletingLastPathComponent().appendingPathComponent("\(phase).json"), options: .atomic)
        }
        if phase == "wizard", ProcessInfo.processInfo.environment["REDSTONE_DESKTOP_SMOKE_EXIT"] == "1" {
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(500)); NSApplication.shared.terminate(nil) }
        }
    }
}
