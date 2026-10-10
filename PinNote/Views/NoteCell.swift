import UIKit

/// A note tile in the two-column list. Its height follows the content: the title
/// and up to `maxBodyLines` lines of the note, so short notes give low tiles.
final class NoteCell: UICollectionViewCell {

    static let reuseID = "NoteCell"

    /// Longest body a tile shows; longer notes end with an ellipsis.
    static let maxBodyLines = 10

    // MARK: - Layout constants

    private let padding: CGFloat = 14
    /// How deep the torn edges bite into the paper: the top, torn off the pad, the
    /// most; the other sides less.
    private let topTearDepth: CGFloat = 8
    private let sideTearDepth: CGFloat = 5
    private let selectionSize: CGFloat = 22

    // MARK: - Subviews

    /// Holds the paper and its shadow; carries the slight per-note tilt.
    private let paperView    = UIView()
    /// The torn-off sheet — all content lives inside this.
    private let cardView     = LayoutReportingView()
    private let paperMask    = CAShapeLayer()
    /// The paper's face, inset from the torn outline by an uneven strip: the
    /// cardView's own color shows in that strip as the white torn-off fibres.
    private let paperFace    = CAShapeLayer()

    /// Per-note shape: the torn edge and tilt come from the note's ID, so every
    /// sheet looks different but stays the same across reloads.
    private var paperSeed: UInt64 = 0
    private var tilt: CGFloat = 0

    private let leftAccent   = UIView()
    private let titleLabel   = UILabel()
    private let bodyLabel    = UILabel()
    private let pinIcon      = UIImageView()
    private let timerIcon    = UIImageView()
    private let statusStack  = UIStackView()

    // Custom multi-select indicator, shown in place of the status icons
    private let selectionIndicator = UIView()
    private let selectionRing = UIView()
    private let selectionFill = UIView()

    private var selectionEditing = false
    private var selectionSelected = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func buildLayout() {
        backgroundColor             = .clear
        contentView.backgroundColor = .clear

        paperView.translatesAutoresizingMaskIntoConstraints = false
        paperView.layer.shadowColor  = UIColor.black.cgColor
        // A soft shadow below, as if the paper lies on a desk.
        paperView.layer.shadowOffset = CGSize(width: 0, height: 3)
        paperView.layer.shadowRadius = 6
        contentView.addSubview(paperView)

        cardView.backgroundColor        = paperRimColor
        cardView.layer.mask             = paperMask
        cardView.onLayout = { [weak self] in self?.updatePaperShape() }
        cardView.layer.insertSublayer(paperFace, at: 0)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        paperView.addSubview(cardView)

        // Left accent bar for the pinned note — clipped by the paper's outline
        leftAccent.backgroundColor = .pnPrimary
        leftAccent.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(leftAccent)

        // Status icons
        let pinCfg = UIImage.SymbolConfiguration(pointSize: 9, weight: .regular)
        pinIcon.image               = UIImage(systemName: "pin.fill", withConfiguration: pinCfg)
        pinIcon.tintColor           = .pnPrimary
        pinIcon.contentMode         = .scaleAspectFit

        let timerCfg = UIImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        timerIcon.image               = UIImage(systemName: "timer.circle.fill", withConfiguration: timerCfg)
        timerIcon.tintColor           = .pnPrimary
        timerIcon.contentMode         = .scaleAspectFit

        statusStack.axis = .horizontal
        statusStack.alignment = .center
        statusStack.spacing = 5
        statusStack.addArrangedSubview(timerIcon)
        statusStack.addArrangedSubview(pinIcon)

        // Selection ring + fill
        selectionRing.layer.cornerRadius = selectionSize / 2
        selectionRing.layer.borderWidth  = 1.5
        selectionRing.layer.borderColor  = UIColor.pnPrimary.cgColor
        selectionRing.translatesAutoresizingMaskIntoConstraints = false
        selectionIndicator.addSubview(selectionRing)

        let fillSize = selectionSize - 8
        selectionFill.layer.cornerRadius = fillSize / 2
        selectionFill.backgroundColor    = .pnPrimary
        selectionFill.translatesAutoresizingMaskIntoConstraints = false
        selectionIndicator.addSubview(selectionFill)
        selectionIndicator.isHidden = true

        // Title
        titleLabel.textColor     = .pnPrimary
        titleLabel.numberOfLines = 3
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Title row: title on the left, status icons or the selection ring on the right
        let titleRow = UIStackView(arrangedSubviews: [titleLabel, statusStack, selectionIndicator])
        titleRow.axis = .horizontal
        titleRow.alignment = .top
        titleRow.spacing = 6

        // Body preview
        bodyLabel.textColor     = .pnPrimary
        bodyLabel.numberOfLines = Self.maxBodyLines
        bodyLabel.lineBreakMode = .byTruncatingTail

        let textStack = UIStackView(arrangedSubviews: [titleRow, bodyLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(textStack)

        let p = padding
        NSLayoutConstraint.activate([
            paperView.topAnchor.constraint(equalTo: contentView.topAnchor),
            paperView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            paperView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            paperView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            cardView.topAnchor.constraint(equalTo: paperView.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: paperView.bottomAnchor),
            cardView.leadingAnchor.constraint(equalTo: paperView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: paperView.trailingAnchor),

            // Inside the torn left edge, so the tear never eats into the bar.
            leftAccent.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: sideTearDepth),
            leftAccent.topAnchor.constraint(equalTo: cardView.topAnchor),
            leftAccent.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            leftAccent.widthAnchor.constraint(equalToConstant: 4),

            pinIcon.widthAnchor.constraint(equalToConstant: 12),
            pinIcon.heightAnchor.constraint(equalToConstant: 12),
            timerIcon.widthAnchor.constraint(equalToConstant: 13),
            timerIcon.heightAnchor.constraint(equalToConstant: 13),

            selectionIndicator.widthAnchor.constraint(equalToConstant: selectionSize),
            selectionIndicator.heightAnchor.constraint(equalToConstant: selectionSize),
            selectionRing.topAnchor.constraint(equalTo: selectionIndicator.topAnchor),
            selectionRing.bottomAnchor.constraint(equalTo: selectionIndicator.bottomAnchor),
            selectionRing.leadingAnchor.constraint(equalTo: selectionIndicator.leadingAnchor),
            selectionRing.trailingAnchor.constraint(equalTo: selectionIndicator.trailingAnchor),
            selectionFill.centerXAnchor.constraint(equalTo: selectionIndicator.centerXAnchor),
            selectionFill.centerYAnchor.constraint(equalTo: selectionIndicator.centerYAnchor),
            selectionFill.widthAnchor.constraint(equalToConstant: fillSize),
            selectionFill.heightAnchor.constraint(equalToConstant: fillSize),

            textStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: p + topTearDepth),
            textStack.leadingAnchor.constraint(equalTo: leftAccent.trailingAnchor, constant: p - 4),
            textStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -(p + sideTearDepth)),
            textStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -(p + sideTearDepth)),
        ])
    }

    // MARK: - Configure

    override func prepareForReuse() {
        super.prepareForReuse()
        paperView.transform = .identity
        // A cell reused mid-landing must not stay hidden.
        contentView.layer.removeAllAnimations()
        contentView.alpha = 1
        contentView.transform = .identity
    }

    /// Redraws the torn outline, fibre rim and shadow for the paper's current size.
    /// Runs from the paper's own layout, so it follows every size change — a reused
    /// cell given a taller tile, edit mode, a theme or font change.
    private func updatePaperShape() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let path = Self.tornPaperPath(
            in: cardView.bounds, topDepth: topTearDepth, sideDepth: sideTearDepth, seed: paperSeed
        )
        paperMask.path = path.cgPath
        // Its own tear, a little inside the outline, so the fibre strip varies in width.
        paperFace.path = Self.tornPaperPath(
            in: cardView.bounds.insetBy(dx: 2.5, dy: 2.5), topDepth: 8, sideDepth: 6,
            seed: paperSeed &* 0x2545_F491_4F6C_DD1D ^ 0xA5A5
        ).cgPath
        paperView.layer.shadowPath = path.cgPath
    }

    func configure(with note: Note, editing: Bool, selected: Bool) {
        paperSeed = withUnsafeBytes(of: note.id.uuid) { $0.load(as: UInt64.self) }
        // Up to about ±1° either way.
        tilt = (CGFloat(paperSeed % 1000) / 1000 - 0.5) * 0.035
        paperView.transform = paperTransform(pressed: isHighlighted)
        paperView.layer.shadowOpacity = ThemeManager.shared.current == .dark ? 0.6 : 0.18
        cardView.setNeedsLayout()

        let hasExplicitTitle = !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        titleLabel.font = hasExplicitTitle ? PN.font(20, bold: true) : PN.font(14, bold: true)
        bodyLabel.font = PN.font(14, bold: true)
        let title = NSMutableAttributedString(attributedString: checklistAttributedText(
            note.displayTitle,
            font: titleLabel.font,
            color: .pnPrimary
        ))
        if hasExplicitTitle {
            title.addAttributes(PN.titleWeightAttributes(color: .pnPrimary),
                                range: NSRange(location: 0, length: title.length))
        }
        titleLabel.attributedText = title
        let previewBody = note.previewBody(maxLines: Self.maxBodyLines)
        bodyLabel.attributedText = checklistAttributedText(
            previewBody,
            font: bodyLabel.font,
            color: .pnPrimary
        )
        bodyLabel.isHidden = previewBody.isEmpty

        let pinned = note.isPinned
        let scheduled = (note.scheduledPinDate ?? .distantPast) > Date()
        pinIcon.isHidden           = !pinned
        timerIcon.isHidden         = !scheduled
        leftAccent.backgroundColor = pinned ? .pnPrimary : .clear

        // Theme-dependent colors (configure runs on every reload, including theme changes)
        cardView.backgroundColor        = paperRimColor
        paperFace.fillColor             = paperFaceColor(highlighted: isHighlighted).cgColor
        titleLabel.textColor            = .pnPrimary
        bodyLabel.textColor             = .pnPrimary
        pinIcon.tintColor               = .pnPrimary
        timerIcon.tintColor             = .pnPrimary
        selectionFill.backgroundColor   = .pnPrimary
        selectionRing.layer.borderColor = UIColor.pnPrimary.cgColor

        selectionEditing = editing
        statusStack.isHidden = editing || (!pinned && !scheduled)
        selectionIndicator.isHidden = !editing
        applySelected(selected, animated: false)
    }

    /// The paper's face.
    private func paperFaceColor(highlighted: Bool) -> UIColor {
        switch ThemeManager.shared.current {
        case .monochrome:
            return highlighted
                ? UIColor(red: 0.955, green: 0.953, blue: 0.947, alpha: 1)
                : .white
        case .dark, .blossom:
            return highlighted ? .pnHighlightedSurface : .pnSurface
        }
    }

    /// The torn-off fibres round the edge: a light grey round the white light-theme
    /// paper, a pale pink on blossom, lighter than the face on dark.
    private var paperRimColor: UIColor {
        switch ThemeManager.shared.current {
        case .monochrome: return UIColor(red: 0.905, green: 0.903, blue: 0.897, alpha: 1)
        case .blossom:    return UIColor(red: 1.0, green: 0.958, blue: 0.970, alpha: 1)
        case .dark:       return UIColor(red: 0.135, green: 0.138, blue: 0.148, alpha: 1)
        }
    }

    private func paperTransform(pressed: Bool) -> CGAffineTransform {
        let rotation = CGAffineTransform(rotationAngle: tilt)
        return pressed ? rotation.scaledBy(x: 0.98, y: 0.98) : rotation
    }

    // MARK: - Torn paper

    /// A torn scrap of paper: every edge is ragged, the top (torn off the pad)
    /// the most, with clipped, rounded corners and soft rounded teeth. The same
    /// seed always gives the same tear.
    static func tornPaperPath(in rect: CGRect, topDepth: CGFloat, sideDepth: CGFloat, seed: UInt64) -> UIBezierPath {
        var random = SplitMix64(seed: seed)
        let path = UIBezierPath()
        guard rect.width > sideDepth * 4, rect.height > topDepth + sideDepth * 3 else { return path }

        // Clockwise round the rect; each edge's inward normal points into the paper.
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ]
        let depths = [topDepth, sideDepth, sideDepth, sideDepth]

        // Points along the torn outline. Each edge stops short of the corners, so
        // the corners come out clipped; the smoothing below then rounds them.
        var points: [CGPoint] = []
        for edge in 0..<4 {
            let from = corners[edge]
            let to = corners[(edge + 1) % 4]
            let depth = depths[edge]
            let length = hypot(to.x - from.x, to.y - from.y)
            let direction = CGPoint(x: (to.x - from.x) / length, y: (to.y - from.y) / length)
            let inward = CGPoint(x: -direction.y, y: direction.x)
            let phase = random.unit() * .pi * 2
            let cornerCut = 4 + random.unit() * 4

            // Irregular teeth riding on a gentle wave, with the odd deeper bite
            // where the paper tore unevenly.
            func point(at distance: CGFloat) -> CGPoint {
                let wave = (sin(distance / length * .pi * 1.6 + phase) + 1) / 2 * depth * 0.4
                var tooth = random.unit() * depth * 0.35
                if random.unit() < 0.18 { tooth += random.unit() * depth * 0.25 }
                let offset = wave + tooth
                return CGPoint(
                    x: from.x + direction.x * distance + inward.x * offset,
                    y: from.y + direction.y * distance + inward.y * offset
                )
            }

            var distance = cornerCut
            while distance < length - cornerCut {
                points.append(point(at: distance))
                distance += 3 + random.unit() * 5
            }
            points.append(point(at: length - cornerCut))
        }

        // Curves through the midpoints, bending at each point: the teeth become
        // soft nibbles instead of sharp spikes.
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        path.move(to: midpoint(points[points.count - 1], points[0]))
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            path.addQuadCurve(to: midpoint(points[index], next), controlPoint: points[index])
        }
        path.close()
        return path
    }

    private func checklistAttributedText(_ text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: color]))
            }
            result.append(checklistAttributedLine(line, font: font, color: color))
        }

        return result
    }

    private func checklistAttributedLine(_ line: String, font: UIFont, color: UIColor) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        guard let item = NoteListItem(line: line) else {
            return NSAttributedString(string: line, attributes: attributes)
        }

        // Marker, then the item text; wrapped lines indent to the text, as in the editor.
        let attributed = NSMutableAttributedString(string: String(item.indent), attributes: attributes)
        switch item.kind {
        case .checklist:
            attributed.append(checklistAttachment(checked: item.isChecked, font: font, color: color))
            attributed.append(NSAttributedString(string: "   ", attributes: attributes))
        case .bullet:
            attributed.append(NSAttributedString(string: "•  ", attributes: attributes))
        }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = ceil(attributed.size().width)
        attributed.append(NSAttributedString(string: item.text, attributes: attributes))
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attributed.length))
        return attributed
    }

    private func checklistAttachment(checked: Bool, font: UIFont, color: UIColor) -> NSAttributedString {
        let size = min(18, max(15, font.lineHeight - 2))
        // The check flies out past the box's top-right corner, so the image has room there.
        let overshoot = ceil(size * 0.15)
        let attachment = NSTextAttachment()
        attachment.image = drawChecklistImage(checked: checked, size: size, overshoot: overshoot, color: color)
        attachment.bounds = CGRect(
            x: 0,
            y: (font.capHeight - size) / 2,
            width: size + overshoot,
            height: size + overshoot
        )
        return NSAttributedString(attachment: attachment)
    }

    private func drawChecklistImage(checked: Bool, size: CGFloat, overshoot: CGFloat, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false

        let canvas = CGSize(width: size + overshoot, height: size + overshoot)
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            color.setFill()
            let box = CGRect(x: 0, y: overshoot, width: size, height: size)
            UIBezierPath(cgPath: HandDrawnCheckbox.path(in: box, checked: checked)).fill()
        }
    }

    // MARK: - Landing

    /// Hidden, ready to land (see `land(after:)`).
    func prepareToLand() {
        contentView.alpha = 0
        contentView.transform = CGAffineTransform(translationX: 0, y: -14).scaledBy(x: 1.04, y: 1.04)
    }

    /// Settles onto the canvas like a sheet of paper floating down onto a desk:
    /// fades in while drifting down and easing to rest, without a bounce.
    func land(after delay: TimeInterval) {
        UIView.animate(withDuration: 0.55, delay: delay, options: [.curveEaseOut, .allowUserInteraction]) {
            self.contentView.alpha = 1
        }
        UIView.animate(
            withDuration: 1.1,
            delay: delay,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction]
        ) {
            self.contentView.transform = .identity
        }
    }

    // MARK: - Selection

    func applySelected(_ selected: Bool, animated: Bool = true) {
        selectionSelected = selectionEditing && selected
        let changes = {
            self.selectionFill.alpha = self.selectionSelected ? 1 : 0
            self.selectionFill.transform = self.selectionSelected ? .identity : CGAffineTransform(scaleX: 0.72, y: 0.72)
        }
        guard animated else {
            UIView.performWithoutAnimation(changes)
            return
        }
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }

    // MARK: - Highlight

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.paperFace.fillColor = self.paperFaceColor(highlighted: self.isHighlighted).cgColor
                self.paperView.transform = self.paperTransform(pressed: self.isHighlighted)
            }
        }
    }
}

/// Small deterministic random generator, so a note's paper looks the same every time.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in 0...1.
    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }
}

/// Reports each layout pass, so shapes drawn for its size can follow it.
private final class LayoutReportingView: UIView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
