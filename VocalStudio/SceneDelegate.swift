import UIKit
import SwiftUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

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

        let root = UIHostingController(rootView: MainTabView(store: store))
        root.view.backgroundColor = .systemBackground

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = root
        window?.makeKeyAndVisible()
    }
}
