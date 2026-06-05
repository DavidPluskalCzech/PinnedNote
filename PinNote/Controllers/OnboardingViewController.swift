import UIKit

private enum OnboardingPalette {
    static let background = UIColor(red: 0.975, green: 0.972, blue: 0.965, alpha: 1)
    static let primary = UIColor(white: 0.08, alpha: 1)
    static let secondary = UIColor(white: 0.45, alpha: 1)
}

final class OnboardingViewController: UIViewController {

    // MARK: - Page data

    private struct Page {
        let symbol: String?
        let title:  String
        let body:   String
    }

    private let pages: [Page] = [
        Page(symbol: nil,
             title:  "",   // page 0 uses attributedWelcomeTitle — field unused
             body:   NSLocalizedString("ob_capture_thoughts", comment: "")),
        Page(symbol: nil,
             title:  "",   // page 1 uses fully custom layout — fields unused
             body:   ""),
        Page(symbol: nil,
             title:  NSLocalizedString("ob_seven_days_free", comment: ""),
             body:   NSLocalizedString("ob_coffee_body", comment: ""))
    ]

    // MARK: - Shared subviews (pages 0, 2, 3)

    private let iconView     = UIImageView()
    private let titleLabel   = UILabel()
    private let bodyLabel    = UILabel()
    private let pageControl   = UIPageControl()
    private let actionButton  = UIButton(type: .system)
    private let coffeeIconView = UIImageView()  // shown only on page 2
    private var iconCenterYConstraint: NSLayoutConstraint?

    // MARK: - Page 1 custom layout

    private let page1Container = UIView()

    // Three independently animated sections
    private let p1Section1 = UIView()   // header: "Capture your ideas"
    private let p1Section2 = UIView()   // image 1 + pin text
    private let p1Section3 = UIView()   // image 2 + write text

    private let p1HeaderTitle = UILabel()
    private let p1HeaderBody  = UILabel()
    private let p1PinTitle    = UILabel()
    private let p1PinBody     = UILabel()
    private let p1WriteTitle  = UILabel()
    private let p1WriteBody   = UILabel()
    private let p1PinImage    = UIImageView()
    private let p1WriteImage  = UIImageView()

    // MARK: -

    private var currentPage = 0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = OnboardingPalette.background
        setupSharedViews()
        setupPage1Views()
        setupGestures()
        showPage(0, animated: false)
    }

    // MARK: - Layout: shared views

    private func setupSharedViews() {
        let contentGuide = view.pnAddReadableContentGuide(maxWidth: 520)
        let buttonGuide = view.pnAddReadableContentGuide(maxWidth: 420)

        let cfg = UIImage.SymbolConfiguration(pointSize: 60, weight: .ultraLight)
        iconView.image       = UIImage(systemName: "lock.fill", withConfiguration: cfg)
        iconView.tintColor   = OnboardingPalette.primary
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font          = Self.onboardingFont(size: 28)
        titleLabel.textColor     = OnboardingPalette.primary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 3
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        bodyLabel.font          = Self.onboardingFont(size: 16)
        bodyLabel.textColor     = OnboardingPalette.secondary
        bodyLabel.textAlignment = .center
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false

        pageControl.numberOfPages   = pages.count
        pageControl.currentPage     = 0
        pageControl.currentPageIndicatorTintColor = OnboardingPalette.primary
        pageControl.pageIndicatorTintColor        = OnboardingPalette.primary.withAlphaComponent(0.2)
        pageControl.isUserInteractionEnabled      = false
        pageControl.translatesAutoresizingMaskIntoConstraints = false

        actionButton.setTitle(NSLocalizedString("ob_continue", comment: ""), for: .normal)
        actionButton.titleLabel?.font   = Self.onboardingFont(size: 17)
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.backgroundColor    = OnboardingPalette.primary
        actionButton.layer.cornerRadius = 14
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        let cfg2 = UIImage.SymbolConfiguration(pointSize: 52, weight: .thin)
        coffeeIconView.image       = UIImage(systemName: "cup.and.heat.waves.fill", withConfiguration: cfg2)
        coffeeIconView.tintColor   = OnboardingPalette.primary
        coffeeIconView.contentMode = .scaleAspectFit
        coffeeIconView.alpha       = 0
        coffeeIconView.translatesAutoresizingMaskIntoConstraints = false

        [iconView, titleLabel, bodyLabel, coffeeIconView, pageControl, actionButton].forEach { view.addSubview($0) }

        let iconCY = iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -110)
        iconCenterYConstraint = iconCY

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconCY,
            iconView.widthAnchor.constraint(equalToConstant: 72),
            iconView.heightAnchor.constraint(equalToConstant: 72),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 36),
            titleLabel.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor, constant: -32),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            bodyLabel.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor, constant: 40),
            bodyLabel.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor, constant: -40),

            coffeeIconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            coffeeIconView.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 36),
            coffeeIconView.widthAnchor.constraint(equalToConstant: 60),
            coffeeIconView.heightAnchor.constraint(equalToConstant: 60),

            actionButton.leadingAnchor.constraint(equalTo: buttonGuide.leadingAnchor, constant: 24),
            actionButton.trailingAnchor.constraint(equalTo: buttonGuide.trailingAnchor, constant: -24),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            actionButton.heightAnchor.constraint(equalToConstant: 54),

            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -16),
        ])
    }

    // MARK: - Layout: page 1

    private func setupPage1Views() {
        let contentGuide = view.pnAddReadableContentGuide(maxWidth: 560)

        page1Container.backgroundColor = .clear
        page1Container.isHidden = true
        page1Container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(page1Container)

        NSLayoutConstraint.activate([
            page1Container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50),
            page1Container.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor, constant: 28),
            page1Container.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor, constant: -28),
            page1Container.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -16),
        ])

        // Labels — titles
        for lbl in [p1HeaderTitle, p1PinTitle, p1WriteTitle] {
            lbl.font          = Self.onboardingFont(size: 22)
            lbl.textColor     = OnboardingPalette.primary
            lbl.numberOfLines = 2
            lbl.textAlignment = .center
        }

        // Labels — bodies
        for lbl in [p1HeaderBody, p1PinBody, p1WriteBody] {
            lbl.font          = Self.onboardingFont(size: 16)
            lbl.textColor     = OnboardingPalette.secondary
            lbl.numberOfLines = 3
            lbl.textAlignment = .center
        }

        p1HeaderTitle.text = NSLocalizedString("ob_capture_ideas_title", comment: "")
        p1HeaderBody.text  = NSLocalizedString("ob_capture_ideas_body",  comment: "")
        p1PinTitle.text    = NSLocalizedString("ob_pin_lock_title",       comment: "")
        p1PinBody.text     = NSLocalizedString("ob_pin_lock_body",        comment: "")
        p1WriteTitle.text  = NSLocalizedString("ob_write_now_title",      comment: "")
        p1WriteBody.text   = NSLocalizedString("ob_write_now_body",       comment: "")

        // Images
        // ⚠️ Add images named "ob_lockscreen_pin" and "ob_lockscreen_write" to Assets.xcassets
        for imgView in [p1PinImage, p1WriteImage] {
            imgView.contentMode        = .scaleAspectFit
            imgView.clipsToBounds      = true
            imgView.layer.cornerRadius = 0
            imgView.backgroundColor    = .clear
            imgView.translatesAutoresizingMaskIntoConstraints = false
            imgView.heightAnchor.constraint(equalToConstant: 150).isActive = true
        }
        p1PinImage.image   = UIImage(named: "ob_lockscreen_pin")
        p1WriteImage.image = UIImage(named: "ob_lockscreen_write")

        // Build section 1: header text (centered)
        let headerStack = makeVStack([p1HeaderTitle, p1HeaderBody], spacing: 8)
        headerStack.alignment = .center

        // Build section 2: text on top, image below (centered)
        let pinText  = makeVStack([p1PinTitle, p1PinBody], spacing: 6)
        pinText.alignment = .center
        let pinRow   = makeVStack([pinText, p1PinImage], spacing: 12)
        pinRow.alignment  = .fill

        // Build section 3: text on top, image below (centered)
        let writeText = makeVStack([p1WriteTitle, p1WriteBody], spacing: 6)
        writeText.alignment = .center
        let writeRow  = makeVStack([writeText, p1WriteImage], spacing: 12)
        writeRow.alignment  = .fill

        // Wrap each in a section container (animated independently)
        embedInSection(headerStack, into: p1Section1)
        embedInSection(pinRow,      into: p1Section2)
        embedInSection(writeRow,    into: p1Section3)

        // Main vertical stack distributed evenly in container
        let mainStack = UIStackView(arrangedSubviews: [p1Section1, p1Section2, p1Section3])
        mainStack.axis         = .vertical
        mainStack.distribution = .equalSpacing
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        page1Container.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: page1Container.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: page1Container.bottomAnchor),
            mainStack.leadingAnchor.constraint(equalTo: page1Container.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: page1Container.trailingAnchor),
        ])
    }

    // MARK: - Stack helpers

    private func makeVStack(_ views: [UIView], spacing: CGFloat) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis    = .vertical
        s.spacing = spacing
        return s
    }

    private func makeHStack(_ views: [UIView], spacing: CGFloat) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis      = .horizontal
        s.spacing   = spacing
        s.alignment = .center
        return s
    }

    private func embedInSection(_ content: UIView, into section: UIView) {
        section.backgroundColor = .clear
        section.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        section.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: section.topAnchor),
            content.bottomAnchor.constraint(equalTo: section.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: section.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: section.trailingAnchor),
        ])
    }

    // MARK: - Gestures

    private func setupGestures() {
        let swipeLeft  = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeLeft.direction = .left
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeLeft)
        view.addGestureRecognizer(swipeRight)
    }

    // MARK: - Attributed title for page 0

    private func attributedWelcomeTitle() -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment   = .center
        para.lineSpacing = 2

        let pinnedNoteFont = UIFont(name: "BradleyHandITCTT-Bold", size: 36)
                          ?? UIFont.systemFont(ofSize: 36, weight: .bold)

        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(
            string: NSLocalizedString("ob_welcome_to", comment: ""),
            attributes: [.font: Self.onboardingFont(size: 22),
                         .foregroundColor: OnboardingPalette.secondary,
                         .paragraphStyle: para]
        ))
        attr.append(NSAttributedString(
            string: "PinnedNote",
            attributes: [.font: pinnedNoteFont,
                         .foregroundColor: OnboardingPalette.primary,
                         .paragraphStyle: para]
        ))
        return attr
    }

    // MARK: - Page transitions

    private func showPage(_ index: Int, animated: Bool) {
        let page    = pages[index]
        let cfg     = UIImage.SymbolConfiguration(pointSize: 60, weight: .ultraLight)
        let isPage1 = (index == 1)

        func applyContent() {
            page1Container.isHidden = !isPage1
            iconView.isHidden       = isPage1 || (page.symbol == nil)

            // Page 2 (coffee page): shift content up so title+body+coffee are vertically centered
            // Page 0: no icon, short content → -110 works fine
            iconCenterYConstraint?.constant = (index == 2) ? -174 : -110
            view.layoutIfNeeded()

            if isPage1 {
                // page 1: standard views stay invisible; page1Container animates separately
            } else {
                if let sym = page.symbol {
                    iconView.image = UIImage(systemName: sym, withConfiguration: cfg)
                }
                if index == 0 {
                    titleLabel.attributedText = attributedWelcomeTitle()
                } else {
                    titleLabel.attributedText = nil
                    titleLabel.font      = Self.onboardingFont(size: 28)
                    titleLabel.textColor = OnboardingPalette.primary
                    titleLabel.text      = page.title
                }
                bodyLabel.text = page.body
                titleLabel.alpha = 0
                bodyLabel.alpha  = 0
                if !iconView.isHidden { iconView.alpha = 0 }
            }
        }

        if animated {
            UIView.animate(withDuration: 0.28) {
                self.iconView.alpha         = 0
                self.titleLabel.alpha       = 0
                self.bodyLabel.alpha        = 0
                self.coffeeIconView.alpha   = 0
                self.page1Container.alpha   = 0
            } completion: { _ in
                applyContent()
                if isPage1 {
                    self.animatePage1In()
                } else {
                    self.animateIn()
                }
            }
        } else {
            applyContent()
            if isPage1 {
                animatePage1In()
            } else {
                animateIn()
            }
        }

        pageControl.currentPage = index
        UIView.transition(with: actionButton, duration: 0.2, options: .transitionCrossDissolve) {
            self.actionButton.setTitle(
                index == self.pages.count - 1
                    ? NSLocalizedString("ob_get_started", comment: "")
                    : NSLocalizedString("ob_continue",    comment: ""),
                for: .normal
            )
            self.actionButton.backgroundColor = OnboardingPalette.primary
        }
    }

    // MARK: - Animate in: shared views

    private func animateIn() {
        if !iconView.isHidden {
            iconView.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
            UIView.animate(withDuration: 0.75, delay: 0,
                           usingSpringWithDamping: 0.65, initialSpringVelocity: 0.3) {
                self.iconView.alpha     = 1
                self.iconView.transform = .identity
            }
        }
        let isLastPage   = (currentPage == 2)
        let titleDur     = isLastPage ? 1.1  : 0.6
        let titleDelay   = isLastPage ? 0.4  : 0.18
        let bodyDur      = isLastPage ? 1.1  : 0.6
        let bodyDelay    = isLastPage ? 0.75 : 0.32

        titleLabel.transform = CGAffineTransform(translationX: 0, y: 22)
        UIView.animate(withDuration: titleDur, delay: titleDelay,
                       usingSpringWithDamping: 0.82, initialSpringVelocity: 0) {
            self.titleLabel.alpha     = 1
            self.titleLabel.transform = .identity
        }
        bodyLabel.transform = CGAffineTransform(translationX: 0, y: 22)
        UIView.animate(withDuration: bodyDur, delay: bodyDelay,
                       usingSpringWithDamping: 0.82, initialSpringVelocity: 0) {
            self.bodyLabel.alpha     = 1
            self.bodyLabel.transform = .identity
        }
        // Coffee icon — only on page 2
        if isLastPage {
            coffeeIconView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            UIView.animate(withDuration: 1.1, delay: 1.1,
                           usingSpringWithDamping: 0.65, initialSpringVelocity: 0.3) {
                self.coffeeIconView.alpha     = 1
                self.coffeeIconView.transform = .identity
            }
        }
    }

    // MARK: - Animate in: page 1 (right → left, staggered)

    private func animatePage1In() {
        let slideOffset = UIScreen.main.bounds.width * 0.85

        // Reset all sections to off-screen right
        for section in [p1Section1, p1Section2, p1Section3] {
            section.transform = CGAffineTransform(translationX: slideOffset, y: 0)
            section.alpha     = 0
        }
        page1Container.alpha = 1

        let dur: TimeInterval = 0.85
        let damp: CGFloat     = 0.85

        UIView.animate(withDuration: dur, delay: 0,
                       usingSpringWithDamping: damp, initialSpringVelocity: 0) {
            self.p1Section1.transform = .identity
            self.p1Section1.alpha     = 1
        }
        UIView.animate(withDuration: dur, delay: 0.75,
                       usingSpringWithDamping: damp, initialSpringVelocity: 0) {
            self.p1Section2.transform = .identity
            self.p1Section2.alpha     = 1
        }
        UIView.animate(withDuration: dur, delay: 1.5,
                       usingSpringWithDamping: damp, initialSpringVelocity: 0) {
            self.p1Section3.transform = .identity
            self.p1Section3.alpha     = 1
        }
    }

    // MARK: - Actions

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        if gesture.direction == .left, currentPage < pages.count - 1 {
            currentPage += 1
            showPage(currentPage, animated: true)
        } else if gesture.direction == .right, currentPage > 0 {
            currentPage -= 1
            showPage(currentPage, animated: true)
        }
    }

    @objc private func actionTapped() {
        if currentPage < pages.count - 1 {
            currentPage += 1
            showPage(currentPage, animated: true)
        } else {
            finish()
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: "pnHasSeenOnboarding")
        guard let window = view.window else { return }

        // Phase 1: celý obsah se pomalu zvětší a vybledne
        UIView.animate(withDuration: 0.7, delay: 0,
                       options: .curveEaseIn) {
            self.view.alpha     = 0
            self.view.transform = CGAffineTransform(scaleX: 1.07, y: 1.07)
        } completion: { _ in
            // Phase 2: swap root VC, překryj cover vrstvou a pomalu ji odhal
            let nav = UINavigationController(rootViewController: NoteListViewController())
            nav.setNavigationBarHidden(true, animated: false)
            window.rootViewController = nav

            if let sceneDelegate = window.windowScene?.delegate as? SceneDelegate {
                sceneDelegate.openPendingNewNoteIfPossible()
            }

            let cover = UIView(frame: window.bounds)
            cover.backgroundColor = OnboardingPalette.background
            cover.alpha = 1
            window.addSubview(cover)

            UIView.animate(withDuration: 1.2, delay: 0.15,
                           options: .curveEaseOut) {
                cover.alpha = 0
            } completion: { _ in
                cover.removeFromSuperview()
            }
        }
    }
}

// MARK: - Onboarding font
// ↓ Pro reverzi na systémový font: zakomentuj řádek s "Cavolini" a odkomentuj fallback.
private extension OnboardingViewController {
    static func onboardingFont(size: CGFloat) -> UIFont {
        UIFont(name: "Cavolini", size: size)            // ← swap tady pro změnu fontu
        ?? .systemFont(ofSize: size, weight: .regular)  // fallback
    }
}
