import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        ThemeManager.shared.startFontSync()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let noteID = response.notification.request.content.userInfo["noteID"] as? String else { return }
        if let uuid = UUID(uuidString: noteID) {
            await ScheduledPinManager.shared.processScheduledPin(noteID: uuid)
        }
        await MainActor.run {
            if UIApplication.shared.applicationState == .active {
                UserDefaults.standard.removeObject(forKey: "openNoteOnLaunch")
                NotificationCenter.default.post(name: .pnOpenNote, object: nil, userInfo: ["noteID": noteID])
            } else {
                UserDefaults.standard.set(noteID, forKey: "openNoteOnLaunch")
            }
        }
    }
}
