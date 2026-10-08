import SwiftUI

/// A disposable playground: these examples never read or write a user's projects.
struct TypefieldTour: View {
    let dismiss: () -> Void
    let open: (WorkspaceMode) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var face = 0
    @State private var word = "Hello"
    @State private var poster = false
    @State private var curve = TourCurveGeometry()
    @State private var forward = true

    private static let names = TourSpecimens.faces.map(\.name)
    private static let fonts = TourSpecimens.faces.map(\.postScriptName)
    private static let labels = ["Hello", "Library", "Spaces", "Letterforms"]
    private static let titles = ["Quite the\ncharacter.", "Your words.\nA new voice.", "Good type.\nGreat company.", "Make it\nyour own."]
    private static let details = [
        "Organize your fonts. Try them in context. Make your own. Let's play with a little of each.",
        "See your words in a different light. Find favorites, build a shortlist, and bring order to your font collection.",
        "Give a heading a partner. Try pairings and layouts in Spaces, then take your favorite direction with you.",
        "Draw letters, refine their outlines, and export your own font."
    ]
    private var ink: Color { Color(red: 0.16, green: 0.18, blue: 0.19) }
    private var coral: Color { Color(red: 0.79, green: 0.25, blue: 0.19) }
    private var paper: Color { Color(red: 0.98, green: 0.96, blue: 0.91) }
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.22) }
    private var specimen: String { word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Hello" : word }

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
                    if step == 3 { fontGuides }
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

    private var fontGuides: some View {
        let guides = [
            ("Baseline", "Where letters sit."),
            ("x-height", "Height of lowercase x."),
            ("Cap height", "Height of capitals."),
            ("Ascender", "Rises above x-height."),
            ("Descender", "Drops below the baseline."),
            ("Side bearings", "Space beside a glyph."),
            ("Advance", "Distance to the next glyph.")
        ]
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(guides.indices, id: \.self) { index in
                (Text(guides[index].0).fontWeight(.semibold) + Text(" · " + guides[index].1))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Font drawing guides")
    }

    private var pageTransition: AnyTransition {
        reduceMotion ? .identity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: forward ? 10 : -10)),
            removal: .opacity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Typefield").font(.system(size: 15, weight: .semibold)).tracking(-0.3)
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
                Button(step == 0 ? "Let's play" : step == 3 ? "Finish tour" : "Next") {
                    if step == 3 { dismiss() } else { navigate(to: step + 1) }
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
                switch step {
                case 1:
                    Button("Browse Fonts") { open(.library) }.buttonStyle(.plain)
                case 2:
                    Button("Open Spaces") { open(.spaces) }.buttonStyle(.plain)
                case 3:
                    Button("Draw a Letter") { open(.fontLab) }.buttonStyle(.plain)
                default:
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
            default: TourCurveDemo(geometry: $curve, ink: ink, coral: coral, paper: paper, motion: motion)
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
                TourHelloSpecimen(face: face)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(face).transition(.opacity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 25)
            .accessibilityLabel("Hello. Change the specimen typeface")
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
