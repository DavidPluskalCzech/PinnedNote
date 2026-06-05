import UIKit

final class PNSchedulePinController: UIViewController {
    var onSet: ((Date) -> Void)?
    var onClear: (() -> Void)?

    private let initialDate: Date?
    private let backdrop = UIView()
    private let card = UIView()
    private let titleLabel = UILabel()
    private let datePicker = UIDatePicker()
    private let clearButton = UIButton(type: .custom)
    private let setButton = UIButton(type: .custom)
    private var hasAnimatedIn = false

    init(initialDate: Date?) {
        self.initialDate = initialDate
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        applyTheme()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateIn()
    }

    private func setupViews() {
        view.backgroundColor = .clear

        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        backdrop.alpha = 0
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(cancelTapped))
        backdrop.addGestureRecognizer(tap)

        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleCardPan(_:)))
        card.addGestureRecognizer(pan)

        titleLabel.text = NSLocalizedString("schedule_pin_title", comment: "")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        datePicker.datePickerMode = .dateAndTime
        datePicker.preferredDatePickerStyle = .wheels
        datePicker.minimumDate = Date().addingTimeInterval(60)
        datePicker.date = max(initialDate ?? Date().addingTimeInterval(3600), Date().addingTimeInterval(60))
        datePicker.translatesAutoresizingMaskIntoConstraints = false

        configureButton(setButton, title: NSLocalizedString("schedule_set", comment: ""))
        configureButton(clearButton, title: NSLocalizedString("schedule_clear", comment: ""))

        setButton.addTarget(self, action: #selector(setTapped), for: .primaryActionTriggered)
        clearButton.addTarget(self, action: #selector(clearTapped), for: .primaryActionTriggered)
        clearButton.isHidden = initialDate == nil

        let actionStack = UIStackView(arrangedSubviews: initialDate == nil
                                      ? [setButton]
                                      : [clearButton, setButton])
        actionStack.axis = .horizontal
        actionStack.spacing = 10
        actionStack.distribution = .fillEqually
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = UIStackView(arrangedSubviews: [titleLabel, datePicker, actionStack])
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(contentStack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -86),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 350),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: PN.padding),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -PN.padding),

            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),

            datePicker.heightAnchor.constraint(equalToConstant: 174),
            clearButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            setButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])

        card.alpha = 1
        card.transform = CGAffineTransform(translationX: 0, y: 420)
    }

    private func applyTheme() {
        card.backgroundColor = .pnFloatingControlBackground
        card.layer.cornerRadius = PN.floatingControlCornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = PN.floatingControlShadowOpacity
        card.layer.shadowRadius = PN.floatingControlShadowRadius
        card.layer.shadowOffset = PN.floatingControlShadowOffset

        titleLabel.textColor = .pnPrimary
        datePicker.tintColor = .pnTextSelection

        [clearButton, setButton].forEach { button in
            button.backgroundColor = buttonBackgroundColor
            button.layer.cornerRadius = 17
            button.layer.cornerCurve = .continuous
            button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        }
        clearButton.setTitleColor(.pnDestructive, for: .normal)
        setButton.setTitleColor(.pnPrimary, for: .normal)
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

    private func configureButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func animateIn() {
        guard !hasAnimatedIn else { return }
        hasAnimatedIn = true
        view.layoutIfNeeded()
        card.transform = CGAffineTransform(translationX: 0, y: view.bounds.height - card.frame.minY + 24)

        UIView.animate(withDuration: 0.18) {
            self.backdrop.alpha = 1
        }
        UIView.animate(
            withDuration: 0.44,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.42,
            options: [.allowUserInteraction]
        ) {
            self.card.transform = .identity
        }
    }

    private func dismissWithAnimation(completion: (() -> Void)? = nil) {
        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.backdrop.alpha = 0
            self.card.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height - self.card.frame.minY + 24)
        } completion: { _ in
            self.dismiss(animated: false, completion: completion)
        }
    }

    @objc private func cancelTapped() {
        dismissWithAnimation()
    }

    @objc private func handleCardPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let y = max(0, translation.y)

        switch gesture.state {
        case .changed:
            card.transform = CGAffineTransform(translationX: 0, y: y)
            backdrop.alpha = max(0.25, 1 - y / 420)
        case .ended, .cancelled, .failed:
            let velocityY = gesture.velocity(in: view).y
            if y > 82 || velocityY > 850 {
                dismissWithAnimation()
            } else {
                UIView.animate(
                    withDuration: 0.34,
                    delay: 0,
                    usingSpringWithDamping: 0.82,
                    initialSpringVelocity: 0.35,
                    options: [.allowUserInteraction]
                ) {
                    self.card.transform = .identity
                    self.backdrop.alpha = 1
                }
            }
        default:
            break
        }
    }

    @objc private func setTapped() {
        let date = datePicker.date
        dismissWithAnimation { [onSet] in
            onSet?(date)
        }
    }

    @objc private func clearTapped() {
        dismissWithAnimation { [onClear] in
            onClear?()
        }
    }
}
