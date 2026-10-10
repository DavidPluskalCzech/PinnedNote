import UIKit
import Combine

/// Deleted notes, shown as the same paper tiles as the note list, each with a live
/// countdown to when it's removed for good. A note can be restored or deleted right
/// away; the whole trash can be emptied.
final class TrashViewController: UIViewController {

    private let infoLabel = UILabel()
    private let masonryLayout = MasonryLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: masonryLayout)
    private let emptyLabel = UILabel()
    /// Floating "Delete All" control at the bottom, styled like the app's toolbars.
    private let deleteAllButton = UIButton(type: .custom)
    /// Off-screen tile used to measure heights for the layout.
    private let sizingCell = NoteCell(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
    private var cancellables = Set<AnyCancellable>()
    private var countdownTimer: Timer?

    private var items: [TrashedNote] { TrashStore.shared.items }

    private static let countdownFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 2
        return formatter
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("trash_title", comment: "")
        view.backgroundColor = .pnBackground

        // How the trash works, kept above the notes.
        infoLabel.text = NSLocalizedString("settings_trash_footer", comment: "")
        infoLabel.font = .systemFont(ofSize: 13)
        infoLabel.textColor = .pnSecondary
        infoLabel.numberOfLines = 0
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoLabel)

        masonryLayout.delegate = self
        collectionView.backgroundColor = .pnBackground
        collectionView.register(NoteCell.self, forCellWithReuseIdentifier: NoteCell.reuseID)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        // Room at the bottom so the last notes can scroll clear of the Delete All button.
        collectionView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 96, right: 0)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        emptyLabel.text = NSLocalizedString("trash_empty", comment: "")
        emptyLabel.textColor = .pnSecondary
        emptyLabel.font = .systemFont(ofSize: 17)
        emptyLabel.textAlignment = .center
        collectionView.backgroundView = emptyLabel

        let readable = view.pnAddReadableContentGuide()
        NSLayoutConstraint.activate([
            infoLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            infoLabel.leadingAnchor.constraint(equalTo: readable.leadingAnchor, constant: 20),
            infoLabel.trailingAnchor.constraint(equalTo: readable.trailingAnchor, constant: -20),

            collectionView.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: readable.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: readable.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        setUpDeleteAllButton()

        TrashStore.shared.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        TrashStore.shared.purgeExpired()
        reload()
        // The countdowns tick while the trash is on screen.
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Updates

    private func reload() {
        collectionView.reloadData()
        masonryLayout.invalidateLayout()
        emptyLabel.isHidden = !items.isEmpty
        deleteAllButton.isHidden = items.isEmpty
    }

    private func tick() {
        // Notes whose time is up leave; the rest just update their countdown.
        TrashStore.shared.purgeExpired()
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard indexPath.item < items.count,
                  let cell = collectionView.cellForItem(at: indexPath) as? NoteCell else { continue }
            cell.setFootnote(remainingTime(for: items[indexPath.item]), symbol: "hourglass")
        }
    }

    /// Time left before the note is deleted for good, e.g. "29 d 18 h".
    private func remainingTime(for item: TrashedNote) -> String {
        Self.countdownFormatter.string(from: max(0, item.expiresAt.timeIntervalSinceNow)) ?? ""
    }

    private func countdownText(for item: TrashedNote) -> String {
        String(format: NSLocalizedString("trash_expires_in", comment: ""), remainingTime(for: item))
    }

    // MARK: - Actions

    private func restore(_ item: TrashedNote) {
        NoteStore.shared.restoreFromTrash(id: item.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func confirmDeleteForever(_ item: TrashedNote) {
        presentPNAlert(
            title: NSLocalizedString("trash_delete_confirm_title", comment: ""),
            message: NSLocalizedString("trash_cannot_undo", comment: ""),
            actions: [
                PNAlertAction(title: NSLocalizedString("detail_cancel", comment: ""), style: .cancel),
                PNAlertAction(title: NSLocalizedString("trash_delete_forever", comment: ""), style: .destructive) {
                    TrashStore.shared.deleteForever(id: item.id)
                },
            ]
        )
    }

    @objc private func confirmEmpty() {
        guard !items.isEmpty else { return }
        presentPNAlert(
            title: NSLocalizedString("trash_empty_confirm_title", comment: ""),
            message: NSLocalizedString("trash_cannot_undo", comment: ""),
            actions: [
                PNAlertAction(title: NSLocalizedString("detail_cancel", comment: ""), style: .cancel),
                PNAlertAction(title: NSLocalizedString("trash_delete_all", comment: ""), style: .destructive) {
                    TrashStore.shared.empty()
                },
            ]
        )
    }

    private func setUpDeleteAllButton() {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "trash",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        config.imagePadding = 8
        config.baseForegroundColor = .pnDestructive
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 24)
        var title = AttributedString(NSLocalizedString("trash_delete_all", comment: ""))
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        config.attributedTitle = title
        deleteAllButton.configuration = config
        deleteAllButton.configurationUpdateHandler = { button in
            // Pressed: sinks a little, like the app's floating toolbars.
            UIView.animate(withDuration: 0.12) {
                button.transform = button.isHighlighted
                    ? CGAffineTransform(translationX: 0, y: 1.5).scaledBy(x: 0.985, y: 0.965)
                    : .identity
            }
        }

        deleteAllButton.backgroundColor = .pnFloatingControlBackground
        deleteAllButton.layer.cornerRadius = PN.floatingControlCornerRadius
        deleteAllButton.layer.cornerCurve = .continuous
        deleteAllButton.layer.shadowColor = UIColor.black.cgColor
        deleteAllButton.layer.shadowOpacity = PN.floatingControlShadowOpacity
        deleteAllButton.layer.shadowRadius = PN.floatingControlShadowRadius
        deleteAllButton.layer.shadowOffset = PN.floatingControlShadowOffset
        deleteAllButton.addTarget(self, action: #selector(confirmEmpty), for: .primaryActionTriggered)
        deleteAllButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(deleteAllButton)
        NSLayoutConstraint.activate([
            deleteAllButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            deleteAllButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            deleteAllButton.heightAnchor.constraint(equalToConstant: PN.floatingControlHeight),
        ])
    }

    /// Tapping a note offers both choices.
    private func showActions(for item: TrashedNote) {
        presentPNAlert(
            title: item.note.displayTitle,
            message: countdownText(for: item),
            actions: [
                PNAlertAction(title: NSLocalizedString("trash_restore", comment: "")) { [weak self] in
                    self?.restore(item)
                },
                PNAlertAction(title: NSLocalizedString("trash_delete_forever", comment: ""), style: .destructive) { [weak self] in
                    self?.confirmDeleteForever(item)
                },
                PNAlertAction(title: NSLocalizedString("detail_cancel", comment: ""), style: .cancel),
            ]
        )
    }
}

// MARK: - Grid

extension TrashViewController: UICollectionViewDataSource, UICollectionViewDelegate, MasonryLayoutDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: NoteCell.reuseID, for: indexPath) as! NoteCell
        guard indexPath.item < items.count else { return cell }
        let item = items[indexPath.item]
        cell.configure(with: item.note, editing: false, selected: false, footnote: remainingTime(for: item), footnoteSymbol: "hourglass")
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard indexPath.item < items.count else { return }
        showActions(for: items[indexPath.item])
    }

    func masonryLayout(_ layout: MasonryLayout, heightForItemAt indexPath: IndexPath, itemWidth: CGFloat) -> CGFloat {
        guard indexPath.item < items.count else { return 0 }
        let item = items[indexPath.item]
        sizingCell.configure(with: item.note, editing: false, selected: false, footnote: remainingTime(for: item), footnoteSymbol: "hourglass")
        return sizingCell.contentView.systemLayoutSizeFitting(
            CGSize(width: itemWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }
}
