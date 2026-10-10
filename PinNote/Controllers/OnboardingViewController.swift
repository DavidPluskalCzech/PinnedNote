import AVFoundation
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
             title:  "",   // page 1 shows the demo video — fields unused
             body:   ""),
        Page(symbol: nil,
             title:  "",   // page 2 shows the three steps — fields unused
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
    private let coffeeIconView = UIImageView()  // shown only on the last page
    private let coffeeCatVideo = OnboardingVideoView(resource: "onboarding-cat", extension: "mp4",
                                                     aspectRatio: 282.0 / 222.0, framedLikePhone: false)
    private var iconCenterYConstraint: NSLayoutConstraint?

    // MARK: - Page 1: demo video

    private let page1Container = UIView()
    private let demoVideo = OnboardingVideoView(resource: "onboarding-demo", extension: "mp4",
                                                aspectRatio: 630.0 / 1276.0, framedLikePhone: true)

    // MARK: - Page 2: idea, write, pin

    private let stepsContainer = UIView()
    private var stepDots: [UIView] = []
    private var stepLabels: [UILabel] = []
    private let justLikeThatLabel = UILabel()
    private let catNoteLabel = UILabel()
    private let catVideo = OnboardingVideoView(resource: "onboarding-cat", extension: "mp4",
                                               aspectRatio: 282.0 / 222.0, framedLikePhone: false)

    // MARK: -

    private var currentPage = 0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = OnboardingPalette.background
        setupSharedViews()
        setupPage1Views()
        setupStepsViews()
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

        let cfg2 = UIImage.SymbolConfiguration(pointSize: 40, weight: .thin)
        coffeeIconView.image       = UIImage(systemName: "cup.and.saucer.fill", withConfiguration: cfg2)
        coffeeIconView.tintColor   = OnboardingPalette.primary
        coffeeIconView.contentMode = .scaleAspectFit
        coffeeIconView.alpha       = 0

        coffeeCatVideo.accessibilityLabel = NSLocalizedString("ob_cat_video", comment: "")
        coffeeCatVideo.alpha = 0
        coffeeCatVideo.translatesAutoresizingMaskIntoConstraints = false
        coffeeIconView.translatesAutoresizingMaskIntoConstraints = false

        [iconView, titleLabel, bodyLabel, coffeeIconView, pageControl, actionButton].forEach { view.addSubview($0) }
        // Beneath everything: the video's empty margins mustn't cover the cup or the text.
        view.insertSubview(coffeeCatVideo, at: 0)

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

            // The cup and the cat side by side, centred as a pair.
            coffeeIconView.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: -52),
            coffeeIconView.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 44),
            coffeeIconView.heightAnchor.constraint(equalToConstant: 56),

            // The video has room around the cat: its tail starts ~35pt in, its paws ~6pt above the bottom; the cup sits a little lower.
            coffeeCatVideo.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: -40),
            coffeeCatVideo.bottomAnchor.constraint(equalTo: coffeeIconView.bottomAnchor, constant: -2),
            coffeeCatVideo.widthAnchor.constraint(equalToConstant: 141),
            coffeeCatVideo.heightAnchor.constraint(equalTo: coffeeCatVideo.widthAnchor,
                                                   multiplier: 1 / coffeeCatVideo.aspectRatio),

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
            page1Container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            page1Container.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor, constant: 16),
            page1Container.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor, constant: -16),
            page1Container.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -10),
        ])

        // The demo video, as large as fits, with the proportions of a phone screen.
        demoVideo.translatesAutoresizingMaskIntoConstraints = false
        page1Container.addSubview(demoVideo)
        let fill = demoVideo.heightAnchor.constraint(equalTo: page1Container.heightAnchor)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            demoVideo.centerXAnchor.constraint(equalTo: page1Container.centerXAnchor),
            demoVideo.centerYAnchor.constraint(equalTo: page1Container.centerYAnchor),
            demoVideo.widthAnchor.constraint(equalTo: demoVideo.heightAnchor, multiplier: demoVideo.aspectRatio),
            demoVideo.heightAnchor.constraint(lessThanOrEqualTo: page1Container.heightAnchor),
            demoVideo.widthAnchor.constraint(lessThanOrEqualTo: page1Container.widthAnchor),
            fill,
        ])
    }

    // MARK: - Layout: page 2

    private func setupStepsViews() {
        stepsContainer.isHidden = true
        stepsContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stepsContainer)

        let rows = UIStackView()
        rows.axis = .vertical
        rows.alignment = .leading
        rows.spacing = 2
        rows.translatesAutoresizingMaskIntoConstraints = false
        stepsContainer.addSubview(rows)

        for key in ["ob_step_idea", "ob_step_write", "ob_step_pin"] {
            let dot = UIView()
            dot.backgroundColor = OnboardingPalette.primary
            dot.layer.cornerRadius = 7
            dot.translatesAutoresizingMaskIntoConstraints = false

            let label = UILabel()
            label.text = NSLocalizedString(key, comment: "")
            label.font = Self.appFont(size: 36, bold: true)
            label.textColor = OnboardingPalette.primary
            label.translatesAutoresizingMaskIntoConstraints = false

            let row = UIView()
            row.addSubview(dot)
            row.addSubview(label)
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 14),
                dot.heightAnchor.constraint(equalToConstant: 14),
                dot.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                dot.centerYAnchor.constraint(equalTo: label.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 20),
                label.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                label.topAnchor.constraint(equalTo: row.topAnchor),
                label.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            ])
            rows.addArrangedSubview(row)
            stepDots.append(dot)
            stepLabels.append(label)
        }

        justLikeThatLabel.text = NSLocalizedString("ob_step_just_like_that", comment: "")
        justLikeThatLabel.font = Self.appFont(size: 30, bold: false)
        justLikeThatLabel.textColor = OnboardingPalette.primary
        justLikeThatLabel.textAlignment = .center
        justLikeThatLabel.translatesAutoresizingMaskIntoConstraints = false
        stepsContainer.addSubview(justLikeThatLabel)

        catNoteLabel.text = NSLocalizedString("ob_step_cat_note", comment: "")
        catNoteLabel.font = Self.appFont(size: 19, bold: false)
        catNoteLabel.textColor = OnboardingPalette.primary
        catNoteLabel.textAlignment = .center
        catNoteLabel.numberOfLines = 0
        catNoteLabel.translatesAutoresizingMaskIntoConstraints = false
        stepsContainer.addSubview(catNoteLabel)

        catVideo.accessibilityLabel = NSLocalizedString("ob_cat_video", comment: "")
        catVideo.translatesAutoresizingMaskIntoConstraints = false
        stepsContainer.addSubview(catVideo)

        NSLayoutConstraint.activate([
            stepsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stepsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stepsContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 36),

            rows.topAnchor.constraint(equalTo: stepsContainer.topAnchor),
            rows.centerXAnchor.constraint(equalTo: stepsContainer.centerXAnchor),

            justLikeThatLabel.topAnchor.constraint(equalTo: rows.bottomAnchor, constant: 28),
            justLikeThatLabel.centerXAnchor.constraint(equalTo: stepsContainer.centerXAnchor),

            catNoteLabel.topAnchor.constraint(equalTo: justLikeThatLabel.bottomAnchor, constant: 40),
            catNoteLabel.centerXAnchor.constraint(equalTo: stepsContainer.centerXAnchor),
            catNoteLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            catNoteLabel.leadingAnchor.constraint(greaterThanOrEqualTo: stepsContainer.leadingAnchor, constant: 36),

            catVideo.topAnchor.constraint(equalTo: catNoteLabel.bottomAnchor, constant: 12),
            catVideo.centerXAnchor.constraint(equalTo: stepsContainer.centerXAnchor),
            catVideo.widthAnchor.constraint(equalToConstant: 141),
            catVideo.heightAnchor.constraint(equalTo: catVideo.widthAnchor, multiplier: 1 / catVideo.aspectRatio),
            catVideo.bottomAnchor.constraint(equalTo: stepsContainer.bottomAnchor),
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

        let pinnedNoteFont = UIFont(name: "BradleyHandITCTT-Bold", size: 52)
                          ?? UIFont.systemFont(ofSize: 52, weight: .bold)

        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(
            string: NSLocalizedString("ob_welcome_to", comment: ""),
            attributes: [.font: Self.appFont(size: 32, bold: false),
                         .foregroundColor: OnboardingPalette.secondary,
                         .paragraphStyle: para]
        ))
        attr.append(NSAttributedString(
            string: "PinnedNote",
            // Stroked in its own colour for heavier letters, as the list's wordmark.
            attributes: [.font: pinnedNoteFont,
                         .foregroundColor: OnboardingPalette.primary,
                         .strokeColor: OnboardingPalette.primary,
                         .strokeWidth: -3.5,
                         .paragraphStyle: para]
        ))
        return attr
    }

    // MARK: - Page transitions

    private func showPage(_ index: Int, animated: Bool) {
        let page    = pages[index]
        let cfg     = UIImage.SymbolConfiguration(pointSize: 60, weight: .ultraLight)
        let isPage1 = (index == 1)
        let isSteps = (index == 2)
        let isLastPage = (index == pages.count - 1)

        func applyContent() {
            page1Container.isHidden = !isPage1
            if isPage1 { demoVideo.playFromStart() } else { demoVideo.pause() }
            stepsContainer.isHidden = !isSteps
            if isSteps { catVideo.playFromStart() } else { catVideo.pause() }
            if isLastPage { coffeeCatVideo.playFromStart() } else { coffeeCatVideo.pause() }
            iconView.isHidden       = isPage1 || isSteps || (page.symbol == nil)

            // Coffee page: shift content up so title+body+coffee are vertically centered
            // Page 0: no icon, short content → a little above the middle
            iconCenterYConstraint?.constant = isLastPage ? -200 : -170
            view.layoutIfNeeded()

            if isPage1 || isSteps {
                // standard views stay invisible; these pages animate their own views
            } else {
                if let sym = page.symbol {
                    iconView.image = UIImage(systemName: sym, withConfiguration: cfg)
                }
                if index == 0 {
                    titleLabel.attributedText = attributedWelcomeTitle()
                } else {
                    titleLabel.attributedText = nil
                    // Like the steps' "Write": bold Kalam.
                    titleLabel.font      = Self.appFont(size: 36, bold: true)
                    titleLabel.textColor = OnboardingPalette.primary
                    titleLabel.text      = page.title
                }
                // The welcome page's line is larger than the other pages' text.
                bodyLabel.font = Self.appFont(size: index == 0 ? 26 : 21, bold: false)
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
                self.coffeeCatVideo.alpha   = 0
                self.page1Container.alpha   = 0
                self.stepsContainer.alpha   = 0
            } completion: { _ in
                applyContent()
                self.animateContentIn(isPage1: isPage1, isSteps: isSteps)
            }
        } else {
            applyContent()
            animateContentIn(isPage1: isPage1, isSteps: isSteps)
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

    private func animateContentIn(isPage1: Bool, isSteps: Bool) {
        if isPage1 {
            animatePage1In()
        } else if isSteps {
            animateStepsIn()
        } else {
            animateIn()
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
        let isLastPage   = (currentPage == pages.count - 1)
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
        // Coffee icon — only on the last page
        if isLastPage {
            coffeeIconView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            UIView.animate(withDuration: 1.1, delay: 1.1,
                           usingSpringWithDamping: 0.65, initialSpringVelocity: 0.3) {
                self.coffeeIconView.alpha     = 1
                self.coffeeIconView.transform = .identity
            }
            UIView.animate(withDuration: 0.9, delay: 1.6, options: .curveEaseInOut) {
                self.coffeeCatVideo.alpha = 1
            }
        }
    }

    // MARK: - Animate in: page 1

    private func animatePage1In() {
        page1Container.alpha = 0
        page1Container.transform = CGAffineTransform(translationX: 0, y: 24)
        UIView.animate(withDuration: 0.7, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.page1Container.alpha = 1
            self.page1Container.transform = .identity
        }
    }

    // MARK: - Animate in: page 2

    /// One step after another: its dot fades in, then its word slides in from the
    /// right; at the end "...just like that!" fades in, then the note about the cat.
    private func animateStepsIn() {
        let animated = stepDots + stepLabels + [justLikeThatLabel, catNoteLabel, catVideo]
        animated.forEach {
            $0.layer.removeAllAnimations()
            $0.alpha = 0
        }
        stepLabels.forEach { $0.transform = CGAffineTransform(translationX: 140, y: 0) }
        stepsContainer.alpha = 1

        for (i, (dot, label)) in zip(stepDots, stepLabels).enumerated() {
            let start = 0.25 + Double(i) * 0.85
            UIView.animate(withDuration: 0.45, delay: start, options: .curveEaseOut) {
                dot.alpha = 1
            }
            UIView.animate(withDuration: 0.8, delay: start + 0.25,
                           usingSpringWithDamping: 0.82, initialSpringVelocity: 0) {
                label.alpha = 1
                label.transform = .identity
            }
        }
        UIView.animate(withDuration: 0.9, delay: 0.25 + 3 * 0.85 + 0.2, options: .curveEaseInOut) {
            self.justLikeThatLabel.alpha = 1
        }
        UIView.animate(withDuration: 0.9, delay: 0.25 + 3 * 0.85 + 1.0, options: .curveEaseInOut) {
            self.catNoteLabel.alpha = 1
        }
        UIView.animate(withDuration: 0.9, delay: 0.25 + 3 * 0.85 + 1.6, options: .curveEaseInOut) {
            self.catVideo.alpha = 1
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

    /// The app's default note typeface (Kalam).
    static func appFont(size: CGFloat, bold: Bool) -> UIFont {
        let font = AppFont.default
        let name = bold ? font.boldName : font.regularName
        return name.flatMap { UIFont(name: $0, size: size * font.sizeScale) }
            ?? .systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

// MARK: - Demo video

/// Plays a bundled video in a loop, silently, optionally framed like a phone screen.
private final class OnboardingVideoView: UIView {

    /// Width ÷ height of the video.
    let aspectRatio: CGFloat

    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private let framedLikePhone: Bool

    /// `aspectRatio`: the size the video is encoded at.
    init(resource: String, extension ext: String, aspectRatio: CGFloat, framedLikePhone: Bool) {
        let url = Bundle.main.url(forResource: resource, withExtension: ext)
        let item = url.map { AVPlayerItem(url: $0) }
        self.aspectRatio = aspectRatio
        self.framedLikePhone = framedLikePhone
        super.init(frame: .zero)

        // No audio: it mustn't stop the music the user may be listening to.
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        if let item { looper = AVPlayerLooper(player: player, templateItem: item) }
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill

        backgroundColor = OnboardingPalette.background
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = NSLocalizedString("ob_demo_video", comment: "")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The curve of an iPhone screen, so the recording's own rounded corners
        // (black while the app opens) stay hidden.
        layer.cornerRadius = framedLikePhone ? bounds.width * 0.14 : 0
    }

    func playFromStart() {
        player.seek(to: .zero)
        player.play()
    }

    func pause() {
        player.pause()
    }
}
