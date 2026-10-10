import Foundation

extension Notification.Name {
    static let pnCatCompanionChanged = Notification.Name("pnCatCompanionChanged")
}

/// The cat living next to the list title: switched on in Settings, part of Pro
/// (free during the trial).
@MainActor
enum CatCompanion {
    private static let enabledKey = "catCompanionEnabled"

    /// The user's choice. Kept when the trial ends, so the cat comes back after a purchase.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
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
