import SwiftUI

enum TourCurveControl: String, CaseIterable, Identifiable {
    case anchor, upperHandle, lowerHandle
    var id: Self { self }
    var title: String {
        switch self {
        case .anchor: return "Solid point"
        case .upperHandle: return "Upper handle"
        case .lowerHandle: return "Lower handle"
        }
    }
}

/// Normalized, disposable geometry for the tour. The control bounds keep the
/// two outer cubics on opposite sides of their anchor and clear of the counter.
struct TourCurveGeometry: Equatable {
    private(set) var anchor: CGPoint
    private(set) var upperHandle: CGPoint
    private(set) var lowerHandle: CGPoint

    init() {
        anchor = CGPoint(x: 0.75, y: 0.40)
        upperHandle = CGPoint(x: 0.75, y: 0.20)
        lowerHandle = CGPoint(x: 0.75, y: 0.60)
    }

    fileprivate init(anchor: CGPoint, upperHandle: CGPoint, lowerHandle: CGPoint) {
        self.anchor = anchor
        self.upperHandle = upperHandle
        self.lowerHandle = lowerHandle
    }

    func point(_ control: TourCurveControl) -> CGPoint {
        switch control {
        case .anchor: return anchor
        case .upperHandle: return upperHandle
        case .lowerHandle: return lowerHandle
        }
    }

    mutating func move(_ control: TourCurveControl, to proposed: CGPoint) {
        guard proposed.x.isFinite, proposed.y.isFinite else { return }
        func clamp(_ value: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
            min(range.upperBound, max(range.lowerBound, value))
        }
        switch control {
        case .anchor:
            let next = CGPoint(x: clamp(proposed.x, 0.67...0.79), y: clamp(proposed.y, 0.35...0.49))
            let dx = next.x - anchor.x, dy = next.y - anchor.y
            upperHandle = CGPoint(x: upperHandle.x + dx, y: upperHandle.y + dy)
            lowerHandle = CGPoint(x: lowerHandle.x + dx, y: lowerHandle.y + dy)
            anchor = next
        case .upperHandle:
            upperHandle = CGPoint(x: clamp(proposed.x, (anchor.x - 0.08)...(anchor.x + 0.08)),
                                  y: clamp(proposed.y, (anchor.y - 0.24)...(anchor.y - 0.12)))
        case .lowerHandle:
            lowerHandle = CGPoint(x: clamp(proposed.x, (anchor.x - 0.08)...(anchor.x + 0.08)),
                                  y: clamp(proposed.y, (anchor.y + 0.12)...(anchor.y + 0.24)))
        }
    }

    func outerOutline(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: p(0.28, 0.17))
        path.addLine(to: p(0.40, 0.17))
        path.addLine(to: p(0.40, 0.21))
        path.addCurve(to: p(anchor.x, anchor.y), control1: p(0.56, 0.08), control2: p(upperHandle.x, upperHandle.y))
        path.addCurve(to: p(0.40, 0.59), control1: p(lowerHandle.x, lowerHandle.y), control2: p(0.56, 0.72))
        path.addLine(to: p(0.40, 0.91))
        path.addLine(to: p(0.28, 0.91))
        path.closeSubpath()
        return path
    }

    func counterOutline(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: p(0.40, 0.32))
        path.addCurve(to: p(0.55, 0.40), control1: p(0.50, 0.25), control2: p(0.55, 0.29))
        path.addCurve(to: p(0.40, 0.48), control1: p(0.55, 0.51), control2: p(0.50, 0.55))
        path.closeSubpath()
        return path
    }

    func outline(in rect: CGRect) -> Path {
        var path = outerOutline(in: rect)
        path.addPath(counterOutline(in: rect))
        return path
    }

    /// Resolve overlapping hit regions by distance, then retain that point for
    /// the entire gesture. Grabbing near a handle never jumps it to the cursor.
    func nearestControl(to location: CGPoint, in size: CGSize, radius: CGFloat = 24) -> TourCurveControl? {
        guard size.width > 0, size.height > 0 else { return nil }
        var nearest: TourCurveControl?
        var distance = radius * radius
        for control in TourCurveControl.allCases {
            let point = point(control)
            let dx = location.x - point.x * size.width, dy = location.y - point.y * size.height
            let candidate = dx * dx + dy * dy
            if candidate <= distance { nearest = control; distance = candidate }
        }
        return nearest
    }
}

struct TourCurveDemo: View {
    @Binding var geometry: TourCurveGeometry
    let ink: Color
    let coral: Color
    let paper: Color
    let motion: Animation?
    @State private var selected: TourCurveControl = .anchor
    @State private var drag: CurveDrag?

    private struct CurveDrag {
        let control: TourCurveControl
        let origin: CGPoint
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("Edit point", selection: $selected) {
                    ForEach(TourCurveControl.allCases) { control in Text(control.title).tag(control) }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
                .frame(width: 148, alignment: .leading)
                .accessibilityLabel("Point to edit")
                Spacer()
                Button("Reset") {
                    drag = nil
                    withAnimation(motion) { geometry = TourCurveGeometry() }
                    selected = .anchor
                }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(coral)
                .accessibilityLabel("Reset curve and handles")
            }
            GeometryReader { proxy in canvas(size: proxy.size) }
                .frame(minHeight: 160, maxHeight: .infinity)
            HStack(spacing: 5) {
                Text("Move").font(.system(size: 10)).foregroundStyle(ink.opacity(0.65))
                moveButton("left", symbol: "arrow.left", dx: -0.01, dy: 0)
                moveButton("right", symbol: "arrow.right", dx: 0.01, dy: 0)
                moveButton("up", symbol: "arrow.up", dx: 0, dy: -0.01)
                moveButton("down", symbol: "arrow.down", dx: 0, dy: 0.01)
                Spacer(minLength: 4)
                Text(coordinates(selected)).font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(ink.opacity(0.65))
                    .accessibilityLabel("\(selected.title): \(coordinates(selected))")
            }
            Text("Drag the solid point to move the curve.\nDrag hollow handles to change its shape.")
                .font(.system(size: 11)).foregroundStyle(ink.opacity(0.65))
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .accessibilityIdentifier("tour-curve-demo")
    }

    private func canvas(size: CGSize) -> some View {
        ZStack {
            Path { path in
                for y in [0.17, 0.63, 0.91] {
                    path.move(to: CGPoint(x: 14, y: size.height * y))
                    path.addLine(to: CGPoint(x: size.width - 14, y: size.height * y))
                }
            }
            .stroke(ink.opacity(0.13), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            .accessibilityHidden(true)
            ForEach(0..<3, id: \.self) { index in
                Text(["x-height", "Baseline", "Descender"][index])
                    .font(.system(size: 8)).foregroundStyle(ink.opacity(0.55))
                    .frame(width: 72, alignment: .leading)
                    .position(x: 50, y: size.height * [0.17, 0.63, 0.91][index] - 7)
                    .accessibilityHidden(true)
            }
            TourCurveShape(geometry: geometry).fill(ink, style: FillStyle(eoFill: true))
                .accessibilityHidden(true)
            TourCurveShape(geometry: geometry).stroke(coral.opacity(0.65), lineWidth: 1)
                .accessibilityHidden(true)
            TourCurveConnectors(geometry: geometry).stroke(coral.opacity(0.7), lineWidth: 1)
                .accessibilityHidden(true)
            ForEach(TourCurveControl.allCases) { control in
                marker(control)
                    .position(x: geometry.point(control).x * size.width, y: geometry.point(control).y * size.height)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                if drag == nil {
                    guard let control = geometry.nearestControl(to: value.startLocation, in: size) else { return }
                    selected = control
                    drag = CurveDrag(control: control, origin: geometry.point(control))
                }
                guard let drag else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    geometry.move(drag.control, to: CGPoint(x: drag.origin.x + value.translation.width / size.width,
                                                           y: drag.origin.y + value.translation.height / size.height))
                }
            }
            .onEnded { _ in drag = nil })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Editable letter p")
    }

    private func marker(_ control: TourCurveControl) -> some View {
        ZStack {
            Circle().stroke(selected == control ? coral.opacity(0.3) : .clear, lineWidth: 2)
                .frame(width: 23, height: 23)
            Circle().fill(control == .anchor ? coral : paper)
                .overlay(Circle().stroke(control == .anchor ? paper : coral, lineWidth: 2))
                .frame(width: control == .anchor ? 13 : 10, height: control == .anchor ? 13 : 10)
        }
        .frame(width: 24, height: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(control.title)
        .accessibilityValue(coordinates(control))
        .accessibilityAddTraits(selected == control ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Select this point, then use the move buttons to adjust it in either direction.")
        .accessibilityAction { selected = control }
    }

    private func moveButton(_ direction: String, symbol: String, dx: CGFloat, dy: CGFloat) -> some View {
        Button {
            let point = geometry.point(selected)
            withAnimation(motion) { geometry.move(selected, to: CGPoint(x: point.x + dx, y: point.y + dy)) }
        } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium))
                .frame(width: 26, height: 26)
                .background(ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Move \(selected.title.lowercased()) \(direction)")
        .accessibilityLabel("Move \(selected.title.lowercased()) \(direction)")
        .accessibilityValue(coordinates(selected))
    }

    private func coordinates(_ control: TourCurveControl) -> String {
        let point = geometry.point(control)
        return "X \(Int((point.x * 100).rounded())), Y \(Int((point.y * 100).rounded()))"
    }
}

private typealias TourCurveAnimation = AnimatablePair<CGPoint.AnimatableData, AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>>

private extension TourCurveGeometry {
    var animation: TourCurveAnimation {
        get { TourCurveAnimation(anchor.animatableData, AnimatablePair(upperHandle.animatableData, lowerHandle.animatableData)) }
        set {
            self = TourCurveGeometry(anchor: CGPoint(x: newValue.first.first, y: newValue.first.second),
                                    upperHandle: CGPoint(x: newValue.second.first.first, y: newValue.second.first.second),
                                    lowerHandle: CGPoint(x: newValue.second.second.first, y: newValue.second.second.second))
        }
    }
}

private struct TourCurveShape: Shape {
    var geometry: TourCurveGeometry
    var animatableData: TourCurveAnimation {
        get { geometry.animation }
        set { geometry.animation = newValue }
    }
    func path(in rect: CGRect) -> Path { geometry.outline(in: rect) }
}

private struct TourCurveConnectors: Shape {
    var geometry: TourCurveGeometry
    var animatableData: TourCurveAnimation {
        get { geometry.animation }
        set { geometry.animation = newValue }
    }
    func path(in rect: CGRect) -> Path {
        func p(_ point: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * point.x, y: rect.minY + rect.height * point.y)
        }
        var path = Path()
        path.move(to: p(geometry.upperHandle))
        path.addLine(to: p(geometry.anchor))
        path.addLine(to: p(geometry.lowerHandle))
        return path
    }
}
