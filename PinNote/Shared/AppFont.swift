import CoreGraphics

/// The note typeface the user picks in Settings. Kalam and Caveat are bundled
/// (PinNote/Fonts, registered via UIAppFonts in the app and the Live Activity
/// extension); `system` is SF Pro.
enum AppFont: String, CaseIterable {
    case kalam
    case system
    case caveat

    static let `default`: AppFont = .kalam

    /// PostScript names of the regular and bold faces; nil means the system font.
    var regularName: String? {
        switch self {
        case .kalam:  return "Kalam-Regular"
        case .system: return nil
        case .caveat: return "Caveat-Regular"
        }
    }

    var boldName: String? {
        switch self {
        case .kalam:  return "Kalam-Bold"
        case .system: return nil
        case .caveat: return "CaveatRoman-Bold"
        }
    }

    /// Caveat has a much smaller x-height than the others, so it's set larger to
    /// read at the same size.
    var sizeScale: CGFloat {
        self == .caveat ? 1.25 : 1
    }
}
