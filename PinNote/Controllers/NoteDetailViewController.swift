import UIKit
import Combine

final class NoteDetailViewController: UIViewController {

    // MARK: - State

    private var note: Note
    private var isNew: Bool
    private var isDirty = false
    private var isPinToggleInFlight = false
    private var keyboardBottomConstraint: NSLayoutConstraint?
    private let textViewBaseBottomInset: CGFloat = 104
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Subviews

    private let titleTapArea = UIControl()
    private let titleField   = UITextField()
    private let textView     = UITextView()
    private let backButton   = UIButton(type: .custom)
    private let bottomBar    = NoteDetailBottomBar()
    private let doneButton   = UIButton(type: .custom)
    private let headerFadeView = UIView()
    private let headerFadeLayer = CAGradientLayer()
    private let readableGuide = UILayoutGuide()

    // MARK: - Init

    init(note: Note?) {
        if let note {
            self.note  = note
            self.isNew = false
        } else {
            self.note  = Note()
            self.isNew = true
        }
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .pnBackground
        setupReadableGuide()
        setupBackButton()
        setupDoneButton()
        setupTitleField()
        setupBottomBar()
        setupTextView()
        setupHeaderFade()
        registerKeyboardObservers()

        titleField.text = note.title
        textView.text = note.content
        bottomBar.setPinned(note.isPinned)
        refreshScheduledState()

        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme),
            name: .pnThemeChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(persistBeforeAppSuspends),
            name: UIApplication.willResignActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(persistBeforeAppSuspends),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )

        // Sync pin button if note is unpinned externally (e.g. Live Activity dismissed)
        NoteStore.shared.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notes in
                guard let self, !self.isNew,
                      let fresh = notes.first(where: { $0.id == self.note.id }),
                      fresh.isPinned != self.note.isPinned ||
                      fresh.scheduledPinDate != self.note.scheduledPinDate else { return }
                self.note = fresh
                self.bottomBar.setPinned(self.note.isPinned)
                self.refreshScheduledState()
            }
            .store(in: &cancellables)

        // Enable swipe-back even though the nav bar is hidden
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-read pin state from store in case another note was pinned while this was on stack
        guard !isNew,
              let fresh = NoteStore.shared.notes.first(where: { $0.id == note.id })
        else { return }
        note = fresh
        bottomBar.setPinned(note.isPinned)
        refreshScheduledState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isNew { textView.becomeFirstResponder() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        headerFadeLayer.frame = headerFadeView.bounds
        updateTextViewBottomInset()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        persistNote()
    }

    // MARK: - Layout

    private func setupReadableGuide() {
        view.addLayoutGuide(readableGuide)
        NSLayoutConstraint.activate([
            readableGuide.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            readableGuide.widthAnchor.constraint(lessThanOrEqualToConstant: PN.readableMaxWidth),
            readableGuide.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            readableGuide.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
            readableGuide.widthAnchor.constraint(equalTo: view.widthAnchor).withPriority(.defaultHigh),
        ])
    }

    private func setupBackButton() {
        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .light)
        let img = UIImage(systemName: "chevron.left", withConfiguration: cfg)
        backButton.setImage(img, for: .normal)
        backButton.tintColor = .pnPrimary
        backButton.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor, constant: PN.padding - 4),
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 19),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupTitleField() {
        titleTapArea.backgroundColor = .clear
        titleTapArea.addTarget(self, action: #selector(focusTitleField), for: .touchUpInside)
        titleTapArea.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleTapArea)

        titleField.font = PN.font(22, bold: true)
        titleField.textColor = .pnPrimary
        titleField.tintColor = .pnTextSelection
        titleField.borderStyle = .none
        titleField.clearButtonMode = .never
        titleField.returnKeyType = .next
        titleField.delegate = self
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField.translatesAutoresizingMaskIntoConstraints = false
        updateTitlePlaceholder()
        titleField.addTarget(self, action: #selector(titleFieldChanged), for: .editingChanged)
        view.addSubview(titleField)

        NSLayoutConstraint.activate([
            titleTapArea.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor, constant: PN.padding + 42),
            titleTapArea.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -12),
            titleTapArea.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 41),
            titleTapArea.heightAnchor.constraint(equalToConstant: 44),

            titleField.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor, constant: PN.padding + 42),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: doneButton.leadingAnchor, constant: -12),
            titleField.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 41),
            titleField.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupDoneButton() {
        let title = NSLocalizedString("detail_done", comment: "")
        doneButton.setTitle(title, for: .normal)
        doneButton.setTitleColor(.pnPrimary, for: .normal)
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        doneButton.alpha = 0
        doneButton.addTarget(self, action: #selector(dismissKeyboard), for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(doneButton)
        NSLayoutConstraint.activate([
            doneButton.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor, constant: -PN.padding),
            doneButton.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 41),
        ])
    }

    private func setupBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)
        keyboardBottomConstraint = bottomBar.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor
        )
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor),
            keyboardBottomConstraint!,
        ])
        bottomBar.onPin    = { [weak self] in
            Task { @MainActor in
                await self?.togglePin()
            }
        }
        bottomBar.onDelete = { [weak self] in self?.confirmDelete() }
        bottomBar.onCopy   = { [weak self] in self?.copyNoteToPasteboard() }
        bottomBar.onSchedule = { [weak self] in self?.showSchedulePicker() }
    }

    private func setupTextView() {
        textView.font                = PN.font(17, bold: true)
        textView.textColor           = .pnPrimary
        textView.tintColor           = .pnTextSelection
        textView.keyboardAppearance  = ThemeManager.shared.current == .dark ? .dark : .light
        textView.textContainerInset  = UIEdgeInsets(
            top: 14,
            left: PN.padding - 4,
            bottom: textViewBaseBottomInset,
            right: PN.padding
        )
        refreshRuledBackground()
        textView.delegate            = self
        textView.autocorrectionType  = .yes
        // Swipe-down to dismiss keyboard. alwaysBounceVertical ensures the
        // gesture fires even when text is short and there's nothing to scroll.
        textView.keyboardDismissMode  = .interactive
        textView.alwaysBounceVertical = true
        // No inputAccessoryView — keeps the keyboard chrome minimal
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 74),
            textView.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        view.bringSubviewToFront(bottomBar)
        updateTextViewBottomInset()
    }

    private func setupHeaderFade() {
        headerFadeView.isUserInteractionEnabled = false
        headerFadeView.backgroundColor = .clear
        headerFadeView.translatesAutoresizingMaskIntoConstraints = false
        headerFadeView.layer.addSublayer(headerFadeLayer)
        view.addSubview(headerFadeView)
        NSLayoutConstraint.activate([
            headerFadeView.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: -4),
            headerFadeView.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor),
            headerFadeView.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor),
            headerFadeView.heightAnchor.constraint(equalToConstant: 50),
        ])
        refreshHeaderFade()
        view.bringSubviewToFront(backButton)
        view.bringSubviewToFront(titleTapArea)
        view.bringSubviewToFront(titleField)
        view.bringSubviewToFront(doneButton)
        view.bringSubviewToFront(bottomBar)
    }

    // MARK: - Keyboard

    private func registerKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil
        )
    }

    @objc private func keyboardWillChange(_ n: Notification) {
        guard
            let frame    = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let duration = n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        let keyboardInView = view.convert(frame, from: nil)
        let overlap = view.bounds.maxY - view.safeAreaInsets.bottom - keyboardInView.minY
        let gap: CGFloat = 8
        keyboardBottomConstraint?.constant = overlap > 0 ? -(overlap + gap) : 0
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
            self.updateTextViewBottomInset()
            self.doneButton.alpha = overlap > 0 ? 1 : 0
        }
    }

    @objc private func keyboardWillHide(_ n: Notification) {
        guard let duration = n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        keyboardBottomConstraint?.constant = 0
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
            self.updateTextViewBottomInset()
            self.doneButton.alpha = 0
        }
    }

    private func updateTextViewBottomInset() {
        guard textView.superview != nil, bottomBar.superview != nil else { return }

        let bottomBarFrame = textView.convert(bottomBar.bounds, from: bottomBar)
        let overlap = max(0, textView.bounds.maxY - bottomBarFrame.minY)
        let bottomInset = max(textViewBaseBottomInset, overlap + 18)

        guard abs(textView.textContainerInset.bottom - bottomInset) > 0.5 else { return }
        textView.textContainerInset.bottom = bottomInset
        textView.verticalScrollIndicatorInsets.bottom = bottomInset
        refreshRuledBackground()
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func focusTitleField() {
        titleField.becomeFirstResponder()
    }

    // MARK: - Actions

    @objc private func applyTheme() {
        view.backgroundColor     = .pnBackground
        titleField.textColor     = .pnPrimary
        titleField.tintColor     = .pnTextSelection
        textView.textColor       = .pnPrimary
        textView.tintColor       = .pnTextSelection
        textView.keyboardAppearance = ThemeManager.shared.current == .dark ? .dark : .light
        refreshRuledBackground()
        refreshHeaderFade()
        doneButton.setTitleColor(.pnPrimary, for: .normal)
        backButton.tintColor = .pnPrimary
        bottomBar.refreshColors()
        updateTitlePlaceholder()
    }

    private func refreshHeaderFade() {
        let background = UIColor.pnBackground
        headerFadeLayer.colors = [
            background.cgColor,
            background.cgColor,
            background.withAlphaComponent(0.99).cgColor,
            background.withAlphaComponent(0.96).cgColor,
            background.withAlphaComponent(0.91).cgColor,
            background.withAlphaComponent(0.84).cgColor,
            background.withAlphaComponent(0.75).cgColor,
            background.withAlphaComponent(0.64).cgColor,
            background.withAlphaComponent(0.52).cgColor,
            background.withAlphaComponent(0.40).cgColor,
            background.withAlphaComponent(0.29).cgColor,
            background.withAlphaComponent(0.19).cgColor,
            background.withAlphaComponent(0.11).cgColor,
            background.withAlphaComponent(0.05).cgColor,
            background.withAlphaComponent(0.0).cgColor,
        ]
        headerFadeLayer.locations = [0, 0.12, 0.17, 0.22, 0.28, 0.34, 0.41, 0.48, 0.55, 0.62, 0.69, 0.76, 0.83, 0.91, 1]
        headerFadeLayer.startPoint = CGPoint(x: 0.5, y: 0)
        headerFadeLayer.endPoint = CGPoint(x: 0.5, y: 1)
    }

    private func refreshRuledBackground() {
        let lineHeight = textView.font?.lineHeight ?? PN.font(17, bold: true).lineHeight
        textView.backgroundColor = pnRuledBackground(
            lineHeight: lineHeight,
            topInset: textView.textContainerInset.top
        )
    }

    private func updateTitlePlaceholder() {
        titleField.attributedPlaceholder = NSAttributedString(
            string: NSLocalizedString("detail_title_placeholder", comment: ""),
            attributes: [
                .foregroundColor: UIColor.pnSecondary.withAlphaComponent(0.45),
                .font: PN.font(22, bold: true),
            ]
        )
    }

    @objc private func persistBeforeAppSuspends() {
        persistNote()
    }

    @objc private func goBack() {
        navigationController?.popViewController(animated: true)
    }

    private func togglePin() async {
        guard !isPinToggleInFlight else { return }
        isPinToggleInFlight = true
        defer { isPinToggleInFlight = false }

        // Block pinning an empty note — shake the text view as feedback
        let isEmpty =
            (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isEmpty && !note.isPinned {
            shakeTextView()
            return
        }

        // Block pinning when trial expired and not Pro
        let pm = PurchaseManager.shared
        if !note.isPinned && !pm.allowsProFeatures() {
            showUpgradePrompt()
            return
        }

        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        if note.isPinned {
            note.isPinned = false
            bottomBar.setPinned(false)
            LiveActivityManager.shared.stop()
            PinStatusToast.show(in: view, pinned: false)
        } else {
            var pinnedNote = note
            pinnedNote.isPinned = true
            pinnedNote.scheduledPinDate = nil
            let didStart = await LiveActivityManager.shared.start(with: pinnedNote)
            guard didStart else {
                bottomBar.setPinned(false)
                return
            }
            note.isPinned = true
            note.scheduledPinDate = nil
            bottomBar.setPinned(true)
            bottomBar.setScheduled(false)
            NoteStore.shared.unpinAll(except: note.id)
            ScheduledPinManager.shared.removeNotificationBackup(noteID: note.id)
            PinStatusToast.show(in: view, pinned: true)
        }

        // Save pin state without touching modifiedAt — note stays in its current position.
        // If the user also edited content (isDirty), let persistNote handle everything normally.
        if isDirty {
            persistNote()
        } else {
            NoteStore.shared.updatePinAndScheduleOnly(note)
        }
    }

    private func showUpgradePrompt() {
        presentPNAlert(
            title:   NSLocalizedString("detail_trial_ended_title",   comment: ""),
            message: NSLocalizedString("detail_trial_ended_message", comment: ""),
            actions: [
                PNAlertAction(title: NSLocalizedString("detail_not_now", comment: ""), style: .cancel),
                PNAlertAction(title: NSLocalizedString("detail_upgrade", comment: "")) { [weak self] in
                    guard let self else { return }
                    let vc  = SettingsViewController()
                    let nav = UINavigationController(rootViewController: vc)
                    nav.modalPresentationStyle = .formSheet
                    self.present(nav, animated: true)
                }
            ]
        )
    }

    private func shakeTextView() {
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values   = [-8, 8, -6, 6, -3, 3, 0]
        shake.duration = 0.42
        textView.layer.add(shake, forKey: "shake")
    }

    @objc private func titleFieldChanged() {
        isDirty = true
        note.title = titleField.text ?? ""
        if note.isPinned {
            LiveActivityManager.shared.update(with: note)
        }
    }

    private func confirmDelete() {
        presentPNAlert(
            title: NSLocalizedString("detail_delete_note", comment: ""),
            actions: [
                PNAlertAction(title: NSLocalizedString("detail_cancel", comment: ""), style: .cancel),
                PNAlertAction(title: NSLocalizedString("detail_delete", comment: ""), style: .destructive) { [weak self] in
                    guard let self else { return }
                    if self.note.isPinned { LiveActivityManager.shared.stop() }
                    ScheduledPinManager.shared.removeNotificationBackup(noteID: self.note.id)
                    if !self.isNew { NoteStore.shared.delete(id: self.note.id) }
                    self.navigationController?.popViewController(animated: true)
                }
            ]
        )
    }

    private func copyNoteToPasteboard() {
        let title = (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let content = textView.text ?? ""
        let isEmpty = title.isEmpty && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isEmpty {
            shakeTextView()
            return
        }

        let copiedText: String

        if title.isEmpty {
            copiedText = content
        } else if content.isEmpty {
            copiedText = title
        } else {
            copiedText = "\(title)\n\(content)"
        }

        UIPasteboard.general.string = copiedText
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        PinStatusToast.show(
            in: view,
            message: NSLocalizedString("copy_toast_copied", comment: "")
        )
    }

    private func showSchedulePicker() {
        let isEmpty =
            (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isEmpty {
            shakeTextView()
            return
        }

        let pm = PurchaseManager.shared
        if !pm.allowsProFeatures() {
            showUpgradePrompt()
            return
        }

        persistNote(force: true)
        guard !isNew else { return }
        view.endEditing(true)

        let picker = PNSchedulePinController(initialDate: note.scheduledPinDate)
        picker.onSet = { [weak self] date in
            guard PurchaseManager.shared.allowsProFeatures(at: date) else {
                self?.showUpgradePrompt()
                return
            }
            self?.setScheduledPinDate(date)
        }
        picker.onClear = { [weak self] in
            self?.setScheduledPinDate(nil)
        }
        present(picker, animated: false)
    }

    private func setScheduledPinDate(_ date: Date?) {
        note.scheduledPinDate = date
        refreshScheduledState()
        NoteStore.shared.updateScheduledPinDate(noteID: note.id, date: date)

        if let date {
            var scheduledNote = note
            scheduledNote.scheduledPinDate = date
            ScheduledPinManager.shared.scheduleNotificationBackupIfPossible(for: scheduledNote)
            ScheduledPinManager.shared.refreshSchedule()
            PinStatusToast.show(
                in: view,
                message: NSLocalizedString("schedule_toast_set", comment: "")
            )
        } else {
            ScheduledPinManager.shared.removeNotificationBackup(noteID: note.id)
            ScheduledPinManager.shared.refreshSchedule()
            PinStatusToast.show(
                in: view,
                message: NSLocalizedString("schedule_toast_cleared", comment: "")
            )
        }
    }

    private func refreshScheduledState() {
        guard let scheduledDate = note.scheduledPinDate else {
            bottomBar.setScheduled(false)
            return
        }

        guard scheduledDate > Date() else {
            note.scheduledPinDate = nil
            bottomBar.setScheduled(false)
            if !isNew {
                NoteStore.shared.updateScheduledPinDate(noteID: note.id, date: nil)
                ScheduledPinManager.shared.removeNotificationBackup(noteID: note.id)
                ScheduledPinManager.shared.refreshSchedule()
            }
            return
        }

        bottomBar.setScheduled(true)
    }

    // MARK: - Persistence

    private func persistNote(force: Bool = false) {
        guard isDirty || isNew || force else { return }
        let title = (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let content = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty && content.isEmpty {
            // Existing note emptied → delete it (new note → just discard)
            if !isNew {
                if note.isPinned { LiveActivityManager.shared.stop() }
                ScheduledPinManager.shared.removeNotificationBackup(noteID: note.id)
                NoteStore.shared.delete(id: note.id)
            }
            return
        }
        note.title      = titleField.text ?? ""
        note.content    = textView.text
        note.modifiedAt = Date()
        if isNew {
            NoteStore.shared.add(note)
            isNew = false   // prevent duplicate add on subsequent calls
        } else {
            NoteStore.shared.update(note)
        }
        if note.isPinned {
            LiveActivityManager.shared.update(with: note)
        }
        isDirty = false
    }
}

// MARK: - UITextFieldDelegate

extension NoteDetailViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textView.becomeFirstResponder()
        return false
    }
}

// MARK: - UITextViewDelegate

extension NoteDetailViewController: UITextViewDelegate {

    private var bulletPrefix: String { "●  " }
    private var supportedBulletPrefixes: [String] { [bulletPrefix, "• "] }

    func textViewDidChange(_ textView: UITextView) {
        isDirty = true
        note.content = textView.text
        if note.isPinned {
            LiveActivityManager.shared.update(with: note)
        }
    }

    func textView(_ textView: UITextView,
                  shouldChangeTextIn range: NSRange,
        replacementText text: String) -> Bool {

        let nsText = textView.text as NSString
        guard range.location <= nsText.length,
              NSMaxRange(range) <= nsText.length else {
            return false
        }

        // Auto-bullet: typing " " after a lone "-" at line start → replace with a bullet.
        if text == " " {
            let lineStart = nsText.lineRange(for: NSRange(location: range.location, length: 0)).location
            let charsFromLineStart = range.location - lineStart
            // Only trigger when cursor is right after a single "-"
            if charsFromLineStart == 1,
               nsText.substring(with: NSRange(location: lineStart, length: 1)) == "-" {
                // Replace "-" with the bullet prefix (bullet + spacing already included)
                guard
                    let start = textView.position(from: textView.beginningOfDocument, offset: lineStart),
                    let end = textView.position(from: textView.beginningOfDocument, offset: range.location),
                    let textRange = textView.textRange(from: start, to: end)
                else { return true }
                textView.replace(textRange, withText: bulletPrefix)
                isDirty = true
                note.content = textView.text
                return false  // we already inserted the space as part of the bullet prefix
            }
        }

        // Auto-continue bullet on new line
        if text == "\n" || text == "\r" {
            let lineRange   = nsText.lineRange(for: NSRange(location: range.location, length: 0))
            let currentLine = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)

            if let currentPrefix = supportedBulletPrefixes.first(where: { currentLine.hasPrefix($0) }) {
                let bulletText = String(currentLine.dropFirst(currentPrefix.count))
                if bulletText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Empty bullet line → strip the bullet and stop
                    if let swiftRange = Range(lineRange, in: textView.text) {
                        textView.text.replaceSubrange(swiftRange, with: "")
                        isDirty = true
                        note.content = textView.text
                    }
                    return false
                }
                // Non-empty bullet line → start a new bullet
                let insert = "\n\(bulletPrefix)"
                guard
                    let pos = textView.position(from: textView.beginningOfDocument, offset: range.location),
                    let textRange = textView.textRange(from: pos, to: pos)
                else { return true }
                textView.replace(textRange, withText: insert)
                isDirty = true
                note.content = textView.text
                return false
            }
        }

        return true
    }
}

// MARK: - UIGestureRecognizerDelegate (swipe-back support)

extension NoteDetailViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow swipe-back only when we're not at the root
        return navigationController?.viewControllers.count ?? 0 > 1
    }
}
