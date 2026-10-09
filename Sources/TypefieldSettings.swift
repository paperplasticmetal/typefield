import SwiftUI
import AppKit

enum TypefieldSupportLinks {
    static let feedback = URL(string: "https://typefield.app/feedback/")!
    static let bugReport = URL(string: "https://typefield.app/feedback/?category=bug")!
}

final class TypefieldSettingsSelection: ObservableObject {
    @Published var page: TypefieldSettingsPage = .appearance
}
enum TypefieldSettingsPage: String, CaseIterable, Identifiable {
    case language = "Language", appearance = "Appearance", icon = "App Icon", folders = "Live Folders", library = "Library", shortcuts = "Keyboard Shortcuts", privacy = "Privacy & Permissions", updates = "Updates", about = "About Typefield"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .language: return "globe"
        case .appearance: return "paintpalette"
        case .icon: return "app"
        case .folders: return "folder"
        case .library: return "textformat"
        case .shortcuts: return "keyboard"
        case .privacy: return "hand.raised"
        case .updates: return "arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

final class TypefieldSettingsWindow {
    private var window: NSWindow?
    private let selection = TypefieldSettingsSelection()
    func refreshLanguage() { window?.title = TypefieldL10n.text("Typefield Settings") }
    func show(library: Library, page: TypefieldSettingsPage? = nil) {
        if let page { selection.page = page }
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            panel.title = TypefieldL10n.text("Typefield Settings")
            panel.minSize = NSSize(width: 820, height: 620)
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: TypefieldSettingsView(library: library, selection: selection).typefieldLocalized())
            panel.setFrameAutosaveName("TypefieldSettingsWindow")
            panel.center()
            window = panel
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct TypefieldSettingsView: View {
    @ObservedObject var library: Library
    @ObservedObject var selection: TypefieldSettingsSelection
    @ObservedObject private var updater = TypefieldUpdater.shared
    @AppStorage("appearance") private var appearance = "Dark"
    @AppStorage("typefield.palette") private var palette = "neutral"
    @AppStorage("typefield.iconPalette") private var iconPalette = "neutral"
    @AppStorage("typefield.iconAppearance") private var iconAppearance = "Automatic"
    @AppStorage("previewText") private var preview = "The quick brown fox jumps over the lazy dog."
    @AppStorage("previewSize") private var size = 64.0
    @AppStorage("adaptiveGridView") private var grid = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var darkIcon: Bool { TypefieldIcon.isDark(mode: iconAppearance, scheme: scheme) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 12)
                ForEach(TypefieldSettingsPage.allCases) { page in
                    Button { selection.page = page } label: {
                        HStack(spacing: 10) {
                            Image(systemName: page.symbol).frame(width: 20)
                            Text(localizedKey(page.rawValue)).font(.subheadline.weight(selection.page == page ? .semibold : .regular))
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if selection.page == page {
                                Image(systemName: "checkmark").font(.caption.weight(.semibold)).accessibilityHidden(true)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .foregroundStyle(selection.page == page ? ShelfPalette.ink : Color.primary)
                        .background(selection.page == page ? ShelfPalette.indiaYellow.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(selection.page == page ? .isSelected : [])
                }
                Spacer()
                Text("Typefield").font(.subheadline.weight(.semibold)).padding(12).foregroundStyle(.secondary)
            }.padding(12).frame(width: 216).background {
                if reduceTransparency { Color(nsColor: .windowBackgroundColor) }
                else { Rectangle().fill(.regularMaterial) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                if selection.page != .shortcuts {
                    Text(localizedKey(selection.page.rawValue)).font(.system(size: 27, weight: .semibold)).padding(.top, 6)
                }
                content
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(ShelfPalette.canvas)
        .tint(ShelfPalette.ink).accentColor(ShelfPalette.ink)
        // The hosting window inherits AppKit's appearance. A separate SwiftUI
        // preference can linger after switching from Light back to System.
        .onChange(of: appearance) { value in
            NSApp.appearance = value == "System" ? nil : NSAppearance(named: value == "Dark" ? .darkAqua : .aqua)
            TypefieldIcon.apply()
        }
        .onChange(of: scheme) { _ in TypefieldIcon.apply() }
        .onChange(of: iconPalette) { _ in TypefieldIcon.apply() }
        .onChange(of: iconAppearance) { _ in TypefieldIcon.apply() }
        .accessibilityIdentifier("typefield-settings")
    }
    @ViewBuilder private var content: some View {
        switch selection.page {
        case .language: languagePane
        case .appearance: appearancePane
        case .icon: iconPane
        case .folders: WatchedFoldersView(library: library)
        case .library: libraryPane
        case .shortcuts: TypefieldShortcutReference(dismiss: {}, embedded: true)
        case .privacy: privacyPane
        case .updates: updatesPane
        case .about: aboutPane
        }
    }
    private var languagePane: some View {
        VStack(alignment: .leading, spacing: 20) {
            TypefieldLanguagePicker().frame(maxWidth: 380)
            Text("Changes apply immediately to all Typefield windows.").foregroundStyle(.secondary)
            Text("Font names, preview text, and saved projects keep their original content.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Some advanced tools and system dialogs may still appear in English or your macOS language.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var appearancePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose a light or dark workspace. Font previews and saved typeboards keep their own colors.").foregroundStyle(.secondary)
                Picker("Appearance", selection: $appearance) {
                    ForEach(["System", "Light", "Dark"], id: \.self) { Text(localizedKey($0)).tag($0) }
                }.pickerStyle(.segmented)
                Text("Accent color").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(TypefieldPalette.allCases) { item in
                        Button { palette = item.rawValue } label: {
                            HStack(spacing: 12) {
                                Circle().fill(Color(nsColor: item.swatch(dark: scheme == .dark))).frame(width: 26, height: 26)
                                Text(localizedKey(item.title)).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: palette == item.rawValue ? "checkmark.circle.fill" : "circle").foregroundStyle(.secondary)
                            }.padding(16).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityLabel(item.title + " accent color").accessibilityAddTraits(palette == item.rawValue ? .isSelected : [])
                    }
                }
                Label("Accent colors highlight selections and controls. The workspace stays neutral.", systemImage: "paintbrush.pointed").font(.callout).foregroundStyle(.secondary)
                Text("Motion and transparency follow your macOS Accessibility settings.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var iconPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choose a color for Typefield’s Dock icon.").foregroundStyle(.secondary)
                Picker("Icon appearance", selection: $iconAppearance) {
                    Text("Follow app").tag("Automatic")
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                }.pickerStyle(.segmented)
                Text("Follow app matches Typefield’s appearance. Light and Dark stay fixed when the app or macOS changes.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Icon color").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(TypefieldPalette.allCases) { item in
                        Button { iconPalette = item.rawValue } label: {
                            HStack(spacing: 12) {
                                Image(nsImage: TypefieldIcon.image(palette: item, dark: darkIcon, size: 128))
                                    .resizable().interpolation(.high).frame(width: 64, height: 64)
                                Text(localizedKey(item.iconColorTitle)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                                Spacer(minLength: 0)
                                if iconPalette == item.rawValue { Image(systemName: "checkmark.circle.fill").foregroundStyle(ShelfPalette.ink) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(iconPalette == item.rawValue ? ShelfPalette.ink.opacity(0.09) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityLabel(item.iconColorTitle + " icon color").accessibilityAddTraits(iconPalette == item.rawValue ? .isSelected : [])
                    }
                }
                Text("Changes apply to the Dock while Typefield is running and are restored on launch. Finder and the app’s closed-state icon use the standard Porcelain artwork.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var libraryPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Font previews").font(.headline)
                TextField("Default preview text", text: $preview).textFieldStyle(.roundedBorder)
                HStack {
                    Text("Preview size")
                    Slider(value: $size, in: 16...160, step: 1)
                        .accessibilityLabel("Preview size")
                        .accessibilityValue("\(Int(size)) points")
                    Text("\(Int(size)) pt").monospacedDigit().frame(width: 50)
                }
                Toggle("Use a grid for the font library", isOn: $grid)
                Divider()
                Text("Library backup").font(.headline)
                Text("Export collections, tags, notes, live-folder references, Spaces, and Letterform Editor projects. Font binaries are not included.").foregroundStyle(.secondary)
                Button("Export Library Backup…") { LibraryBackupTools.export(library) }
                Button("Import Library Backup…") { LibraryBackupTools.restore(library) }
                Button("Show Library Data in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: library.saveURL.deletingLastPathComponent().path) }
                Text("Your library stays in its existing storage location. Changing appearance does not move or modify fonts.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var privacyPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("Stored on this Mac", "Your collections, tags, notes, settings, projects, and folder bookmarks are stored locally. Typefield has no account, advertising, analytics, or tracking. It does not upload fonts, preview text, or your library.")
                section("Live-folder permissions", "You grant access through the macOS folder picker. Local builds pause saved watches that include Desktop, Documents or Downloads when Typefield opens, avoiding repeated system permission prompts. Resume a paused watch from Live Folders when you need it. Stopping a watch leaves the original font files in place.")
                Button("Manage Live Folders") { selection.page = .folders }
                section("Google Fonts & network access", "Browsing Google Fonts contacts Google’s public font repository on GitHub for previews. Downloads also retrieve font files and licenses. GitHub receives normal connection information such as your IP address and the requested public file path. Preview text is rendered locally and is not sent. Remote previews use an ephemeral network session and an in-memory font cache; explicit downloads are saved locally.")
                if TypefieldUpdateConfiguration.isDirectDistribution {
                section("App updates", "When automatic checks are enabled, Typefield contacts typefield.app to look for published updates. Installing an update downloads a signed app from our public GitHub releases. These services receive normal connection information; your fonts, library, and projects are never sent. You can turn automatic checks off in Updates.")
                }
                section("Exports & licensing", "Exports are saved where you choose. Figma, Adobe, and developer handoffs refer to fonts by name and do not contain font binaries. Adobe scripts are saved for you to run manually. Use or export only fonts and artwork you have permission to use; Typefield cannot verify redistribution, embedding, or commercial-use rights.")
            }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
    }
    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(localizedKey(title)).font(.headline); Text(localizedKey(text)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
    private var updatesPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Keep Typefield up to date.").font(.title3)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .foregroundStyle(.secondary)
                if updater.isAvailable {
                    Text("Get the latest published Typefield release, including new features and fixes. Your fonts, library, and projects stay on this Mac.")
                        .foregroundStyle(.secondary)
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                        .accessibilityIdentifier("typefield-check-for-updates")
                    if let date = updater.lastUpdateCheckDate {
                        Text("Last checked: \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.setAutomaticallyChecksForUpdates($0) }))
                        .accessibilityIdentifier("typefield-automatic-update-checks")
                    Toggle("Automatically download and install updates", isOn: Binding(
                        get: { updater.automaticallyDownloadsUpdates },
                        set: { updater.setAutomaticallyDownloadsUpdates($0) }))
                        .disabled(!updater.automaticallyChecksForUpdates || !updater.allowsAutomaticUpdates)
                        .accessibilityIdentifier("typefield-automatic-update-downloads")
                    Text("Automatic checks run daily. With automatic installation enabled, updates can install when you quit Typefield. You can always check manually.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(updater.unavailableReason ?? "Update checks are unavailable.").foregroundStyle(.secondary)
                }
                if TypefieldUpdateConfiguration.isDirectDistribution {
                    Link("View Downloads & Release Information", destination: URL(string: "https://typefield.app/download/")!)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(nsImage: TypefieldIcon.image(palette: .resolve(iconPalette), dark: darkIcon)).resizable().frame(width: 100, height: 100)
            Text("A place for fonts, typeboards, and your own letterforms.").font(.title3)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))").foregroundStyle(.secondary)
            Divider()
            Button("Take the Tour") {
                NSApp.windows.first(where: { $0.title == "Typefield" })?.makeKeyAndOrderFront(nil)
                NotificationCenter.default.post(name: Notification.Name("TypefieldMenu"), object: "tour")
            }
            Button("Updates…") { selection.page = .updates }
            Button("Keyboard Shortcuts") { selection.page = .shortcuts }
            Button("Privacy & Permissions") { selection.page = .privacy }
            Divider()
            Text("Trying the beta? Tell us what worked, what was confusing, or what went wrong.")
                .font(.callout).foregroundStyle(.secondary)
            Link("Send Feedback", destination: TypefieldSupportLinks.feedback)
            Link("Report a Bug", destination: TypefieldSupportLinks.bugReport)
            Spacer()
        }
    }
}

private extension TypefieldPalette {
    var iconColorTitle: String {
        switch self {
        case .neutral: return "Porcelain"
        case .amber: return "Ochre"
        case .ocean: return "Indigo"
        case .forest: return "Sage"
        case .plum: return "Plum"
        case .rose: return "Coral"
        }
    }
}
