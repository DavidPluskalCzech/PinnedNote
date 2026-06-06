import UIKit
import Combine

final class NoteListViewController: UIViewController {

    // MARK: - Subviews

    private let titleLabel   = UILabel()
    private let tableView    = UITableView()
    private let bottomBar    = NoteListBottomBar()
    private let emptyState   = EmptyStateView()
    private let trialBanner  = TrialExpiredBannerView()
    private let headerFadeView = UIView()
    private let headerFadeLayer = CAGradientLayer()

    // MARK: - State

    private var isInEditMode = false
    private var isSwipeActionOpen = false
    private var quickPinPanIndexPath: IndexPath?
    private var quickPinPanMovedLeft = false
    private var quickPinPanDidPin = false
    private let quickPinRevealThreshold: CGFloat = 56
    private let dragSelectRailWidth: CGFloat = 76
    private let dragSelectAutoScrollZoneHeight: CGFloat = 72
    private let dragSelectMaxAutoScrollSpeed: CGFloat = 7
    private var suppressSelectionUntil: Date?
    private var dragSelectPathIDs: [UUID] = []
    private var dragSelectInitialSelectedIDs = Set<UUID>()
    private var dragSelectStartID: UUID?
    private var dragSelectStartLocation: CGPoint?
    private var dragSelectCanRestoreStart = false
    private var dragSelectStartRestored = false
    private var dragSelectCurrentLocation: CGPoint?
    private var dragSelectDisplayLink: CADisplayLink?
    private var dragSelectIsRemoving = false
    private var selectedIDs  = Set<UUID>()
    private var cancellables = Set<AnyCancellable>()

    private var tableTopNoBanner:   NSLayoutConstraint!
    private var tableTopWithBanner: NSLayoutConstraint!
    private lazy var quickPinPanGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleQuickPinPan(_:)))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()
    private lazy var dragSelectPanGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handleDragSelectPan(_:)))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .pnBackground
        buildLayout()
        wireBottomBar()
        bindStore()
        listenForCreateNote()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme),
            name: .pnThemeChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshTrialBanner),
            name: .pnPurchaseStateChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(showStorageError),
            name: .pnStorageError, object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Sync displayedIDs so applyDiff has a correct baseline after returning from detail
        displayedIDs = NoteStore.shared.notes.map { $0.id }
        tableView.reloadData()
        refreshEmptyState()
    }

    // MARK: - Build layout

    private func buildLayout() {
        let readableGuide = view.pnAddReadableContentGuide()

        // Title — negative stroke width fills the stroke, making the glyphs heavier
        let titleFont = UIFont(name: "BradleyHandITCTT-Bold", size: 44) ?? PN.font(44, bold: true)
        titleLabel.attributedText = NSAttributedString(string: "PinnedNote", attributes: [
            .font:        titleFont,
            .foregroundColor: UIColor.pnPrimary,
            .strokeColor: UIColor.pnPrimary,
            .strokeWidth: -3.5,
        ])
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Table
        tableView.backgroundColor              = .pnBackground
        tableView.register(NoteCell.self, forCellReuseIdentifier: NoteCell.reuseID)
        tableView.dataSource                   = self
        tableView.delegate                     = self
        tableView.separatorStyle               = .none
        tableView.rowHeight                    = UITableView.automaticDimension
        tableView.estimatedRowHeight           = 90
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.contentInsetAdjustmentBehavior = .automatic
        tableView.contentInset                 = UIEdgeInsets(top: 38, left: 0, bottom: 80, right: 0)
        tableView.scrollIndicatorInsets        = UIEdgeInsets(top: 38, left: 0, bottom: 80, right: 0)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        tableView.addGestureRecognizer(quickPinPanGesture)
        tableView.addGestureRecognizer(dragSelectPanGesture)

        // Softens the handoff from the solid title area into scrolling notes.
        headerFadeView.isUserInteractionEnabled = false
        headerFadeView.backgroundColor = .clear
        headerFadeView.translatesAutoresizingMaskIntoConstraints = false
        headerFadeView.layer.addSublayer(headerFadeLayer)
        view.addSubview(headerFadeView)

        // Bottom bar — UIToolbar, pinned to the very bottom edge (system handles safe area inset)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        // Trial expired banner
        trialBanner.translatesAutoresizingMaskIntoConstraints = false
        trialBanner.isHidden = true
        trialBanner.onUpgrade = { [weak self] in self?.openSettings() }
        view.addSubview(trialBanner)

        // Empty state
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.isHidden = true
        view.addSubview(emptyState)
        emptyState.onCreateNote = { [weak self] in self?.openNewNote() }

        tableTopNoBanner   = tableView.topAnchor.constraint(equalTo: headerFadeView.topAnchor)
        tableTopWithBanner = tableView.topAnchor.constraint(equalTo: trialBanner.bottomAnchor, constant: 4)
        tableTopNoBanner.isActive = true

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 26),
            titleLabel.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor, constant: PN.padding),

            headerFadeView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: -8),
            headerFadeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerFadeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerFadeView.heightAnchor.constraint(equalToConstant: 50),

            trialBanner.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            trialBanner.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor, constant: PN.padding),
            trialBanner.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor, constant: -PN.padding),

            bottomBar.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            tableView.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyState.centerXAnchor.constraint(equalTo: readableGuide.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
        ])

        refreshHeaderFade()
        refreshTrialBanner()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        headerFadeLayer.frame = headerFadeView.bounds
    }

    // MARK: - Bottom bar wiring

    private func wireBottomBar() {
        bottomBar.onNewNote  = { [weak self] in self?.openNewNote() }
        bottomBar.onEdit     = { [weak self] in self?.setListEditMode(true) }
        bottomBar.onSettings = { [weak self] in self?.openSettings() }
        bottomBar.onDelete   = { [weak self] in self?.deleteSelected() }
        bottomBar.onCancel   = { [weak self] in self?.setListEditMode(false) }
    }

    // MARK: - Combine binding

    private var displayedIDs: [UUID] = []
    private var pendingAnimatedDeletionID: UUID?

    private func bindStore() {
        NoteStore.shared.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newNotes in
                self?.applyDiff(newNotes)
            }
            .store(in: &cancellables)
    }

    private func applyDiff(_ newNotes: [Note]) {
        let oldIDs = displayedIDs
        let newIDs = newNotes.map { $0.id }

        guard oldIDs != newIDs else {
            // Same order/count — just reload visible cells to refresh content (e.g. date)
            tableView.visibleCells.compactMap { $0 as? NoteCell }.forEach { cell in
                guard let ip = tableView.indexPath(for: cell),
                      ip.row < newNotes.count else { return }
                let note = newNotes[ip.row]
                cell.configure(
                    with: note,
                    editing: isInEditMode,
                    selected: selectedIDs.contains(note.id)
                )
            }
            refreshEmptyState()
            return
        }

        if let deletedID = pendingAnimatedDeletionID,
           oldIDs.count == newIDs.count + 1,
           !newIDs.contains(deletedID),
           let deletedRow = oldIDs.firstIndex(of: deletedID) {
            pendingAnimatedDeletionID = nil
            displayedIDs = newIDs
            let indexPath = IndexPath(row: deletedRow, section: 0)
            UIView.animate(
                withDuration: 0.38,
                delay: 0,
                options: [.curveEaseInOut, .allowUserInteraction]
            ) {
                self.tableView.performBatchUpdates {
                    self.tableView.deleteRows(at: [indexPath], with: .fade)
                }
            } completion: { _ in
                self.refreshEmptyState()
            }
            return
        }

        pendingAnimatedDeletionID = nil
        displayedIDs = newIDs

        tableView.reloadData()
        refreshEmptyState()
    }

    // MARK: - Lock-screen intent notification

    private func listenForCreateNote() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCreateNoteNotification),
            name: .pnCreateNote,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenNoteNotification(_:)),
            name: .pnOpenNote,
            object: nil
        )
    }

    @objc private func handleCreateNoteNotification() {
        // Longer delay — app may be animating back from lock screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.openNewNote()
        }
    }

    @objc private func handleOpenNoteNotification(_ notification: Notification) {
        guard let noteIDString = notification.userInfo?["noteID"] as? String,
              let noteID = UUID(uuidString: noteIDString)
        else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.openNote(withID: noteID)
        }
    }

    // MARK: - Empty state

    private func refreshEmptyState() {
        let empty = NoteStore.shared.notes.isEmpty
        emptyState.isHidden = !empty
        tableView.isHidden  = empty
    }

    // MARK: - Actions

    private func openNewNote() {
        // If a note detail is already on top, pop it first (saves note via viewWillDisappear)
        if navigationController?.topViewController is NoteDetailViewController {
            navigationController?.popToViewController(self, animated: false)
        }
        let vc = NoteDetailViewController(note: nil)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openNote(withID noteID: UUID) {
        guard let note = NoteStore.shared.notes.first(where: { $0.id == noteID }) else { return }

        if navigationController?.topViewController is NoteDetailViewController {
            navigationController?.popToViewController(self, animated: false)
        }

        let vc = NoteDetailViewController(note: note)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func setListEditMode(_ editing: Bool) {
        guard isInEditMode != editing else {
            selectedIDs.removeAll()
            resetDragSelectionState()
            syncVisibleSelectionCells(animated: false)
            bottomBar.setDeleteEnabled(false)
            return
        }

        isInEditMode = editing
        selectedIDs.removeAll()
        resetDragSelectionState()
        tableView.setEditing(false, animated: false)
        tableView.endEditing(true)
        // Do NOT use tableView.setEditing — that shows the system's native circles.
        // Drive edit-mode UI entirely through the cell's own selection state.
        syncVisibleSelectionCells(animated: editing)
        bottomBar.setEditMode(isInEditMode)
        bottomBar.setDeleteEnabled(false)
    }

    private func resetDragSelectionState() {
        dragSelectPathIDs.removeAll()
        dragSelectInitialSelectedIDs.removeAll()
        dragSelectStartID = nil
        dragSelectStartLocation = nil
        dragSelectCanRestoreStart = false
        dragSelectStartRestored = false
        dragSelectIsRemoving = false
        dragSelectCurrentLocation = nil
        stopDragSelectAutoScroll()
    }

    private func syncVisibleSelectionCells(animated: Bool) {
        visibleSelectionIndexPaths().forEach { indexPath in
            guard let cell = tableView.cellForRow(at: indexPath) as? NoteCell else { return }
            let note = NoteStore.shared.notes[indexPath.row]
            if animated {
                cell.configure(with: note)
                cell.setSelectionState(
                    editing: isInEditMode,
                    selected: selectedIDs.contains(note.id),
                    animated: true
                )
            } else {
                cell.configure(
                    with: note,
                    editing: isInEditMode,
                    selected: selectedIDs.contains(note.id)
                )
            }
        }
    }

    private func visibleSelectionIndexPaths() -> [IndexPath] {
        let expandedBounds = tableView.bounds.insetBy(dx: 0, dy: -120)
        let visible = tableView.indexPathsForVisibleRows ?? []
        let nearVisible = tableView.indexPathsForRows(in: expandedBounds) ?? []
        let rowCount = NoteStore.shared.notes.count
        let unique = Set(visible + nearVisible)
        return unique
            .filter { $0.section == 0 && $0.row >= 0 && $0.row < rowCount }
            .sorted { $0.row < $1.row }
    }

    private func deleteSelected() {
        guard !selectedIDs.isEmpty else { return }

        let count = selectedIDs.count
        let title = count == 1
            ? NSLocalizedString("list_delete_note_singular", comment: "")
            : String(format: NSLocalizedString("list_delete_notes_plural", comment: ""), count)
        presentPNAlert(
            title: title,
            actions: [
                PNAlertAction(title: NSLocalizedString("list_cancel", comment: ""), style: .cancel),
                PNAlertAction(title: NSLocalizedString("list_delete", comment: ""), style: .destructive) { [weak self] in
                    guard let self else { return }
                    // Stop Live Activity for any pinned note being deleted
                    NoteStore.shared.notes
                        .filter { self.selectedIDs.contains($0.id) && $0.isPinned }
                        .forEach { _ in LiveActivityManager.shared.stop() }
                    self.selectedIDs.forEach {
                        ScheduledPinManager.shared.removeNotificationBackup(noteID: $0)
                    }

                    NoteStore.shared.delete(ids: self.selectedIDs)
                    self.setListEditMode(false)
                }
            ]
        )
    }

    @objc private func handleDragSelectPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            dragSelectPathIDs.removeAll()
            dragSelectInitialSelectedIDs = selectedIDs
            tableView.isScrollEnabled = false
            let location = gesture.location(in: tableView)
            dragSelectStartLocation = location
            dragSelectIsRemoving = isNoteSelectedUnderDrag(at: location)
            dragSelectCurrentLocation = location
            selectNoteUnderDrag(at: location)
            startDragSelectAutoScroll()

        case .changed:
            let location = gesture.location(in: tableView)
            dragSelectCurrentLocation = location
            selectNoteUnderDrag(at: location)

        case .ended, .cancelled, .failed:
            dragSelectPathIDs.removeAll()
            dragSelectInitialSelectedIDs.removeAll()
            dragSelectStartID = nil
            dragSelectStartLocation = nil
            dragSelectCanRestoreStart = false
            dragSelectStartRestored = false
            dragSelectIsRemoving = false
            dragSelectCurrentLocation = nil
            tableView.isScrollEnabled = true
            stopDragSelectAutoScroll()

        default:
            break
        }
    }

    private func isNoteSelectedUnderDrag(at location: CGPoint) -> Bool {
        guard let indexPath = tableView.indexPathForRow(at: location),
              indexPath.row < NoteStore.shared.notes.count
        else { return false }

        let note = NoteStore.shared.notes[indexPath.row]
        return selectedIDs.contains(note.id)
    }

    private func selectNoteUnderDrag(at location: CGPoint) {
        guard isInEditMode,
              let indexPath = tableView.indexPathForRow(at: location),
              indexPath.row < NoteStore.shared.notes.count
        else { return }

        let note = NoteStore.shared.notes[indexPath.row]
        if dragSelectPathIDs.isEmpty,
           dragSelectStartRestored,
           note.id == dragSelectStartID,
           shouldKeepRestoredStartSuppressed(at: location) {
            return
        }

        if let existingIndex = dragSelectPathIDs.firstIndex(of: note.id) {
            let removedIDs = Array(dragSelectPathIDs.suffix(from: existingIndex + 1))
            if removedIDs.isEmpty {
                if shouldRestoreDragStart(at: location, noteID: note.id) {
                    dragSelectPathIDs.removeAll()
                    dragSelectStartRestored = true
                    restoreDragSelection(for: note.id)
                    bottomBar.setDeleteEnabled(!selectedIDs.isEmpty)
                }
                return
            }

            dragSelectPathIDs.removeLast(removedIDs.count)
            removedIDs.forEach { restoreDragSelection(for: $0) }
            if shouldRestoreDragStart(at: location, noteID: note.id) {
                dragSelectPathIDs.removeAll()
                dragSelectStartRestored = true
                restoreDragSelection(for: note.id)
            }
            bottomBar.setDeleteEnabled(!selectedIDs.isEmpty)
            return
        }

        dragSelectPathIDs.append(note.id)
        if dragSelectStartID == nil {
            dragSelectStartID = note.id
        } else {
            dragSelectCanRestoreStart = true
            dragSelectStartRestored = false
        }

        if dragSelectIsRemoving {
            selectedIDs.remove(note.id)
        } else {
            selectedIDs.insert(note.id)
        }

        refreshDragSelectionCell(noteID: note.id)
        bottomBar.setDeleteEnabled(!selectedIDs.isEmpty)
    }

    private func shouldRestoreDragStart(at location: CGPoint, noteID: UUID) -> Bool {
        guard dragSelectCanRestoreStart,
              dragSelectPathIDs.count == 1,
              noteID == dragSelectStartID,
              let startLocation = dragSelectStartLocation
        else { return false }

        return location.y <= startLocation.y + 8
    }

    private func shouldKeepRestoredStartSuppressed(at location: CGPoint) -> Bool {
        guard let startLocation = dragSelectStartLocation else { return false }
        return location.y <= startLocation.y + 8
    }

    private func restoreDragSelection(for noteID: UUID) {
        if dragSelectInitialSelectedIDs.contains(noteID) {
            selectedIDs.insert(noteID)
        } else {
            selectedIDs.remove(noteID)
        }
        refreshDragSelectionCell(noteID: noteID)
    }

    private func refreshDragSelectionCell(noteID: UUID) {
        guard let row = NoteStore.shared.notes.firstIndex(where: { $0.id == noteID }) else { return }
        let indexPath = IndexPath(row: row, section: 0)
        if let cell = tableView.cellForRow(at: indexPath) as? NoteCell {
            cell.applySelected(selectedIDs.contains(noteID))
        }
        bottomBar.setDeleteEnabled(!selectedIDs.isEmpty)
    }

    private func startDragSelectAutoScroll() {
        guard dragSelectDisplayLink == nil else { return }
        let displayLink = CADisplayLink(target: self, selector: #selector(handleDragSelectAutoScroll))
        displayLink.add(to: .main, forMode: .common)
        dragSelectDisplayLink = displayLink
    }

    private func stopDragSelectAutoScroll() {
        dragSelectDisplayLink?.invalidate()
        dragSelectDisplayLink = nil
        tableView.isScrollEnabled = true
    }

    @objc private func handleDragSelectAutoScroll() {
        guard isInEditMode,
              let location = dragSelectCurrentLocation
        else {
            stopDragSelectAutoScroll()
            return
        }

        let visibleY = location.y - tableView.contentOffset.y
        let topZone = tableView.adjustedContentInset.top + dragSelectAutoScrollZoneHeight
        let bottomZone = tableView.bounds.height - tableView.adjustedContentInset.bottom - dragSelectAutoScrollZoneHeight

        var delta: CGFloat = 0
        if visibleY < topZone {
            delta = -dragSelectMaxAutoScrollSpeed * ((topZone - visibleY) / dragSelectAutoScrollZoneHeight)
        } else if visibleY > bottomZone {
            delta = dragSelectMaxAutoScrollSpeed * ((visibleY - bottomZone) / dragSelectAutoScrollZoneHeight)
        }

        guard delta != 0 else { return }

        let minOffsetY = -tableView.adjustedContentInset.top
        let maxOffsetY = max(
            minOffsetY,
            tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom
        )
        let newOffsetY = min(max(tableView.contentOffset.y + delta, minOffsetY), maxOffsetY)
        guard newOffsetY != tableView.contentOffset.y else { return }

        tableView.contentOffset.y = newOffsetY
        let adjustedLocation = CGPoint(x: location.x, y: location.y + delta)
        dragSelectCurrentLocation = adjustedLocation
        selectNoteUnderDrag(at: adjustedLocation)
    }

    @objc private func handleQuickPinPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            quickPinPanIndexPath = nil
            quickPinPanMovedLeft = false
            quickPinPanDidPin = false

            guard !isInEditMode, !isSwipeActionOpen else { return }
            let location = gesture.location(in: tableView)
            quickPinPanIndexPath = tableView.indexPathForRow(at: location)

        case .changed:
            guard !quickPinPanDidPin,
                  !quickPinPanMovedLeft,
                  let indexPath = quickPinPanIndexPath,
                  indexPath.row < NoteStore.shared.notes.count,
                  let cell = tableView.cellForRow(at: indexPath) as? NoteCell else { return }

            let translation = gesture.translation(in: tableView)
            let horizontalDistance = abs(translation.x)
            let verticalDistance = abs(translation.y)

            if translation.x < -12 {
                quickPinPanMovedLeft = true
                cell.resetQuickPinReveal(animated: true)
                return
            }

            guard horizontalDistance > verticalDistance * 1.4 else { return }

            let note = NoteStore.shared.notes[indexPath.row]
            cell.setQuickPinRevealPinnedState(note.isPinned)
            let progress = max(0, min(translation.x / quickPinRevealThreshold, 1))
            cell.setQuickPinRevealProgress(progress)

            guard translation.x >= quickPinRevealThreshold else { return }

            quickPinPanDidPin = true
            if canTogglePinFromList(note) {
                suppressSelectionUntil = Date().addingTimeInterval(0.8)
                cell.completeQuickPinReveal { [weak self] in
                    guard let self else { return }
                    Task { @MainActor in
                        await self.commitPinToggleFromList(note)
                        self.refreshQuickPinnedRow(at: indexPath)
                    }
                }
            } else {
                cell.resetQuickPinReveal(animated: true)
            }

        case .ended, .cancelled, .failed:
            if !quickPinPanDidPin,
               let indexPath = quickPinPanIndexPath,
               let cell = tableView.cellForRow(at: indexPath) as? NoteCell {
                cell.resetQuickPinReveal(animated: true)
            }
            quickPinPanIndexPath = nil
            quickPinPanMovedLeft = false
            quickPinPanDidPin = false

        default:
            break
        }
    }

    @objc private func refreshTrialBanner() {
        let pm = PurchaseManager.shared
        let showBanner = !pm.isPro && !pm.isTrialActive
        guard trialBanner.isHidden == showBanner else { return }  // no change
        trialBanner.isHidden        = !showBanner
        headerFadeView.isHidden = showBanner
        let topInset: CGFloat = showBanner ? 12 : 38
        tableView.contentInset.top = topInset
        tableView.scrollIndicatorInsets = UIEdgeInsets(top: topInset, left: 0, bottom: 80, right: 0)
        tableTopNoBanner.isActive   = !showBanner
        tableTopWithBanner.isActive = showBanner
        UIView.animate(withDuration: 0.3) { self.view.layoutIfNeeded() }
    }

    @objc private func showStorageError() {
        guard let message = NoteStore.shared.storageError else { return }
        DispatchQueue.main.async {
            guard !(self.topMostViewController() is PNAlertController) else { return }
            self.topMostViewController()?.presentPNAlert(
                title: NSLocalizedString("storage_error_title", comment: ""),
                message: message,
                actions: [
                    PNAlertAction(title: NSLocalizedString("settings_ok", comment: ""))
                ]
            )
        }
    }

    private func topMostViewController() -> UIViewController? {
        var top = view.window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        if let nav = top as? UINavigationController {
            return nav.topViewController
        }
        return top
    }

    @objc private func applyTheme() {
        view.backgroundColor      = .pnBackground
        tableView.backgroundColor = .pnBackground
        refreshHeaderFade()
        bottomBar.refreshColors()
        trialBanner.refreshColors()
        emptyState.refreshColors()
        let titleFont = UIFont(name: "BradleyHandITCTT-Bold", size: 44) ?? PN.font(44, bold: true)
        titleLabel.attributedText = NSAttributedString(string: "PinnedNote", attributes: [
            .font:        titleFont,
            .foregroundColor: UIColor.pnPrimary,
            .strokeColor: UIColor.pnPrimary,
            .strokeWidth: -3.5,
        ])
        tableView.reloadData()
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

    private func openSettings() {
        let vc  = SettingsViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    private func canTogglePinFromList(_ note: Note) -> Bool {
        guard !note.isPinned else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return true
        }

        guard !note.isEmpty else { return false }

        let pm = PurchaseManager.shared
        guard pm.isPro || pm.isTrialActive else {
            showUpgradePrompt()
            return false
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        return true
    }

    private func commitPinToggleFromList(_ note: Note) async {
        if note.isPinned {
            var unpinnedNote = note
            unpinnedNote.isPinned = false
            NoteStore.shared.updatePinOnly(unpinnedNote)
            LiveActivityManager.shared.stop()
            PinStatusToast.show(in: view, pinned: false)
            return
        }

        var pinnedNote = note
        pinnedNote.isPinned = true
        let didStart = await LiveActivityManager.shared.start(with: pinnedNote)
        guard didStart else { return }
        NoteStore.shared.unpinAll(except: note.id)
        NoteStore.shared.updatePinOnly(pinnedNote)
        PinStatusToast.show(in: view, pinned: true)
    }

    private func refreshQuickPinnedRow(at indexPath: IndexPath) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard indexPath.row < NoteStore.shared.notes.count else {
                self.tableView.reloadData()
                return
            }
            UIView.performWithoutAnimation {
                self.tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
    }

    private func showUpgradePrompt() {
        presentPNAlert(
            title: NSLocalizedString("detail_trial_ended_title", comment: ""),
            message: NSLocalizedString("detail_trial_ended_message", comment: ""),
            actions: [
                PNAlertAction(title: NSLocalizedString("detail_cancel", comment: ""), style: .cancel),
                PNAlertAction(title: NSLocalizedString("detail_upgrade", comment: "")) { [weak self] in
                    self?.openSettings()
                }
            ]
        )
    }
}

// MARK: - UITableViewDataSource

extension NoteListViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        NoteStore.shared.notes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: NoteCell.reuseID, for: indexPath) as! NoteCell
        guard indexPath.row < NoteStore.shared.notes.count else { return cell }
        let note = NoteStore.shared.notes[indexPath.row]
        cell.configure(with: note, editing: isInEditMode, selected: selectedIDs.contains(note.id))
        return cell
    }

}

// MARK: - UITableViewDelegate

extension NoteListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        if let suppressSelectionUntil {
            if Date() < suppressSelectionUntil {
                self.suppressSelectionUntil = nil
                return
            }
            self.suppressSelectionUntil = nil
        }

        guard indexPath.row < NoteStore.shared.notes.count else { return }
        let note = NoteStore.shared.notes[indexPath.row]

        if isInEditMode {
            // Toggle selection manually
            if selectedIDs.contains(note.id) {
                selectedIDs.remove(note.id)
            } else {
                selectedIDs.insert(note.id)
            }
            if let cell = tableView.cellForRow(at: indexPath) as? NoteCell {
                cell.applySelected(selectedIDs.contains(note.id))
            }
            bottomBar.setDeleteEnabled(!selectedIDs.isEmpty)
        } else {
            let vc = NoteDetailViewController(note: note)
            navigationController?.pushViewController(vc, animated: true)
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !isInEditMode else { return nil }

        let action = UIContextualAction(style: .destructive, title: nil) { _, _, done in
            guard indexPath.row < NoteStore.shared.notes.count else {
                done(false)
                return
            }
            let note = NoteStore.shared.notes[indexPath.row]
            if note.isPinned { LiveActivityManager.shared.stop() }
            ScheduledPinManager.shared.removeNotificationBackup(noteID: note.id)
            self.pendingAnimatedDeletionID = note.id
            NoteStore.shared.delete(id: note.id)
            done(true)
        }
        action.image           = UIImage(systemName: "trash")
        action.backgroundColor = .pnDestructive
        return UISwipeActionsConfiguration(actions: [action])
    }

    func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
        isSwipeActionOpen = true
    }

    func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
        isSwipeActionOpen = false
    }
}

// MARK: - UIGestureRecognizerDelegate

extension NoteListViewController: UIGestureRecognizerDelegate {

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }

        let velocity = pan.velocity(in: tableView)
        if gestureRecognizer === quickPinPanGesture {
            guard !isInEditMode, !isSwipeActionOpen else { return false }
            return velocity.x > 0 && abs(velocity.x) > abs(velocity.y) * 1.2
        }

        if gestureRecognizer === dragSelectPanGesture {
            guard isInEditMode, !isSwipeActionOpen else { return false }
            let location = pan.location(in: tableView)
            guard location.x <= dragSelectRailWidth else { return false }
            return abs(velocity.y) >= abs(velocity.x)
        }

        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === dragSelectPanGesture || otherGestureRecognizer === dragSelectPanGesture {
            return false
        }

        return true
    }
}

// MARK: - TrialExpiredBannerView

private final class TrialExpiredBannerView: UIView {

    var onUpgrade: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor    = .pnSurface
        layer.cornerRadius = 12
        layer.masksToBounds = true

        let label = UILabel()
        label.text          = NSLocalizedString("list_trial_ended_banner", comment: "")
        label.font          = UIFont.systemFont(ofSize: 13, weight: .regular)
        label.textColor     = .pnSecondary
        label.numberOfLines = 1

        let btn = UIButton(type: .system)
        btn.setTitle(NSLocalizedString("list_upgrade", comment: ""), for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        btn.tintColor        = .pnPrimary
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.addTarget(self, action: #selector(upgradeTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, btn])
        stack.axis      = .horizontal
        stack.alignment = .center
        stack.spacing   = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func upgradeTapped() { onUpgrade?() }

    func refreshColors() {
        backgroundColor = .pnSurface
        // Re-traverse subviews to update label and button colors
        for sub in subviews.flatMap({ $0.subviews }) {
            if let lbl = sub as? UILabel  { lbl.textColor = .pnSecondary }
            if let btn = sub as? UIButton { btn.tintColor = .pnPrimary }
        }
    }
}

// MARK: - EmptyStateView

private final class EmptyStateView: UIView {

    var onCreateNote: (() -> Void)?

    private let label = UILabel()
    private let btn   = UIButton(type: .system)

    func refreshColors() {
        label.textColor = .pnSecondary
        btn.tintColor   = .pnPrimary
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        let font = UIFont(name: "BradleyHandITCTT-Bold", size: 24) ?? PN.font(24, bold: true)

        label.text      = NSLocalizedString("list_no_notes", comment: "")
        label.font      = font
        label.textColor = .pnSecondary

        btn.setTitle(NSLocalizedString("list_write_first", comment: ""), for: .normal)
        btn.titleLabel?.font = font
        btn.tintColor        = .pnPrimary
        btn.addTarget(self, action: #selector(tap), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, btn])
        stack.axis      = .vertical
        stack.alignment = .center
        stack.spacing   = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func tap() { onCreateNote?() }
}
