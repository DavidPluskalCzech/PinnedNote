import AppIntents
import Foundation

extension Notification.Name {
    static let pnCreateNote = Notification.Name("pnCreateNote")
    static let pnOpenNote = Notification.Name("pnOpenNote")
}

// MARK: - App Intent

/// Registered as a lock-screen shortcut and Siri action.
/// When triggered, opens PinNote and navigates to a blank new note.
struct CreateNoteIntent: AppIntent {

    static let title: LocalizedStringResource       = "Create New Note"
    static let description: IntentDescription       = "Opens PinNote to quickly write a new note."
    static let openAppWhenRun: Bool                 = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Set a flag only — sceneDidBecomeActive will read it and fire the notification
        // exactly once, whether the app cold-launches or resumes from background.
        UserDefaults.standard.set(true, forKey: "openNewNoteOnLaunch")
        return .result()
    }
}

// MARK: - App Shortcuts (lock-screen widget / Siri phrase)

struct PinNoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateNoteIntent(),
            phrases: [
                "New note in \(.applicationName)",
                "Create note in \(.applicationName)",
                "Add note in \(.applicationName)",
            ],
            shortTitle: "New Note",
            systemImageName: "square.and.pencil"
        )
    }
}
