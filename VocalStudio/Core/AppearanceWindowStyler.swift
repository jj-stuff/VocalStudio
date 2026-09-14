import UIKit

/// Applies the saved app theme to the whole window instead of to a view.
///
/// `preferredColorScheme` only styles the view tree it is attached to. A sheet is
/// its own presentation, hosted outside that tree, so Settings was born with
/// whatever scheme was current and never heard about a change — which is why the
/// picker restyled the app underneath it but not the sheet it was sitting in, and
/// why closing and reopening Settings "fixed" it.
///
/// `overrideUserInterfaceStyle` on the `UIWindow` is inherited by every view
/// controller the window presents, sheets and alerts included, so one assignment
/// restyles everything at once. That makes the window the single source of truth
/// for the theme, which is why `RootView` no longer sets `preferredColorScheme`.
@MainActor
final class AppearanceWindowStyler {
    private weak var window: UIWindow?
    // `nonisolated(unsafe)` only so `deinit` — which is not main-actor isolated —
    // can hand the token back. Nothing outside this class ever touches it.
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    init(window: UIWindow) {
        self.window = window
        apply(animated: false)

        // `@AppStorage` writes straight to `UserDefaults.standard`, and this is the
        // notification that write posts. Watching defaults rather than exposing a
        // callback keeps the picker a plain `@AppStorage` binding with nothing to
        // remember to call.
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.apply(animated: true) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private var savedTheme: AppearanceTheme {
        UserDefaults.standard.string(forKey: AppearanceKeys.theme)
            .flatMap(AppearanceTheme.init(rawValue:)) ?? .system
    }

    private func apply(animated: Bool) {
        guard let window else { return }
        let style = savedTheme.userInterfaceStyle
        // The notification fires for every defaults write in the app, so bail on
        // the ones that aren't ours rather than re-running the cross-fade.
        guard window.overrideUserInterfaceStyle != style else { return }

        guard animated else {
            window.overrideUserInterfaceStyle = style
            return
        }
        // `animations:` spelled out rather than trailing: the trailing closure on
        // `transition(with:duration:options:animations:completion:)` is ambiguous.
        UIView.transition(
            with: window,
            duration: 0.25,
            options: .transitionCrossDissolve,
            animations: { window.overrideUserInterfaceStyle = style }
        )
    }
}
