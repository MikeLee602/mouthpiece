import Foundation

enum InjectionError: Error, Equatable, Sendable {
    case noAccessibilityPermission
    case clipboardWriteFailed
    case eventPostFailed
}

protocol TextInjecting: AnyObject, Sendable {
    func inject(_ text: String) async throws
}
