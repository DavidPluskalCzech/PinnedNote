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
}
