import UIKit

/// A small grey tabby drawn in code, living next to the list title. It's a puppet
/// of separate layers (body, tail, head, ears, eyes…) moved with Core Animation:
/// curled up asleep while the app is away; when it opens the cat lifts its head,
/// yawns and sits up, then blinks, licks a paw and stretches now and then.
///
/// The cat is drawn in a 120 × 80 point design space and scaled to the view's height.
final class CatCompanionView: UIView {

    private enum Pose { case asleep, awake }

    // MARK: - Colours

    private enum Palette {
        static let fur = UIColor(red: 0.60, green: 0.60, blue: 0.62, alpha: 1).cgColor
        /// Legs on the far side, a shade darker so the standing cat has depth.
        static let farFur = UIColor(red: 0.50, green: 0.50, blue: 0.52, alpha: 1).cgColor
        static let stripe = UIColor(red: 0.36, green: 0.36, blue: 0.38, alpha: 1).cgColor
        static let light = UIColor(red: 0.89, green: 0.89, blue: 0.90, alpha: 1).cgColor
        static let outline = UIColor(white: 0.12, alpha: 1).cgColor
        static let pink = UIColor(red: 0.96, green: 0.63, blue: 0.67, alpha: 1).cgColor
    }

    // MARK: - Design space

    private static let canvas = CGSize(width: 120, height: 80)
    private static let ground: CGFloat = 76

    // MARK: - Layers

    /// Holds the whole cat in design coordinates; scaled to fit the view.
    private let rig = CALayer()
    /// Wraps everything that breathes while asleep.
    private let breath = CALayer()
    private let shadow = CAShapeLayer()

    private let tail = CALayer()
    private let tailOutline = CAShapeLayer()
    private let tailFur = CAShapeLayer()
    /// Fur over the start of the sleeping tail, hiding its round outlined end so the
    /// tail grows out of the body.
    private let tailRoot = CAShapeLayer()

    private let body = CALayer()
    private let bodyShape = CAShapeLayer()
    private let belly = CAShapeLayer()
    private let bodyStripes = CAShapeLayer()
    /// Front paws tucked under the chin while curled up asleep.
    private let sleepPaws = CALayer()
    private let leftLeg = CAShapeLayer()
    private let rightLeg = CAShapeLayer()
    /// The left front leg as a jointed limb (shoulder, elbow, wrist, paw), raised
    /// to the mouth while licking; hidden otherwise, when the drawn leg line shows.
    private let raisedLeg = CALayer()
    /// Drawn back to front: outline stroke and paw, then fur stroke and paw on top,
    /// so the outline only shows round the edge.
    private let legOutline = CAShapeLayer()
    private let pawOutline = CAShapeLayer()
    private let legFur = CAShapeLayer()
    private let pawFur = CAShapeLayer()
    /// Light patch where the leg meets the chest, hiding the outline's shoulder end.
    private let shoulderPatch = CAShapeLayer()
    private let pawToes = CAShapeLayer()

    private let head = CALayer()
    private let leftEar = CALayer()
    private let rightEar = CALayer()
    private let headShape = CAShapeLayer()
    private let muzzle = CAShapeLayer()
    private let headStripes = CAShapeLayer()
    private let openEyes = CAShapeLayer()
    private let closedEyes = CAShapeLayer()
    private let mouth = CAShapeLayer()
    private let yawn = CAShapeLayer()
    private let tongue = CAShapeLayer()
    private let whiskers = CAShapeLayer()

    private var pose: Pose = .asleep
    private var snoreTimer: Timer?
    /// Bumped to cancel whatever the cat is in the middle of (it fell asleep).
    private var routineToken = 0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        buildRig()
        applyColors()
        apply(pose: .asleep)
        startSleepLoops()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        snoreTimer?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = bounds.height / Self.canvas.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rig.bounds = CGRect(origin: .zero, size: Self.canvas)
        rig.anchorPoint = CGPoint(x: 1, y: 1)
        rig.position = CGPoint(x: bounds.maxX, y: bounds.maxY)
        rig.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Self.canvas.width * 0.6, height: Self.canvas.height * 0.6)
    }

    // MARK: - Public

    /// Wakes up the way a cat does: ears perk up, the head lifts while still lying
    /// down, the eyes open sleepily, a big yawn, then it pushes up into a sit. After
    /// that it carries on with little things.
    func wakeUp() {
        guard pose == .asleep else { return }
        pose = .awake
        stopSleepLoops()
        let duration = playWakeSequence()
        startAwakeBreathing(after: duration)
        startTailLoop(after: duration - 0.3)

        let token = routineToken
        after(duration + 0.6, token) { [weak self] in self?.idle(token) }
    }

    /// Curls up and goes to sleep, wherever it is.
    func fallAsleep(animated: Bool = true) {
        guard pose == .awake else { return }
        pose = .asleep
        routineToken += 1
        stopActions()
        stopTailLoop()
        body.removeAnimation(forKey: "awakeBreath")

        if animated {
            crossfadeEyes(open: false, delay: 0)
            animatePose(.asleep, duration: 0.8, delay: 0.15)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.pose == .asleep else { return }
                self.startSleepLoops()
            }
        } else {
            removeAllPartAnimations()
            crossfadeEyes(open: false, delay: 0, duration: 0)
            apply(pose: .asleep)
            startSleepLoops()
        }
    }

    func applyColors() {
        let fur = Palette.fur
        let stripe = Palette.stripe
        let light = Palette.light
        let outline = Palette.outline
        let pink = Palette.pink

        shadow.fillColor = UIColor.black.withAlphaComponent(
            ThemeManager.shared.current == .dark ? 0.0 : 0.12
        ).cgColor
        tailOutline.strokeColor = outline
        tailFur.strokeColor = fur
        tailRoot.fillColor = fur
        bodyShape.fillColor = fur
        bodyShape.strokeColor = outline
        belly.fillColor = light
        bodyStripes.strokeColor = stripe
        leftLeg.strokeColor = outline
        rightLeg.strokeColor = outline
        yawn.fillColor = pink
        yawn.strokeColor = outline
        tongue.fillColor = pink
        tongue.strokeColor = outline
        headShape.fillColor = fur
        headShape.strokeColor = outline
        muzzle.fillColor = light
        headStripes.strokeColor = stripe
        openEyes.fillColor = outline
        closedEyes.strokeColor = outline
        mouth.strokeColor = outline
        whiskers.strokeColor = outline
        for ear in [leftEar, rightEar] {
            let layers = ear.sublayers as? [CAShapeLayer] ?? []
            layers.first?.fillColor = fur
            layers.first?.strokeColor = outline
            layers.last?.fillColor = pink
        }
    }

    // MARK: - Building the cat

    private func buildRig() {
        layer.addSublayer(rig)
        breath.frame = CGRect(origin: .zero, size: Self.canvas)
        setAnchor(breath, to: CGPoint(x: 60, y: Self.ground))
        rig.addSublayer(breath)

        shadow.path = UIBezierPath(ovalIn: CGRect(x: 26, y: Self.ground - 3.5, width: 68, height: 7)).cgPath
        rig.insertSublayer(shadow, below: breath)

        // Tail: a thick outlined stroke curling up on the left.
        let tailPath = Self.tailPath(curl: 0)
        for (shapeLayer, width) in [(tailOutline, CGFloat(8)), (tailFur, CGFloat(4.6))] {
            shapeLayer.path = tailPath.cgPath
            shapeLayer.fillColor = nil
            shapeLayer.lineWidth = width
            shapeLayer.lineCap = .round
            shapeLayer.lineJoin = .round
            tail.addSublayer(shapeLayer)
        }
        // Set back along the tail into the body, so it hides the round end but leaves
        // the tail's side outlines, which carry on from the body's outline.
        let root = CGPoint(x: Self.lyingTailRoot.x + 1.4, y: Self.lyingTailRoot.y - 2.6)
        tailRoot.path = UIBezierPath(ovalIn: CGRect(x: root.x - 4.2, y: root.y - 4.2, width: 8.4, height: 8.4)).cgPath
        tail.addSublayer(tailRoot)
        tail.frame = breath.bounds
        setAnchor(tail, to: CGPoint(x: 44, y: 72))
        breath.addSublayer(tail)

        // Body: a pear sitting on the ground, with a light belly, side stripes and legs.
        bodyShape.path = Self.sittingBody
        bodyShape.lineWidth = 2.4
        bodyShape.lineJoin = .round

        belly.path = UIBezierPath(ovalIn: CGRect(x: 48.5, y: 45, width: 23, height: 31)).cgPath

        bodyStripes.path = Self.sittingStripes
        styleStroke(bodyStripes, width: 2.3)

        leftLeg.path = strokes([(CGPoint(x: 54, y: 61), CGPoint(x: 54, y: 75.5))]).cgPath
        rightLeg.path = strokes([(CGPoint(x: 66, y: 61), CGPoint(x: 66, y: 75.5))]).cgPath
        styleStroke(leftLeg, width: 2.1)
        styleStroke(rightLeg, width: 2.1)

        body.frame = breath.bounds
        setAnchor(body, to: CGPoint(x: 60, y: Self.ground))
        [bodyShape, belly, bodyStripes, leftLeg, rightLeg].forEach(body.addSublayer)
        breath.addSublayer(body)

        // Head: ears behind a rounded head, light muzzle, forehead stripes and face.
        head.frame = breath.bounds
        setAnchor(head, to: CGPoint(x: 60, y: 46))
        breath.addSublayer(head)

        buildEar(leftEar, outer: [CGPoint(x: 39, y: 25), CGPoint(x: 43.5, y: 6), CGPoint(x: 55, y: 16)],
                 inner: [CGPoint(x: 42.5, y: 20.5), CGPoint(x: 44.5, y: 11), CGPoint(x: 50.5, y: 16)],
                 pivot: CGPoint(x: 47, y: 19))
        buildEar(rightEar, outer: [CGPoint(x: 81, y: 25), CGPoint(x: 76.5, y: 6), CGPoint(x: 65, y: 16)],
                 inner: [CGPoint(x: 77.5, y: 20.5), CGPoint(x: 75.5, y: 11), CGPoint(x: 69.5, y: 16)],
                 pivot: CGPoint(x: 73, y: 19))
        head.addSublayer(leftEar)
        head.addSublayer(rightEar)

        headShape.path = UIBezierPath(roundedRect: CGRect(x: 37, y: 13, width: 46, height: 34), cornerRadius: 17).cgPath
        headShape.lineWidth = 2.4
        head.addSublayer(headShape)

        muzzle.path = UIBezierPath(ovalIn: CGRect(x: 47, y: 29, width: 26, height: 16.5)).cgPath
        head.addSublayer(muzzle)

        headStripes.path = strokes([
            (CGPoint(x: 55, y: 16.5), CGPoint(x: 55.6, y: 21.5)),
            (CGPoint(x: 60, y: 15.5), CGPoint(x: 60, y: 21.5)),
            (CGPoint(x: 65, y: 16.5), CGPoint(x: 64.4, y: 21.5)),
        ]).cgPath
        styleStroke(headStripes, width: 2.1)
        head.addSublayer(headStripes)

        let eyes = UIBezierPath(ovalIn: CGRect(x: 48.4, y: 25.4, width: 5.2, height: 5.2))
        eyes.append(UIBezierPath(ovalIn: CGRect(x: 66.4, y: 25.4, width: 5.2, height: 5.2)))
        openEyes.path = eyes.cgPath
        // Full canvas with the anchor on the eye line, so blinks squash around it.
        openEyes.frame = CGRect(origin: .zero, size: Self.canvas)
        setAnchor(openEyes, to: CGPoint(x: 60, y: 28))
        head.addSublayer(openEyes)

        let shut = UIBezierPath()
        for x in [47.5, 65.5] as [CGFloat] {
            shut.move(to: CGPoint(x: x, y: 27.5))
            shut.addQuadCurve(to: CGPoint(x: x + 7, y: 27.5), controlPoint: CGPoint(x: x + 3.5, y: 31))
        }
        closedEyes.path = shut.cgPath
        styleStroke(closedEyes, width: 1.9)
        head.addSublayer(closedEyes)

        let mouthPath = UIBezierPath()
        mouthPath.move(to: CGPoint(x: 56.5, y: 33.5))
        mouthPath.addQuadCurve(to: CGPoint(x: 60, y: 34), controlPoint: CGPoint(x: 58, y: 36.5))
        mouthPath.addQuadCurve(to: CGPoint(x: 63.5, y: 33.5), controlPoint: CGPoint(x: 62, y: 36.5))
        mouth.path = mouthPath.cgPath
        styleStroke(mouth, width: 1.6)
        head.addSublayer(mouth)

        // Wide-open mouth for the yawn, and a tongue for licking; both hidden at rest.
        yawn.path = UIBezierPath(ovalIn: CGRect(x: 56, y: 31.5, width: 8, height: 7.5)).cgPath
        yawn.lineWidth = 1.6
        yawn.opacity = 0
        head.addSublayer(yawn)

        tongue.path = UIBezierPath(ovalIn: CGRect(x: 57.6, y: 34.6, width: 4.8, height: 4.2)).cgPath
        tongue.lineWidth = 1.2
        tongue.opacity = 0
        head.addSublayer(tongue)

        whiskers.path = strokes([
            (CGPoint(x: 44, y: 31), CGPoint(x: 32, y: 28.5)),
            (CGPoint(x: 44, y: 34), CGPoint(x: 32, y: 34)),
            (CGPoint(x: 44.5, y: 37), CGPoint(x: 33.5, y: 40)),
            (CGPoint(x: 76, y: 31), CGPoint(x: 88, y: 28.5)),
            (CGPoint(x: 76, y: 34), CGPoint(x: 88, y: 34)),
            (CGPoint(x: 75.5, y: 37), CGPoint(x: 86.5, y: 40)),
        ]).cgPath
        styleStroke(whiskers, width: 1.3)
        head.addSublayer(whiskers)

        // The left front leg, which bends up to the mouth for licking. Its resting
        // shape lines up with the drawn leg, so the swap doesn't show.
        raisedLeg.frame = breath.bounds
        for stroke in [legOutline, legFur] { styleStroke(stroke, width: 1) }
        legOutline.strokeColor = Palette.outline
        legFur.strokeColor = Palette.light
        pawOutline.fillColor = Palette.outline
        pawFur.fillColor = Palette.light
        shoulderPatch.fillColor = Palette.light
        pawToes.strokeColor = Palette.outline
        styleStroke(pawToes, width: 1.2)
        [legOutline, pawOutline, legFur, pawFur, shoulderPatch, pawToes].forEach(raisedLeg.addSublayer)
        apply(LegPose.rest.shapes())
        raisedLeg.opacity = 0
        breath.addSublayer(raisedLeg)

        // Two front paws under the chin for the curled-up pose.
        sleepPaws.frame = breath.bounds
        for rect in [CGRect(x: 55, y: 69.5, width: 10.5, height: 7), CGRect(x: 69.5, y: 70, width: 10.5, height: 6.6)] {
            let paw = CAShapeLayer()
            paw.path = UIBezierPath(ovalIn: rect).cgPath
            paw.fillColor = Palette.light
            paw.strokeColor = Palette.outline
            paw.lineWidth = 2
            sleepPaws.addSublayer(paw)
            let toes = CAShapeLayer()
            toes.path = strokes([
                (CGPoint(x: rect.midX - 1.6, y: rect.maxY - 0.6), CGPoint(x: rect.midX - 1.4, y: rect.maxY - 2.6)),
                (CGPoint(x: rect.midX + 1.6, y: rect.maxY - 0.6), CGPoint(x: rect.midX + 1.4, y: rect.maxY - 2.6)),
            ]).cgPath
            toes.strokeColor = Palette.outline
            styleStroke(toes, width: 1.2)
            sleepPaws.addSublayer(toes)
        }
        breath.addSublayer(sleepPaws)

        // Drawing order that changes with the pose: the tail goes in front of the
        // body when it wraps round a sleeping cat; head and paws stay on top.
        head.zPosition = 2
        sleepPaws.zPosition = 3
        raisedLeg.zPosition = 4
    }

    // MARK: - Shapes for the two poses

    /// Sitting up: a pear on the ground.
    private static let sittingBody: CGPath = {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 38, y: 76))
        path.addCurve(to: CGPoint(x: 44, y: 40), controlPoint1: CGPoint(x: 33, y: 66), controlPoint2: CGPoint(x: 36, y: 46))
        path.addCurve(to: CGPoint(x: 76, y: 40), controlPoint1: CGPoint(x: 52, y: 33), controlPoint2: CGPoint(x: 68, y: 33))
        path.addCurve(to: CGPoint(x: 82, y: 76), controlPoint1: CGPoint(x: 84, y: 46), controlPoint2: CGPoint(x: 87, y: 66))
        path.addQuadCurve(to: CGPoint(x: 38, y: 76), controlPoint: CGPoint(x: 60, y: 78))
        path.close()
        return path.cgPath
    }()

    /// Curled up: a low, round mound, its back rising on the left. Same structure
    /// as the sitting body, so one morphs into the other.
    private static let lyingBody: CGPath = {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 26, y: 76))
        path.addCurve(to: CGPoint(x: 34, y: 55), controlPoint1: CGPoint(x: 22, y: 70), controlPoint2: CGPoint(x: 25, y: 59))
        path.addCurve(to: CGPoint(x: 80, y: 50), controlPoint1: CGPoint(x: 44, y: 46), controlPoint2: CGPoint(x: 66, y: 43))
        path.addCurve(to: CGPoint(x: 94, y: 76), controlPoint1: CGPoint(x: 92, y: 56), controlPoint2: CGPoint(x: 97, y: 68))
        path.addQuadCurve(to: CGPoint(x: 26, y: 76), controlPoint: CGPoint(x: 60, y: 78))
        path.close()
        return path.cgPath
    }()

    private static let sittingStripes: CGPath = {
        let path = UIBezierPath()
        for (a, b) in [(CGPoint(x: 39.5, y: 57), CGPoint(x: 46, y: 55)), (CGPoint(x: 38.5, y: 64), CGPoint(x: 45, y: 63)),
                       (CGPoint(x: 80.5, y: 57), CGPoint(x: 74, y: 55)), (CGPoint(x: 81.5, y: 64), CGPoint(x: 75, y: 63))] {
            path.move(to: a); path.addLine(to: b)
        }
        return path.cgPath
    }()

    /// Stripes across the curled back.
    private static let lyingStripes: CGPath = {
        let path = UIBezierPath()
        for (a, b) in [(CGPoint(x: 29, y: 66), CGPoint(x: 34.5, y: 63)), (CGPoint(x: 32.5, y: 58), CGPoint(x: 38, y: 57)),
                       (CGPoint(x: 39.5, y: 51.5), CGPoint(x: 42.5, y: 56)), (CGPoint(x: 47, y: 48.5), CGPoint(x: 49, y: 53))] {
            path.move(to: a); path.addLine(to: b)
        }
        return path.cgPath
    }()

    /// The tail wrapped round the front of a sleeping cat: along the ground just in
    /// front of the body, its tip curling up by the paws. Same structure as
    /// `tailPath(curl:)`.
    private static let lyingTail: CGPath = {
        let path = UIBezierPath()
        path.move(to: CatCompanionView.lyingTailRoot)
        path.addQuadCurve(to: CGPoint(x: 36, y: 78.3), controlPoint: CGPoint(x: 24.8, y: 77.5))
        path.addQuadCurve(to: CGPoint(x: 48.5, y: 74.3), controlPoint: CGPoint(x: 45, y: 79.2))
        return path.cgPath
    }()

    /// Where the sleeping tail leaves the body, a little inside its outline.
    private static let lyingTailRoot = CGPoint(x: 28.6, y: 65.5)

    /// Halfway between lying and sitting: swung out to the left, clear of the body,
    /// where it can pass from in front of the body to behind it unseen.
    private static let tailOut: CGPath = {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 34, y: 72))
        path.addQuadCurve(to: CGPoint(x: 21, y: 75), controlPoint: CGPoint(x: 27, y: 78.5))
        path.addQuadCurve(to: CGPoint(x: 14, y: 63), controlPoint: CGPoint(x: 12, y: 72))
        return path.cgPath
    }()

    /// Head lowered onto the paws, a little to the right and smaller in the curl.
    private static let lyingHead = headTransform(x: 8, y: 23, turned: 0.06, scale: 0.9)

    private static func headTransform(x: CGFloat, y: CGFloat, turned angle: CGFloat = 0,
                                      scale: CGFloat = 1) -> CATransform3D {
        var t = CATransform3DMakeScale(scale, scale, 1)
        t = CATransform3DConcat(t, CATransform3DMakeRotation(angle, 0, 0, 1))
        return CATransform3DConcat(t, CATransform3DMakeTranslation(x, y, 0))
    }

    private func buildEar(_ ear: CALayer, outer: [CGPoint], inner: [CGPoint], pivot: CGPoint) {
        let outerLayer = CAShapeLayer()
        outerLayer.path = polygon(outer).cgPath
        outerLayer.lineWidth = 2.4
        outerLayer.lineJoin = .round
        let innerLayer = CAShapeLayer()
        innerLayer.path = polygon(inner).cgPath
        innerLayer.lineJoin = .round
        ear.frame = CGRect(origin: .zero, size: Self.canvas)
        ear.addSublayer(outerLayer)
        ear.addSublayer(innerLayer)
        setAnchor(ear, to: pivot)
    }

    // MARK: - Poses

    /// Transforms and visibility of each part for a pose.
    private func targets(for pose: Pose) -> [(CALayer, CATransform3D, Float)] {
        switch pose {
        case .awake:
            return [
                (body, CATransform3DIdentity, 1),
                (head, CATransform3DIdentity, 1),
                (tail, CATransform3DIdentity, 1),
                (leftEar, CATransform3DIdentity, 1),
                (rightEar, CATransform3DIdentity, 1),
                (leftLeg, CATransform3DIdentity, 1),
                (rightLeg, CATransform3DIdentity, 1),
                (belly, CATransform3DIdentity, 1),
                (sleepPaws, CATransform3DIdentity, 0),
                (tailRoot, CATransform3DIdentity, 0),
            ]
        case .asleep:
            // Curled up: the body shape changes (see shapes(for:)); head rests on
            // the paws, ears relaxed outwards.
            return [
                (body, CATransform3DIdentity, 1),
                (head, Self.lyingHead, 1),
                (tail, CATransform3DIdentity, 1),
                (leftEar, CATransform3DMakeRotation(-0.2, 0, 0, 1), 1),
                (rightEar, CATransform3DMakeRotation(0.2, 0, 0, 1), 1),
                (leftLeg, CATransform3DIdentity, 0),
                (rightLeg, CATransform3DIdentity, 0),
                (belly, CATransform3DIdentity, 0),
                (sleepPaws, CATransform3DIdentity, 1),
                (tailRoot, CATransform3DIdentity, 1),
            ]
        }
    }

    /// Body, stripes and tail outlines for a pose.
    private func shapes(for pose: Pose) -> [(CAShapeLayer, CGPath)] {
        let asleep = pose == .asleep
        return [
            (bodyShape, asleep ? Self.lyingBody : Self.sittingBody),
            (bodyStripes, asleep ? Self.lyingStripes : Self.sittingStripes),
            (tailOutline, asleep ? Self.lyingTail : Self.tailPath(curl: 0).cgPath),
            (tailFur, asleep ? Self.lyingTail : Self.tailPath(curl: 0).cgPath),
        ]
    }

    private func apply(pose: Pose) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (part, transform, opacity) in targets(for: pose) {
            part.transform = transform
            part.opacity = opacity
        }
        for (layer, path) in shapes(for: pose) { layer.path = path }
        tail.zPosition = pose == .asleep ? 1 : 0
        openEyes.opacity = pose == .awake ? 1 : 0
        closedEyes.opacity = pose == .awake ? 0 : 1
        CATransaction.commit()
    }

    private func animatePose(_ pose: Pose, duration: CFTimeInterval, delay: CFTimeInterval) {
        // Explicit animations only; no implicit ones from setting the model values.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let begin = CACurrentMediaTime() + delay
        for (part, transform, opacity) in targets(for: pose) {
            let spring = CASpringAnimation(keyPath: "transform")
            spring.fromValue = part.presentation()?.transform ?? part.transform
            spring.toValue = transform
            spring.damping = 14
            spring.stiffness = 120
            spring.mass = 1
            spring.duration = max(duration, spring.settlingDuration)
            spring.beginTime = begin
            spring.fillMode = .backwards
            part.transform = transform
            part.add(spring, forKey: "pose")

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = part.presentation()?.opacity ?? part.opacity
            fade.toValue = opacity
            fade.duration = duration * 0.6
            fade.beginTime = begin
            fade.fillMode = .backwards
            part.opacity = opacity
            part.add(fade, forKey: "poseFade")
        }
        for (layer, path) in shapes(for: pose) {
            let morph = CAKeyframeAnimation(keyPath: "path")
            let from = layer.presentation()?.path ?? layer.path ?? path
            // The tail goes round the side of the body, not through it.
            let isTail = layer === tailOutline || layer === tailFur
            morph.values = isTail ? [from, Self.tailOut, path] : [from, path]
            morph.keyTimes = isTail ? [0, 0.38, 1] : [0, 1]
            morph.duration = duration
            morph.beginTime = begin
            morph.fillMode = .backwards
            morph.calculationMode = .cubic
            layer.path = path
            layer.add(morph, forKey: "pose")
        }
        // The tail swaps in front of or behind the body halfway through.
        let swap = CAKeyframeAnimation(keyPath: "zPosition")
        swap.values = [tail.zPosition, tail.zPosition, pose == .asleep ? 1 : 0]
        swap.keyTimes = [0, 0.38, 0.4]
        swap.duration = duration
        swap.beginTime = begin
        swap.fillMode = .backwards
        tail.zPosition = pose == .asleep ? 1 : 0
        tail.add(swap, forKey: "poseZ")
    }

    private func crossfadeEyes(open: Bool, delay: CFTimeInterval, duration: CFTimeInterval = 0.18) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for (eyes, visible) in [(openEyes, open), (closedEyes, !open)] {
            let target: Float = visible ? 1 : 0
            guard duration > 0 else {
                eyes.removeAllAnimations()
                eyes.opacity = target
                continue
            }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = eyes.presentation()?.opacity ?? eyes.opacity
            fade.toValue = target
            fade.duration = duration
            fade.beginTime = CACurrentMediaTime() + delay
            fade.fillMode = .backwards
            eyes.opacity = target
            eyes.add(fade, forKey: "eyes")
        }
    }

    private func removeAllPartAnimations() {
        let parts: [CALayer] = [body, head, tail, leftEar, rightEar, leftLeg, rightLeg, belly, openEyes,
                                closedEyes, breath, raisedLeg, legOutline, pawOutline, legFur, pawFur,
                                shoulderPatch, pawToes, tongue, yawn,
                                mouth, rig, bodyShape, bodyStripes, tailOutline, tailFur, sleepPaws]
        parts.forEach { $0.removeAllAnimations() }
    }

    // MARK: - Waking up

    /// Plays the wake-up on every moving part, as one timeline, and leaves the cat in
    /// the sitting pose. Returns its length.
    private func playWakeSequence() -> TimeInterval {
        let total: TimeInterval = 3.95
        func rot(_ angle: CGFloat) -> CATransform3D { CATransform3DMakeRotation(angle, 0, 0, 1) }
        func at(_ x: CGFloat, _ y: CGFloat, turned angle: CGFloat = 0) -> CATransform3D {
            CATransform3DConcat(rot(angle), CATransform3DMakeTranslation(x, y, 0))
        }
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)

        /// One keyframe track for `layer`, times in seconds from now.
        func track(_ layer: CALayer, _ keyPath: String, _ keys: [(TimeInterval, Any)]) {
            let anim = CAKeyframeAnimation(keyPath: keyPath)
            anim.values = keys.map { value -> Any in
                if let transform = value.1 as? CATransform3D { return NSValue(caTransform3D: transform) }
                return value.1
            }
            anim.keyTimes = keys.map { NSNumber(value: $0.0 / total) }
            anim.timingFunctions = Array(repeating: ease, count: max(1, keys.count - 1))
            anim.duration = total
            layer.add(anim, forKey: "wake")
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The model ends in the sitting pose; the tracks play the way there.
        apply(pose: .awake)

        let sleepingHead = Self.lyingHead
        let liftedHead = Self.headTransform(x: 7, y: 17.5, scale: 0.93)
        let yawningHead = Self.headTransform(x: 7, y: 16, turned: -0.1, scale: 0.93)

        // Ears: relaxed while asleep, perk up first thing, a twitch.
        track(leftEar, "transform", [(0, rot(-0.2)), (0.1, rot(-0.2)), (0.3, rot(0.1)), (0.45, rot(-0.04)),
                                     (0.6, CATransform3DIdentity), (total, CATransform3DIdentity)])
        track(rightEar, "transform", [(0, rot(0.2)), (0.15, rot(0.2)), (0.35, rot(-0.1)), (0.5, rot(0.04)),
                                      (0.65, CATransform3DIdentity), (total, CATransform3DIdentity)])

        // Head: lifts while lying, tips back to yawn, then rides up into the sit,
        // a beat behind the body, overshooting a touch.
        track(head, "transform", [
            (0, sleepingHead), (0.35, sleepingHead), (0.85, liftedHead), (1.1, liftedHead),
            (1.35, yawningHead), (1.95, yawningHead), (2.15, liftedHead),
            (2.45, Self.headTransform(x: 6, y: 18.5, scale: 0.94)),
            (3.2, at(0, -1.6)), (3.62, CATransform3DIdentity), (total, CATransform3DIdentity),
        ])

        // Body: stays curled, gathers itself, then the curl reshapes into the sit,
        // rising a little past it and settling.
        track(bodyShape, "path", [(0, Self.lyingBody), (2.4, Self.lyingBody),
                                  (3.12, Self.sittingBody), (total, Self.sittingBody)])
        track(bodyStripes, "path", [(0, Self.lyingStripes), (2.4, Self.lyingStripes),
                                    (3.12, Self.sittingStripes), (total, Self.sittingStripes)])
        track(body, "transform", [
            (0, CATransform3DIdentity), (2.22, CATransform3DIdentity),
            (2.42, CATransform3DMakeScale(1.03, 0.95, 1)),
            (3.15, CATransform3DMakeScale(0.98, 1.035, 1)), (3.6, CATransform3DIdentity),
            (total, CATransform3DIdentity),
        ])
        // Tail unwraps from round the front to its sitting curl, moving behind the
        // body on the way, with a little flick at the end.
        let sittingTail = Self.tailPath(curl: 0).cgPath
        for layer in [tailOutline, tailFur] {
            track(layer, "path", [(0, Self.lyingTail), (2.6, Self.lyingTail), (3.12, Self.tailOut),
                                  (3.45, Self.tailPath(curl: 0.5).cgPath), (3.8, sittingTail), (total, sittingTail)])
        }
        track(tailRoot, "opacity", [(0, 1.0), (2.6, 1.0), (2.85, 0.0), (total, 0.0)])
        // Goes behind the body only once it's fully out to the side, clear of the
        // (by then nearly sitting) body, so no part of it vanishes.
        track(tail, "zPosition", [(0, 1.0), (3.11, 1.0), (3.13, 0.0), (total, 0.0)])
        // The tucked paws give way to the front legs as it sits up.
        track(sleepPaws, "opacity", [(0, 1.0), (2.55, 1.0), (2.85, 0.0), (total, 0.0)])
        // Front legs and the light chest appear as it sits up.
        for part in [leftLeg, rightLeg, belly] {
            track(part, "opacity", [(0, 0.0), (2.75, 0.0), (3.15, 1.0), (total, 1.0)])
        }

        // Eyes: open sleepily, shut for the yawn, open again.
        let eyesOpen: [(TimeInterval, Any)] = [(0, 0.0), (0.5, 0.0), (0.65, 1.0), (1.15, 1.0), (1.22, 0.0),
                                               (1.95, 0.0), (2.05, 1.0), (total, 1.0)]
        track(openEyes, "opacity", eyesOpen)
        track(closedEyes, "opacity", eyesOpen.map { ($0.0, 1.0 - ($0.1 as! Double)) })
        // A big yawn while still lying down.
        track(yawn, "opacity", [(0, 0.0), (1.22, 0.0), (1.32, 1.0), (1.85, 1.0), (1.95, 0.0), (total, 0.0)])
        track(mouth, "opacity", [(0, 1.0), (1.22, 1.0), (1.3, 0.0), (1.88, 0.0), (1.95, 1.0), (total, 1.0)])
        CATransaction.commit()
        return total
    }

    // MARK: - Little movements

    private func twitchEars() {
        for (ear, direction) in [(leftEar, -1.0), (rightEar, 1.0)] as [(CALayer, CGFloat)] {
            let twitch = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            twitch.values = [0.2 * direction, -0.15 * direction, 0.08 * direction, 0]
            twitch.keyTimes = [0, 0.3, 0.65, 1]
            twitch.duration = 0.45
            twitch.isAdditive = false
            ear.add(twitch, forKey: "twitch")
        }
    }

    private func blink() {
        let squint = CAKeyframeAnimation(keyPath: "transform.scale.y")
        squint.values = [1, 0.1, 1]
        squint.keyTimes = [0, 0.45, 1]
        squint.duration = 0.18
        openEyes.add(squint, forKey: "blink")
    }

    /// A quick flick on top of the tail's lazy swaying.
    private func swayTail(duration: TimeInterval = 1.1) {
        let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        sway.values = [0, 0.24, -0.08, 0.12, 0]
        sway.keyTimes = [0, 0.3, 0.6, 0.82, 1]
        sway.duration = duration
        sway.isAdditive = true
        sway.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        tail.add(sway, forKey: "sway")
    }

    /// The sitting tail, from its base by the body round to the tip. `curl` bends
    /// the tip: 0 is the drawn shape, 1 curls it in, -1 lets it relax outwards.
    private static func tailPath(curl: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 44, y: 72))
        path.addQuadCurve(to: CGPoint(x: 24, y: 69), controlPoint: CGPoint(x: 32, y: 77))
        let tip = curl >= 0
            ? CGPoint(x: 22 + 5 * curl, y: 55 - 1.5 * curl)
            : CGPoint(x: 22 + 4 * curl, y: 55 + 3 * -curl)
        let control = curl >= 0
            ? CGPoint(x: 15 - 1.5 * curl, y: 63 - 3 * curl)
            : CGPoint(x: 15 + 0.5 * curl, y: 63 + 2 * -curl)
        path.addQuadCurve(to: tip, controlPoint: control)
        return path
    }

    /// While sitting: the tail sways lazily side to side and its tip curls and
    /// uncurls, on different rhythms so it never looks mechanical.
    private func startTailLoop(after delay: TimeInterval) {
        let begin = CACurrentMediaTime() + delay
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)

        let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        sway.values = [0, 0.1, 0.02, -0.05, 0.06, 0]
        sway.duration = 4.6
        sway.repeatCount = .infinity
        sway.isAdditive = true
        sway.timingFunctions = Array(repeating: ease, count: 5)
        sway.beginTime = begin
        tail.add(sway, forKey: "tailIdle")

        let curls: [CGFloat] = [0, 0.9, 0.2, -0.7, 0]
        let paths = curls.map { Self.tailPath(curl: $0).cgPath }
        for layer in [tailOutline, tailFur] {
            let curl = CAKeyframeAnimation(keyPath: "path")
            curl.values = paths
            curl.duration = 3.4
            curl.repeatCount = .infinity
            curl.timingFunctions = Array(repeating: ease, count: curls.count - 1)
            curl.beginTime = begin
            layer.add(curl, forKey: "tailCurl")
        }
    }

    private func stopTailLoop() {
        tail.removeAnimation(forKey: "tailIdle")
        tail.removeAnimation(forKey: "sway")
        tailOutline.removeAnimation(forKey: "tailCurl")
        tailFur.removeAnimation(forKey: "tailCurl")
    }

    // MARK: - Routine

    /// Runs `action` after `delay`, unless the cat has fallen asleep since `token`.
    private func after(_ delay: TimeInterval, _ token: Int, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.routineToken == token, self.pose == .awake else { return }
            action()
        }
    }

    /// While awake: a pause, then something small, now and then something bigger.
    private func idle(_ token: Int) {
        let pause = Double.random(in: 1.8...4.2)
        after(pause, token) { [weak self] in
            guard let self else { return }
            let roll = Int.random(in: 0..<100)
            let busy: TimeInterval
            switch roll {
            case ..<30: self.blink(); busy = 0.3
            case ..<48: self.swayTail(); busy = 1.4
            case ..<62: self.twitchEars(); busy = 0.5
            case ..<85: busy = self.lick()
            default: busy = self.stretch()
            }
            self.after(busy, token) { self.idle(token) }
        }
    }

    /// Stops anything in progress and freezes the cat where it is.
    private func stopActions() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        [breath, leftLeg, rightLeg, raisedLeg, tongue, yawn, mouth, body, openEyes, closedEyes].forEach {
            $0.removeAnimation(forKey: "action")
        }
        // A wake-up still in progress.
        [body, head, tail, leftEar, rightEar, leftLeg, rightLeg, belly, openEyes, closedEyes, yawn, mouth,
         bodyShape, bodyStripes, tailOutline, tailFur, tailRoot, sleepPaws]
            .forEach { $0.removeAnimation(forKey: "wake") }
        head.removeAnimation(forKey: "action")
        [raisedLeg, legOutline, pawOutline, legFur, pawFur, shoulderPatch, pawToes]
            .forEach { $0.removeAllAnimations() }
        raisedLeg.opacity = 0
        breath.opacity = 1
        tongue.opacity = 0
        yawn.opacity = 0
        mouth.opacity = 1
        CATransaction.commit()
    }

    // MARK: - Stretch

    /// Rises up tall with a big yawn, eyes squeezed shut, then settles. Returns its length.
    @discardableResult
    private func stretch() -> TimeInterval {
        let duration: TimeInterval = 2.0
        let times: [NSNumber] = [0, 0.25, 0.7, 1]

        let rise = CAKeyframeAnimation(keyPath: "transform")
        rise.values = [
            CATransform3DIdentity,
            CATransform3DMakeScale(0.93, 1.12, 1),
            CATransform3DMakeScale(0.93, 1.12, 1),
            CATransform3DIdentity,
        ].map { NSValue(caTransform3D: $0) }
        rise.keyTimes = times
        rise.duration = duration
        rise.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 3)
        body.add(rise, forKey: "action")

        // The head rides up with the body and tips back for the yawn.
        let lift = CAKeyframeAnimation(keyPath: "transform")
        let up = CATransform3DConcat(CATransform3DMakeRotation(-0.06, 0, 0, 1), CATransform3DMakeTranslation(0, -4.5, 0))
        lift.values = [CATransform3DIdentity, up, up, CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
        lift.keyTimes = times
        lift.duration = duration
        lift.timingFunctions = rise.timingFunctions
        head.add(lift, forKey: "action")

        showDuringAction(yawn, from: 0.22, to: 0.72, duration: duration)
        hideDuringAction(mouth, from: 0.22, to: 0.72, duration: duration)
        hideDuringAction(openEyes, from: 0.2, to: 0.75, duration: duration)
        showDuringAction(closedEyes, from: 0.2, to: 0.75, duration: duration)
        return duration
    }

    // MARK: - Lick

    /// Lifts the left front paw to the mouth, bending at elbow and wrist, licks it
    /// three times with the head tilted down to it, then puts it back. The limb is
    /// posed from joint angles at many moments, so the paw travels in an arc.
    @discardableResult
    private func lick() -> TimeInterval {
        let duration: TimeInterval = 3.2
        let raiseEnd = 0.24, lowerStart = 0.84
        let licks = (0..<3).map { 0.33 + Double($0) * 0.16 }   // when each lick lands

        func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        /// 0 at rest, 1 with the paw at the mouth.
        func raise(_ t: Double) -> Double {
            if t < 0.04 { return 0 }
            if t < raiseEnd { return smooth((t - 0.04) / (raiseEnd - 0.04)) }
            if t < lowerStart { return 1 }
            if t < 0.97 { return 1 - smooth((t - lowerStart) / (0.97 - lowerStart)) }
            return 0
        }
        /// A short pulse around each lick: the tongue pushes the paw and the head dips.
        func lickPulse(_ t: Double) -> Double {
            licks.map { max(0, 1 - abs(t - $0) / 0.06) }.max() ?? 0
        }

        let samples = 64
        let times = (0...samples).map { Double($0) / Double(samples) }
        var frames: [LegPose.Shapes] = [], heads: [NSValue] = []
        for t in times {
            let r = raise(t), pulse = lickPulse(t)
            frames.append(LegPose.raised(CGFloat(r)).licked(CGFloat(pulse)).shapes())

            // Head tilts down towards the paw, with a little nod on each lick.
            let tilt = CGFloat(-0.17 * smooth(min(1, r * 1.15)) - 0.04 * pulse)
            let dip = CGFloat(2.4 * r + 0.8 * pulse)
            heads.append(NSValue(caTransform3D: CATransform3DConcat(
                CATransform3DMakeRotation(tilt, 0, 0, 1),
                CATransform3DMakeTranslation(CGFloat(-1.2 * r), dip, 0)
            )))
        }
        let keyTimes = times.map { NSNumber(value: $0) }
        func animate(_ layer: CALayer, _ keyPath: String, _ values: [Any]) {
            let anim = CAKeyframeAnimation(keyPath: keyPath)
            anim.values = values
            anim.keyTimes = keyTimes
            anim.duration = duration
            layer.add(anim, forKey: "lift" + keyPath)
        }
        animate(legOutline, "path", frames.map(\.leg))
        animate(legFur, "path", frames.map(\.leg))
        animate(legOutline, "lineWidth", frames.map { $0.width + 3.8 })
        animate(legFur, "lineWidth", frames.map(\.width))
        animate(pawOutline, "path", frames.map(\.pawOutline))
        animate(pawFur, "path", frames.map(\.pawFur))
        animate(shoulderPatch, "path", frames.map(\.shoulderPatch))
        animate(pawToes, "path", frames.map(\.toes))
        let headAnim = CAKeyframeAnimation(keyPath: "transform")
        headAnim.values = heads
        headAnim.keyTimes = keyTimes
        headAnim.duration = duration
        head.add(headAnim, forKey: "action")

        // The jointed leg takes over from the drawn line just as it starts to move.
        showDuringAction(raisedLeg, from: 0.02, to: 0.975, duration: duration, fade: 0.02)
        hideDuringAction(leftLeg, from: 0.025, to: 0.97, duration: duration, fade: 0.015)

        // Tongue out for each lick.
        let flick = CAKeyframeAnimation(keyPath: "opacity")
        var flickValues: [Double] = [0], flickTimes: [Double] = [0]
        for at in licks {
            flickValues += [0, 1, 1, 0]
            flickTimes += [at - 0.05, at - 0.025, at + 0.02, at + 0.05]
        }
        flickValues.append(0); flickTimes.append(1)
        flick.values = flickValues
        flick.keyTimes = flickTimes.map { NSNumber(value: $0) }
        flick.duration = duration
        tongue.add(flick, forKey: "action")

        hideDuringAction(openEyes, from: 0.16, to: 0.9, duration: duration)
        showDuringAction(closedEyes, from: 0.16, to: 0.9, duration: duration)
        return duration
    }

    // MARK: - Helpers for actions

    /// Fades `layer` in at `from` and out at `to` (fractions of `duration`).
    private func showDuringAction(_ layer: CALayer, from: Double, to: Double,
                                  duration: TimeInterval, fade: Double = 0.04) {
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [0, 0, 1, 1, 0, 0]
        anim.keyTimes = [0, from, from + fade, to - fade, to, 1].map { NSNumber(value: $0) }
        anim.duration = duration
        layer.add(anim, forKey: "action")
    }

    /// Fades `layer` out at `from` and back in at `to`.
    private func hideDuringAction(_ layer: CALayer, from: Double, to: Double,
                                  duration: TimeInterval, fade: Double = 0.04) {
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = [1, 1, 0, 0, 1, 1]
        anim.keyTimes = [0, from, from + fade, to - fade, to, 1].map { NSNumber(value: $0) }
        anim.duration = duration
        layer.add(anim, forKey: "action")
    }

    private func startSleepLoops() {
        let breathing = CABasicAnimation(keyPath: "transform.scale.y")
        breathing.fromValue = 1
        breathing.toValue = 1.035
        breathing.duration = 1.7
        breathing.autoreverses = true
        breathing.repeatCount = .infinity
        breathing.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        breath.add(breathing, forKey: "breathing")

        snoreTimer?.invalidate()
        snoreTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { [weak self] _ in
            self?.floatZ()
        }
    }

    private func apply(_ shapes: LegPose.Shapes) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        legOutline.path = shapes.leg
        legFur.path = shapes.leg
        legOutline.lineWidth = shapes.width + 3.8
        legFur.lineWidth = shapes.width
        pawOutline.path = shapes.pawOutline
        pawFur.path = shapes.pawFur
        shoulderPatch.path = shapes.shoulderPatch
        pawToes.path = shapes.toes
        CATransaction.commit()
    }

    /// Slow, small breathing while sitting up: the chest rises a little.
    private func startAwakeBreathing(after delay: TimeInterval) {
        let breathe = CABasicAnimation(keyPath: "transform.scale.y")
        breathe.fromValue = 1
        breathe.toValue = 1.018
        breathe.duration = 2.1
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.isAdditive = false
        breathe.beginTime = CACurrentMediaTime() + delay
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        body.add(breathe, forKey: "awakeBreath")
    }

    private func stopSleepLoops() {
        breath.removeAnimation(forKey: "breathing")
        snoreTimer?.invalidate()
        snoreTimer = nil
    }

    /// A small "z" drifting up and away from the sleeping head.
    private func floatZ() {
        let z = CATextLayer()
        z.string = "z"
        z.font = UIFont.systemFont(ofSize: 9, weight: .heavy)
        z.fontSize = 9
        z.foregroundColor = UIColor.pnPrimary.withAlphaComponent(0.55).cgColor
        z.contentsScale = UIScreen.main.scale * 2
        z.alignmentMode = .center
        z.frame = CGRect(x: 90, y: 30, width: 10, height: 12)
        z.opacity = 0
        rig.addSublayer(z)

        let rise = CABasicAnimation(keyPath: "position")
        rise.fromValue = CGPoint(x: 92, y: 42)
        rise.toValue = CGPoint(x: 104, y: 16)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.2, 0.7, 1]
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.7
        grow.toValue = 1.25

        let group = CAAnimationGroup()
        group.animations = [rise, fade, grow]
        group.duration = 2.4
        group.isRemovedOnCompletion = true
        CATransaction.begin()
        CATransaction.setCompletionBlock { z.removeFromSuperlayer() }
        z.add(group, forKey: "float")
        CATransaction.commit()
    }

    // MARK: - Helpers

    /// Moves a full-canvas layer's anchor to `point` without moving its content.
    private func setAnchor(_ layer: CALayer, to point: CGPoint) {
        let size = Self.canvas
        layer.anchorPoint = CGPoint(x: point.x / size.width, y: point.y / size.height)
        layer.position = point
    }

    private func strokes(_ segments: [(CGPoint, CGPoint)]) -> UIBezierPath {
        let path = UIBezierPath()
        for (from, to) in segments {
            path.move(to: from)
            path.addLine(to: to)
        }
        return path
    }

    private func polygon(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.close()
        return path
    }

    private func styleStroke(_ layer: CAShapeLayer, width: CGFloat) {
        layer.fillColor = nil
        layer.lineWidth = width
        layer.lineCap = .round
        layer.lineJoin = .round
    }
}

// MARK: - Jointed front leg

/// The left front leg as joint angles (radians, 0 = pointing right, π/2 = down) and
/// segment lengths, in the cat's design space. Lengths shrink when a segment points
/// at the viewer. Poses blend by their angles, so the paw moves along an arc.
private struct LegPose {
    var upperAngle: CGFloat, upperLength: CGFloat
    var foreAngle: CGFloat, foreLength: CGFloat
    /// The paw's bend at the wrist, relative to the forearm.
    var pawBend: CGFloat
    /// Width of the leg's fur; a leg raised towards the viewer looks chunkier.
    var width: CGFloat

    static let shoulder = CGPoint(x: 50.3, y: 57)
    /// Hanging straight down; its right edge falls on the drawn leg line.
    static let rest = LegPose(upperAngle: .pi / 2, upperLength: 8, foreAngle: .pi / 2, foreLength: 7,
                              pawBend: 0, width: 5.5)
    /// Elbow out, forearm pointing at the viewer (so it looks short): the paw lifted
    /// forward at belly height.
    static let lifted = LegPose(upperAngle: 2.3, upperLength: 6.2, foreAngle: -0.3, foreLength: 2.5,
                                pawBend: 0.4, width: 6.4)
    /// Elbow low, forearm reaching up across the chest, paw curled in under the mouth.
    static let atMouth = LegPose(upperAngle: 2.27, upperLength: 6.6, foreAngle: -1.25, foreLength: 19,
                                 pawBend: 0.65, width: 6.8)

    /// Rest at 0, lifted at 0.5, at the mouth at 1.
    static func raised(_ t: CGFloat) -> LegPose {
        t < 0.5 ? lerp(rest, lifted, t * 2) : lerp(lifted, atMouth, (t - 0.5) * 2)
    }

    static func lerp(_ a: LegPose, _ b: LegPose, _ t: CGFloat) -> LegPose {
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        return LegPose(upperAngle: mix(a.upperAngle, b.upperAngle), upperLength: mix(a.upperLength, b.upperLength),
                       foreAngle: mix(a.foreAngle, b.foreAngle), foreLength: mix(a.foreLength, b.foreLength),
                       pawBend: mix(a.pawBend, b.pawBend), width: mix(a.width, b.width))
    }

    /// The tongue pushing the paw: it tips back a little at the wrist.
    func licked(_ amount: CGFloat) -> LegPose {
        var pose = self
        pose.pawBend -= 0.35 * amount
        pose.foreAngle -= 0.05 * amount
        return pose
    }

    struct Shapes {
        /// Centre line from shoulder through the elbow to the wrist, for the strokes.
        let leg: CGPath
        let width: CGFloat
        let pawOutline: CGPath
        let pawFur: CGPath
        let shoulderPatch: CGPath
        let toes: CGPath
    }

    /// Every pose gives paths of the same structure, so they animate into each other.
    func shapes() -> Shapes {
        func point(_ from: CGPoint, _ angle: CGFloat, _ length: CGFloat) -> CGPoint {
            CGPoint(x: from.x + cos(angle) * length, y: from.y + sin(angle) * length)
        }
        func circle(_ center: CGPoint, _ radius: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                     width: radius * 2, height: radius * 2), transform: nil)
        }
        let shoulder = Self.shoulder
        let elbow = point(shoulder, upperAngle, upperLength)
        let wrist = point(elbow, foreAngle, foreLength)

        // A soft bend at the elbow.
        let leg = CGMutablePath()
        leg.move(to: shoulder)
        leg.addQuadCurve(to: wrist, control: elbow)

        let pawAngle = foreAngle + pawBend
        let pawRadius = width * 0.56
        let pawCenter = point(wrist, pawAngle, pawRadius * 0.45)

        let toes = CGMutablePath()
        for side in [-1.0, 1.0] as [CGFloat] {
            let base = point(pawCenter, pawAngle, pawRadius * 0.95)
            let start = CGPoint(x: base.x - sin(pawAngle) * side * 1.2, y: base.y + cos(pawAngle) * side * 1.2)
            toes.move(to: start)
            toes.addLine(to: point(start, pawAngle + .pi, 1.6))
        }

        return Shapes(
            leg: leg,
            width: width,
            pawOutline: circle(pawCenter, pawRadius + 1.9),
            pawFur: circle(pawCenter, pawRadius),
            shoulderPatch: circle(shoulder, width / 2 + 2.2),
            toes: toes
        )
    }
}
