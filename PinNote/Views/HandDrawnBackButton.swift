import UIKit

/// The back button as a brush-painted "<": both strokes start heavy and round at
/// the point and run out into dry-brush bristles at their ends. Painted in the
/// button's tint colour.
final class HandDrawnBackButton: UIButton {

    private let arrow = CAShapeLayer()
    /// The arrow's size inside the (larger) tap area.
    private let arrowSize = CGSize(width: 15.5, height: 25)

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(arrow)
        accessibilityLabel = NSLocalizedString("Back", comment: "")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rect = CGRect(
            x: bounds.midX - arrowSize.width / 2 - 1,
            y: bounds.midY - arrowSize.height / 2,
            width: arrowSize.width,
            height: arrowSize.height
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arrow.frame = bounds
        arrow.path = Self.arrowPath(in: rect)
        CATransaction.commit()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        arrow.fillColor = tintColor.cgColor
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) { self.alpha = self.isHighlighted ? 0.4 : 1 }
        }
    }

    /// Two brush strokes from the point out to the upper and lower ends.
    static func arrowPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        let tip = point(0.02, 0.5)
        // Each stroke bows very slightly, as a hand-drawn line does.
        let strokes: [(end: CGPoint, bow: CGPoint)] = [
            (point(0.92, 0.0), point(0.44, 0.27)),
            (point(1.0, 1.0), point(0.5, 0.74)),
        ]

        for (index, stroke) in strokes.enumerated() {
            let points = HandDrawnCheckbox.sample([.quad(tip, stroke.bow, stroke.end)], step: h / 60)
            let wobble = CGFloat(index) * 1.7

            // Body: heavy and round at the point, thinning out towards the end.
            HandDrawnCheckbox.addStroke(along: Array(points.prefix(Int(Double(points.count) * 0.9))), to: path) { t in
                let taper = 1 - pow(t, 1.4) * 0.88
                return h * 0.15 * taper * (1 + 0.03 * sin(t * 17 + wobble))
            }

            // Dry-brush end: fine bristles within the stroke's width, each running
            // out at a different point, so the end frays.
            let bristles: [(offset: CGFloat, from: Double, to: Double, width: CGFloat)] = [
                (-0.044, 0.5, 0.92, 0.026), (-0.018, 0.55, 1.0, 0.034),
                (0.008, 0.52, 0.97, 0.029), (0.031, 0.48, 0.88, 0.023), (0.05, 0.46, 0.8, 0.018),
            ]
            for bristle in bristles {
                let from = Int(Double(points.count - 1) * bristle.from)
                let to = Int(Double(points.count - 1) * bristle.to)
                guard to > from + 1 else { continue }
                let slice = Array(points[from...to])
                let dx = stroke.end.x - tip.x, dy = stroke.end.y - tip.y
                let length = max(hypot(dx, dy), 0.001)
                let normal = CGPoint(x: -dy / length * h * bristle.offset, y: dx / length * h * bristle.offset)
                let shifted = slice.map { CGPoint(x: $0.x + normal.x, y: $0.y + normal.y) }
                HandDrawnCheckbox.addStroke(along: shifted, to: path) { t in
                    h * bristle.width * (1 - t * 0.85)
                }
            }
        }
        return path
    }
}
