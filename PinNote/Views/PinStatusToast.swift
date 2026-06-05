import UIKit

final class PinStatusToast: UIView {
    private static weak var visibleToast: PinStatusToast?

    private let label = UILabel()

    static func show(in hostView: UIView, pinned: Bool) {
        let messageKey = pinned ? "pin_toast_pinned" : "pin_toast_unpinned"
        show(in: hostView, message: NSLocalizedString(messageKey, comment: ""))
    }

    static func show(in hostView: UIView, message: String) {
        visibleToast?.removeFromSuperview()

        let toast = PinStatusToast(text: message)
        visibleToast = toast

        hostView.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
            toast.topAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.topAnchor, constant: -3),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: hostView.leadingAnchor, constant: PN.padding),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: hostView.trailingAnchor, constant: -PN.padding),
        ])

        toast.animateInAndOut()
    }

    private init(text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false

        backgroundColor = .pnFloatingControlBackground
        layer.cornerRadius = 17
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = PN.floatingControlShadowOpacity
        layer.shadowRadius = PN.floatingControlShadowRadius
        layer.shadowOffset = PN.floatingControlShadowOffset

        label.text = text
        label.textColor = .pnPrimary
        label.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func animateInAndOut() {
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: -8).scaledBy(x: 0.92, y: 0.92)

        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.45,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.alpha = 1
            self.transform = .identity
        }

        UIView.animate(
            withDuration: 0.72,
            delay: 1.25,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut]
        ) {
            self.alpha = 0
            self.transform = CGAffineTransform(translationX: 0, y: -5).scaledBy(x: 0.98, y: 0.98)
        } completion: { _ in
            if Self.visibleToast === self {
                Self.visibleToast = nil
            }
            self.removeFromSuperview()
        }
    }
}
