import SwiftUI
import AppKit
import CoreText

enum FontActivationAvailability: Equatable {
    case local, typefield, external, unavailable
    static func state(url: URL?, owned: Bool, scope: CTFontManagerScope) -> Self {
        guard let url else { return .unavailable }
        if owned { return .typefield }
        if url.path.hasPrefix("/System/") || url.path.hasPrefix("/Library/Apple/") || scope == .persistent || scope == .session { return .external }
        return .local
    }
    var title: String {
        switch self {
        case .local: return "Activate font"
        case .typefield: return "Deactivate font"
        case .external: return "Font already active"
        case .unavailable: return "Font file unavailable"
        }
    }
}

/// Uses the existing journaled session activation; never unregisters another app's fonts.
struct FontActivationButton: View {
    let face: Face
    let onResult: (String) -> Void
    @ObservedObject private var manager = ActivationManager.shared
    private var availability: FontActivationAvailability {
        FontActivationAvailability.state(url: face.url, owned: face.url.map(manager.owns) ?? false,
                                         scope: face.url.map { CTFontManagerGetScopeForURL($0 as CFURL) } ?? .none)
    }
    var body: some View {
        Button(availability.title) {
            guard let url = face.url else { return }
            do {
                if manager.owns(url) { try manager.deactivate(url); onResult("Deactivated for other apps. The font remains available in Typefield.") }
                else { onResult(try manager.activate(url)) }
            } catch { onResult("Activation failed: " + error.localizedDescription) }
        }
        .disabled(availability == .external || availability == .unavailable)
        .help("Make this font file available to other apps until Typefield quits. A font collection file activates all its styles.")
    }
}

enum FontLicenseSource {
    static func webURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

struct FontLicenseSourcesView: View {
    let face: Face
    @Environment(\.dismiss) private var dismiss
    private var font: CTFont { CTFontCreateWithName(face.name as CFString, 24, nil) }
    private func name(_ key: CFString) -> String? { CTFontCopyName(font, key) as String? }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("License sources").font(.headline); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text(face.originalFamily + " · " + face.style).foregroundStyle(.secondary)
            if let foundry = name(kCTFontManufacturerNameKey), !foundry.isEmpty { Text(foundry).font(.subheadline.weight(.medium)) }
            if let license = name(kCTFontLicenseNameKey), !license.isEmpty {
                ScrollView { Text(license).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 130)
            }
            HStack {
                if let url = FontLicenseSource.webURL(name(kCTFontLicenseURLNameKey)) { Link("Font license ↗", destination: url) }
                if let url = FontLicenseSource.webURL(name(kCTFontVendorURLNameKey)) { Link("Foundry ↗", destination: url) }
            }
            Divider()
            Text("Use your licensing provider").font(.subheadline.weight(.medium))
            HStack {
                Link("Adobe Fonts ↗", destination: URL(string: "https://fonts.adobe.com/")!)
                Link("Monotype Fonts ↗", destination: URL(string: "https://enterprise.monotype.com/")!)
            }
            Text("Sign in with your own or team account at the provider to manage licensed fonts. Download foundry purchases, then add their folder to Typefield.").font(.caption).foregroundStyle(.secondary)
            Text("License price and account coverage are not connected yet. Font metadata and local activation do not verify a personal or team license.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 440)
    }
}
