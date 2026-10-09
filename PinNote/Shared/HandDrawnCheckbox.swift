import CoreGraphics
import Foundation

/// A checkbox that looks painted with a brush: every line is a filled outline whose
/// width swells and tapers along the stroke. The box stays open at the top right,
/// wider when checked so the check can fly out through the gap.
///
/// The check reaches slightly beyond `rect` (up and to the right), like the original
/// drawing, so don't clip the result to `rect`.
enum HandDrawnCheckbox {

    /// Filled outlines of the box and, when `checked`, the check. Fill with the
    /// non-zero rule (the default for UIKit, SwiftUI and Core Graphics).
    static func path(in rect: CGRect, checked: Bool) -> CGPath {
        let path = CGMutablePath()
        let size = min(rect.width, rect.height)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        // An empty box is nearly closed; a checked one opens wider for the check.
        let topStart: CGFloat = checked ? 0.62 : 0.8
        let rightEnd: CGFloat = checked ? 0.4 : 0.22
        let box = sample([
            .line(point(topStart, 0.035), point(0.16, 0.045)),
            .quad(point(0.16, 0.045), point(0.035, 0.04), point(0.035, 0.17)),
            .line(point(0.035, 0.17), point(0.03, 0.84)),
            .quad(point(0.03, 0.84), point(0.035, 0.97), point(0.16, 0.965)),
            .line(point(0.16, 0.965), point(0.84, 0.97)),
            .quad(point(0.84, 0.97), point(0.97, 0.975), point(0.965, 0.85)),
            .line(point(0.965, 0.85), point(0.96, rightEnd)),
        ], step: size / 40)
        addStroke(along: box, to: path) { t in
            let entry = min(1, 0.4 + t / 0.06 * 0.6)
            let exit = t > 0.86 ? max(0.3, 1 - (t - 0.86) / 0.14 * 0.7) : 1
            let wobble = 1 + 0.1 * sin(t * 26) + 0.05 * sin(t * 61)
            return size * 0.1 * entry * exit * wobble
        }

        guard checked else { return path }

        // Short heavy downstroke, then a long stroke that thins to a point.
        let downstroke = sample([.quad(point(0.16, 0.48), point(0.29, 0.58), point(0.4, 0.77))], step: size / 40)
        addStroke(along: downstroke, to: path) { t in size * (0.12 + 0.06 * t) }

        let upstroke = sample([.quad(point(0.4, 0.77), point(0.62, 0.36), point(1.06, -0.04))], step: size / 40)
        addStroke(along: upstroke, to: path) { t in size * (0.18 * pow(1 - t, 0.85) + 0.012) }

        return path
    }

    // MARK: - Brush strokes

    private enum Segment {
        case line(CGPoint, CGPoint)
        case quad(CGPoint, CGPoint, CGPoint)
    }

    /// Points about `step` apart along contiguous segments.
    private static func sample(_ segments: [Segment], step: CGFloat) -> [CGPoint] {
        var points: [CGPoint] = []
        for segment in segments {
            let (start, control, end): (CGPoint, CGPoint, CGPoint)
            switch segment {
            case let .line(from, to):
                (start, control, end) = (from, CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2), to)
            case let .quad(from, c, to):
                (start, control, end) = (from, c, to)
            }
            let length = hypot(control.x - start.x, control.y - start.y) + hypot(end.x - control.x, end.y - control.y)
            let count = max(2, Int(length / max(step, 0.1)))
            for i in (points.isEmpty ? 0 : 1)...count {
                let t = CGFloat(i) / CGFloat(count)
                let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t
                points.append(CGPoint(
                    x: a * start.x + b * control.x + c * end.x,
                    y: a * start.y + b * control.y + c * end.y
                ))
            }
        }
        return points
    }

    /// Adds one closed outline: the left edge forward, a round cap, the right edge
    /// back and a round cap. Every stroke winds the same way, so overlapping strokes
    /// fill solid under the non-zero rule. `width` receives progress 0...1.
    private static func addStroke(along points: [CGPoint], to path: CGMutablePath, width: (CGFloat) -> CGFloat) {
        guard points.count > 1 else { return }

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        var normalAngles: [CGFloat] = []
        var halfWidths: [CGFloat] = []
        for (index, point) in points.enumerated() {
            let previous = points[max(0, index - 1)]
            let next = points[min(points.count - 1, index + 1)]
            let dx = next.x - previous.x, dy = next.y - previous.y
            let length = max(hypot(dx, dy), 0.0001)
            let normal = CGPoint(x: -dy / length, y: dx / length)
            let half = width(CGFloat(index) / CGFloat(points.count - 1)) / 2
            left.append(CGPoint(x: point.x + normal.x * half, y: point.y + normal.y * half))
            right.append(CGPoint(x: point.x - normal.x * half, y: point.y - normal.y * half))
            normalAngles.append(atan2(normal.y, normal.x))
            halfWidths.append(half)
        }

        func addCap(around center: CGPoint, from angle: CGFloat, radius: CGFloat) {
            let steps = 8
            for step in 1..<steps {
                let a = angle - .pi * CGFloat(step) / CGFloat(steps)
                path.addLine(to: CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius))
            }
        }

        let last = points.count - 1
        path.move(to: left[0])
        left.dropFirst().forEach { path.addLine(to: $0) }
        addCap(around: points[last], from: normalAngles[last], radius: halfWidths[last])
        right.reversed().forEach { path.addLine(to: $0) }
        addCap(around: points[0], from: normalAngles[0] + .pi, radius: halfWidths[0])
        path.closeSubpath()
    }
}
