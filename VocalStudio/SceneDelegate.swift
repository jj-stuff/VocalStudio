import UIKit
import SwiftUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    /// Keeps the window's colour scheme in step with the saved appearance setting.
    /// Held for the scene's lifetime — it owns the defaults observer.
    private var appearanceStyler: AppearanceWindowStyler?

    #if DEBUG
    private let store: ProjectStoreInterface = DevSeedingProjectStore(wrapping: FileProjectStore())
    #else
    private let store: ProjectStoreInterface = FileProjectStore()
    #endif

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let root = UIHostingController(rootView: RootView(store: store))
        root.view.backgroundColor = .systemBackground

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = root
        // Before `makeKeyAndVisible`, so the first frame is already in the saved
        // theme rather than flashing the system one.
        appearanceStyler = AppearanceWindowStyler(window: window)
        window.makeKeyAndVisible()
        self.window = window
    }
}
