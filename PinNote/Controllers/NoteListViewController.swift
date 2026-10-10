import UIKit
import Combine

final class NoteListViewController: UIViewController {

    // MARK: - Subviews

    private let titleLabel   = UILabel()
    private let catView      = CatCompanionView()
    private let masonryLayout = MasonryLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: masonryLayout)
    private let bottomBar    = NoteListBottomBar()
    private let emptyState   = EmptyStateView()
    private let trialBanner  = TrialExpiredBannerView()
    private let headerFadeView = UIView()
    private let headerFadeLayer = CAGradientLayer()

    // MARK: - State

    private var isInEditMode = false
    /// The notes land on the canvas once, when the app opens.
    private var hasPlayedLanding = false
    /// Until the user scrolls, the grid is held at its top, below the header.
    private var hasUserScrolled = false
    private var selectedIDs  = Set<UUID>()
    private var cancellables = Set<AnyCancellable>()

    private var tableTopNoBanner:   NSLayoutConstraint!
    private var tableTopWithBanner: NSLayoutConstraint!

    /// Off-screen tile used to measure heights for the masonry layout.
    private let sizingCell = NoteCell(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    private var tileHeightCache: [String: CGFloat] = [:]

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
            self, selector: #selector(fontChanged),
            name: .pnFontChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshTrialBanner),
            name: .pnPurchaseStateChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(showStorageError),
            name: .pnStorageError, object: nil
        )
        for name in [Notification.Name.pnCatCompanionChanged, .pnPurchaseStateChanged] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(refreshCatCompanion), name: name, object: nil
            )
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasPlayedLanding {
            hasPlayedLanding = true
            playLanding()
        }
        wakeCatSoon()
    }

    // MARK: - Landing

    /// Everything that fades in, in place, as the notes land.
    private var landingChrome: [UIView] { [titleLabel, catView, bottomBar, trialBanner, emptyState] }

    /// The canvas starts completely empty: title, cat, controls and the visible
    /// notes are all hidden until the landing.
    private func prepareLanding() {
        view.layoutIfNeeded()
        scrollGridToTop()
        landingChrome.forEach { $0.alpha = 0 }
        collectionView.layoutIfNeeded()
        collectionView.visibleCells.compactMap { $0 as? NoteCell }.forEach { $0.prepareToLand() }
    }

    /// Notes drop onto the canvas one after another, top to bottom, while the title,
    /// cat and controls fade in where they are.
    private func playLanding() {
        UIView.animate(withDuration: 1.0, delay: 0.4, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.landingChrome.forEach { $0.alpha = 1 }
        }
        let cells = collectionView.indexPathsForVisibleItems
            .sorted { lhs, rhs in
                let a = collectionView.layoutAttributesForItem(at: lhs)?.frame ?? .zero
                let b = collectionView.layoutAttributesForItem(at: rhs)?.frame ?? .zero
                return a.minY != b.minY ? a.minY < b.minY : a.minX < b.minX
            }
            .compactMap { collectionView.cellForItem(at: $0) as? NoteCell }
        for (index, cell) in cells.enumerated() {
            // A moment of empty canvas first, then one note after another.
            cell.land(after: 0.4 + Double(index) * 0.14)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Sync displayedIDs so applyDiff has a correct baseline after returning from detail
        displayedIDs = NoteStore.shared.notes.map { $0.id }
        collectionView.reloadData()
        refreshEmptyState()
        if !hasPlayedLanding { prepareLanding() }
    }

    // MARK: - Build layout

    private func buildLayout() {
        let readableGuide = view.pnAddReadableContentGuide()

        // Title — negative stroke width fills the stroke, making the glyphs heavier
        let titleFont = UIFont(name: "BradleyHandITCTT-Bold", size: 46) ?? PN.font(46, bold: true)
        titleLabel.attributedText = NSAttributedString(string: "PinnedNote", attributes: [
            .font:        titleFont,
            .foregroundColor: UIColor.pnPrimary,
            .strokeColor: UIColor.pnPrimary,
            .strokeWidth: -3.5,
        ])
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // The cat sits at the right of the title, on the title's baseline.
        catView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(catView)
        NSLayoutConstraint.activate([
            catView.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor, constant: -PN.padding),
            catView.bottomAnchor.constraint(equalTo: titleLabel.lastBaselineAnchor, constant: 8),
            catView.heightAnchor.constraint(equalToConstant: 48),
            catView.widthAnchor.constraint(equalToConstant: 72),
            catView.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 4),
        ])
        catView.isHidden = !CatCompanion.isActive

        // Two-column grid of note tiles
        masonryLayout.delegate                      = self
        collectionView.backgroundColor              = .pnBackground
        collectionView.register(NoteCell.self, forCellWithReuseIdentifier: NoteCell.reuseID)
        collectionView.dataSource                   = self
        collectionView.delegate                     = self
        collectionView.alwaysBounceVertical         = true
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.contentInset                 = UIEdgeInsets(top: 38, left: 0, bottom: 80, right: 0)
        collectionView.scrollIndicatorInsets        = UIEdgeInsets(top: 38, left: 0, bottom: 80, right: 0)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleTileLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        collectionView.addGestureRecognizer(longPress)

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

        tableTopNoBanner   = collectionView.topAnchor.constraint(equalTo: headerFadeView.topAnchor)
        tableTopWithBanner = collectionView.topAnchor.constraint(equalTo: trialBanner.bottomAnchor, constant: 4)
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

            collectionView.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyState.centerXAnchor.constraint(equalTo: readableGuide.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
        ])

        refreshHeaderFade()
        refreshTrialBanner()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        headerFadeLayer.frame = headerFadeView.bounds
        if !hasUserScrolled { scrollGridToTop() }
    }

    /// The top of the grid just below the header, clear of its fade. The insets
    /// settle only after the first layout passes, so this runs again until the user
    /// takes over by scrolling.
    private func scrollGridToTop() {
        let top = -collectionView.adjustedContentInset.top
        guard collectionView.contentOffset.y != top else { return }
        collectionView.contentOffset = CGPoint(x: collectionView.contentOffset.x, y: top)
    }

    // MARK: - Bottom bar wiring

    private func wireBottomBar() {
        bottomBar.onNewNote  = { [weak self] in self?.openNewNote() }
        bottomBar.onEdit     = { [weak self] in self?.setListEditMode(true) }
        bottomBar.onSettings = { [weak self] in self?.openSettings() }
        bottomBar.onDelete   = { [weak self] in self?.deleteSelected() }
        bottomBar.onCancel   = { [weak self] in self?.setListEditMode(false) }
        bottomBar.onSelectAll = { [weak self] in self?.toggleSelectAll() }
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
        selectedIDs = selectedIDs.intersection(Set(newIDs))
        refreshSelectionControls()

        guard oldIDs != newIDs else {
            // Same order/count — just reload visible cells to refresh content (e.g. date)
            collectionView.visibleCells.compactMap { $0 as? NoteCell }.forEach { cell in
                guard let ip = collectionView.indexPath(for: cell),
                      ip.item < newNotes.count else { return }
                let note = newNotes[ip.item]
                cell.configure(
                    with: note,
                    editing: isInEditMode,
                    selected: selectedIDs.contains(note.id)
                )
            }
            // Pinning or a schedule can change a tile's height.
            masonryLayout.invalidateLayout()
            refreshEmptyState()
            refreshSelectionControls()
            return
        }

        if let deletedID = pendingAnimatedDeletionID,
           oldIDs.count == newIDs.count + 1,
           !newIDs.contains(deletedID),
           let deletedRow = oldIDs.firstIndex(of: deletedID) {
            pendingAnimatedDeletionID = nil
            displayedIDs = newIDs
            let indexPath = IndexPath(item: deletedRow, section: 0)
            collectionView.performBatchUpdates {
                self.collectionView.deleteItems(at: [indexPath])
            } completion: { _ in
                self.refreshEmptyState()
                self.refreshSelectionControls()
            }
            return
        }

        pendingAnimatedDeletionID = nil
        displayedIDs = newIDs

        collectionView.reloadData()
        refreshEmptyState()
        refreshSelectionControls()
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
        collectionView.isHidden  = empty
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
            syncVisibleSelectionCells(animated: false)
            refreshSelectionControls()
            return
        }

        isInEditMode = editing
        selectedIDs.removeAll()
        // Edit mode swaps status icons for selection rings, which can change tile heights.
        collectionView.reloadData()
        masonryLayout.invalidateLayout()
        collectionView.layoutIfNeeded()
        bottomBar.setEditMode(isInEditMode)
        refreshSelectionControls()
    }

    private func syncVisibleSelectionCells(animated: Bool) {
        let notes = NoteStore.shared.notes
        collectionView.indexPathsForVisibleItems.forEach { indexPath in
            guard indexPath.item < notes.count,
                  let cell = collectionView.cellForItem(at: indexPath) as? NoteCell else { return }
            cell.applySelected(selectedIDs.contains(notes[indexPath.item].id), animated: animated)
        }
    }

    private func toggleSelectAll() {
        guard isInEditMode else { return }

        let allIDs = Set(NoteStore.shared.notes.map(\.id))
        if !allIDs.isEmpty, selectedIDs.count == allIDs.count {
            selectedIDs.removeAll()
        } else {
            selectedIDs = allIDs
        }

        syncVisibleSelectionCells(animated: false)
        refreshSelectionControls()
    }

    private func refreshSelectionControls() {
        let noteCount = NoteStore.shared.notes.count
        bottomBar.setDeleteEnabled(!selectedIDs.isEmpty)
        bottomBar.setAllSelected(noteCount > 0 && selectedIDs.count == noteCount)
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

    // MARK: - Cat companion

    @objc private func refreshCatCompanion() {
        let active = CatCompanion.isActive
        guard catView.isHidden == active else { return }
        catView.isHidden = !active
        if active {
            catView.fallAsleep(animated: false)
            wakeCatSoon()
        }
    }

    /// The cat sleeps on for a few seconds after the list comes into view, then wakes.
    private func wakeCatSoon() {
        guard CatCompanion.isActive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self, self.view.window != nil,
                  UIApplication.shared.applicationState == .active else { return }
            self.catView.wakeUp()
        }
    }

    @objc private func appBecameActive() {
        wakeCatSoon()
    }

    @objc private func appWillResignActive() {
        catView.fallAsleep()
    }

    // MARK: - Tile menu

    /// Long press on a tile: lift it and show the pin / delete menu under it.
    @objc private func handleTileLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let indexPath = collectionView.indexPathForItem(at: gesture.location(in: collectionView)) else { return }
        showTileMenu(at: indexPath)
    }

    private func showTileMenu(at indexPath: IndexPath) {
        guard !isInEditMode,
              presentedViewController == nil,
              indexPath.item < NoteStore.shared.notes.count,
              let cell = collectionView.cellForItem(at: indexPath) else { return }

        let noteID = NoteStore.shared.notes[indexPath.item].id
        let isPinned = NoteStore.shared.notes[indexPath.item].isPinned

        // Capture the tile at rest, not mid press.
        cell.isHighlighted = false
        cell.layoutIfNeeded()
        guard let snapshot = cell.snapshotView(afterScreenUpdates: true) else { return }
        let sourceFrame = cell.convert(cell.bounds, to: nil)

        let menu = NoteActionMenuController(snapshot: snapshot, sourceFrame: sourceFrame, isPinned: isPinned)
        menu.onDismiss = { [weak self] in
            self?.collectionView.visibleCells.forEach { $0.alpha = 1 }
        }
        menu.onTogglePin = { [weak self] in
            guard let self,
                  let note = NoteStore.shared.notes.first(where: { $0.id == noteID }),
                  self.canTogglePinFromList(note) else { return }
            Task { @MainActor in await self.commitPinToggleFromList(note) }
        }
        menu.onDelete = { [weak self] in
            guard let self,
                  let note = NoteStore.shared.notes.first(where: { $0.id == noteID }) else { return }
            if note.isPinned { LiveActivityManager.shared.stop() }
            ScheduledPinManager.shared.removeNotificationBackup(noteID: note.id)
            self.pendingAnimatedDeletionID = note.id
            NoteStore.shared.delete(id: note.id)
        }

        // The snapshot stands in for the tile while the menu is open.
        cell.alpha = 0
        present(menu, animated: false)
    }

    @objc private func refreshTrialBanner() {
        let pm = PurchaseManager.shared
        let showBanner = !pm.isPro && !pm.isTrialActive
        guard trialBanner.isHidden == showBanner else { return }  // no change
        trialBanner.isHidden        = !showBanner
        headerFadeView.isHidden = showBanner
        let topInset: CGFloat = showBanner ? 12 : 38
        collectionView.contentInset.top = topInset
        collectionView.scrollIndicatorInsets = UIEdgeInsets(top: topInset, left: 0, bottom: 80, right: 0)
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

    @objc private func fontChanged() {
        tileHeightCache.removeAll()
        collectionView.reloadData()
        masonryLayout.invalidateLayout()
    }

    @objc private func applyTheme() {
        view.backgroundColor      = .pnBackground
        collectionView.backgroundColor = .pnBackground
        refreshHeaderFade()
        bottomBar.refreshColors()
        trialBanner.refreshColors()
        emptyState.refreshColors()
        catView.applyColors()
        let titleFont = UIFont(name: "BradleyHandITCTT-Bold", size: 46) ?? PN.font(46, bold: true)
        titleLabel.attributedText = NSAttributedString(string: "PinnedNote", attributes: [
            .font:        titleFont,
            .foregroundColor: UIColor.pnPrimary,
            .strokeColor: UIColor.pnPrimary,
            .strokeWidth: -3.5,
        ])
        tileHeightCache.removeAll()
        collectionView.reloadData()
        masonryLayout.invalidateLayout()
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

// MARK: - UICollectionViewDataSource

extension NoteListViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        NoteStore.shared.notes.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NoteCell.reuseID, for: indexPath) as! NoteCell
        guard indexPath.item < NoteStore.shared.notes.count else { return cell }
        let note = NoteStore.shared.notes[indexPath.item]
        cell.configure(with: note, editing: isInEditMode, selected: selectedIDs.contains(note.id))
        return cell
    }
}

// MARK: - MasonryLayoutDelegate

extension NoteListViewController: MasonryLayoutDelegate {

    func masonryLayout(_ layout: MasonryLayout, heightForItemAt indexPath: IndexPath, itemWidth: CGFloat) -> CGFloat {
        let notes = NoteStore.shared.notes
        guard indexPath.item < notes.count else { return 0 }
        let note = notes[indexPath.item]

        // Anything that changes the tile's content or layout is part of the key.
        let scheduled = (note.scheduledPinDate ?? .distantPast) > Date()
        let key = "\(note.id)|\(note.modifiedAt.timeIntervalSince1970)|\(note.title.hashValue)|\(note.content.hashValue)|\(note.isPinned)|\(scheduled)|\(isInEditMode)|\(itemWidth)"
        if let cached = tileHeightCache[key] { return cached }

        sizingCell.configure(with: note, editing: isInEditMode, selected: false)
        let height = sizingCell.contentView.systemLayoutSizeFitting(
            CGSize(width: itemWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        tileHeightCache[key] = height
        return height
    }
}

// MARK: - UICollectionViewDelegate

extension NoteListViewController: UICollectionViewDelegate {

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        hasUserScrolled = true
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard indexPath.item < NoteStore.shared.notes.count else { return }
        let note = NoteStore.shared.notes[indexPath.item]

        if isInEditMode {
            // Toggle selection manually
            if selectedIDs.contains(note.id) {
                selectedIDs.remove(note.id)
            } else {
                selectedIDs.insert(note.id)
            }
            if let cell = collectionView.cellForItem(at: indexPath) as? NoteCell {
                cell.applySelected(selectedIDs.contains(note.id))
            }
            refreshSelectionControls()
        } else {
            let vc = NoteDetailViewController(note: note)
            navigationController?.pushViewController(vc, animated: true)
        }
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
