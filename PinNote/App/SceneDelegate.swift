import UIKit
import StoreKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Always show splash first — it decides whether to go to onboarding or main
        _ = NoteStore.shared
        ScheduledPinManager.shared.start()

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .pnBackground
        window.rootViewController = SplashViewController()

        window.overrideUserInterfaceStyle = ThemeManager.shared.current.interfaceStyle
        window.makeKeyAndVisible()
        self.window = window

        if let url = connectionOptions.urlContexts.first?.url {
            handleDeepLink(url)
        }
        if let noteID = connectionOptions.notificationResponse?
            .notification.request.content.userInfo["noteID"] as? String {
            UserDefaults.standard.set(noteID, forKey: "openNoteOnLaunch")
        }

        scheduleReviewPromptIfNeeded(in: windowScene)

        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged),
            name: .pnThemeChanged, object: nil
        )
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Task { @MainActor in
            LiveActivityManager.shared.reconcileCurrentState()
            await ScheduledPinManager.shared.processDuePins()
        }
        openPendingNoteIfPossible()
        openPendingNewNoteIfPossible()
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        handleDeepLink(url)
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "pinnote",
              url.host == "note",
              let noteID = url.pathComponents.dropFirst().first
        else { return }

        UserDefaults.standard.set(noteID, forKey: "openNoteOnLaunch")
        openPendingNoteIfPossible()
    }

    private func openPendingNoteIfPossible() {
        guard let noteID = UserDefaults.standard.string(forKey: "openNoteOnLaunch") else { return }

        guard canOpenNoteFromCurrentNavigation() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.openPendingNoteIfPossible()
            }
            return
        }

        UserDefaults.standard.removeObject(forKey: "openNoteOnLaunch")
        NotificationCenter.default.post(name: .pnOpenNote, object: nil, userInfo: ["noteID": noteID])
    }

    func openPendingNewNoteIfPossible() {
        guard UserDefaults.standard.bool(forKey: "openNewNoteOnLaunch") else { return }

        let pm = PurchaseManager.shared
        guard pm.isPro || pm.isTrialActive else {
            UserDefaults.standard.removeObject(forKey: "openNewNoteOnLaunch")
            return
        }

        guard canOpenNewNoteFromCurrentNavigation() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.openPendingNewNoteIfPossible()
            }
            return
        }

        UserDefaults.standard.removeObject(forKey: "openNewNoteOnLaunch")
        NotificationCenter.default.post(name: .pnCreateNote, object: nil)
    }

    private func topMostViewController() -> UIViewController? {
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        if let nav = top as? UINavigationController {
            return nav.topViewController
        }
        return top
    }

    private func canOpenNewNoteFromCurrentNavigation() -> Bool {
        guard let top = topMostViewController() else { return false }
        if top is NoteListViewController { return true }
        if top is NoteDetailViewController {
            return (top.navigationController?.viewControllers.contains { $0 is NoteListViewController }) == true
        }
        return false
    }

    private func canOpenNoteFromCurrentNavigation() -> Bool {
        canOpenNewNoteFromCurrentNavigation()
    }

    // MARK: - Review prompt

    private func scheduleReviewPromptIfNeeded(in scene: UIWindowScene) {
        let key   = "pnLaunchCount"
        let count = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(count, forKey: key)

        // Show after 5th launch, then every 20 launches after that
        let shouldPrompt = count == 5 || (count > 5 && (count - 5) % 20 == 0)
        guard shouldPrompt else { return }

        // Delay past the splash screen (2.2s animation + 0.75s transition + buffer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    // MARK: - Theme

    @objc private func themeChanged() {
        // Just keep the window background in sync — each VC updates itself.
        window?.backgroundColor = .pnBackground
        window?.overrideUserInterfaceStyle = ThemeManager.shared.current.interfaceStyle
    }
}
