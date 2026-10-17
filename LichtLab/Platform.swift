import SceneKit

#if os(iOS)
import UIKit
typealias PlatformColor = UIColor
typealias PlatformBezierPath = UIBezierPath
typealias SCNFloat = Float
#else
import AppKit
typealias PlatformColor = NSColor
typealias PlatformBezierPath = NSBezierPath
typealias SCNFloat = CGFloat
#endif

func v3(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
    SCNVector3(x: SCNFloat(x), y: SCNFloat(y), z: SCNFloat(z))
}

extension PlatformColor {
    convenience init(rgb: (r: Double, g: Double, b: Double), scale: Double = 1) {
        self.init(red: CGFloat(rgb.r * scale), green: CGFloat(rgb.g * scale), blue: CGFloat(rgb.b * scale), alpha: 1)
    }
}

/// Bézierpfade plattformunabhängig bauen (UIBezierPath / NSBezierPath).
struct PathBuilder {
    let path = PlatformBezierPath()
    private var current = CGPoint.zero

    mutating func move(_ p: CGPoint) {
        path.move(to: p)
        current = p
    }

    mutating func quad(to p: CGPoint, control c: CGPoint) {
        #if os(iOS)
        path.addQuadCurve(to: p, controlPoint: c)
        #else
        let c1 = CGPoint(x: current.x + 2 / 3 * (c.x - current.x), y: current.y + 2 / 3 * (c.y - current.y))
        let c2 = CGPoint(x: p.x + 2 / 3 * (c.x - p.x), y: p.y + 2 / 3 * (c.y - p.y))
        path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
        #endif
        current = p
    }

    func close() { path.close() }

    /// Geschlossene, weich gerundete Form durch die Mittelpunkte der Kanten.
    static func smoothClosed(_ points: [CGPoint]) -> PlatformBezierPath {
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var builder = PathBuilder()
        builder.move(mid(points[points.count - 1], points[0]))
        for i in points.indices {
            builder.quad(to: mid(points[i], points[(i + 1) % points.count]), control: points[i])
        }
        builder.close()
        builder.path.flatness = 0.004
        return builder.path
    }
}

enum Haptics {
    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func confirm() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
