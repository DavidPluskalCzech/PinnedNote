import UIKit

struct PNAlertAction {
    enum Style {
        case `default`
        case cancel
        case destructive
    }

    let title: String
    let style: Style
    let handler: (() -> Void)?

    init(title: String, style: Style = .default, handler: (() -> Void)? = nil) {
        self.title = title
        self.style = style
        self.handler = handler
    }
}

final class PNAlertController: UIViewController {
    private let alertTitle: String?
    private let message: String?
    private let actions: [PNAlertAction]

    private let dimView = UIView()
    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionStack = UIStackView()

    init(title: String?, message: String?, actions: [PNAlertAction]) {
        self.alertTitle = title
        self.message = message
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        dimView.alpha = 0
        cardView.alpha = 0
        cardView.transform = CGAffineTransform(translationX: 0, y: 10).scaledBy(x: 0.96, y: 0.96)
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0.35,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.dimView.alpha = 1
            self.cardView.alpha = 1
            self.cardView.transform = .identity
        }
    }

    private func setupViews() {
        view.backgroundColor = .clear

        dimView.backgroundColor = ThemeManager.shared.current == .dark
            ? UIColor.black.withAlphaComponent(0.42)
            : UIColor.black.withAlphaComponent(0.18)
        dimView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimView)

        cardView.backgroundColor = .pnFloatingControlBackground
        cardView.layer.cornerRadius = PN.floatingControlCornerRadius
        cardView.layer.cornerCurve = .continuous
        cardView.layer.masksToBounds = false
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = PN.floatingControlShadowOpacity
        cardView.layer.shadowRadius = PN.floatingControlShadowRadius
        cardView.layer.shadowOffset = PN.floatingControlShadowOffset
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 14
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(contentStack)

        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .pnPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        messageLabel.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        messageLabel.textColor = .pnSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        actionStack.axis = actions.count <= 2 ? .horizontal : .vertical
        actionStack.alignment = .fill
        actionStack.distribution = .fillEqually
        actionStack.spacing = 8

        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(messageLabel)
        contentStack.addArrangedSubview(actionStack)

        NSLayoutConstraint.activate([
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: PN.padding),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -PN.padding),
            cardView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.86),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 360),

            contentStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 22),
            contentStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
            contentStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
        ])
    }

    private func setupContent() {
        titleLabel.text = alertTitle
        messageLabel.text = message
        titleLabel.isHidden = (alertTitle ?? "").isEmpty
        messageLabel.isHidden = (message ?? "").isEmpty

        actions.forEach { action in
            let button = UIButton(type: .custom)
            button.setTitle(action.title, for: .normal)
            button.setTitleColor(color(for: action.style), for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            button.backgroundColor = buttonBackgroundColor
            button.layer.cornerRadius = 17
            button.layer.cornerCurve = .continuous
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
            button.addAction(UIAction { [weak self] _ in
                self?.dismissAlert(action)
            }, for: .primaryActionTriggered)
            actionStack.addArrangedSubview(button)
        }
    }

    private func color(for style: PNAlertAction.Style) -> UIColor {
        switch style {
        case .destructive: return .pnDestructive
        case .cancel: return .pnSecondary
        case .default: return .pnPrimary
        }
    }

    private var buttonBackgroundColor: UIColor {
        switch ThemeManager.shared.current {
        case .monochrome:
            return UIColor(white: 0, alpha: 0.075)
        case .blossom:
            return UIColor(red: 0.90, green: 0.68, blue: 0.76, alpha: 0.38)
        case .dark:
            return UIColor.pnBackground.withAlphaComponent(0.24)
        }
    }

    private func dismissAlert(_ action: PNAlertAction) {
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseIn]
        ) {
            self.dimView.alpha = 0
            self.cardView.alpha = 0
            self.cardView.transform = CGAffineTransform(translationX: 0, y: 6).scaledBy(x: 0.98, y: 0.98)
        } completion: { _ in
            self.dismiss(animated: false) {
                action.handler?()
            }
        }
    }
}

extension UIViewController {
    func presentPNAlert(title: String?, message: String? = nil, actions: [PNAlertAction]) {
        let alert = PNAlertController(title: title, message: message, actions: actions)
        present(alert, animated: false)
    }
}
