import UIKit
import AudioToolbox

private final class ToolbarButton: UIButton {
    private let minimumHitSize = CGSize(width: 44, height: 44)
    var restingTransform: CGAffineTransform = .identity {
        didSet {
            transform = restingTransform
        }
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: max(size.width, minimumHitSize.width),
            height: max(size.height, minimumHitSize.height)
        )
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let widthDelta = max(minimumHitSize.width - bounds.width, 0)
        let heightDelta = max(minimumHitSize.height - bounds.height, 0)
        let hitBounds = bounds.insetBy(dx: -widthDelta / 2, dy: -heightDelta / 2)
        return hitBounds.contains(point)
    }
}

private let standaloneFloatingPillWidth: CGFloat = 74

// MARK: - NoteListBottomBar

final class NoteListBottomBar: UIView {

    var onNewNote:  (() -> Void)?
    var onEdit:     (() -> Void)?
    var onSettings: (() -> Void)?
    var onDelete:   (() -> Void)?
    var onCancel:   (() -> Void)?
    var onSelectAll: (() -> Void)?

    private lazy var newNoteButton = makePillButton(systemName: "square.and.pencil", action: #selector(tapNew))
    private lazy var settingsButton = makePillButton(systemName: "gearshape", action: #selector(tapSettings))
    private lazy var editButton = makePillButton(systemName: "checklist", action: #selector(tapEdit))
    private lazy var cancelButton = makeTextButton(title: NSLocalizedString("toolbar_cancel", comment: ""), action: #selector(tapCancel))
    private lazy var selectAllButton = makeTextButton(title: NSLocalizedString("toolbar_select_all", comment: ""), action: #selector(tapSelectAll))
    private lazy var deleteButton = makePillButton(systemName: "trash", action: #selector(tapDelete))

    private lazy var normalBar: UIView = {
        let view = UIView()
        view.backgroundColor = .pnFloatingControlBackground
        view.layer.cornerRadius = PN.floatingControlCornerRadius
        view.layer.masksToBounds = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowRadius = PN.floatingControlShadowRadius
        view.layer.shadowOffset = PN.floatingControlShadowOffset

        let buttonStack = UIStackView(arrangedSubviews: [editButton, settingsButton])
        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.spacing = 0
        settingsButton.restingTransform = .identity
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonStack)
        [editButton, settingsButton].forEach { button in
            addPressFeedback(to: button, targetView: view)
        }

        NSLayoutConstraint.activate([
            buttonStack.topAnchor.constraint(equalTo: view.topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view.heightAnchor.constraint(equalToConstant: PN.floatingControlHeight),
        ])

        return view
    }()

    private lazy var newNoteBar: UIView = {
        let view = UIView()
        view.backgroundColor = .pnFloatingControlBackground
        view.layer.cornerRadius = PN.floatingControlCornerRadius
        view.layer.masksToBounds = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowRadius = PN.floatingControlShadowRadius
        view.layer.shadowOffset = PN.floatingControlShadowOffset

        view.addSubview(newNoteButton)
        addPressFeedback(to: newNoteButton, targetView: view)

        NSLayoutConstraint.activate([
            newNoteButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            newNoteButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.heightAnchor.constraint(equalToConstant: PN.floatingControlHeight),
            view.widthAnchor.constraint(equalToConstant: standaloneFloatingPillWidth),
        ])

        return view
    }()

    private lazy var normalStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [UIView(), normalBar, newNoteBar])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        return stack
    }()

    private lazy var editStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [cancelButton, selectAllButton, UIView(), deleteButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.isHidden = true
        addPressFeedback(to: cancelButton, targetView: cancelButton)
        addPressFeedback(to: selectAllButton, targetView: selectAllButton)
        addPressFeedback(to: deleteButton, targetView: deleteButton)
        return stack
    }()

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 70)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        setupLayout()
        refreshColors()
        setEditMode(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        normalBar.layer.cornerRadius = max(normalBar.bounds.height / 2, PN.floatingControlCornerRadius)
        newNoteBar.layer.cornerRadius = max(newNoteBar.bounds.height / 2, PN.floatingControlCornerRadius)
    }

    func setEditMode(_ editing: Bool) {
        normalStack.isHidden = editing
        editStack.isHidden = !editing
    }

    func setDeleteEnabled(_ enabled: Bool) {
        deleteButton.isEnabled = enabled
        deleteButton.alpha = enabled ? 1 : 0.38
    }

    func setAllSelected(_ allSelected: Bool) {
        let titleKey = allSelected ? "toolbar_deselect_all" : "toolbar_select_all"
        selectAllButton.setTitle(NSLocalizedString(titleKey, comment: ""), for: .normal)
        selectAllButton.invalidateIntrinsicContentSize()
    }

    func refreshColors() {
        normalBar.backgroundColor = .pnFloatingControlBackground
        normalBar.layer.shadowOpacity = PN.floatingControlShadowOpacity
        newNoteBar.backgroundColor = .pnFloatingControlBackground
        newNoteBar.layer.shadowOpacity = PN.floatingControlShadowOpacity

        [newNoteButton, settingsButton, editButton].forEach { button in
            button.backgroundColor = .clear
            button.tintColor = .pnPrimary
            button.layer.shadowOpacity = 0
        }

        [cancelButton, selectAllButton, deleteButton].forEach { button in
            button.backgroundColor = .pnFloatingControlBackground
            button.tintColor = .pnPrimary
            button.layer.shadowOpacity = PN.floatingControlShadowOpacity
        }
        cancelButton.setTitleColor(.pnPrimary, for: .normal)
        selectAllButton.setTitleColor(.pnPrimary, for: .normal)
        deleteButton.tintColor = .pnDestructive
    }

    private func makePillButton(systemName: String, action: Selector) -> ToolbarButton {
        let button = ToolbarButton(type: .custom)
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = .pnPrimary
        button.backgroundColor = .pnFloatingControlBackground
        button.layer.cornerRadius = PN.floatingControlCornerRadius
        button.layer.masksToBounds = false
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowRadius = PN.floatingControlShadowRadius
        button.layer.shadowOffset = PN.floatingControlShadowOffset
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 57),
            button.heightAnchor.constraint(equalToConstant: PN.floatingControlHeight),
        ])
        button.addTarget(self, action: action, for: .primaryActionTriggered)
        return button
    }

    private func makeTextButton(title: String, action: Selector) -> ToolbarButton {
        let button = ToolbarButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.pnPrimary, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.72
        button.titleLabel?.lineBreakMode = .byClipping
        button.backgroundColor = .pnFloatingControlBackground
        button.layer.cornerRadius = PN.floatingControlCornerRadius
        button.layer.masksToBounds = false
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowRadius = PN.floatingControlShadowRadius
        button.layer.shadowOffset = PN.floatingControlShadowOffset
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
            button.widthAnchor.constraint(lessThanOrEqualToConstant: 132),
            button.heightAnchor.constraint(equalToConstant: PN.floatingControlHeight),
        ])
        button.addTarget(self, action: action, for: .primaryActionTriggered)
        return button
    }

    private func addPressFeedback(to button: ToolbarButton, targetView: UIView) {
        button.addAction(UIAction { [weak self, weak targetView] _ in
            guard let targetView else { return }
            self?.setControlSurface(targetView, pressed: true)
        }, for: [.touchDown, .touchDragEnter])
        button.addAction(UIAction { [weak self, weak targetView] _ in
            guard let targetView else { return }
            self?.setControlSurface(targetView, pressed: false)
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    private func setControlSurface(_ surface: UIView, pressed: Bool) {
        let targetTransform = pressed
            ? CGAffineTransform(translationX: 0, y: 1.5).scaledBy(x: 0.985, y: 0.965)
            : .identity
        let targetShadowOpacity = pressed
            ? max(PN.floatingControlShadowOpacity - 0.13, 0.08)
            : PN.floatingControlShadowOpacity
        let targetShadowRadius = pressed
            ? PN.floatingControlShadowRadius - 5
            : PN.floatingControlShadowRadius

        UIView.animate(
            withDuration: pressed ? 0.12 : 0.32,
            delay: 0,
            usingSpringWithDamping: pressed ? 1 : 0.68,
            initialSpringVelocity: pressed ? 0 : 0.45,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            surface.transform = targetTransform
            surface.layer.shadowOpacity = targetShadowOpacity
            surface.layer.shadowRadius = targetShadowRadius
        }
    }

    private func setupLayout() {
        [normalStack, editStack].forEach { stack in
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PN.padding),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PN.padding),
                stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
    }

    @objc private func tapNew() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onNewNote?()
    }
    @objc private func tapEdit()     { onEdit?() }
    @objc private func tapSettings() { onSettings?() }
    @objc private func tapDelete()   { onDelete?() }
    @objc private func tapCancel()   { onCancel?() }
    @objc private func tapSelectAll() { onSelectAll?() }
}

// MARK: - NoteDetailBottomBar

final class NoteDetailBottomBar: UIView {

    var onPin:    (() -> Void)?
    var onDelete: (() -> Void)?
    var onCopy:   (() -> Void)?
    var onSchedule: (() -> Void)?
    private var isScheduled = false

    private lazy var deleteButton: ToolbarButton = {
        let button = makeIconButton(systemName: "trash", tintColor: .pnDestructive)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(tapDelete), for: .primaryActionTriggered)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: PN.floatingControlHeight),
            button.widthAnchor.constraint(equalToConstant: 57),
        ])
        return button
    }()

    private lazy var pinButton: ToolbarButton = {
        let button = makeIconButton(systemName: "pin", tintColor: .pnPrimary)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(pinTapped), for: .primaryActionTriggered)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: PN.floatingControlHeight),
            button.widthAnchor.constraint(equalToConstant: 57),
        ])
        return button
    }()

    private lazy var copyButton: ToolbarButton = {
        let button = makeIconButton(systemName: "doc.on.doc", tintColor: .pnPrimary)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(tapCopy), for: .primaryActionTriggered)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: PN.floatingControlHeight),
            button.widthAnchor.constraint(equalToConstant: 57),
        ])
        return button
    }()

    private lazy var scheduleButton: ToolbarButton = {
        let button = makeIconButton(systemName: "timer", tintColor: .pnPrimary)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(tapSchedule), for: .primaryActionTriggered)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: PN.floatingControlHeight),
            button.widthAnchor.constraint(equalToConstant: 57),
        ])
        return button
    }()

    private lazy var detailBar: UIView = {
        let view = UIView()
        applyFloatingStyle(to: view)

        let firstSpacer = UIView()
        firstSpacer.translatesAutoresizingMaskIntoConstraints = false
        firstSpacer.widthAnchor.constraint(equalToConstant: 8).isActive = true

        let buttonStack = UIStackView(arrangedSubviews: [deleteButton, firstSpacer, scheduleButton, copyButton])
        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.spacing = 0
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            buttonStack.topAnchor.constraint(equalTo: view.topAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            view.heightAnchor.constraint(equalToConstant: PN.floatingControlHeight),
        ])

        [deleteButton, scheduleButton, copyButton].forEach { button in
            addPressFeedback(to: button, targetView: view)
        }

        return view
    }()

    private lazy var pinBar: UIView = {
        let view = UIView()
        applyFloatingStyle(to: view)

        view.addSubview(pinButton)
        NSLayoutConstraint.activate([
            pinButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pinButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            view.heightAnchor.constraint(equalToConstant: PN.floatingControlHeight),
            view.widthAnchor.constraint(equalToConstant: standaloneFloatingPillWidth),
        ])

        addPressFeedback(to: pinButton, targetView: view)

        return view
    }()

    private lazy var stack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [UIView(), detailBar, pinBar])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        return stack
    }()


    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 70)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        setupLayout()
        refreshColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        detailBar.layer.cornerRadius = max(detailBar.bounds.height / 2, PN.floatingControlCornerRadius)
        pinBar.layer.cornerRadius = max(pinBar.bounds.height / 2, PN.floatingControlCornerRadius)
    }

    func setPinned(_ pinned: Bool) {
        let symbolName = pinned ? "pin.slash" : "pin"
        let symbolCfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        pinButton.setImage(UIImage(systemName: symbolName, withConfiguration: symbolCfg), for: .normal)
        pinButton.invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    func setScheduled(_ scheduled: Bool) {
        isScheduled = scheduled
        let symbolName = scheduled ? "timer.circle.fill" : "timer"
        let symbolCfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        scheduleButton.setImage(UIImage(systemName: symbolName, withConfiguration: symbolCfg), for: .normal)
        scheduleButton.tintColor = .pnPrimary
        scheduleButton.invalidateIntrinsicContentSize()
    }

    func refreshColors() {
        applyFloatingStyle(to: detailBar)
        applyFloatingStyle(to: pinBar)
        [deleteButton, scheduleButton, copyButton, pinButton].forEach { button in
            button.backgroundColor = .clear
            button.layer.shadowOpacity = 0
        }
        deleteButton.tintColor = .pnDestructive
        scheduleButton.tintColor = .pnPrimary
        copyButton.tintColor = .pnPrimary
        pinButton.tintColor = .pnPrimary
    }

    private func setupLayout() {
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PN.padding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PN.padding),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func applyFloatingStyle(to view: UIView) {
        view.backgroundColor = .pnFloatingControlBackground
        view.layer.cornerRadius = max(view.bounds.height / 2, PN.floatingControlCornerRadius)
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = false
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowRadius = PN.floatingControlShadowRadius
        view.layer.shadowOffset = PN.floatingControlShadowOffset
        view.layer.shadowOpacity = PN.floatingControlShadowOpacity
    }

    private func makeIconButton(systemName: String, tintColor: UIColor) -> ToolbarButton {
        let button = ToolbarButton(type: .custom)
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = tintColor
        return button
    }

    private func addPressFeedback(to button: ToolbarButton, targetView: UIView) {
        button.addAction(UIAction { [weak self, weak targetView] _ in
            guard let targetView else { return }
            self?.setControlSurface(targetView, pressed: true)
        }, for: [.touchDown, .touchDragEnter])
        button.addAction(UIAction { [weak self, weak targetView] _ in
            guard let targetView else { return }
            self?.setControlSurface(targetView, pressed: false)
        }, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    private func setControlSurface(_ surface: UIView, pressed: Bool) {
        let targetTransform = pressed
            ? CGAffineTransform(translationX: 0, y: 1.5).scaledBy(x: 0.985, y: 0.965)
            : .identity
        let targetShadowOpacity = pressed
            ? max(PN.floatingControlShadowOpacity - 0.13, 0.08)
            : PN.floatingControlShadowOpacity
        let targetShadowRadius = pressed
            ? PN.floatingControlShadowRadius - 5
            : PN.floatingControlShadowRadius

        UIView.animate(
            withDuration: pressed ? 0.12 : 0.32,
            delay: 0,
            usingSpringWithDamping: pressed ? 1 : 0.68,
            initialSpringVelocity: pressed ? 0 : 0.45,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            surface.transform = targetTransform
            surface.layer.shadowOpacity = targetShadowOpacity
            surface.layer.shadowRadius = targetShadowRadius
        }
    }

    @objc private func pinTapped() {
        // System sound 1520 = "Pop" — combines Taptic Engine kick + audible click
        AudioServicesPlaySystemSound(1520)
        onPin?()
    }

    @objc private func tapDelete() { onDelete?() }
    @objc private func tapSchedule() { onSchedule?() }
    @objc private func tapCopy() { onCopy?() }
}
