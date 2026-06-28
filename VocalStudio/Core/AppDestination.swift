// Navigation destinations used with SwiftUI NavigationStack.

enum AppDestination: Hashable {
    /// `autoRecord`: the instant-record donut button creates a project and wants
    /// the editor to start recording itself, with no extra tap once it opens.
    case editor(Project, autoRecord: Bool)
}
