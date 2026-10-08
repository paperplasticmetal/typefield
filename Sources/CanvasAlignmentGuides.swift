import Foundation
import CoreGraphics

/// All geometry is in canvas coordinates; the attraction distance is measured
/// in view points so zooming never creates a coarser or finer snapping grid.
struct CanvasAlignmentTarget {
    var id: String
    var rect: CGRect
}
struct CanvasAlignmentGuide: Equatable {
    enum Axis { case vertical, horizontal }
    var axis: Axis
    var position: CGFloat
    var start: CGFloat
    var end: CGFloat
    var canvas: Bool
}
struct CanvasAlignmentResult {
    var rect: CGRect
    var guides: [CanvasAlignmentGuide]
}
enum CanvasAlignmentGuides {
    static let attractionDistance: CGFloat = 6
    private struct Reference {
        var rect: CGRect
        var canvas: Bool
    }
    private static func references(canvas: CGSize, objects: [CanvasAlignmentTarget], selected: Set<String>) -> [Reference] {
        [Reference(rect: CGRect(origin: .zero, size: canvas), canvas: true)] + objects.compactMap { object in
            guard !selected.contains(object.id), valid(object.rect) else { return nil }
            return Reference(rect: object.rect, canvas: false)
        }
    }
    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && [rect.minX, rect.minY, rect.width, rect.height].allSatisfy { $0.isFinite } && rect.width > 0 && rect.height > 0
    }
    private static func values(_ rect: CGRect, axis: CanvasAlignmentGuide.Axis) -> [CGFloat] {
        axis == .vertical ? [rect.minX, rect.midX, rect.maxX] : [rect.minY, rect.midY, rect.maxY]
    }
    /// A stable nearest match, with canvas references first on exact ties. No
    /// accumulated drag offset is kept, so leaving a guide follows the pointer.
    private static func correction(anchors: [CGFloat], axis: CanvasAlignmentGuide.Axis, references: [Reference], tolerance: CGFloat, allowed: ClosedRange<CGFloat>) -> CGFloat {
        var best: CGFloat?
        for reference in references {
            for target in values(reference.rect, axis: axis) {
                for anchor in anchors {
                    let delta = target - anchor
                    guard abs(delta) <= tolerance, allowed.contains(delta) else { continue }
                    if best == nil || abs(delta) < abs(best!) - 0.00001 { best = delta }
                }
            }
        }
        return best ?? 0
    }
    private static func guides(rect: CGRect, references: [Reference], axes: [CanvasAlignmentGuide.Axis], zoom: CGFloat) -> [CanvasAlignmentGuide] {
        var result: [CanvasAlignmentGuide] = []
        let padding = 8 / max(0.01, zoom)
        for axis in axes {
            for reference in references {
                for position in values(reference.rect, axis: axis) where values(rect, axis: axis).contains(where: { abs($0 - position) < 0.00001 }) {
                    let union = rect.union(reference.rect)
                    let start = (axis == .vertical ? union.minY : union.minX) - (reference.canvas ? 0 : padding)
                    let end = (axis == .vertical ? union.maxY : union.maxX) + (reference.canvas ? 0 : padding)
                    if let index = result.firstIndex(where: { $0.axis == axis && abs($0.position - position) < 0.00001 }) {
                        result[index].start = min(result[index].start, start)
                        result[index].end = max(result[index].end, end)
                        result[index].canvas = result[index].canvas || reference.canvas
                    } else {
                        result.append(CanvasAlignmentGuide(axis: axis, position: position, start: start, end: end, canvas: reference.canvas))
                    }
                }
            }
        }
        return result
    }
    static func translated(_ box: CGRect, delta: CGSize, canvas: CGSize, objects: [CanvasAlignmentTarget], selected: Set<String>, zoom: CGFloat, bypass: Bool = false) -> CanvasAlignmentResult {
        guard valid(box), canvas.width > 0, canvas.height > 0 else { return CanvasAlignmentResult(rect: box, guides: []) }
        var rect = box.offsetBy(dx: delta.width, dy: delta.height)
        rect.origin.x = min(max(0, rect.minX), max(0, canvas.width - rect.width))
        rect.origin.y = min(max(0, rect.minY), max(0, canvas.height - rect.height))
        guard !bypass else { return CanvasAlignmentResult(rect: rect, guides: []) }
        let references = references(canvas: canvas, objects: objects, selected: selected)
        let tolerance = attractionDistance / max(0.01, zoom)
        let x = correction(anchors: values(rect, axis: .vertical), axis: .vertical, references: references, tolerance: tolerance, allowed: -rect.minX...max(-rect.minX, canvas.width - rect.maxX))
        let y = correction(anchors: values(rect, axis: .horizontal), axis: .horizontal, references: references, tolerance: tolerance, allowed: -rect.minY...max(-rect.minY, canvas.height - rect.maxY))
        rect = rect.offsetBy(dx: x, dy: y)
        return CanvasAlignmentResult(rect: rect, guides: guides(rect: rect, references: references, axes: [.vertical, .horizontal], zoom: zoom))
    }
    /// `handle` is a normalized handle location: 0/1 changes that edge, 0.5
    /// leaves the axis alone. The opposite edge stays fixed during snapping.
    static func resized(_ proposed: CGRect, handle: CGPoint, canvas: CGSize, objects: [CanvasAlignmentTarget], selected: Set<String>, zoom: CGFloat, bypass: Bool = false) -> CanvasAlignmentResult {
        guard valid(proposed), !bypass else { return CanvasAlignmentResult(rect: proposed, guides: []) }
        let references = references(canvas: canvas, objects: objects, selected: selected)
        let tolerance = attractionDistance / max(0.01, zoom)
        var x = proposed.minX, y = proposed.minY, right = proposed.maxX, bottom = proposed.maxY
        var axes: [CanvasAlignmentGuide.Axis] = []
        if handle.x == 0 {
            x += correction(anchors: [x], axis: .vertical, references: references, tolerance: tolerance, allowed: -x...max(-x, right - x - 1))
            axes.append(.vertical)
        } else if handle.x == 1 {
            right += correction(anchors: [right], axis: .vertical, references: references, tolerance: tolerance, allowed: min(x + 1 - right, canvas.width - right)...(canvas.width - right))
            axes.append(.vertical)
        }
        if handle.y == 0 {
            y += correction(anchors: [y], axis: .horizontal, references: references, tolerance: tolerance, allowed: -y...max(-y, bottom - y - 1))
            axes.append(.horizontal)
        } else if handle.y == 1 {
            bottom += correction(anchors: [bottom], axis: .horizontal, references: references, tolerance: tolerance, allowed: min(y + 1 - bottom, canvas.height - bottom)...(canvas.height - bottom))
            axes.append(.horizontal)
        }
        let rect = CGRect(x: x, y: y, width: right - x, height: bottom - y)
        return CanvasAlignmentResult(rect: rect, guides: guides(rect: rect, references: references, axes: axes, zoom: zoom))
    }
    /// Text and mixed groups resize proportionally. A guide may adjust their
    /// shared factor, never one dimension independently or the anchor corner.
    static func scaled(_ box: CGRect, factor: CGFloat, canvas: CGSize, objects: [CanvasAlignmentTarget], selected: Set<String>, zoom: CGFloat, bypass: Bool = false) -> CanvasAlignmentResult {
        guard valid(box), factor.isFinite, factor > 0 else { return CanvasAlignmentResult(rect: box, guides: []) }
        let proposed = CGRect(origin: box.origin, size: CGSize(width: box.width * factor, height: box.height * factor))
        guard !bypass else { return CanvasAlignmentResult(rect: proposed, guides: []) }
        let references = references(canvas: canvas, objects: objects, selected: selected)
        let tolerance = attractionDistance / max(0.01, zoom)
        let maximum = min((canvas.width - box.minX) / box.width, (canvas.height - box.minY) / box.height)
        var bestFactor = factor, distance: CGFloat?
        for reference in references {
            let factors = values(reference.rect, axis: .vertical).map { ($0 - box.minX) / box.width }
                + values(reference.rect, axis: .horizontal).map { ($0 - box.minY) / box.height }
            for candidate in factors where candidate >= 0.05 && candidate <= maximum {
                let movement = abs(candidate - factor) * max(box.width, box.height)
                guard movement <= tolerance else { continue }
                if distance == nil || movement < distance! - 0.00001 { bestFactor = candidate; distance = movement }
            }
        }
        let rect = CGRect(origin: box.origin, size: CGSize(width: box.width * bestFactor, height: box.height * bestFactor))
        return CanvasAlignmentResult(rect: rect, guides: guides(rect: rect, references: references, axes: [.vertical, .horizontal], zoom: zoom))
    }
}
