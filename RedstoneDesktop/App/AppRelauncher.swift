import AppKit

@MainActor
protocol AppRelaunching {
    func relaunch() async throws
}

@MainActor
struct NativeAppRelauncher: AppRelaunching {
    var applicationURL = Bundle.main.bundleURL
    var environment: [String: String]? = nil
    func relaunch() async throws {
        guard applicationURL.pathExtension == "app" else { throw MaintenanceError(message: "Application bundle is unavailable; quit and reopen manually.") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.environment = (environment ?? ProcessInfo.processInfo.environment).filter { $0.key.hasPrefix("REDSTONE_DESKTOP_") }
        _ = try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    }
}
