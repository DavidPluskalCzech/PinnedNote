import UIKit

// The handwriting fonts lean to the right: a letter's ink reaches past its advance
// width, which is where UIKit draws the caret, so the caret cuts into the last
// letter. These inputs move the caret past the ink. SF Pro has no such overhang.

enum GlyphOverhang {
    /// How far the ink of `character` reaches past its advance width, in points.
    static func trailing(of character: Character, font: UIFont) -> CGFloat {
        let utf16 = Array(String(character).utf16)
        guard (1...2).contains(utf16.count) else { return 0 }

        let ctFont = font as CTFont
        var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
        guard CTFontGetGlyphsForCharacters(ctFont, utf16, &glyphs, utf16.count), glyphs[0] != 0 else { return 0 }

        var glyph = glyphs[0]
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)
        let ink = CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyph, nil, 1)
        guard !ink.isNull, !ink.isEmpty else { return 0 }
        return max(0, ink.maxX - advance.width)
    }

    /// The caret rect moved just past the ink of the character before `position`,
    /// unless that's whitespace or on another line (the caret starts a wrapped line).
    static func adjustedCaretRect<Input: UIView & UITextInput>(
        _ rect: CGRect,
        for position: UITextPosition,
        in input: Input,
        caretRectFor: (UITextPosition) -> CGRect,
        fontAt: (UITextPosition) -> UIFont?
    ) -> CGRect {
        guard ThemeManager.shared.font != .system,
              let start = input.position(from: position, offset: -1),
              let range = input.textRange(from: start, to: position),
              let character = input.text(in: range)?.last,
              !character.isWhitespace,
              let font = fontAt(start) else { return rect }

        let previousCaret = caretRectFor(start)
        guard abs(previousCaret.midY - rect.midY) < rect.height / 2 else { return rect }

        // UIKit centres the caret on the boundary between letters, so its middle marks
        // where the letter's advance ends. Start the caret a point past the ink.
        let inkEnd = rect.midX + trailing(of: character, font: font)
        var adjusted = rect
        adjusted.origin.x = max(rect.minX, ((inkEnd + 1) * 2).rounded(.up) / 2)
        return adjusted
    }
}

/// The note body's text view, with the caret kept clear of slanted letters.
final class NoteTextView: UITextView {
    override func caretRect(for position: UITextPosition) -> CGRect {
        GlyphOverhang.adjustedCaretRect(
            super.caretRect(for: position),
            for: position,
            in: self,
            caretRectFor: { super.caretRect(for: $0) },
            fontAt: { [unowned self] position in
                let location = self.offset(from: self.beginningOfDocument, to: position)
                guard location >= 0, location < self.textStorage.length else { return self.font }
                return self.textStorage.attribute(.font, at: location, effectiveRange: nil) as? UIFont ?? self.font
            }
        )
    }
}

/// The note title field, with the caret kept clear of slanted letters.
final class NoteTitleField: UITextField {
    override func caretRect(for position: UITextPosition) -> CGRect {
        GlyphOverhang.adjustedCaretRect(
            super.caretRect(for: position),
            for: position,
            in: self,
            caretRectFor: { super.caretRect(for: $0) },
            fontAt: { [unowned self] _ in self.font }
        )
    }
}
