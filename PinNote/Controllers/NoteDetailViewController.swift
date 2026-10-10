import UIKit
import Combine

private final class ChecklistOverlayView: UIView {
    struct Entry {
        enum Kind {
            case checkbox(checked: Bool)
            case bullet
        }

        let rect: CGRect
        let kind: Kind
    }

    var entries: [Entry] = [] {
        didSet { setNeedsDisplay() }
    }

    var strokeColor: UIColor = .label {
        didSet { setNeedsDisplay() }
    }

    var coverColor: UIColor = .systemBackground {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        for entry in entries {
            switch entry.kind {
            case .checkbox(let checked):
                drawCover(around: entry.rect, context: context)
                strokeColor.setFill()
                UIBezierPath(cgPath: HandDrawnCheckbox.path(in: entry.rect, checked: checked)).fill()
            case .bullet:
                // The dash underneath is drawn in clear, so no cover is needed.
                context.setFillColor(strokeColor.cgColor)
                context.fillEllipse(in: entry.rect)
            }
        }
    }

    private func drawCover(around rect: CGRect, context: CGContext) {
        let coverRect = rect.insetBy(dx: -3.5, dy: -2.5)
        context.setFillColor(coverColor.cgColor)
        context.fill(coverRect)
    }
}

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
    private let titleField   = NoteTitleField()
    private let textView     = NoteTextView()
    private let backButton   = HandDrawnBackButton()
    private let bottomBar    = NoteDetailBottomBar()
    private let doneButton   = UIButton(type: .custom)
    private let headerFadeView = UIView()
    private let headerFadeLayer = CAGradientLayer()
    private let checklistOverlay = ChecklistOverlayView()
    private let readableGuide = UILayoutGuide()
    private weak var checklistTapGesture: UITapGestureRecognizer?
    private weak var wordSelectionLongPressGesture: UILongPressGestureRecognizer?
    private var wordSelectionAnchorRange: NSRange?
    private var isRefreshingChecklistDisplay = false
    private var isApplyingListParagraphStyles = false
    private var isAnimatingKeyboardLayout = false
    private var isKeepingSelectionOutOfListPrefix = false
    /// The selection when a tap on a checkbox began; set only while that tap is in
    /// progress. The tap just toggles the box: it doesn't open the keyboard or move
    /// the cursor.
    private var selectionBeforeChecklistTap: NSRange?
    private var lastSelectedRange = NSRange(location: 0, length: 0)

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
        applyListParagraphStyles()
        refreshChecklistDisplay()
        bottomBar.setPinned(note.isPinned)
        refreshScheduledState()

        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme),
            name: .pnThemeChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyFont),
            name: .pnFontChanged, object: nil
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
        refreshChecklistDisplay()
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

        titleField.font = PN.titleFont(24)
        titleField.textColor = .pnPrimary
        applyTitleWeight()
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
        bottomBar.onChecklist = { [weak self] in self?.insertChecklistItem() }
    }

    private func setupTextView() {
        textView.font                = PN.font(17, bold: true)
        textView.textColor           = .pnPrimary
        textView.tintColor           = .pnTextSelection
        textView.keyboardAppearance  = ThemeManager.shared.current == .dark ? .dark : .light
        textView.textContainerInset  = UIEdgeInsets(
            // Room for the header fade: the text starts just below it, and scrolls up
            // underneath it (as the note list does).
            top: 40,
            left: PN.padding - 4,
            bottom: textViewBaseBottomInset,
            right: PN.padding
        )
        refreshRuledBackground()
        textView.delegate            = self
        textView.autocorrectionType  = .yes
        textView.isSelectable        = true
        textView.textDragInteraction?.isEnabled = false
        checklistOverlay.strokeColor = .pnPrimary
        checklistOverlay.coverColor = .pnBackground
        textView.addSubview(checklistOverlay)
        let checklistTap = UITapGestureRecognizer(target: self, action: #selector(handleChecklistTap(_:)))
        checklistTap.cancelsTouchesInView = false
        checklistTap.delegate = self
        checklistTapGesture = checklistTap
        textView.addGestureRecognizer(checklistTap)
        let wordSelectionPress = UILongPressGestureRecognizer(target: self, action: #selector(handleWordSelectionLongPress(_:)))
        wordSelectionPress.minimumPressDuration = 0.45
        wordSelectionPress.cancelsTouchesInView = true
        wordSelectionPress.delegate = self
        wordSelectionLongPressGesture = wordSelectionPress
        textView.addGestureRecognizer(wordSelectionPress)
        // Swipe-down to dismiss keyboard. alwaysBounceVertical ensures the
        // gesture fires even when text is short and there's nothing to scroll.
        textView.keyboardDismissMode  = .interactive
        textView.alwaysBounceVertical = true
        // No inputAccessoryView — keeps the keyboard chrome minimal
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
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
            headerFadeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerFadeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerFadeView.heightAnchor.constraint(equalToConstant: 50),
            // The text scrolls from the top of the fade, so it passes under it
            // smoothly instead of being cut off at a hard edge.
            textView.topAnchor.constraint(equalTo: headerFadeView.topAnchor),
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
        isAnimatingKeyboardLayout = true
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
            self.updateTextViewBottomInset()
            self.doneButton.alpha = overlap > 0 ? 1 : 0
        } completion: { _ in
            self.isAnimatingKeyboardLayout = false
            self.refreshChecklistDisplay()
        }
    }

    @objc private func keyboardWillHide(_ n: Notification) {
        guard let duration = n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        keyboardBottomConstraint?.constant = 0
        isAnimatingKeyboardLayout = true
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
            self.updateTextViewBottomInset()
            self.doneButton.alpha = 0
        } completion: { _ in
            self.isAnimatingKeyboardLayout = false
            self.refreshChecklistDisplay()
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

    /// Heavier title lettering where the font calls for it (see `PN.titleWeightAttributes`).
    private func applyTitleWeight() {
        var attributes = titleField.defaultTextAttributes
        attributes.removeValue(forKey: .strokeColor)
        attributes.merge(PN.titleWeightAttributes(color: .pnPrimary)) { $1 }
        titleField.defaultTextAttributes = attributes
    }

    @objc private func applyFont() {
        titleField.font = PN.titleFont(24)
        applyTitleWeight()
        textView.font   = PN.font(17, bold: true)
        updateTitlePlaceholder()
        applyListParagraphStyles()
        refreshRuledBackground()
        refreshChecklistDisplay()
    }

    @objc private func applyTheme() {
        view.backgroundColor     = .pnBackground
        titleField.textColor     = .pnPrimary
        titleField.tintColor     = .pnTextSelection
        applyTitleWeight()
        textView.textColor       = .pnPrimary
        textView.tintColor       = .pnTextSelection
        textView.keyboardAppearance = ThemeManager.shared.current == .dark ? .dark : .light
        checklistOverlay.strokeColor = .pnPrimary
        checklistOverlay.coverColor = .pnBackground
        applyListParagraphStyles()
        refreshChecklistDisplay()
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
                .font: PN.titleFont(24),
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

    private func insertChecklistItem() {
        textView.becomeFirstResponder()

        let nsText = textView.text as NSString
        let range = textView.selectedRange
        guard range.location <= nsText.length else { return }

        let lineBounds = currentLineBounds(in: nsText, at: range.location)
        let lineRange = NSRange(location: lineBounds.start, length: lineBounds.end - lineBounds.start)
        let currentLine = nsText.substring(with: lineRange)

        if NoteListItem(line: currentLine)?.kind == .checklist {
            toggleChecklistItem(at: range.location)
            return
        }

        let trimmedLine = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedLine.isEmpty {
            replaceText(
                in: textView,
                range: lineRange,
                with: uncheckedChecklistPrefix,
                cursorOffset: lineBounds.start + uncheckedChecklistPrefixLength
            )
        } else {
            replaceText(
                in: textView,
                range: NSRange(location: lineBounds.start, length: 0),
                with: uncheckedChecklistPrefix,
                cursorOffset: range.location + uncheckedChecklistPrefixLength
            )
        }
    }

    @objc private func handleChecklistTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }

        guard let line = lineInfo(at: gesture.location(in: textView)) else { return }
        let savedSelection = selectionBeforeChecklistTap
        toggleChecklistItem(at: line.characterIndex, onlyWhenNearCheckbox: true)

        // The text view handles the same tap and may move the cursor before or after
        // this runs, so put the selection back now and once more on the next pass.
        guard let savedSelection else { return }
        textView.selectedRange = savedSelection
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.textView.isFirstResponder { self.textView.selectedRange = savedSelection }
            self.selectionBeforeChecklistTap = nil
        }
    }

    @objc private func handleWordSelectionLongPress(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: textView)

        switch gesture.state {
        case .began:
            guard !isPointInsideChecklistHitArea(point),
                  let range = wordRange(at: point) else {
                wordSelectionAnchorRange = nil
                return
            }
            let contentOffset = textView.contentOffset
            if !textView.isFirstResponder {
                textView.becomeFirstResponder()
                textView.layoutIfNeeded()
                textView.setContentOffset(contentOffset, animated: false)
            }
            wordSelectionAnchorRange = range
            selectText(range)

        case .changed:
            guard let anchorRange = wordSelectionAnchorRange else { return }
            let currentRange = wordRange(at: point) ?? characterRange(at: point)
            let start = min(anchorRange.location, currentRange.location)
            let end = max(NSMaxRange(anchorRange), NSMaxRange(currentRange))
            selectText(NSRange(location: start, length: max(0, end - start)))

        case .ended, .cancelled, .failed:
            wordSelectionAnchorRange = nil

        default:
            break
        }
    }

    private func wordRange(at point: CGPoint) -> NSRange? {
        guard let position = textView.closestPosition(to: point),
              let wordRange = textView.tokenizer.rangeEnclosingPosition(
                position,
                with: .word,
                inDirection: UITextDirection(rawValue: UITextLayoutDirection.right.rawValue)
              ),
              let selectedText = textView.text(in: wordRange),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return nsRange(from: wordRange)
    }

    private func characterRange(at point: CGPoint) -> NSRange {
        guard let position = textView.closestPosition(to: point) else {
            return NSRange(location: textView.selectedRange.location, length: 0)
        }
        let location = textView.offset(from: textView.beginningOfDocument, to: position)
        return NSRange(location: min(max(location, 0), (textView.text as NSString).length), length: 0)
    }

    private func nsRange(from textRange: UITextRange) -> NSRange {
        let location = textView.offset(from: textView.beginningOfDocument, to: textRange.start)
        let end = textView.offset(from: textView.beginningOfDocument, to: textRange.end)
        return NSRange(location: max(0, location), length: max(0, end - location))
    }

    private func selectText(_ range: NSRange) {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: textView.beginningOfDocument, offset: NSMaxRange(range)),
              let selectedRange = textView.textRange(from: start, to: end) else {
            return
        }
        textView.selectedTextRange = selectedRange
    }

    private func isPointInsideChecklistHitArea(_ point: CGPoint) -> Bool {
        guard let line = lineInfo(at: point),
              let item = NoteListItem(line: line.text),
              item.kind == .checklist else {
            return false
        }

        let nsText = textView.text as NSString
        let lineBounds = currentLineBounds(in: nsText, at: line.characterIndex)
        return checklistHitRect(for: lineBounds, item: item)?.contains(point) == true
    }

    private func toggleChecklistItem(at location: Int, onlyWhenNearCheckbox: Bool = false) {
        let nsText = textView.text as NSString
        guard location <= nsText.length else { return }

        let lineBounds = currentLineBounds(in: nsText, at: location)
        let lineRange = NSRange(location: lineBounds.start, length: lineBounds.end - lineBounds.start)
        let currentLine = nsText.substring(with: lineRange)
        guard let info = NoteListItem(line: currentLine), info.kind == .checklist else { return }

        let offsetInLine = max(0, location - lineBounds.start)
        if onlyWhenNearCheckbox && offsetInLine > info.prefixLength {
            return
        }

        let replacement = info.isChecked ? uncheckedChecklistPrefix : checkedChecklistPrefix
        replaceText(
            in: textView,
            range: NSRange(location: lineBounds.start, length: info.prefixLength),
            with: replacement,
            cursorOffset: min(textView.selectedRange.location, nsText.length)
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func refreshChecklistDisplay() {
        guard !isRefreshingChecklistDisplay else { return }
        guard isViewLoaded else { return }
        guard !isAnimatingKeyboardLayout else { return }
        isRefreshingChecklistDisplay = true
        defer { isRefreshingChecklistDisplay = false }

        let nsText = textView.text as NSString

        var entries: [ChecklistOverlayView.Entry] = []
        var lineStart = 0

        while lineStart <= nsText.length {
            let lineBounds = currentLineBounds(in: nsText, at: lineStart)
            let lineRange = NSRange(location: lineBounds.start, length: lineBounds.end - lineBounds.start)
            let line = nsText.substring(with: lineRange)

            if let item = NoteListItem(line: line), item.kind == .bullet,
               let dotRect = bulletDotRect(for: item, lineStart: lineBounds.start) {
                entries.append(ChecklistOverlayView.Entry(rect: dotRect, kind: .bullet))
            } else if let item = NoteListItem(line: line), item.kind == .checklist {
                let markerRange = NSRange(location: lineBounds.start, length: item.prefixLength)
                if NSMaxRange(markerRange) <= nsText.length {
                    let markerLocation = lineBounds.start + item.markerOffset
                    let glyphRange = textView.layoutManager.glyphRange(
                        forCharacterRange: NSRange(location: markerLocation, length: 1),
                        actualCharacterRange: nil
                    )
                    let lineFragment = textView.layoutManager.lineFragmentRect(
                        forGlyphAt: glyphRange.location,
                        effectiveRange: nil
                    )
                    let glyphRect = textView.layoutManager.boundingRect(
                        forGlyphRange: glyphRange,
                        in: textView.textContainer
                    )
                    let boxSize = checkboxSize
                    let x = textView.textContainerInset.left + glyphRect.minX + 1
                    let y = textView.textContainerInset.top + lineFragment.midY - boxSize / 2
                    entries.append(
                        ChecklistOverlayView.Entry(
                            rect: CGRect(x: x, y: y, width: boxSize, height: boxSize),
                            kind: .checkbox(checked: item.isChecked)
                        )
                    )
                }
            }

            guard lineBounds.end < nsText.length else { break }
            lineStart = lineBounds.end + 1
        }

        let contentHeight = max(textView.contentSize.height, textView.bounds.height)
        checklistOverlay.frame = CGRect(
            x: 0,
            y: 0,
            width: max(textView.contentSize.width, textView.bounds.width),
            height: contentHeight
        )
        checklistOverlay.entries = entries
    }

    /// Side of the drawn checkbox for the editor font.
    private var checkboxSize: CGFloat {
        min(22, max(18, (textView.font?.lineHeight ?? 22) - 3))
    }

    private var bulletDotDiameter: CGFloat {
        max(5, round((textView.font ?? PN.font(17, bold: true)).lineHeight * 0.2))
    }

    /// The bullet dot's distance from the start of its line (after any indent).
    private var bulletDotInset: CGFloat { 9 }

    /// Space between a list marker (checkbox or bullet dot) and the item text.
    private var listMarkerGap: CGFloat {
        round(checkboxSize * 0.85)
    }

    /// The bullet's dot, at the middle of the x-height. It ends `listMarkerGap` before
    /// the item text, like a checkbox does, and sits on the dash when there's no gap.
    private func bulletDotRect(for item: NoteListItem, lineStart: Int) -> CGRect? {
        let nsText = textView.text as NSString
        let dashLocation = lineStart + item.markerOffset
        guard dashLocation < nsText.length else { return nil }
        let layoutManager = textView.layoutManager
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: dashLocation)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        let font = textView.font ?? PN.font(17, bold: true)
        let lineFragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let dashOrigin = layoutManager.location(forGlyphAt: glyphIndex)
        let diameter = bulletDotDiameter

        let rightEdge: CGFloat
        if item.prefixLength > item.markerOffset + 1 {
            // The space ending the prefix comes after the widened gap, so it marks
            // where the item text starts.
            let spaceGlyph = layoutManager.glyphIndexForCharacter(at: lineStart + item.prefixLength - 1)
            let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
            let textStart = layoutManager.location(forGlyphAt: spaceGlyph).x + spaceWidth
            rightEdge = textStart - listMarkerGap
        } else {
            let dashWidth = ("-" as NSString).size(withAttributes: [.font: font]).width
            rightEdge = dashOrigin.x + (dashWidth + diameter) / 2
        }

        return CGRect(
            x: textView.textContainerInset.left + lineFragment.minX + rightEdge - diameter,
            y: textView.textContainerInset.top + lineFragment.minY + dashOrigin.y - font.xHeight / 2 - diameter / 2,
            width: diameter,
            height: diameter
        )
    }

    private func lineInfo(at point: CGPoint) -> (text: String, characterIndex: Int, characterOffset: Int)? {
        var location = point
        location.x -= textView.textContainerInset.left
        location.y -= textView.textContainerInset.top
        guard location.x >= -8, location.y >= -8 else { return nil }

        let glyphIndex = textView.layoutManager.glyphIndex(
            for: location,
            in: textView.textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        let characterIndex = textView.layoutManager.characterIndexForGlyph(at: glyphIndex)
        let nsText = textView.text as NSString
        guard characterIndex <= nsText.length else { return nil }

        let lineBounds = currentLineBounds(in: nsText, at: characterIndex)
        let lineRange = NSRange(location: lineBounds.start, length: lineBounds.end - lineBounds.start)
        return (
            nsText.substring(with: lineRange),
            characterIndex,
            max(0, characterIndex - lineBounds.start)
        )
    }

    private func checklistHitRect(for lineBounds: (start: Int, end: Int), item: NoteListItem) -> CGRect? {
        let nsText = textView.text as NSString
        let markerLocation = lineBounds.start + item.markerOffset
        guard markerLocation < nsText.length else { return nil }

        let glyphRange = textView.layoutManager.glyphRange(
            forCharacterRange: NSRange(location: markerLocation, length: 1),
            actualCharacterRange: nil
        )
        guard glyphRange.location != NSNotFound else { return nil }

        let lineFragment = textView.layoutManager.lineFragmentRect(
            forGlyphAt: glyphRange.location,
            effectiveRange: nil
        )
        let glyphRect = textView.layoutManager.boundingRect(
            forGlyphRange: glyphRange,
            in: textView.textContainer
        )
        let boxSize = checkboxSize
        let boxRect = CGRect(
            x: textView.textContainerInset.left + glyphRect.minX + 1,
            y: textView.textContainerInset.top + lineFragment.midY - boxSize / 2,
            width: boxSize,
            height: boxSize
        )
        return boxRect.insetBy(dx: -8, dy: -8)
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

    private var bulletPrefix: String { "- " }
    private var uncheckedChecklistPrefix: String { "  \(NoteListItem.uncheckedMarker)    " }
    private var checkedChecklistPrefix: String { "  \(NoteListItem.checkedMarker)    " }
    private var uncheckedChecklistPrefixLength: Int { (uncheckedChecklistPrefix as NSString).length }

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        // A tap on a checkbox toggles it without bringing up the keyboard.
        selectionBeforeChecklistTap == nil
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !isRefreshingChecklistDisplay else { return }
        isDirty = true
        note.content = textView.text
        applyListParagraphStyles()
        refreshChecklistDisplay()
        if note.isPinned {
            LiveActivityManager.shared.update(with: note)
        }
    }

    /// The cursor never rests inside a list prefix (left of the item text): a tap on
    /// the checkbox, a dragged handle or arrow keys land at the start of the text.
    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isKeepingSelectionOutOfListPrefix,
              textView.markedTextRange == nil else { return }

        let selection = textView.selectedRange
        let previousSelection = lastSelectedRange
        lastSelectedRange = selection
        let nsText = textView.text as NSString
        let lineBounds = currentLineBounds(in: nsText, at: selection.location)
        // Selections spanning several lines may include whole items; leave them be.
        guard NSMaxRange(selection) <= lineBounds.end else { return }

        let line = nsText.substring(with: NSRange(location: lineBounds.start, length: lineBounds.end - lineBounds.start))
        guard let item = NoteListItem(line: line) else { return }

        let textStart = lineBounds.start + item.prefixLength
        guard selection.location < textStart else { return }

        // Moving left from the start of the text (arrow keys) continues to the end of
        // the previous line instead of bouncing back.
        let isStepLeftFromTextStart = selection.length == 0
            && previousSelection == NSRange(location: textStart, length: 0)
            && lineBounds.start > 0
        let adjusted = isStepLeftFromTextStart
            ? NSRange(location: lineBounds.start - 1, length: 0)
            : NSRange(location: textStart, length: max(NSMaxRange(selection), textStart) - textStart)

        isKeepingSelectionOutOfListPrefix = true
        textView.selectedRange = adjusted
        isKeepingSelectionOutOfListPrefix = false
        lastSelectedRange = adjusted
    }

    func textView(_ textView: UITextView,
                  shouldChangeTextIn range: NSRange,
        replacementText text: String) -> Bool {

        // IME composition (Japanese, Korean, …) must not be rewritten mid-way;
        // list handling runs once the marked text is committed.
        guard textView.markedTextRange == nil else { return true }

        let nsText = textView.text as NSString
        guard range.location <= nsText.length,
              NSMaxRange(range) <= nsText.length else {
            return false
        }

        if text.isEmpty,
           range.length > 0,
           shouldRemoveListPrefix(in: nsText, changing: range) {
            return false
        }

        if shouldNormalizePastedListText(text) {
            let normalizedText = normalizedPastedListText(text)
            if normalizedText != text {
                replaceText(
                    in: textView,
                    range: range,
                    with: normalizedText,
                    cursorOffset: range.location + (normalizedText as NSString).length
                )
                return false
            }
        }

        // Keep typed bullets lightly indented without changing them to symbol bullets.
        if text == " " {
            let lineStart = currentLineBounds(in: nsText, at: range.location).start
            let charsFromLineStart = range.location - lineStart
            if charsFromLineStart == 1,
               nsText.substring(with: NSRange(location: lineStart, length: 1)) == "-" {
                replaceText(
                    in: textView,
                    range: NSRange(location: lineStart, length: range.location - lineStart),
                    with: bulletPrefix,
                    cursorOffset: lineStart + bulletPrefix.count
                )
                return false
            }
        }

        // Auto-continue bullet on new line. Autocorrect can submit a corrected word
        // and the newline in the same replacement, so detect newlines inside text too.
        let replacementText = text as NSString
        let newlineRange = replacementText.rangeOfCharacter(from: .newlines)
        if newlineRange.location != NSNotFound {
            let prospectiveText = nsText.replacingCharacters(in: range, with: text) as NSString
            let newlineLocation = range.location + newlineRange.location
            let lineBounds = currentLineBounds(in: prospectiveText, at: newlineLocation)
            let lineRange = NSRange(location: lineBounds.start, length: lineBounds.end - lineBounds.start)
            let currentLine = prospectiveText.substring(with: lineRange)

            if let item = NoteListItem(line: currentLine) {
                if item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Empty bullet line -> strip the bullet and stop the list.
                    let originalLineBounds = currentLineBounds(in: nsText, at: range.location)
                    let originalLineRange = NSRange(
                        location: originalLineBounds.start,
                        length: originalLineBounds.end - originalLineBounds.start
                    )
                    replaceText(
                        in: textView,
                        range: originalLineRange,
                        with: "",
                        cursorOffset: originalLineBounds.start
                    )
                    return false
                }
                // Non-empty list line -> start a new list item.
                let nextPrefix = item.kind == .checklist ? uncheckedChecklistPrefix : bulletPrefix
                let adjustedReplacement = replacementText.replacingCharacters(
                    in: newlineRange,
                    with: "\n\(nextPrefix)"
                )
                replaceText(
                    in: textView,
                    range: range,
                    with: adjustedReplacement,
                    cursorOffset: range.location + (adjustedReplacement as NSString).length
                )
                return false
            }
        }

        return true
    }

    private func shouldNormalizePastedListText(_ text: String) -> Bool {
        text.contains("\n") || NoteListItem.containsChecklistMarker(text)
    }

    private func normalizedPastedListText(_ text: String) -> String {
        text
            .components(separatedBy: "\n")
            .map(normalizedPastedListLine)
            .joined(separator: "\n")
    }

    private func normalizedPastedListLine(_ line: String) -> String {
        guard let item = NoteListItem(line: line), item.kind == .checklist else { return line }
        let prefix = item.isChecked ? checkedChecklistPrefix : uncheckedChecklistPrefix
        return "\(prefix)\(item.text)"
    }

    /// Backspace at the start of a list item removes its whole marker: an empty item
    /// becomes an empty line, a filled one keeps its text as a plain line.
    private func shouldRemoveListPrefix(in text: NSString, changing range: NSRange) -> Bool {
        let lineBounds = currentLineBounds(in: text, at: range.location)
        let lineRange = NSRange(location: lineBounds.start, length: lineBounds.end - lineBounds.start)
        let currentLine = text.substring(with: lineRange)

        guard let item = NoteListItem(line: currentLine) else { return false }

        // Only deletions that stay inside the prefix; a selection reaching into the
        // text or other lines deletes normally.
        let prefixRange = NSRange(location: lineBounds.start, length: item.prefixLength)
        guard range.location >= prefixRange.location,
              NSMaxRange(range) <= NSMaxRange(prefixRange) else { return false }

        let isEmpty = item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        replaceText(
            in: textView,
            range: isEmpty ? lineRange : prefixRange,
            with: "",
            cursorOffset: lineBounds.start
        )
        return true
    }

    private func currentLineBounds(in text: NSString, at location: Int) -> (start: Int, end: Int) {
        let safeLocation = min(max(location, 0), text.length)
        let prefix = text.substring(to: safeLocation) as NSString
        let previousNewline = prefix.range(of: "\n", options: .backwards)
        let start = previousNewline.location == NSNotFound ? 0 : previousNewline.location + 1

        let suffixRange = NSRange(location: safeLocation, length: text.length - safeLocation)
        let nextNewline = text.range(of: "\n", options: [], range: suffixRange)
        let end = nextNewline.location == NSNotFound ? text.length : nextNewline.location

        return (start, end)
    }

    private func replaceText(in textView: UITextView, range: NSRange, with replacement: String, cursorOffset: Int) {
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: textView.beginningOfDocument, offset: NSMaxRange(range)),
              let uiTextRange = textView.textRange(from: start, to: end) else {
            return
        }

        textView.replace(uiTextRange, withText: replacement)
        let updatedText = textView.text ?? ""
        let safeCursorOffset = min(cursorOffset, (updatedText as NSString).length)
        if let cursorPosition = textView.position(from: textView.beginningOfDocument, offset: safeCursorOffset) {
            textView.selectedTextRange = textView.textRange(from: cursorPosition, to: cursorPosition)
        }
        isDirty = true
        note.content = updatedText
        applyListParagraphStyles()
        refreshChecklistDisplay()
        if note.isPinned {
            LiveActivityManager.shared.update(with: note)
        }
    }

    private func applyListParagraphStyles() {
        guard !isApplyingListParagraphStyles else { return }
        guard textView.textStorage.length > 0 else { return }
        // Touching attributes or the selection while text is marked cancels the IME composition.
        guard textView.markedTextRange == nil else { return }

        isApplyingListParagraphStyles = true
        defer { isApplyingListParagraphStyles = false }

        let selectedRange = textView.selectedRange
        let font = textView.font ?? PN.font(17, bold: true)
        let nsText = textView.text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        func width(_ string: String) -> CGFloat {
            (string as NSString).size(withAttributes: [.font: font]).width
        }
        // Item text starts one marker gap after its marker: after the checkbox (drawn
        // 1pt after the marker glyph), or after the bullet dot, which sits right at
        // the start of the line.
        func textColumn(indent: Substring) -> CGFloat {
            ceil(width(String(indent)) + 1 + checkboxSize + listMarkerGap)
        }
        func bulletTextColumn(indent: Substring) -> CGFloat {
            ceil(width(String(indent)) + bulletDotInset + bulletDotDiameter + listMarkerGap)
        }

        textView.textStorage.beginEditing()
        textView.textStorage.removeAttribute(.paragraphStyle, range: fullRange)
        textView.textStorage.removeAttribute(.kern, range: fullRange)
        textView.textStorage.addAttribute(.foregroundColor, value: textView.textColor ?? UIColor.pnPrimary, range: fullRange)

        var lineStart = 0
        while lineStart <= nsText.length {
            let lineBounds = currentLineBounds(in: nsText, at: lineStart)
            let lineRange = NSRange(location: lineBounds.start, length: lineBounds.end - lineBounds.start)
            let line = nsText.substring(with: lineRange)

            if let item = NoteListItem(line: line) {
                let prefix = (line as NSString).substring(to: min(item.prefixLength, (line as NSString).length))
                var headIndent = ceil(width(prefix))

                if item.kind == .bullet {
                    textView.textStorage.addAttribute(
                        .foregroundColor,
                        value: UIColor.clear,
                        range: NSRange(location: lineBounds.start + item.markerOffset, length: 1)
                    )
                }

                if item.prefixLength > item.markerOffset + 1 {
                    // Widen the space after the marker into one gap instead of padding
                    // with more spaces. The kern sits on the marker, so text typed after
                    // the prefix never inherits it.
                    let column = item.kind == .bullet
                        ? bulletTextColumn(indent: item.indent)
                        : textColumn(indent: item.indent)
                    let natural = width(prefix)
                    let extra = max(0, column - natural)
                    textView.textStorage.addAttribute(
                        .kern,
                        value: extra,
                        range: NSRange(location: lineBounds.start + item.markerOffset, length: 1)
                    )
                    headIndent = ceil(natural + extra)
                }

                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.headIndent = headIndent
                paragraphStyle.firstLineHeadIndent = 0
                textView.textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
            }

            guard lineBounds.end < nsText.length else { break }
            lineStart = lineBounds.end + 1
        }

        textView.textStorage.endEditing()
        textView.selectedRange = NSRange(
            location: min(selectedRange.location, textView.textStorage.length),
            length: min(selectedRange.length, max(0, textView.textStorage.length - min(selectedRange.location, textView.textStorage.length)))
        )
        // Text typed right after a hidden dash must not inherit its clear color or gap.
        textView.typingAttributes[.foregroundColor] = textView.textColor
        textView.typingAttributes[.kern] = nil
    }
}

// MARK: - UIGestureRecognizerDelegate (swipe-back support)

extension NoteDetailViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === checklistTapGesture else { return true }

        let point = touch.location(in: textView)
        guard let line = lineInfo(at: point),
              let item = NoteListItem(line: line.text),
              item.kind == .checklist else {
            return false
        }

        let nsText = textView.text as NSString
        let lineBounds = currentLineBounds(in: nsText, at: line.characterIndex)
        guard let hitRect = checklistHitRect(for: lineBounds, item: item),
              hitRect.contains(point) else { return false }

        // Called as the finger touches down, before the text view reacts to the tap.
        selectionBeforeChecklistTap = textView.selectedRange
        // In case the touch never becomes a tap (the finger moves away).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.selectionBeforeChecklistTap = nil
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === wordSelectionLongPressGesture || otherGestureRecognizer === wordSelectionLongPressGesture {
            return false
        }
        return gestureRecognizer === checklistTapGesture
            || otherGestureRecognizer === checklistTapGesture
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === checklistTapGesture { return true }
        if gestureRecognizer === wordSelectionLongPressGesture { return true }
        // Allow swipe-back only when we're not at the root
        return navigationController?.viewControllers.count ?? 0 > 1
    }
}
