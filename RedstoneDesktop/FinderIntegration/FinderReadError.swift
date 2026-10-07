import Foundation
import CoreServices

enum FinderReadError: Error, Equatable, LocalizedError {
    case permissionDenied
    case scriptFailure(code: Int?, message: String)
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Finder Automation access was denied. Enable Finder for Redstone Desktop in System Settings → Privacy & Security → Automation, then read again."
        case let .scriptFailure(code, message):
            return "Finder query failed\(code.map { " (\($0))" } ?? ""): \(message)"
        case let .malformedResponse(message):
            return "Finder returned a response this app could not parse: \(message)"
        }
    }

    static func fromScriptError(_ error: NSDictionary?) -> FinderReadError {
        let code = (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        if code == Int(errAEEventNotPermitted) { return .permissionDenied }
        return .scriptFailure(code: code, message: error?[NSAppleScript.errorMessage] as? String ?? "No error details were returned.")
    }
}
