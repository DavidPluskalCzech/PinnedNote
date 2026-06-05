import UIKit

// MARK: - Color palette (dynamic — reads current theme each time)

extension UIColor {

    /// Main background (screen / table background)
    static var pnBackground: UIColor {
        switch ThemeManager.shared.current {
        case .monochrome: return UIColor(red: 0.975, green: 0.972, blue: 0.965, alpha: 1)
        case .dark:       return UIColor(red: 0.010, green: 0.011, blue: 0.013, alpha: 1)
        case .blossom:    return UIColor(red: 0.998, green: 0.905, blue: 0.930, alpha: 1)
        }
    }

    /// Card / cell surface
    static var pnSurface: UIColor {
        switch ThemeManager.shared.current {
        case .monochrome: return .white
        case .dark:       return UIColor(red: 0.058, green: 0.060, blue: 0.066, alpha: 1)
        case .blossom:    return UIColor(red: 1.0, green: 0.940, blue: 0.958, alpha: 1)
        }
    }

    static var pnHighlightedSurface: UIColor {
        switch ThemeManager.shared.current {
        case .monochrome: return UIColor(white: 0, alpha: 0.04)
        case .dark:       return UIColor(red: 0.095, green: 0.098, blue: 0.106, alpha: 1)
        case .blossom:    return UIColor(red: 0.975, green: 0.850, blue: 0.890, alpha: 1)
        }
    }

    /// Ink / primary accent
    static var pnPrimary: UIColor {
        switch ThemeManager.shared.current {
        case .monochrome: return UIColor(white: 0.08, alpha: 1)
        case .dark:       return UIColor(red: 0.94, green: 0.92, blue: 0.86, alpha: 1)
        case .blossom:    return UIColor(red: 0.55, green: 0.33, blue: 0.41, alpha: 1)
        }
    }

    /// Secondary text (dates, captions)
    static var pnSecondary: UIColor {
        switch ThemeManager.shared.current {
        case .monochrome: return UIColor(white: 0.45, alpha: 1)
        case .dark:       return UIColor(red: 0.68, green: 0.65, blue: 0.59, alpha: 1)
        case .blossom:    return UIColor(red: 0.65, green: 0.48, blue: 0.53, alpha: 1)
        }
    }

    /// Very light separator
    static var pnSeparator: UIColor {
        switch ThemeManager.shared.current {
        case .monochrome: return UIColor(white: 0.87, alpha: 1)
        case .dark:       return UIColor(red: 0.130, green: 0.128, blue: 0.118, alpha: 1)
        case .blossom:    return UIColor(red: 0.90, green: 0.80, blue: 0.83, alpha: 1)
        }
    }

    /// Ruled-line tint inside UITextView
    static var pnRuledLine: UIColor {
        switch ThemeManager.shared.current {
        case .monochrome: return UIColor(white: 0, alpha: 0.055)
        case .dark:       return UIColor(white: 1, alpha: 0.075)
        case .blossom:    return UIColor(red: 0.55, green: 0.33, blue: 0.41, alpha: 0.07)
        }
    }

    /// Destructive action (always muted red)
    static var pnDestructive: UIColor {
        switch ThemeManager.shared.current {
        case .dark: return UIColor(red: 0.92, green: 0.30, blue: 0.26, alpha: 1)
        default:    return UIColor(red: 0.72, green: 0.12, blue: 0.08, alpha: 1)
        }
    }

    /// Cursor and text-selection handles.
    static var pnTextSelection: UIColor {
        switch ThemeManager.shared.current {
        case .dark:       return UIColor(red: 0.44, green: 0.62, blue: 1.0, alpha: 1)
        case .blossom:    return UIColor(red: 0.78, green: 0.20, blue: 0.46, alpha: 1)
        case .monochrome: return UIColor.systemBlue
        }
    }

    /// Solid floating controls used for prominent app actions.
    static var pnFloatingControlBackground: UIColor {
        switch ThemeManager.shared.current {
        case .dark:
            return UIColor(red: 0.125, green: 0.128, blue: 0.138, alpha: 1)
        case .blossom:
            return UIColor(red: 0.985, green: 0.865, blue: 0.905, alpha: 1)
        case .monochrome:
            return .pnSurface
        }
    }
}

// MARK: - Typography

enum PN {
    private static let regularName = "Noteworthy-Light"
    private static let boldName    = "Noteworthy-Bold"

    /// Languages where Noteworthy renders poorly — use system font instead.
    private static let systemFontLanguages: Set<String> = ["ja"]

    static func font(_ size: CGFloat, bold: Bool = false) -> UIFont {
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        if systemFontLanguages.contains(lang) {
            return bold
                ? .boldSystemFont(ofSize: size)
                : .systemFont(ofSize: size, weight: .light)
        }
        let name = bold ? boldName : regularName
        return UIFont(name: name, size: size) ?? (bold
            ? .boldSystemFont(ofSize: size)
            : .systemFont(ofSize: size, weight: .light))
    }

    static let hairline:     CGFloat = 1 / UIScreen.main.scale
    static let padding:      CGFloat = 18
    static let cornerRadius: CGFloat = 0
    static let readableMaxWidth: CGFloat = 1024

    static let floatingControlHeight: CGFloat = 52
    static let floatingControlCornerRadius: CGFloat = 26
    static let floatingControlShadowRadius: CGFloat = 21
    static let floatingControlShadowOffset = CGSize(width: 0, height: 9)

    static var floatingControlShadowOpacity: Float {
        ThemeManager.shared.current == .dark ? 0.56 : 0.31
    }
}

extension UIView {
    func pnAddReadableContentGuide(maxWidth: CGFloat = PN.readableMaxWidth) -> UILayoutGuide {
        let guide = UILayoutGuide()
        addLayoutGuide(guide)
        NSLayoutConstraint.activate([
            guide.centerXAnchor.constraint(equalTo: centerXAnchor),
            guide.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            guide.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            guide.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            guide.widthAnchor.constraint(equalTo: widthAnchor).withPriority(.defaultHigh),
        ])
        return guide
    }
}

extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

// MARK: - Ruled-line background for UITextView

var _ruledBackgroundCache: [String: UIColor] = [:]

func pnRuledBackground(lineHeight: CGFloat, topInset: CGFloat = 0) -> UIColor {
    let height = ceil(lineHeight)
    let offset = topInset.truncatingRemainder(dividingBy: height)
    let normalizedOffset = offset < 0 ? offset + height : offset
    let key = "\(height)-\(round(normalizedOffset * 1000) / 1000)"
    if let cached = _ruledBackgroundCache[key] { return cached }

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: height))
    let image = renderer.image { ctx in
        UIColor.pnRuledLine.setFill()
        let y = max(0, min(height - PN.hairline, normalizedOffset - PN.hairline / 2))
        ctx.fill(CGRect(x: 0, y: y, width: 1, height: PN.hairline))
    }
    let color = UIColor(patternImage: image.resizableImage(withCapInsets: .zero, resizingMode: .tile))
    _ruledBackgroundCache[key] = color
    return color
}
