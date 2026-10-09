import UIKit

// MARK: - Theme definition

enum AppTheme: String, CaseIterable {
    case monochrome = "monochrome"
    case dark       = "dark"
    case blossom    = "blossom"

    var displayName: String {
        switch self {
        case .monochrome: return NSLocalizedString("theme_light",   comment: "")
        case .dark:       return NSLocalizedString("theme_dark",    comment: "")
        case .blossom:    return NSLocalizedString("theme_blossom", comment: "")
        }
    }

    // Representative swatch colors shown in the picker
    var primaryColor: UIColor {
        switch self {
        case .monochrome: return UIColor(white: 0.08, alpha: 1)
        case .dark:       return UIColor(red: 0.94, green: 0.92, blue: 0.86, alpha: 1)
        case .blossom:    return UIColor(red: 0.55, green: 0.33, blue: 0.41, alpha: 1)
        }
    }

    /// Color of the round swatch dot in the theme picker card
    var swatchColor: UIColor {
        switch self {
        case .monochrome: return .white
        case .dark:       return UIColor(red: 0.058, green: 0.060, blue: 0.066, alpha: 1)
        case .blossom:    return UIColor(red: 0.55, green: 0.33, blue: 0.41, alpha: 1)
        }
    }

    var backgroundColor: UIColor {
        switch self {
        case .monochrome: return UIColor(red: 0.975, green: 0.972, blue: 0.965, alpha: 1)
        case .dark:       return UIColor(red: 0.010, green: 0.011, blue: 0.013, alpha: 1)
        case .blossom:    return UIColor(red: 0.998, green: 0.905, blue: 0.930, alpha: 1)
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        self == .dark ? .dark : .light
    }
}

// MARK: - Manager

extension Notification.Name {
    static let pnThemeChanged = Notification.Name("pnThemeChanged")
    static let pnFontChanged  = Notification.Name("pnFontChanged")
}

final class ThemeManager {
    static let shared = ThemeManager()
    private let key = "appTheme"
    private init() {}

    var current: AppTheme {
        get { AppTheme(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .monochrome }
        set {
            guard newValue != current else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            _ruledBackgroundCache.removeAll()       // invalidate texture cache
            NotificationCenter.default.post(name: .pnThemeChanged, object: nil)
        }
    }

    private let fontKey = "appFont"

    /// The note font. While iCloud sync is on, it's also kept in iCloud key-value
    /// storage so every device uses the same one.
    var font: AppFont {
        AppFont(rawValue: UserDefaults.standard.string(forKey: fontKey) ?? "") ?? .default
    }

    @MainActor
    func setFont(_ newValue: AppFont) {
        applyFont(newValue)
        if NoteStore.shared.isICloudEnabled {
            cloudStore.set(newValue.rawValue, forKey: fontKey)
        }
    }

    // MARK: - iCloud font sync

    private let cloudStore = NSUbiquitousKeyValueStore.default

    /// Call once at launch: listens for the font changing on other devices and
    /// picks up a change made while the app wasn't running.
    @MainActor
    func startFontSync() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(cloudStoreChanged(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )
        cloudStore.synchronize()
        syncFontWithICloud()
    }

    /// Reconciles the font with iCloud while sync is on: a font already in iCloud
    /// wins (it's what the user's other devices show), otherwise this device's
    /// choice is uploaded. Call again when the user turns iCloud sync on.
    @MainActor
    func syncFontWithICloud() {
        guard NoteStore.shared.isICloudEnabled else { return }
        if let cloudFont = cloudStore.string(forKey: fontKey).flatMap(AppFont.init(rawValue:)) {
            applyFont(cloudFont)
        } else {
            cloudStore.set(font.rawValue, forKey: fontKey)
        }
    }

    @objc private func cloudStoreChanged(_ notification: Notification) {
        let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
        guard keys.contains(fontKey) else { return }
        Task { @MainActor in self.syncFontWithICloud() }
    }

    private func applyFont(_ newValue: AppFont) {
        guard newValue != font else { return }
        UserDefaults.standard.set(newValue.rawValue, forKey: fontKey)
        NotificationCenter.default.post(name: .pnFontChanged, object: nil)
    }
}
