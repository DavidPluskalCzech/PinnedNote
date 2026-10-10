import Foundation

extension Notification.Name {
    static let pnCatCompanionChanged = Notification.Name("pnCatCompanionChanged")
}

/// The cat living next to the list title: on unless switched off in Settings, part of Pro
/// (free during the trial).
@MainActor
enum CatCompanion {
    private static let enabledKey = "catCompanionEnabled"
    /// Set once the cat has been switched on for everyone (new installs and the update
    /// that made her the default); from then on the user's own choice stands.
    private static let switchedOnForAllKey = "catCompanionSwitchedOnForAll"

    /// The user's choice, on by default. Kept when the trial ends, so the cat comes
    /// back after a purchase.
    static var isEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            if !defaults.bool(forKey: switchedOnForAllKey) {
                defaults.set(true, forKey: switchedOnForAllKey)
                defaults.set(true, forKey: enabledKey)
            }
            return defaults.bool(forKey: enabledKey)
        }
        set {
            guard newValue != isEnabled else { return }
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: .pnCatCompanionChanged, object: nil)
        }
    }

    /// Whether Pro features are open: bought, or still in the trial.
    static var isAvailable: Bool {
        PurchaseManager.shared.isPro || PurchaseManager.shared.isTrialActive
    }

    /// Whether the cat is shown.
    static var isActive: Bool {
        isEnabled && isAvailable
    }
}
