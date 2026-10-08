import SwiftUI

// Run from the repository root:
// swiftc -warnings-as-errors -swift-version 5 -module-cache-path .build/module-cache \
//   Sources/TypefieldTourCurve.swift tests/tour-curve-geometry.swift -o /tmp/typefield-tour-curve-checks
// /tmp/typefield-tour-curve-checks
@main
enum TourCurveGeometryChecks {
    static let frame = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func main() {
        var configurations = 0
        let values: [CGFloat] = [0, 0.5, 1]
        for x in values { for y in values {
            for ux in values { for uy in values {
                for lx in values { for ly in values {
                    var geometry = TourCurveGeometry()
                    geometry.move(.anchor, to: CGPoint(x: 0.67 + x * 0.12, y: 0.35 + y * 0.14))
                    geometry.move(.upperHandle, to: CGPoint(x: geometry.anchor.x - 0.08 + ux * 0.16,
                                                           y: geometry.anchor.y - 0.24 + uy * 0.12))
                    geometry.move(.lowerHandle, to: CGPoint(x: geometry.anchor.x - 0.08 + lx * 0.16,
                                                           y: geometry.anchor.y + 0.12 + ly * 0.12))
                    checkContours(geometry)
                    configurations += 1
                }}
            }}
        }}

        var geometry = TourCurveGeometry()
        geometry.move(.upperHandle, to: CGPoint(x: 0.69, y: 0.17))
        geometry.move(.lowerHandle, to: CGPoint(x: 0.81, y: 0.55))
        let initial = geometry
        geometry.move(.anchor, to: CGPoint(x: -10, y: 10))
        require(near(geometry.anchor, CGPoint(x: 0.67, y: 0.49)), "Anchor must stop at both demo bounds")
        require(near(offset(geometry.upperHandle, geometry.anchor), offset(initial.upperHandle, initial.anchor)), "Moving anchor must translate upper handle exactly")
        require(near(offset(geometry.lowerHandle, geometry.anchor), offset(initial.lowerHandle, initial.anchor)), "Moving anchor must translate lower handle exactly")

        let beforeUpper = geometry
        geometry.move(.upperHandle, to: CGPoint(x: 10, y: -10))
        require(geometry.anchor == beforeUpper.anchor && geometry.lowerHandle == beforeUpper.lowerHandle,
                "Upper handle must not move anchor or lower handle")
        require(geometry.upperHandle != beforeUpper.upperHandle &&
                geometry.outline(in: frame) != beforeUpper.outline(in: frame), "Upper handle must change actual outline")
        let beforeLower = geometry
        geometry.move(.lowerHandle, to: CGPoint(x: -10, y: 10))
        require(geometry.anchor == beforeLower.anchor && geometry.upperHandle == beforeLower.upperHandle,
                "Lower handle must not move anchor or upper handle")
        require(geometry.lowerHandle != beforeLower.lowerHandle &&
                geometry.outline(in: frame) != beforeLower.outline(in: frame), "Lower handle must change actual outline")
        checkContours(geometry)
        let finite = geometry
        geometry.move(.anchor, to: CGPoint(x: CGFloat.nan, y: 0.4))
        geometry.move(.upperHandle, to: CGPoint(x: 0.7, y: CGFloat.infinity))
        require(geometry == finite, "Nonfinite input must leave geometry intact")

        // Deterministic out-of-bounds drags exercise cumulative translations and
        // handle clamps, including repeated movement in and out of the canvas.
        var seed: UInt64 = 0x747970656669656c
        for index in 0..<2_000 {
            func random() -> CGFloat {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                return CGFloat(seed >> 11) / CGFloat(UInt64.max >> 11)
            }
            geometry.move(TourCurveControl.allCases[index % 3], to: CGPoint(x: random() * 2 - 0.5, y: random() * 2 - 0.5))
            checkContours(geometry)
        }

        let size = CGSize(width: 354, height: 180)
        for control in TourCurveControl.allCases {
            let point = geometry.point(control)
            let center = CGPoint(x: point.x * size.width, y: point.y * size.height)
            require(geometry.nearestControl(to: center, in: size) == control, "Overlapping targets must prefer nearest point")
        }
        require(geometry.nearestControl(to: .zero, in: size) == nil, "Empty canvas must not grab a distant point")
        require(geometry.nearestControl(to: .zero, in: .zero) == nil, "Zero-sized canvas must not create a drag")
        print("PASS tour curve: \(configurations) bounded configurations, 2,000 deterministic drags, counter containment, contour intersections, independent handles, translation and hit testing")
    }

    static func checkContours(_ geometry: TourCurveGeometry) {
        let outer = flatten(geometry.outerOutline(in: frame))
        let counter = flatten(geometry.counterOutline(in: frame))
        require(outer.first == outer.last && counter.first == counter.last, "Both contours must stay closed")
        require(abs(area(outer)) > 0.10 && abs(area(counter)) > 0.01, "Letter and counter must retain useful area")
        require(!intersectsItself(outer) && !intersectsItself(counter), "Contour must not cross itself")
        for point in outer + counter {
            require(point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y), "Outline must stay within demo bounds")
        }
        // CoreGraphics containment flattens curves in point units; use a large
        // frame so its tolerance cannot exceed the normalized stroke widths.
        let testFrame = CGRect(x: 0, y: 0, width: 1_024, height: 1_024)
        let outerPath = geometry.outerOutline(in: testFrame).cgPath
        for point in counter {
            require(outerPath.contains(CGPoint(x: point.x * 1_024, y: point.y * 1_024)), "Counter escaped at \(point): \(geometry)")
        }
        let outline = geometry.outline(in: testFrame).cgPath
        require(!outline.contains(CGPoint(x: 0.46 * 1_024, y: 0.40 * 1_024), using: .evenOdd), "Counter must remain unfilled: \(geometry)")
        require(outline.contains(CGPoint(x: 0.33 * 1_024, y: 0.70 * 1_024), using: .evenOdd), "Stem must retain its ink")
    }

    // Sample the produced paths, rather than a duplicate of the model's shape.
    static func flatten(_ path: Path) -> [CGPoint] {
        var result: [CGPoint] = []
        var start = CGPoint.zero
        path.forEach { element in
            switch element {
            case .move(to: let point): start = point; result.append(point)
            case .line(to: let point): result.append(point)
            case .curve(to: let end, control1: let c1, control2: let c2):
                let begin = result.last!
                for step in 1...48 {
                    let t = CGFloat(step) / 48, u = 1 - t
                    result.append(CGPoint(x: u * u * u * begin.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * end.x,
                                          y: u * u * u * begin.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * end.y))
                }
            case .closeSubpath: result.append(start)
            case .quadCurve: fatalError("Unexpected quadratic curve")
            }
        }
        return result
    }

    static func intersectsItself(_ points: [CGPoint]) -> Bool {
        func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        let segmentCount = points.count - 1
        for first in 0..<segmentCount {
            guard first + 2 < segmentCount else { continue }
            for second in (first + 2)..<segmentCount {
                if first == 0 && second == segmentCount - 1 { continue }
                let a = points[first], b = points[first + 1], c = points[second], d = points[second + 1]
                if cross(a, b, c) * cross(a, b, d) < -1e-15 && cross(c, d, a) * cross(c, d, b) < -1e-15 { return true }
            }
        }
        return false
    }

    static func area(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y } / 2
    }
    static func offset(_ point: CGPoint, _ origin: CGPoint) -> CGPoint { CGPoint(x: point.x - origin.x, y: point.y - origin.y) }
    static func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 1e-12 && abs(a.y - b.y) < 1e-12 }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
