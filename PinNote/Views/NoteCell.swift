import UIKit

final class NoteCell: UITableViewCell {

    static let reuseID = "NoteCell"

    // MARK: - Layout constants

    private let hMargin:  CGFloat = 16   // horizontal gap from screen edge to card
    private let vMargin:  CGFloat = 6    // vertical gap between cards
    private let cardRadius: CGFloat = 12

    // MARK: - Subviews

    private let quickPinRevealView = UIView()
    private let quickPinCircle     = UIView()
    private let quickPinIcon       = UIImageView()

    /// The visible rounded card — all content lives inside this.
    private let cardView     = UIView()

    private let leftAccent   = UIView()
    private let titleLabel   = UILabel()
    private let bodyLabel    = UILabel()
    private let pinIcon      = UIImageView()
    private let timerIcon    = UIImageView()
    private let statusStack  = UIStackView()

    // Custom multi-select indicator
    private let selectionRing = UIView()
    private let selectionFill = UIView()

    // Shifts text right when selection ring is visible
    private var textLeadingConstraint: NSLayoutConstraint!
    private var selectionEditing = false
    private var selectionSelected = false

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func buildLayout() {
        backgroundColor             = .pnBackground
        contentView.backgroundColor = .pnBackground
        selectionStyle              = .none

        // Quick pin reveal shown behind the card during a short right swipe.
        quickPinRevealView.backgroundColor = .clear
        quickPinRevealView.alpha = 0
        quickPinRevealView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(quickPinRevealView)

        quickPinCircle.backgroundColor = .systemBlue
        quickPinCircle.layer.cornerRadius = 23
        quickPinCircle.translatesAutoresizingMaskIntoConstraints = false
        quickPinRevealView.addSubview(quickPinCircle)

        let quickPinCfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        quickPinIcon.image = UIImage(systemName: "pin.fill", withConfiguration: quickPinCfg)
        quickPinIcon.tintColor = .white
        quickPinIcon.contentMode = .scaleAspectFit
        quickPinIcon.translatesAutoresizingMaskIntoConstraints = false
        quickPinCircle.addSubview(quickPinIcon)

        // Card
        cardView.backgroundColor        = .pnSurface
        cardView.layer.cornerRadius     = cardRadius
        cardView.layer.cornerCurve      = .continuous
        cardView.layer.masksToBounds    = true
        cardView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cardView)

        NSLayoutConstraint.activate([
            quickPinRevealView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: vMargin),
            quickPinRevealView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -vMargin),
            quickPinRevealView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: hMargin),
            quickPinRevealView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -hMargin),

            quickPinCircle.leadingAnchor.constraint(equalTo: quickPinRevealView.leadingAnchor, constant: 22),
            quickPinCircle.centerYAnchor.constraint(equalTo: quickPinRevealView.centerYAnchor),
            quickPinCircle.widthAnchor.constraint(equalToConstant: 46),
            quickPinCircle.heightAnchor.constraint(equalToConstant: 46),

            quickPinIcon.centerXAnchor.constraint(equalTo: quickPinCircle.centerXAnchor),
            quickPinIcon.centerYAnchor.constraint(equalTo: quickPinCircle.centerYAnchor),
            quickPinIcon.widthAnchor.constraint(equalToConstant: 22),
            quickPinIcon.heightAnchor.constraint(equalToConstant: 22),

            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: vMargin),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -vMargin),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: hMargin),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -hMargin),
        ])

        // Left accent bar — clipped by cardView's corner mask
        leftAccent.backgroundColor = .pnPrimary
        leftAccent.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(leftAccent)

        // Status icons
        let pinCfg = UIImage.SymbolConfiguration(pointSize: 9, weight: .regular)
        pinIcon.image               = UIImage(systemName: "pin.fill", withConfiguration: pinCfg)
        pinIcon.tintColor           = .pnPrimary
        pinIcon.contentMode         = .scaleAspectFit
        pinIcon.translatesAutoresizingMaskIntoConstraints = false

        let timerCfg = UIImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        timerIcon.image               = UIImage(systemName: "timer.circle.fill", withConfiguration: timerCfg)
        timerIcon.tintColor           = .pnPrimary
        timerIcon.contentMode         = .scaleAspectFit
        timerIcon.translatesAutoresizingMaskIntoConstraints = false

        statusStack.axis = .horizontal
        statusStack.alignment = .center
        statusStack.spacing = 5
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusStack.addArrangedSubview(timerIcon)
        statusStack.addArrangedSubview(pinIcon)
        cardView.addSubview(statusStack)

        // Title
        titleLabel.font          = PN.font(18, bold: true)
        titleLabel.textColor     = .pnPrimary
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(titleLabel)

        // Body preview
        bodyLabel.font          = PN.font(14, bold: true)
        bodyLabel.textColor     = .pnPrimary
        bodyLabel.numberOfLines = 4
        bodyLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(bodyLabel)

        // Selection ring
        let ringSize: CGFloat = 22
        selectionRing.isHidden           = false
        selectionRing.alpha              = 0
        selectionRing.layer.cornerRadius  = ringSize / 2
        selectionRing.layer.borderWidth   = 1.5
        selectionRing.layer.borderColor   = UIColor.pnPrimary.cgColor
        selectionRing.backgroundColor     = .clear
        selectionRing.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(selectionRing)

        // Selection fill
        let fillSize: CGFloat = ringSize - 8
        selectionFill.isHidden           = false
        selectionFill.alpha              = 0
        selectionFill.layer.cornerRadius  = fillSize / 2
        selectionFill.backgroundColor     = .pnPrimary
        selectionFill.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(selectionFill)

        let p = PN.padding
        textLeadingConstraint = titleLabel.leadingAnchor.constraint(
            equalTo: leftAccent.trailingAnchor, constant: p
        )

        NSLayoutConstraint.activate([
            // Accent bar
            leftAccent.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            leftAccent.topAnchor.constraint(equalTo: cardView.topAnchor),
            leftAccent.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            leftAccent.widthAnchor.constraint(equalToConstant: 4),

            // Selection ring
            selectionRing.leadingAnchor.constraint(equalTo: leftAccent.trailingAnchor, constant: 10),
            selectionRing.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            selectionRing.widthAnchor.constraint(equalToConstant: ringSize),
            selectionRing.heightAnchor.constraint(equalToConstant: ringSize),

            // Selection fill
            selectionFill.centerXAnchor.constraint(equalTo: selectionRing.centerXAnchor),
            selectionFill.centerYAnchor.constraint(equalTo: selectionRing.centerYAnchor),
            selectionFill.widthAnchor.constraint(equalToConstant: fillSize),
            selectionFill.heightAnchor.constraint(equalToConstant: fillSize),

            // Status icons
            statusStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -p),
            statusStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: p),
            pinIcon.widthAnchor.constraint(equalToConstant: 12),
            pinIcon.heightAnchor.constraint(equalToConstant: 12),
            timerIcon.widthAnchor.constraint(equalToConstant: 13),
            timerIcon.heightAnchor.constraint(equalToConstant: 13),

            // Text block
            textLeadingConstraint,
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: statusStack.leadingAnchor, constant: -8),

            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -p),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            bodyLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - Configure

    override func prepareForReuse() {
        super.prepareForReuse()
        resetSelectionIndicator()
        resetQuickPinReveal(animated: false)
    }

    func configure(with note: Note, editing: Bool, selected: Bool) {
        configure(with: note)
        setSelectionState(editing: editing, selected: selected, animated: false)
    }

    func configure(with note: Note) {
        let hasExplicitTitle = !note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        titleLabel.font = hasExplicitTitle ? PN.font(18, bold: true) : PN.font(14, bold: true)
        bodyLabel.font = PN.font(14, bold: true)
        titleLabel.text = note.displayTitle
        let previewBody = note.previewBody
        bodyLabel.text = previewBody
        bodyLabel.isHidden = previewBody.isEmpty

        let pinned = note.isPinned
        let scheduled = (note.scheduledPinDate ?? .distantPast) > Date()
        pinIcon.isHidden           = !pinned
        timerIcon.isHidden         = !scheduled
        statusStack.isHidden       = !pinned && !scheduled
        leftAccent.backgroundColor = pinned ? .pnPrimary : .clear

        // Refresh theme-dependent colors (called on every reloadData, including after theme change)
        backgroundColor                   = .pnBackground
        contentView.backgroundColor       = .pnBackground
        cardView.backgroundColor          = .pnSurface
        quickPinRevealView.alpha          = 0
        cardView.transform                = .identity
        titleLabel.textColor              = .pnPrimary
        bodyLabel.textColor               = .pnPrimary
        pinIcon.tintColor                 = .pnPrimary
        timerIcon.tintColor               = .pnPrimary
        selectionFill.backgroundColor     = .pnPrimary
        selectionRing.layer.borderColor   = UIColor.pnPrimary.cgColor
    }

    // MARK: - Edit mode

    func applyEditMode(_ editing: Bool, animated: Bool = true) {
        setSelectionState(editing: editing, selected: editing && selectionSelected, animated: animated)
    }

    func applySelected(_ selected: Bool, animated: Bool = true) {
        setSelectionState(editing: selectionEditing, selected: selected, animated: animated)
    }

    func resetSelectionIndicator() {
        setSelectionState(editing: false, selected: false, animated: false)
    }

    private func setSelectionState(editing: Bool, selected: Bool, animated: Bool) {
        selectionEditing = editing
        selectionSelected = editing && selected

        contentView.layoutIfNeeded()
        cardView.layoutIfNeeded()
        selectionRing.layer.removeAllAnimations()
        selectionFill.layer.removeAllAnimations()
        cardView.layer.removeAllAnimations()

        let block = {
            self.textLeadingConstraint.constant = editing ? 44 : PN.padding
            self.selectionRing.alpha = editing ? 1 : 0
            self.selectionFill.alpha = editing && selected ? 1 : 0
            self.selectionRing.transform = editing ? .identity : CGAffineTransform(scaleX: 0.82, y: 0.82)
            self.selectionFill.transform = editing && selected ? .identity : CGAffineTransform(scaleX: 0.72, y: 0.72)
            self.contentView.layoutIfNeeded()
            self.cardView.layoutIfNeeded()
        }

        guard animated else {
            UIView.performWithoutAnimation(block)
            selectionRing.isHidden = !editing
            selectionFill.isHidden = !(editing && selected)
            return
        }

        if editing {
            selectionRing.isHidden = false
        }
        if editing && selected {
            selectionFill.isHidden = false
        }

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: block
        ) { _ in
            self.selectionRing.isHidden = !editing
            self.selectionFill.isHidden = !(editing && selected)
        }
    }

    // MARK: - Quick pin reveal

    func setQuickPinRevealPinnedState(_ isPinned: Bool) {
        let symbolName = isPinned ? "pin.slash.fill" : "pin.fill"
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        quickPinIcon.image = UIImage(systemName: symbolName, withConfiguration: config)
    }

    func setQuickPinRevealProgress(_ progress: CGFloat) {
        let clamped = min(max(progress, 0), 1)
        quickPinRevealView.alpha = clamped
        quickPinCircle.transform = CGAffineTransform(scaleX: 0.92 + clamped * 0.08, y: 0.92 + clamped * 0.08)
        cardView.transform = CGAffineTransform(translationX: clamped * 76, y: 0)
    }

    func completeQuickPinReveal(completion: (() -> Void)? = nil) {
        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.setQuickPinRevealProgress(1)
        } completion: { _ in
            UIView.animate(
                withDuration: 0.24,
                delay: 0.22,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction]
            ) {
                self.quickPinRevealView.alpha = 0
                self.quickPinCircle.transform = .identity
                self.cardView.transform = .identity
            } completion: { _ in
                completion?()
            }
        }
    }

    func resetQuickPinReveal(animated: Bool, completion: (() -> Void)? = nil) {
        let block = {
            self.quickPinRevealView.alpha = 0
            self.quickPinCircle.transform = .identity
            self.cardView.transform = .identity
        }
        guard animated else {
            block()
            completion?()
            return
        }
        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction]
        ) {
            block()
        } completion: { _ in
            completion?()
        }
    }

    // MARK: - Highlight

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        UIView.animate(withDuration: 0.12) {
            self.cardView.backgroundColor = highlighted
                ? .pnHighlightedSurface
                : .pnSurface
        }
    }
}
