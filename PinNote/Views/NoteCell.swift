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
    /// The pinned note stands a little proud of the others, as if held up by its pin.
    private var isRaised = false

    private let leftAccent   = UIView()
    private let titleLabel   = UILabel()
    private let bodyLabel    = UILabel()
    /// Small secondary line under the text, e.g. the countdown in the trash.
    private let footnoteLabel = UILabel()
    /// Keeps a little room in the title row for the pin, which is drawn above the paper.
    private let pinIcon      = UIView()
    /// The pushpin stuck through the pinned note's paper.
    private let pinBadge     = PushPinView()
    /// Alarm clock for a scheduled pin: in the pin's corner, or under the pin.
    private let timerIcon    = UIImageView()
    private var timerTopConstraint: NSLayoutConstraint!
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

        // Spacer before the text (once an accent bar for the pinned note)
        leftAccent.backgroundColor = .clear
        leftAccent.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(leftAccent)

        // Status icons
        pinIcon.isUserInteractionEnabled = false

        // The pin sits on the paper, in its top-right corner.
        pinBadge.translatesAutoresizingMaskIntoConstraints = false
        paperView.addSubview(pinBadge)

        let timerCfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        timerIcon.image               = UIImage(systemName: "alarm.fill", withConfiguration: timerCfg)
        timerIcon.tintColor           = .pnPrimary
        timerIcon.contentMode         = .scaleAspectFit

        statusStack.axis = .horizontal
        statusStack.alignment = .center
        statusStack.spacing = 5
        timerIcon.translatesAutoresizingMaskIntoConstraints = false
        paperView.addSubview(timerIcon)
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

        footnoteLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        footnoteLabel.numberOfLines = 1
        footnoteLabel.isHidden = true

        let textStack = UIStackView(arrangedSubviews: [titleRow, bodyLabel, footnoteLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(textStack)

        let p = padding
        timerTopConstraint = timerIcon.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 10)
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

            pinIcon.widthAnchor.constraint(equalToConstant: 4),
            pinIcon.heightAnchor.constraint(equalToConstant: 12),
            // Inside the paper, in the corner above and right of the text.
            pinBadge.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 3),
            pinBadge.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -4),
            pinBadge.widthAnchor.constraint(equalToConstant: PushPinView.size.width),
            pinBadge.heightAnchor.constraint(equalToConstant: PushPinView.size.height),
            timerIcon.widthAnchor.constraint(equalToConstant: 17),
            timerIcon.heightAnchor.constraint(equalToConstant: 17),
            // Centred under the pin's head (18 pt into the pin's square from its left).
            timerIcon.centerXAnchor.constraint(equalTo: pinBadge.leadingAnchor, constant: 18),
            timerTopConstraint,

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

    func configure(with note: Note, editing: Bool, selected: Bool,
                   footnote: String? = nil, footnoteSymbol: String? = nil) {
        setFootnote(footnote, symbol: footnoteSymbol)
        paperSeed = withUnsafeBytes(of: note.id.uuid) { $0.load(as: UInt64.self) }
        // Up to about ±1° either way.
        tilt = (CGFloat(paperSeed % 1000) / 1000 - 0.5) * 0.035
        isRaised = note.isPinned && !editing
        paperView.transform = paperTransform(pressed: isHighlighted)
        let dark = ThemeManager.shared.current == .dark
        // Raised: a bigger, softer shadow falling further below.
        paperView.layer.shadowOpacity = isRaised ? (dark ? 0.85 : 0.26) : (dark ? 0.6 : 0.18)
        paperView.layer.shadowRadius = isRaised ? 12 : 6
        paperView.layer.shadowOffset = CGSize(width: 0, height: isRaised ? 9 : 3)
        cardView.setNeedsLayout()

        let hasExplicitTitle = !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        titleLabel.font = hasExplicitTitle ? PN.titleFont(20) : PN.font(14, bold: true)
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
        // The title row keeps a little room in the corner for the pin or alarm.
        pinIcon.isHidden           = !pinned && !scheduled
        timerIcon.isHidden         = !scheduled || editing
        pinBadge.isHidden          = !pinned || editing
        // Alone, the alarm takes the pin's place; with a pin, it sits just below it.
        timerTopConstraint.constant = pinned ? 33 : 9

        // Theme-dependent colors (configure runs on every reload, including theme changes)
        cardView.backgroundColor        = paperRimColor
        paperFace.fillColor             = paperFaceColor(highlighted: isHighlighted).cgColor
        titleLabel.textColor            = .pnPrimary
        bodyLabel.textColor             = .pnPrimary
        pinBadge.refreshColors()
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
        let lift: CGFloat = isRaised ? 1.03 : 1
        let scale = pressed ? lift * 0.98 : lift
        return CGAffineTransform(translationX: 0, y: isRaised ? -2 : 0)
            .rotated(by: tilt)
            .scaledBy(x: scale, y: scale)
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

    /// Updates just the footnote, e.g. a ticking countdown, without a full configure.
    /// `symbol` puts an SF Symbol in front of the text.
    func setFootnote(_ text: String?, symbol: String? = nil) {
        footnoteLabel.isHidden = text == nil
        guard let text else { footnoteLabel.attributedText = nil; return }
        let line = NSMutableAttributedString()
        if let symbol, let image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(font: footnoteLabel.font)
        )?.withTintColor(.pnSecondary, renderingMode: .alwaysOriginal) {
            line.append(NSAttributedString(attachment: NSTextAttachment(image: image)))
            line.append(NSAttributedString(string: " "))
        }
        line.append(NSAttributedString(string: text))
        line.addAttributes([.font: footnoteLabel.font as Any, .foregroundColor: UIColor.pnSecondary],
                           range: NSRange(location: 0, length: line.length))
        footnoteLabel.attributedText = line
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

// MARK: - Push pin

/// A pushpin stuck through the paper: the pin leans to the right and casts a small
/// shadow; where its point goes in, the paper has a little hole, a soft dimple
/// and a few tiny creases.
private final class PushPinView: UIView {

    static let size = CGSize(width: 34, height: 34)

    private let pin = UIImageView()
    private let puncture = CALayer()
    private let dimple = CAGradientLayer()
    private let hole = CAShapeLayer()
    private let creases = CAShapeLayer()

    /// How far the pin leans to the right.
    private let lean: CGFloat = 0.45
    private let pinSize: CGFloat = 22
    private var pinCenter: CGPoint { CGPoint(x: 18, y: 14) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        // Puncture, under the pin.
        dimple.type = .radial
        dimple.startPoint = CGPoint(x: 0.5, y: 0.5)
        dimple.endPoint = CGPoint(x: 1, y: 1)
        puncture.addSublayer(dimple)
        creases.fillColor = nil
        creases.lineWidth = 0.6
        creases.lineCap = .round
        puncture.addSublayer(creases)
        puncture.addSublayer(hole)
        layer.addSublayer(puncture)

        pin.image = UIImage(systemName: "pin.fill",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        pin.contentMode = .scaleAspectFit
        pin.layer.shadowColor = UIColor.black.cgColor
        pin.layer.shadowOpacity = 0.28
        pin.layer.shadowRadius = 1.2
        pin.layer.shadowOffset = CGSize(width: 1.2, height: 1.6)
        addSubview(pin)
        refreshColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        pin.transform = .identity
        pin.bounds = CGRect(x: 0, y: 0, width: pinSize, height: pinSize)
        pin.center = pinCenter
        pin.transform = CGAffineTransform(rotationAngle: lean)

        // The point is at the bottom of the upright symbol; leaning turns it left.
        let reach = pinSize / 2 - 0.5
        let tip = CGPoint(x: pinCenter.x - reach * sin(lean), y: pinCenter.y + reach * cos(lean))

        let area = CGRect(x: tip.x - 7, y: tip.y - 6, width: 14, height: 12)
        puncture.frame = area
        dimple.frame = CGRect(x: 1, y: 1.5, width: 12, height: 9)
        let center = CGPoint(x: area.width / 2, y: area.height / 2)
        hole.path = UIBezierPath(ovalIn: CGRect(x: center.x - 1.4, y: center.y - 1.1, width: 2.8, height: 2.2)).cgPath

        let lines = UIBezierPath()
        for (angle, length) in [(-2.4, 3.6), (-0.9, 2.9), (0.4, 3.9), (2.1, 3.2)] as [(CGFloat, CGFloat)] {
            lines.move(to: CGPoint(x: center.x + cos(angle) * 1.8, y: center.y + sin(angle) * 1.5))
            lines.addLine(to: CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length * 0.8))
        }
        creases.path = lines.cgPath
    }

    func refreshColors() {
        let ink = UIColor.pnPrimary
        pin.tintColor = ink
        dimple.colors = [ink.withAlphaComponent(0.28).cgColor, ink.withAlphaComponent(0).cgColor]
        hole.fillColor = ink.withAlphaComponent(0.85).cgColor
        creases.strokeColor = ink.withAlphaComponent(0.2).cgColor
    }
}
