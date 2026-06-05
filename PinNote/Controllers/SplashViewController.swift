import UIKit

// MARK: - SplashViewController

final class SplashViewController: UIViewController {

    private let wordmarkLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .pnSurface
        setupWordmark()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateIn()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.transitionToMain()
        }
    }

    // MARK: - Layout

    private func setupWordmark() {
        let wordmarkFont = UIFont(name: "BradleyHandITCTT-Bold", size: 44) ?? PN.font(44, bold: true)
        wordmarkLabel.attributedText = NSAttributedString(string: "PinnedNote", attributes: [
            .font:            wordmarkFont,
            .foregroundColor: UIColor.pnPrimary,
            .strokeColor:     UIColor.pnPrimary,
            .strokeWidth:     -3.5,
        ])
        wordmarkLabel.alpha = 0
        wordmarkLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(wordmarkLabel)
        NSLayoutConstraint.activate([
            wordmarkLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            wordmarkLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Animation

    private func animateIn() {
        wordmarkLabel.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)

        UIView.animate(withDuration: 0.55, delay: 0.1,
                       usingSpringWithDamping: 0.68, initialSpringVelocity: 0.4) {
            self.wordmarkLabel.alpha = 1
            self.wordmarkLabel.transform = .identity
        }
    }

    private func transitionToMain() {
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "pnHasSeenOnboarding")
        let destination: UIViewController

        if isFirstLaunch {
            destination = OnboardingViewController()
        } else {
            let listVC = NoteListViewController()
            let nav    = UINavigationController(rootViewController: listVC)
            nav.setNavigationBarHidden(true, animated: false)
            destination = nav
        }

        guard let window = view.window else { return }
        UIView.transition(with: window, duration: 0.75, options: .transitionCrossDissolve) {
            window.rootViewController = destination
        } completion: { _ in
            if let sceneDelegate = window.windowScene?.delegate as? SceneDelegate {
                sceneDelegate.openPendingNewNoteIfPossible()
            }
        }
    }
}
