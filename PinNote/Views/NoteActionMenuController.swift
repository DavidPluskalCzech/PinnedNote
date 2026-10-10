import UIKit

/// Long-press menu for a note tile. The tile lifts above the dimmed list and a
/// small card with the note's actions appears right under it, styled like the
/// app's dialogs: delete (icon only) on the left, pin to the lock screen on the right.
final class NoteActionMenuController: UIViewController {

    var onDelete: (() -> Void)?
    var onTogglePin: (() -> Void)?
    /// Called once the menu is gone, however it closed.
    var onDismiss: (() -> Void)?

    private let snapshot: UIView
    private let sourceFrame: CGRect
    private let isPinned: Bool

    private let dimView = UIView()
    private let menuCard = UIView()
    private let deleteButton = UIButton(type: .custom)
    private lazy var pinButton = MenuActionControl(
        symbolName: isPinned ? "pin.slash" : "pin",
        title: NSLocalizedString(isPinned ? "list_menu_unpin" : "list_menu_pin", comment: "")
    )

    /// How far the tile moves up so the menu fits under it.
    private var liftOffset: CGFloat = 0
    private var hasLaidOut = false
    private var isDismissing = false

    private let menuGap: CGFloat = 12
    private let screenMargin: CGFloat = 16

    /// - Parameters:
    ///   - snapshot: an image of the tile, shown in place of the real one.
    ///   - sourceFrame: where the tile is, in window coordinates.
    init(snapshot: UIView, sourceFrame: CGRect, isPinned: Bool) {
        self.snapshot = snapshot
        self.sourceFrame = sourceFrame
        self.isPinned = isPinned
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimView.backgroundColor = ThemeManager.shared.current == .dark
            ? UIColor.black.withAlphaComponent(0.42)
            : UIColor.black.withAlphaComponent(0.18)
        dimView.alpha = 0
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissMenu)))
        view.addSubview(dimView)

        snapshot.frame = sourceFrame
        snapshot.isUserInteractionEnabled = false
        view.addSubview(snapshot)

        setUpMenuCard()
        view.addSubview(menuCard)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dimView.frame = view.bounds
        guard !hasLaidOut else { return }
        hasLaidOut = true
        layoutMenu()
        animateIn()
    }

    // MARK: - Menu card

    private func setUpMenuCard() {
        menuCard.backgroundColor = .pnFloatingControlBackground
        menuCard.layer.cornerRadius = PN.floatingControlCornerRadius
        menuCard.layer.cornerCurve = .continuous
        menuCard.layer.shadowColor = UIColor.black.cgColor
        menuCard.layer.shadowOpacity = PN.floatingControlShadowOpacity
        menuCard.layer.shadowRadius = PN.floatingControlShadowRadius
        menuCard.layer.shadowOffset = PN.floatingControlShadowOffset

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)

        var deleteConfig = UIButton.Configuration.plain()
        deleteConfig.image = UIImage(systemName: "trash", withConfiguration: symbolConfig)
        deleteConfig.baseForegroundColor = .pnDestructive
        deleteButton.configuration = deleteConfig
        deleteButton.accessibilityLabel = NSLocalizedString("detail_toolbar_delete", comment: "")
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .primaryActionTriggered)

        // A plain UIControl sends touch events, not .primaryActionTriggered.
        pinButton.addTarget(self, action: #selector(pinTapped), for: .touchUpInside)

        // Same rounded fill as the timer sheet's buttons.
        [deleteButton, pinButton].forEach { (button: UIControl) in
            button.backgroundColor = buttonBackgroundColor
            button.layer.cornerRadius = 17
            button.layer.cornerCurve = .continuous
            button.translatesAutoresizingMaskIntoConstraints = false
        }

        let stack = UIStackView(arrangedSubviews: [deleteButton, pinButton])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        menuCard.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: menuCard.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: menuCard.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: menuCard.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: menuCard.trailingAnchor, constant: -8),
            deleteButton.widthAnchor.constraint(equalToConstant: 52),
            deleteButton.heightAnchor.constraint(equalToConstant: 44),
            pinButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private var buttonBackgroundColor: UIColor {
        switch ThemeManager.shared.current {
        case .monochrome: return UIColor(white: 0, alpha: 0.075)
        case .blossom:    return UIColor(red: 0.90, green: 0.68, blue: 0.76, alpha: 0.38)
        case .dark:       return UIColor.pnBackground.withAlphaComponent(0.24)
        }
    }

    /// Puts the card under the tile, centred on it and kept on screen. If there's
    /// no room below, the tile moves up to make some.
    private func layoutMenu() {
        let safe = view.bounds.inset(by: view.safeAreaInsets)
        let maxWidth = view.bounds.width - screenMargin * 2
        let fitting = menuCard.systemLayoutSizeFitting(
            CGSize(width: maxWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
        let size = CGSize(width: min(fitting.width, maxWidth), height: fitting.height)

        let lowestMenuY = safe.maxY - menuGap - size.height
        let wantedMenuY = sourceFrame.maxY + menuGap
        let highestTileY = safe.minY + menuGap
        liftOffset = max(0, min(wantedMenuY - lowestMenuY, sourceFrame.minY - highestTileY))

        let x = min(max(sourceFrame.midX - size.width / 2, screenMargin), view.bounds.width - screenMargin - size.width)
        let y = min(wantedMenuY - liftOffset, lowestMenuY)
        // Grows out of its top edge, towards the tile.
        menuCard.layer.anchorPoint = CGPoint(x: 0.5, y: 0)
        menuCard.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    // MARK: - Animation

    private func animateIn() {
        menuCard.alpha = 0
        menuCard.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.35,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.dimView.alpha = 1
            self.snapshot.transform = CGAffineTransform(translationX: 0, y: -self.liftOffset)
                .scaledBy(x: 1.03, y: 1.03)
            self.menuCard.alpha = 1
            self.menuCard.transform = .identity
        }
    }

    private func close(then action: (() -> Void)? = nil) {
        guard !isDismissing else { return }
        isDismissing = true
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            self.dimView.alpha = 0
            self.snapshot.transform = .identity
            self.menuCard.alpha = 0
            self.menuCard.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        } completion: { _ in
            self.dismiss(animated: false) {
                self.onDismiss?()
                action?()
            }
        }
    }

    // MARK: - Actions

    @objc private func dismissMenu() {
        close()
    }

    @objc private func deleteTapped() {
        close { [onDelete] in onDelete?() }
    }

    @objc private func pinTapped() {
        close { [onTogglePin] in onTogglePin?() }
    }
}

/// Icon and title in one tappable pill. Long titles (some languages) shrink a
/// little to fit rather than being cut off.
private final class MenuActionControl: UIControl {

    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    init(symbolName: String, title: String) {
        super.init(frame: .zero)

        iconView.image = UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        )
        iconView.tintColor = .pnPrimary
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .pnPrimary
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }
}
