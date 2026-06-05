import UIKit
import StoreKit
import MessageUI

final class SettingsViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .pnBackground
        setupNavBar()
        setupTableView()

        NotificationCenter.default.addObserver(
            self, selector: #selector(purchaseStateChanged),
            name: .pnPurchaseStateChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeUpdated),
            name: .pnThemeChanged, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(purchaseErrorChanged),
            name: .pnPurchaseError, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(restoreStateChanged),
            name: .pnRestoreStateChanged, object: nil
        )
    }

    // MARK: - Setup

    private func setupNavBar() {
        title = NSLocalizedString("settings_title", comment: "")
        navigationController?.navigationBar.tintColor = .pnPrimary
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
    }

    private func setupTableView() {
        tableView.dataSource          = self
        tableView.delegate            = self
        tableView.backgroundColor     = .pnBackground
        tableView.estimatedRowHeight  = 160
        tableView.contentInset.bottom = 40
        tableView.verticalScrollIndicatorInsets.bottom = 40
        tableView.register(UpgradeCardsCell.self,  forCellReuseIdentifier: UpgradeCardsCell.reuseID)
        tableView.register(ThemePickerCell.self,   forCellReuseIdentifier: ThemePickerCell.reuseID)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func close() { dismiss(animated: true) }

    @objc private func purchaseStateChanged() {
        DispatchQueue.main.async { self.tableView.reloadData() }
    }

    @objc private func themeUpdated() {
        view.backgroundColor      = .pnBackground
        tableView.backgroundColor = .pnBackground
        setupNavBar()
        tableView.reloadData()
    }

    @objc private func restoreStateChanged() {
        DispatchQueue.main.async {
            // Reload only the Restore row to update the spinner
            guard let section = self.visibleSections().firstIndex(of: .support) else { return }
            self.tableView.reloadRows(at: [IndexPath(row: 0, section: section)], with: .none)
        }
    }

    @objc private func purchaseErrorChanged() {
        guard let message = PurchaseManager.shared.purchaseError else { return }
        DispatchQueue.main.async {
            self.presentPNAlert(
                title: NSLocalizedString("settings_purchase_failed", comment: ""),
                message: message,
                actions: [
                    PNAlertAction(title: NSLocalizedString("settings_ok", comment: ""))
                ]
            )
        }
    }

    @objc private func iCloudToggled(_ sender: UISwitch) {
        let didChange = NoteStore.shared.setICloudEnabled(sender.isOn)
        if !didChange {
            sender.setOn(NoteStore.shared.isICloudEnabled, animated: true)
        }
    }
}

// MARK: - Section / Row model

private extension SettingsViewController {

    var pm: PurchaseManager { PurchaseManager.shared }

    enum Section: Int, CaseIterable {
        case sync, theme, status, upgrade, support
    }

    func visibleSections() -> [Section] {
        pm.isPro
            ? [.sync, .theme, .status, .support]
            : [.sync, .theme, .status, .upgrade, .support]
    }

    func rowsInSupport() -> Int { 3 }  // restore + feedback + version

    static let feedbackEmail   = "davethepcguy@proton.me"
    static let privacyPolicyURL = "https://github.com/DavidPluskalCzech/PinnedNote/blob/main/privacy-policy.md"
    static let termsOfUseURL    = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
}

// MARK: - UITableViewDataSource / Delegate

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        visibleSections().count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch visibleSections()[section] {
        case .upgrade: return 1
        case .support: return rowsInSupport()
        default:       return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch visibleSections()[section] {
        case .sync:    return NSLocalizedString("settings_sync_header",       comment: "")
        case .theme:   return NSLocalizedString("settings_appearance_header", comment: "")
        case .status:  return NSLocalizedString("settings_pro_header",        comment: "")
        case .upgrade: return nil
        case .support: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        nil  // all footers handled via viewForFooterInSection
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let s = visibleSections()[section]
        if s == .status { return UIView() }   // empty — height controlled below
        guard (s == .upgrade && !pm.isPro) || (s == .support && pm.isPro) else { return nil }
        let footer = UpgradeFooterView()
        footer.onPrivacy = { [weak self] in self?.openURL(SettingsViewController.privacyPolicyURL) }
        footer.onTerms   = { [weak self] in self?.openURL(SettingsViewController.termsOfUseURL) }
        return footer
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        let s = visibleSections()[section]
        if s == .status  { return CGFloat.leastNormalMagnitude }
        if s == .upgrade || (s == .support && pm.isPro) { return UITableView.automaticDimension }
        return CGFloat.leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        visibleSections()[section] == .upgrade ? CGFloat.leastNormalMagnitude : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard visibleSections()[section] == .upgrade else { return nil }
        return UIView()
    }

    func tableView(_ tableView: UITableView,
                   heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch visibleSections()[indexPath.section] {
        case .status where !pm.isPro: return 72
        case .upgrade:                return UITableView.automaticDimension
        case .theme:                  return 90
        default:                      return UITableView.automaticDimension
        }
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        switch visibleSections()[indexPath.section] {

        // ── Theme ────────────────────────────────────────────────────
        case .theme:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: ThemePickerCell.reuseID, for: indexPath
            ) as! ThemePickerCell
            cell.onSelect = { theme in ThemeManager.shared.current = theme }
            return cell

        // ── Pro status ───────────────────────────────────────────────
        case .status:
            if pm.isPro {
                let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
                cell.backgroundColor  = .pnSurface
                cell.selectionStyle   = .none
                cell.textLabel?.text  = NSLocalizedString("settings_pro_active", comment: "")
                cell.imageView?.image = UIImage(systemName: "checkmark.seal.fill")
                cell.imageView?.tintColor = .pnPrimary
                return cell
            } else {
                return trialCell(for: tableView)
            }

        // ── Upgrade ──────────────────────────────────────────────────
        case .upgrade:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: UpgradeCardsCell.reuseID, for: indexPath
            ) as! UpgradeCardsCell
            cell.configurePrices(
                monthly: pm.monthlyDisplayPrice,
                lifetime: pm.lifetimeDisplayPrice
            )
            cell.onMonthly  = { [weak self] in
                guard let self else { return }
                Task { await self.pm.purchase(productID: self.pm.monthlyProductID) }
            }
            cell.onLifetime = { [weak self] in
                guard let self else { return }
                Task { await self.pm.purchase(productID: self.pm.lifetimeProductID) }
            }
            return cell

        // ── Sync ─────────────────────────────────────────────────────
        case .sync:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.backgroundColor = .pnSurface
            cell.textLabel?.text = NSLocalizedString("settings_icloud_sync", comment: "")
            cell.selectionStyle  = .none
            let toggle           = UISwitch()
            toggle.isOn          = NoteStore.shared.isICloudEnabled
            toggle.onTintColor   = .pnPrimary
            toggle.addTarget(self, action: #selector(iCloudToggled(_:)), for: .valueChanged)
            cell.accessoryView   = toggle
            return cell

        // ── Support ──────────────────────────────────────────────────
        case .support:
            let style: UITableViewCell.CellStyle = indexPath.row == 1 ? .subtitle : .default
            let cell = UITableViewCell(style: style, reuseIdentifier: nil)
            cell.backgroundColor = .pnSurface
            if indexPath.row == 0 {
                cell.textLabel?.text = NSLocalizedString("settings_restore", comment: "")
                if pm.isRestoring {
                    let spinner = UIActivityIndicatorView(style: .medium)
                    spinner.startAnimating()
                    cell.accessoryView  = spinner
                    cell.selectionStyle = .none
                } else {
                    cell.accessoryType  = .disclosureIndicator
                }
            } else if indexPath.row == 1 {
                cell.textLabel?.text          = NSLocalizedString("settings_feedback",        comment: "")
                cell.detailTextLabel?.text    = NSLocalizedString("settings_feedback_detail", comment: "")
                cell.detailTextLabel?.numberOfLines = 0
                cell.accessoryType            = .disclosureIndicator
            } else {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                cell.textLabel?.text      = String(format: NSLocalizedString("settings_version", comment: ""), version)
                cell.textLabel?.textColor = .pnSecondary
                cell.selectionStyle       = .none
            }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard visibleSections()[indexPath.section] == .support else { return }
        switch indexPath.row {
        case 0: Task { await pm.restore() }
        case 1: openFeedback()
        default: break
        }
    }

    func tableView(_ tableView: UITableView,
                   shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        let s = visibleSections()[indexPath.section]
        return s != .upgrade && s != .theme
    }
}

// MARK: - Trial progress cell

private extension SettingsViewController {

    func trialCell(for tableView: UITableView) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .pnSurface
        cell.selectionStyle  = .none

        let daysLeft = pm.trialDaysRemaining
        let titleLabel = UILabel()
        titleLabel.font      = UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .pnPrimary
        titleLabel.text      = daysLeft > 0
            ? String(format: NSLocalizedString(
                daysLeft == 1 ? "settings_days_remaining_singular" : "settings_days_remaining_plural",
                comment: ""), daysLeft)
            : NSLocalizedString("settings_trial_ended", comment: "")

        let progress = UIProgressView(progressViewStyle: .default)
        progress.progressTintColor  = .pnPrimary
        progress.trackTintColor     = UIColor.pnPrimary.withAlphaComponent(0.15)
        progress.layer.cornerRadius = 2
        progress.clipsToBounds      = true
        progress.progress           = Float(1.0 - pm.trialProgress)

        let stack = UIStackView(arrangedSubviews: [titleLabel, progress])
        stack.axis    = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            progress.heightAnchor.constraint(equalToConstant: 5),
        ])
        return cell
    }

    // MARK: - URL opener

    func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Feedback

    func openFeedback() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let subject  = "PinnedNote Feedback (v\(version))"
        let email    = SettingsViewController.feedbackEmail

        if MFMailComposeViewController.canSendMail() {
            let vc = MFMailComposeViewController()
            vc.mailComposeDelegate = self
            vc.setToRecipients([email])
            vc.setSubject(subject)
            present(vc, animated: true)
        } else {
            // Mail app not configured — fallback: mailto link, or show email to copy
            if let url = URL(string: "mailto:\(email)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                presentPNAlert(
                    title:   NSLocalizedString("settings_feedback_alert_title",   comment: ""),
                    message: String(format: NSLocalizedString("settings_feedback_alert_message", comment: ""), email),
                    actions: [
                        PNAlertAction(title: NSLocalizedString("settings_copy_email", comment: "")) {
                            UIPasteboard.general.string = email
                        },
                        PNAlertAction(title: NSLocalizedString("settings_ok", comment: ""), style: .cancel)
                    ]
                )
            }
        }
    }
}

// MARK: - MFMailComposeViewControllerDelegate

extension SettingsViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController,
                               didFinishWith result: MFMailComposeResult,
                               error: Error?) {
        controller.dismiss(animated: true)
    }
}

// MARK: - UpgradeCardsCell

private final class UpgradeCardsCell: UITableViewCell {

    static let reuseID = "UpgradeCardsCell"

    var onMonthly:  (() -> Void)?
    var onLifetime: (() -> Void)?

    private let monthlyCard  = UpgradeCardView()
    private let lifetimeCard = UpgradeCardView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor      = .clear
        contentView.backgroundColor = .clear
        selectionStyle       = .none

        configurePrices(
            monthly: NSLocalizedString("settings_price_loading", comment: ""),
            lifetime: NSLocalizedString("settings_price_loading", comment: "")
        )

        monthlyCard.onTap  = { [weak self] in self?.onMonthly?() }
        lifetimeCard.onTap = { [weak self] in self?.onLifetime?() }

        let featuresLabel = UILabel()
        featuresLabel.text          = NSLocalizedString("settings_pro_features", comment: "")
        featuresLabel.font          = UIFont.systemFont(ofSize: 13, weight: .regular)
        featuresLabel.textColor     = .pnSecondary
        featuresLabel.numberOfLines = 0
        featuresLabel.textAlignment = .center

        let cardsStack = UIStackView(arrangedSubviews: [monthlyCard, lifetimeCard])
        cardsStack.axis         = .horizontal
        cardsStack.distribution = .fillEqually
        cardsStack.spacing      = 12

        let stack = UIStackView(arrangedSubviews: [featuresLabel, cardsStack])
        stack.axis    = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            cardsStack.heightAnchor.constraint(equalToConstant: 110),
        ])
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        monthlyCard.refreshColors()
        lifetimeCard.refreshColors()
    }

    func configurePrices(monthly: String, lifetime: String) {
        monthlyCard.configure(
            title:    NSLocalizedString("settings_monthly_title",    comment: ""),
            price:    monthly,
            subtitle: NSLocalizedString("settings_monthly_subtitle", comment: "")
        )
        lifetimeCard.configure(
            title:    NSLocalizedString("settings_lifetime_title",    comment: ""),
            price:    lifetime,
            subtitle: NSLocalizedString("settings_lifetime_subtitle", comment: "")
        )
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - UpgradeCardView

private final class UpgradeCardView: UIView {

    var onTap: (() -> Void)?

    private let titleLabel    = UILabel()
    private let priceLabel    = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor    = .pnSurface
        layer.cornerRadius = 12
        layer.masksToBounds = true

        titleLabel.font      = UIFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .pnSecondary

        priceLabel.font      = UIFont.systemFont(ofSize: 26, weight: .semibold)
        priceLabel.textColor = .pnPrimary
        priceLabel.adjustsFontSizeToFitWidth = true

        subtitleLabel.font      = UIFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .pnSecondary

        let stack = UIStackView(arrangedSubviews: [titleLabel, priceLabel, subtitleLabel])
        stack.axis      = .vertical
        stack.spacing   = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, price: String, subtitle: String) {
        titleLabel.text    = title
        priceLabel.text    = price
        subtitleLabel.text = subtitle
    }

    func refreshColors() {
        backgroundColor         = .pnSurface
        titleLabel.textColor    = .pnSecondary
        priceLabel.textColor    = .pnPrimary
        subtitleLabel.textColor = .pnSecondary
    }

    @objc private func tapped() {
        UIView.animate(withDuration: 0.1, animations: {
            self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }, completion: { _ in
            UIView.animate(withDuration: 0.1) { self.transform = .identity }
            self.onTap?()
        })
    }
}

// MARK: - UpgradeFooterView

private final class UpgradeFooterView: UIView {

    var onPrivacy: (() -> Void)?
    var onTerms:   (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        let bodyLabel = UILabel()
        bodyLabel.text          = NSLocalizedString("settings_upgrade_footer", comment: "")
        bodyLabel.font          = UIFont.systemFont(ofSize: 12, weight: .regular)
        bodyLabel.textColor     = .secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.textAlignment = .center

        let privacyBtn = UIButton(type: .system)
        privacyBtn.setTitle(NSLocalizedString("settings_privacy_policy", comment: ""), for: .normal)
        privacyBtn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        privacyBtn.tintColor        = .secondaryLabel
        privacyBtn.addTarget(self, action: #selector(privacyTapped), for: .touchUpInside)

        let termsBtn = UIButton(type: .system)
        termsBtn.setTitle(NSLocalizedString("settings_terms_of_use", comment: ""), for: .normal)
        termsBtn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        termsBtn.tintColor        = .secondaryLabel
        termsBtn.addTarget(self, action: #selector(termsTapped), for: .touchUpInside)

        let linkStack = UIStackView(arrangedSubviews: [privacyBtn, termsBtn])
        linkStack.axis      = .horizontal
        linkStack.spacing   = 16
        linkStack.alignment = .center

        let stack = UIStackView(arrangedSubviews: [bodyLabel, linkStack])
        stack.axis      = .vertical
        stack.spacing   = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func privacyTapped() { onPrivacy?() }
    @objc private func termsTapped()   { onTerms?() }
}

// MARK: - ThemePickerCell

private final class ThemePickerCell: UITableViewCell {

    static let reuseID = "ThemePickerCell"

    var onSelect: ((AppTheme) -> Void)?

    private var cards: [ThemeCardView] = []

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor             = .clear
        contentView.backgroundColor = .clear
        selectionStyle              = .none

        let cardViews = AppTheme.allCases.map { theme -> ThemeCardView in
            let card = ThemeCardView()
            card.configure(theme: theme)
            card.onTap = { [weak self] in self?.onSelect?(theme) }
            return card
        }
        self.cards = cardViews

        let stack = UIStackView(arrangedSubviews: cardViews)
        stack.axis         = .horizontal
        stack.distribution = .fillEqually
        stack.spacing      = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Refresh checkmark state each time cell re-renders
        let current = ThemeManager.shared.current
        cards.forEach { $0.setSelected(ThemeManager.shared.current == $0.theme) }
        _ = current  // suppress warning
    }
}

// MARK: - ThemeCardView

private final class ThemeCardView: UIView {

    var onTap: (() -> Void)?
    private(set) var theme: AppTheme = .monochrome

    private let swatch    = UIView()
    private let nameLabel = UILabel()
    private let checkmark = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.cornerRadius  = 12
        layer.masksToBounds = true

        swatch.layer.cornerRadius  = 12
        swatch.layer.masksToBounds = false
        swatch.layer.borderWidth   = 1
        swatch.layer.borderColor   = UIColor.black.withAlphaComponent(0.12).cgColor
        swatch.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font          = UIFont.systemFont(ofSize: 12, weight: .medium)
        nameLabel.textAlignment = .center
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.72
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let cfg = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        checkmark.image       = UIImage(systemName: "checkmark.circle.fill", withConfiguration: cfg)
        checkmark.contentMode = .scaleAspectFit
        checkmark.translatesAutoresizingMaskIntoConstraints = false

        // Swatch + label stacked and centred in the card
        let stack = UIStackView(arrangedSubviews: [swatch, nameLabel])
        stack.axis      = .vertical
        stack.alignment = .center
        stack.spacing   = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        addSubview(checkmark)

        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: 24),
            swatch.heightAnchor.constraint(equalToConstant: 24),

            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),

            checkmark.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            checkmark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            checkmark.widthAnchor.constraint(equalToConstant: 16),
            checkmark.heightAnchor.constraint(equalToConstant: 16),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(theme: AppTheme) {
        self.theme            = theme
        backgroundColor       = theme.backgroundColor
        swatch.backgroundColor = theme.swatchColor
        nameLabel.text        = theme.displayName
        nameLabel.textColor   = theme.primaryColor
        setSelected(ThemeManager.shared.current == theme)
    }

    func setSelected(_ selected: Bool) {
        checkmark.isHidden  = !selected
        checkmark.tintColor = theme.primaryColor
        layer.borderWidth   = selected ? 2 : 0
        layer.borderColor   = theme.primaryColor.cgColor
    }

    @objc private func tapped() {
        UIView.animate(withDuration: 0.1, animations: {
            self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }, completion: { _ in
            UIView.animate(withDuration: 0.1) { self.transform = .identity }
            self.onTap?()
        })
    }
}
