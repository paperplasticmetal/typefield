import SwiftUI

/// A disposable playground: these examples never read or write a user's projects.
struct TypefieldTour: View {
    let dismiss: () -> Void
    let open: (WorkspaceMode) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var face = 0
    @State private var word = "Play"
    @State private var poster = false
    @State private var roundness = 0.55
    @State private var forward = true

    private static let names = ["Baskerville", "Helvetica Neue", "Courier"]
    private static let fonts = ["Baskerville", "HelveticaNeue-Bold", "Courier-Bold"]
    private static let labels = ["Hello", "Library", "Spaces", "Letterforms"]
    private static let titles = ["Quite the\ncharacter.", "Your words.\nA new voice.", "Good type.\nGreat company.", "Make it\nyour own."]
    private static let details = [
        "Organize your fonts. Try them in context. Make your own. Let's play with a little of each.",
        "See your words in a different light. Find favorites, build a shortlist, and bring order to your font collection.",
        "Give a heading a partner. Try pairings and layouts in Spaces, then take your favorite direction with you.",
        "Every curve has character. Draw letters or bring in your artwork, refine the outlines, and export your own font."
    ]
    private var ink: Color { Color(red: 0.16, green: 0.18, blue: 0.19) }
    private var coral: Color { Color(red: 0.79, green: 0.25, blue: 0.19) }
    private var paper: Color { Color(red: 0.98, green: 0.96, blue: 0.91) }
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.22) }
    private var specimen: String { word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Play" : word }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 30) {
                playground
                    .frame(width: 402, height: 346)
                    .background(paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(ink.opacity(0.09)))
                    .clipped()
                VStack(alignment: .leading, spacing: 18) {
                    Text(Self.titles[step])
                        .font(.system(size: 35, weight: .semibold))
                        .tracking(-1.3).lineSpacing(-1)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(Self.details[step])
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                        .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(step)
                .transition(pageTransition)
            }
            .padding(.vertical, 26)
            footer
        }
        .padding(28)
        .frame(width: 760, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("typefield-onboarding")
    }

    private var pageTransition: AnyTransition {
        reduceMotion ? .identity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: forward ? 10 : -10)),
            removal: .opacity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Typefield").font(.system(size: 15, weight: .semibold)).tracking(-0.3)
            Circle().fill(coral).frame(width: 6, height: 6).accessibilityHidden(true)
            Spacer()
            Button("Skip tour", action: dismiss)
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Close the tour. Reopen it from the Help menu.")
        }
    }

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 4) {
                ForEach(Self.labels.indices, id: \.self) { index in
                    Button { navigate(to: index) } label: {
                        HStack(spacing: 6) {
                            Text(String(format: "%02d", index + 1)).monospacedDigit().opacity(0.55)
                            Text(Self.labels[index])
                        }
                        .font(.system(size: 11, weight: step == index ? .semibold : .regular))
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(step == index ? Color.primary.opacity(0.08) : .clear, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Step \(index + 1) of 4: \(Self.labels[index])")
                    .accessibilityAddTraits(step == index ? .isSelected : [])
                }
                Spacer(minLength: 0)
                if step > 0 {
                    Button("Back") { navigate(to: step - 1) }
                        .buttonStyle(.plain).font(.system(size: 12)).padding(.trailing, 8)
                }
                Button(step == 0 ? "Let's play" : step == 3 ? "Draw a letter" : "Next") {
                    if step == 3 { open(.fontLab) } else { navigate(to: step + 1) }
                }
                .buttonStyle(TourPrimaryButton())
                .keyboardShortcut(.defaultAction)
            }
            HStack {
                if step == 0 {
                    Text("Your fonts and projects stay on this Mac.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if step > 0 {
                    Button("Browse fonts") { open(.library) }.buttonStyle(.plain)
                    Text("·").foregroundStyle(.tertiary)
                    Button("Open Spaces") { open(.spaces) }.buttonStyle(.plain)
                } else {
                    Text("You can return from Help → Getting Started Tour.").foregroundStyle(.secondary)
                }
            }.font(.system(size: 11))
        }
    }

    private func navigate(to next: Int) {
        guard (0..<Self.labels.count).contains(next), next != step else { return }
        forward = next > step
        withAnimation(motion) { step = next }
    }

    private var playground: some View {
        ZStack {
            switch step {
            case 0: welcome
            case 1: library
            case 2: space
            default: letter
            }
        }
        .foregroundStyle(ink)
        .tint(coral)
        // Paper specimens intentionally retain their light appearance in either app theme.
        .environment(\.colorScheme, .light)
        .id(step)
        .transition(pageTransition)
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(motion) { face = (face + 1) % Self.fonts.count }
            } label: {
                Text("Aa")
                    .font(.custom(Self.fonts[face], size: 152))
                    .tracking(-9).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(face).transition(.opacity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 25)
            .accessibilityLabel("Change the specimen typeface")
            .accessibilityValue(Self.names[face])
            HStack {
                Text(Self.names[face]).font(.system(size: 11, weight: .medium))
                Spacer()
                Label("Click the letters", systemImage: "cursorarrow")
                    .font(.system(size: 11)).foregroundStyle(coral)
            }.padding(26)
        }
    }

    private var library: some View {
        VStack(spacing: 18) {
            HStack {
                Image(systemName: "text.cursor").foregroundStyle(coral)
                TextField("A word to play with", text: $word)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .accessibilityLabel("Your specimen text")
                    .onChange(of: word) { value in
                        if value.count > 40 { word = String(value.prefix(40)) }
                    }
                Text("Try your name").font(.system(size: 10)).foregroundStyle(ink.opacity(0.55))
            }
            .padding(13).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
            Text(specimen)
                .font(.custom(Self.fonts[face], size: 82))
                .minimumScaleFactor(0.12).lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("\(specimen), in \(Self.names[face])")
            facePicker
        }.padding(24)
    }

    private var facePicker: some View {
        HStack(spacing: 6) {
            ForEach(Self.names.indices, id: \.self) { index in
                Button {
                    withAnimation(motion) { face = index }
                } label: {
                    VStack(spacing: 5) {
                        Text("Ag").font(.custom(Self.fonts[index], size: 24))
                        Text(["Serif", "Sans", "Mono"][index]).font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity).frame(height: 64)
                    .background(face == index ? .white : ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(face == index ? coral : .clear, lineWidth: 1.5))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain).accessibilityLabel(Self.names[index])
                .accessibilityAddTraits(face == index ? .isSelected : [])
            }
        }
    }

    private var space: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach([false, true], id: \.self) { value in
                    Button {
                        withAnimation(motion) { poster = value }
                    } label: {
                        Text(value ? "Poster" : "Editorial")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(poster == value ? ink : .clear, in: Capsule())
                            .foregroundStyle(poster == value ? paper : ink)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(value ? "Poster" : "Editorial") layout")
                        .accessibilityAddTraits(poster == value ? .isSelected : [])
                }
                Spacer()
                Image(systemName: "square.stack").foregroundStyle(ink.opacity(0.5)).accessibilityHidden(true)
            }
            VStack(alignment: poster ? .center : .leading, spacing: 8) {
                HStack {
                    Text("THE TYPE CLUB").tracking(2)
                    Spacer()
                    Text("No. 01")
                }.font(.system(size: 8, weight: .semibold))
                Spacer(minLength: 0)
                Text(specimen)
                    .font(.custom(Self.fonts[face], size: poster ? 58 : 44))
                    .minimumScaleFactor(0.15).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: poster ? .center : .leading)
                Text("A little room for big ideas.")
                    .font(.custom("HelveticaNeue", size: 12))
                if !poster {
                    Rectangle().frame(height: 1).opacity(0.22)
                    Text("A bold beginning. A quieter voice to follow.\nFind a pairing that feels like you.")
                        .font(.custom("HelveticaNeue", size: 10)).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack {
                    Text("EXPERIMENT / 001").tracking(1)
                    Spacer()
                    Image(systemName: "arrow.up.right").accessibilityHidden(true)
                }.font(.system(size: 8, weight: .medium))
            }
            .padding(20).frame(maxWidth: .infinity).frame(height: 214)
            .foregroundStyle(poster ? paper : ink)
            .background(poster ? coral : .white, in: RoundedRectangle(cornerRadius: 4))
            .rotationEffect(.degrees(poster ? -2 : 0))
            .shadow(color: ink.opacity(0.10), radius: 9, y: 4)
            Text("Try another layout.")
                .font(.system(size: 11)).foregroundStyle(ink.opacity(0.65))
        }.padding(24)
    }

    private var letter: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button("Reset") { withAnimation(motion) { roundness = 0.55 } }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(coral)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let right = 0.63 + roundness * 0.22
                ZStack {
                    Path { path in
                        for y in [0.17, 0.63, 0.91] {
                            path.move(to: CGPoint(x: 14, y: height * y))
                            path.addLine(to: CGPoint(x: width - 14, y: height * y))
                        }
                    }.stroke(ink.opacity(0.13), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    TourLetterShape(roundness: roundness)
                        .fill(ink, style: FillStyle(eoFill: true))
                    TourLetterShape(roundness: roundness).stroke(coral.opacity(0.65), lineWidth: 1)
                    Path { path in
                        path.move(to: CGPoint(x: width * right, y: height * 0.23))
                        path.addLine(to: CGPoint(x: width * right, y: height * 0.57))
                    }.stroke(coral.opacity(0.6), lineWidth: 1)
                    ForEach([0.23, 0.57], id: \.self) { y in
                        Circle().fill(paper).overlay(Circle().stroke(coral, lineWidth: 1.5))
                            .frame(width: 6, height: 6)
                            .position(x: width * right, y: height * y)
                    }
                    Circle().fill(coral).overlay(Circle().stroke(paper, lineWidth: 2))
                        .frame(width: 14, height: 14).padding(14).contentShape(Rectangle())
                        .position(x: width * right, y: height * 0.40)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("tour-letter"))
                            .onChanged { value in
                                roundness = min(1, max(0, (value.location.x / width - 0.63) / 0.22))
                            })
                }
                .coordinateSpace(name: "tour-letter")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Editable letter p preview")
            }.frame(height: 211)
            HStack(spacing: 12) {
                Text("Narrow").font(.system(size: 10))
                Slider(value: $roundness, in: 0...1)
                    .accessibilityLabel("Letter bowl width")
                    .accessibilityValue("\(Int(roundness * 100)) percent")
                Text("Round").font(.system(size: 10))
            }
            Text("Drag the coral point.")
                .font(.system(size: 11)).foregroundStyle(ink.opacity(0.65))
        }.padding(24)
    }
}

private struct TourLetterShape: Shape {
    var roundness: Double
    var animatableData: Double {
        get { roundness }
        set { roundness = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let right = 0.63 + roundness * 0.22
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y) }
        var path = Path()
        path.move(to: p(0.28, 0.17))
        path.addLine(to: p(0.40, 0.17))
        path.addLine(to: p(0.40, 0.21))
        path.addCurve(to: p(right, 0.40), control1: p(0.56, 0.08), control2: p(right, 0.23))
        path.addCurve(to: p(0.40, 0.59), control1: p(right, 0.57), control2: p(0.56, 0.72))
        path.addLine(to: p(0.40, 0.91))
        path.addLine(to: p(0.28, 0.91))
        path.closeSubpath()
        path.move(to: p(0.40, 0.32))
        path.addCurve(to: p(right - 0.12, 0.40), control1: p(0.50, 0.23), control2: p(right - 0.12, 0.28))
        path.addCurve(to: p(0.40, 0.48), control1: p(right - 0.12, 0.52), control2: p(0.50, 0.57))
        path.closeSubpath()
        return path
    }
}

private struct TourPrimaryButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white).padding(.horizontal, 17).frame(height: 34)
            .background(Color(red: 0.18, green: 0.20, blue: 0.21), in: Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
