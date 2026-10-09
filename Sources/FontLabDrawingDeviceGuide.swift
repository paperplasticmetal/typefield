import SwiftUI

/// Setup guidance only. macOS and the device's driver own the connection;
/// opening this sheet never pairs hardware or changes a saved glyph.
struct FontLabDrawingDeviceGuide: View {
    var canStartSketch = true
    var inputDetected = false
    let onStartSketch: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var device = Device.iPad
    @State private var showConnectionHelp = false
    @State private var showTest = false

    private enum Device: Hashable { case iPad, tablet }
    private static let sidecarURL = URL(string: "https://support.apple.com/en-us/102597")!
    private static let pencilCompatibilityURL = URL(string: "https://support.apple.com/en-us/108937")!
    private static let pencilFeaturesURL = URL(string: "https://www.apple.com/apple-pencil/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "ipad")
                    .font(.system(size: 28)).foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Draw with iPad or tablet").font(.title2.weight(.semibold))
                    Text("Set up your pen, then draw directly into a letter.")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Close drawing device guide")
            }
            Picker("Drawing device", selection: $device) {
                Text("iPad + Apple Pencil").tag(Device.iPad)
                Text("Pen tablet").tag(Device.tablet)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("font-lab-drawing-device-picker")

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if device == .iPad { iPadGuide } else { tabletGuide }
                    Divider()
                    pressureGuide
                    DisclosureGroup("Try it on a test glyph", isExpanded: $showTest) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Draw a light-to-firm stroke with Pressure on, then another with it off. Width should vary only when pressure is supported and reported.")
                            Text("2. Undo and redo. Each completed stroke should return as one edit.")
                            Text("3. Choose another glyph, return, then reopen the project. Your strokes should look the same.")
                            Text("4. Switch to Vector to edit anchors and handles. Pressure affects Sketch strokes; vector tools use the pen as a pointer.")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)
            }

            Divider()
            if !canStartSketch {
                Text("Sketch needs an editable glyph. Glyphs with linked components stay in Vector; choose a glyph without components to draw freehand.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start sketching") {
                    dismiss()
                    onStartSketch()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(!canStartSketch)
                .accessibilityIdentifier("font-lab-start-device-sketch")
            }.controlSize(.large)
        }
        .padding(22).frame(width: 560, height: 620)
        .accessibilityIdentifier("font-lab-drawing-device-guide")
    }

    private var iPadGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sidecar shows your Mac’s Typefield window on iPad. Your letters stay in the project on your Mac.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            step(1, "Connect with Sidecar", "On your Mac, open System Settings → Displays. Use Add Display (+) to choose your iPad as an extended display.")
            step(2, "Move Typefield onto iPad", "Drag the Typefield window to the iPad display. Use your paired Apple Pencil to choose tools and draw.")
            step(3, "Start in Sketch", "Start sketching opens the Pen tool with a Round nib and Pressure enabled. Adjust the width and smoothing in Brush settings.")
            HStack(spacing: 18) {
                Link("Apple’s Sidecar guide", destination: Self.sidecarURL)
                Link("Pencil compatibility", destination: Self.pencilCompatibilityURL)
            }.font(.callout)
            DisclosureGroup("iPad not listed?", isExpanded: $showConnectionHelp) {
                Text("Use compatible devices signed into the same Apple Account with two-factor authentication. For wireless Sidecar, keep the devices nearby with Wi-Fi, Bluetooth and Handoff on. Over USB, unlock your iPad and trust the Mac when asked. Apple’s guide lists the full requirements.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
        }
    }

    private var tabletGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Use a macOS-compatible pen tablet or pen display. Typefield receives the pen input provided by macOS.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            step(1, "Connect your tablet", "Follow your tablet maker’s setup instructions. Install its macOS driver and allow the permissions it requires.")
            step(2, "Check the pen’s position", "In the tablet’s settings, map it to the display containing Typefield. Check that the pen reaches the whole drawing area.")
            step(3, "Start in Sketch", "Start sketching opens the Pen tool with a Round nib and Pressure enabled. Adjust the width and smoothing in Brush settings.")
            Text("If the pen moves the cursor but strokes stay uniform, check Pressure in Brush settings and your tablet’s driver settings.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pressureGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(inputDetected ? "Pen input received this session" : "Draw a stroke in Sketch to check pen input",
                  systemImage: inputDetected ? "checkmark.circle.fill" : "pencil.tip")
                .font(.callout.weight(.medium))
                .foregroundStyle(inputDetected ? Color.green : Color.primary)
            Text("Pressure changes stroke width when your pen supports it and macOS reports it. A detected pen is not a live connection or pressure check.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if device == .iPad {
                Text("Apple Pencil (USB-C) has no pressure sensitivity.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Link("Compare Apple Pencil features", destination: Self.pencilFeaturesURL).font(.caption)
            }
            Text("Reported tilt is saved with Sketch strokes; it does not rotate the nib. Use the visible tools to switch: Pencil double-tap, squeeze and barrel roll have no custom Typefield actions.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ number: Int, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number.formatted()).font(.callout.weight(.semibold))
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
