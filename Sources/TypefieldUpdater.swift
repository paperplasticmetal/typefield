import Foundation
import Combine

#if TYPEFIELD_DIRECT_DISTRIBUTION
import AppKit
import Sparkle
#endif

/// Validate the launch before constructing Sparkle, which reads and writes its
/// own preferences. Keeping this pure lets the native suite check the guard
/// without starting a network request or touching a user's update preferences.
enum TypefieldUpdateConfiguration {
    static let feedURL = "https://typefield.app/updates/appcast.xml"
    static let bundleIdentifier = "local.typefield.app"
    #if TYPEFIELD_DIRECT_DISTRIBUTION
    static let isDirectDistribution = true
    #else
    static let isDirectDistribution = false
    #endif

    static func permitsInstallation(arguments: [String]) -> Bool {
        !arguments.contains("--updater-qa")
    }

    static func permitsUpdateCheck(informationOnly: Bool, arguments: [String]) -> Bool {
        permitsInstallation(arguments: arguments) || informationOnly
    }

    static func unavailableReason(info: [String: Any], bundleURL: URL, executableURL: URL?, arguments: [String],
                                  directDistribution: Bool = isDirectDistribution) -> String? {
        guard directDistribution else {
            return "This edition receives updates through the App Store."
        }
        let diagnosticArguments: Set<String> = [
            "--self-test", "--window-self-test", "--window-qa", "--spaces-interaction-qa",
            "--font-available", "--integration-check", "--handoff-fixture", "--font-lab-artwork-fixtures",
            "--performance-audit", "--starter-quality-audit", "--stress-regression-check"
        ]
        let isDiagnostic = arguments.contains { argument in
            diagnosticArguments.contains(argument) ||
                (argument.hasPrefix("--") && (argument.hasSuffix("-qa") || argument.hasSuffix("-self-test") || argument.hasSuffix("-audit")))
        }
        if isDiagnostic && !arguments.contains("--updater-qa") {
            return "Update checks are disabled in this test session."
        }
        guard bundleURL.isFileURL, bundleURL.pathExtension == "app",
              info["CFBundleIdentifier"] as? String == bundleIdentifier,
              info["CFBundlePackageType"] as? String == "APPL",
              info["CFBundleExecutable"] as? String == "Typefield",
              executableURL?.standardizedFileURL == bundleURL.appendingPathComponent("Contents/MacOS/Typefield").standardizedFileURL else {
            return "Updates are available in the installed Typefield app."
        }
        guard let version = info["CFBundleShortVersionString"] as? String, !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let build = info["CFBundleVersion"] as? String, let buildNumber = Int(build), buildNumber > 0 else {
            return "This copy of Typefield is missing its release version. Download the latest app from typefield.app."
        }
        guard info["SUFeedURL"] as? String == feedURL else {
            return "This copy of Typefield has an invalid update source. Download the latest app from typefield.app."
        }
        guard let publicKey = info["SUPublicEDKey"] as? String,
              let keyData = Data(base64Encoded: publicKey), keyData.count == 32,
              keyData.contains(where: { $0 != 0 }) else {
            return "This copy of Typefield is missing its update verification key. Download the latest app from typefield.app."
        }
        guard info["SURequireSignedFeed"] as? Bool == true,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              let expiration = info["SUSignedFeedFailureExpirationInterval"] as? NSNumber, expiration.doubleValue == 0 else {
            return "This copy of Typefield has incomplete update security settings. Download the latest app from typefield.app."
        }
        return nil
    }
}

/// One updater for the running app. Sparkle owns scheduling, version comparison,
/// signature verification, installation, and persistent user preferences.
@MainActor
final class TypefieldUpdater: NSObject, ObservableObject {
    static let shared = TypefieldUpdater()

    @Published private(set) var isAvailable = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyDownloadsUpdates = false
    @Published private(set) var allowsAutomaticUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var unavailableReason: String? = "Update checks have not started yet."

    private var didAttemptStart = false
    #if TYPEFIELD_DIRECT_DISTRIBUTION
    private var controller: SPUStandardUpdaterController?
    private var observations = Set<AnyCancellable>()
    private var qaProbeResult: String?
    #endif

    private override init() { super.init() }

    /// Call once from applicationDidFinishLaunching. Test launches return before
    /// constructing the controller; --updater-qa permits information-only QA.
    /// That mode uses a harmless result alert, not Sparkle's installation UI.
    func start() {
        guard !didAttemptStart else { return }
        didAttemptStart = true
        unavailableReason = TypefieldUpdateConfiguration.unavailableReason(
            info: Bundle.main.infoDictionary ?? [:], bundleURL: Bundle.main.bundleURL,
            executableURL: Bundle.main.executableURL, arguments: CommandLine.arguments)
        guard unavailableReason == nil else { return }
        #if TYPEFIELD_DIRECT_DISTRIBUTION
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        do {
            // Starting the wrapped updater directly exposes configuration errors
            // to Settings rather than silently leaving its controls enabled.
            try controller.updater.start()
            isAvailable = true
            observe(controller.updater)
            synchronize(controller.updater)
        } catch {
            self.controller = nil
            unavailableReason = "The updater could not start: \(error.localizedDescription)"
        }
        #endif
    }

    func checkForUpdates() {
        start()
        #if TYPEFIELD_DIRECT_DISTRIBUTION
        guard isAvailable, canCheckForUpdates else { return }
        if TypefieldUpdateConfiguration.permitsInstallation(arguments: CommandLine.arguments) {
            controller?.checkForUpdates(nil)
        } else {
            qaProbeResult = nil
            controller?.updater.checkForUpdateInformation()
        }
        #endif
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        #if TYPEFIELD_DIRECT_DISTRIBUTION
        guard isAvailable, let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        synchronize(updater)
        #endif
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        #if TYPEFIELD_DIRECT_DISTRIBUTION
        guard isAvailable, let updater = controller?.updater, !enabled || updater.allowsAutomaticUpdates else { return }
        updater.automaticallyDownloadsUpdates = enabled
        synchronize(updater)
        #endif
    }

    #if TYPEFIELD_DIRECT_DISTRIBUTION
    private func observe(_ updater: SPUUpdater) {
        // Sparkle documents these properties and callbacks as main-thread only.
        // Observe its source of truth so choices in Sparkle's own dialogs also
        // update Settings, without copying preferences into AppStorage.
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self, weak updater] _ in
                if let updater { self?.synchronize(updater) }
            }.store(in: &observations)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self, weak updater] _ in
                if let updater { self?.synchronize(updater) }
            }.store(in: &observations)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak self, weak updater] _ in
                if let updater { self?.synchronize(updater) }
            }.store(in: &observations)
        updater.publisher(for: \.allowsAutomaticUpdates)
            .sink { [weak self, weak updater] _ in
                if let updater { self?.synchronize(updater) }
            }.store(in: &observations)
        updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self, weak updater] _ in
                if let updater { self?.synchronize(updater) }
            }.store(in: &observations)
    }

    private func synchronize(_ updater: SPUUpdater) {
        canCheckForUpdates = isAvailable && updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }
    #endif
}

#if TYPEFIELD_DIRECT_DISTRIBUTION
extension TypefieldUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        // This gate runs before Sparkle resumes a pending installation. Its
        // shouldProceedWithUpdate callback alone does not cover resumed updates.
        try validateUpdateCheckForQA(updateCheck)
    }

    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        try validateUpdateCheckForQA(updateCheck)
    }

    private func validateUpdateCheckForQA(_ updateCheck: SPUUpdateCheck) throws {
        guard TypefieldUpdateConfiguration.permitsUpdateCheck(
            informationOnly: updateCheck == .updateInformation, arguments: CommandLine.arguments) else {
            throw NSError(domain: "Typefield.UpdaterQA", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Only update information can be checked in this test session. Downloading and installation are disabled."
            ])
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard !TypefieldUpdateConfiguration.permitsInstallation(arguments: CommandLine.arguments) else { return }
        qaProbeResult = "Typefield \(item.displayVersionString) is available."
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        guard !TypefieldUpdateConfiguration.permitsInstallation(arguments: CommandLine.arguments) else { return }
        qaProbeResult = error.localizedDescription
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard !TypefieldUpdateConfiguration.permitsInstallation(arguments: CommandLine.arguments),
              updateCheck == .updateInformation else { return }
        let result = qaProbeResult ?? error?.localizedDescription ?? "Update information was checked."
        let failed = qaProbeResult == nil && error != nil
        qaProbeResult = nil
        // Let Sparkle complete its state transition before opening the QA alert.
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Typefield Update Check — Test Session"
            alert.informativeText = result + "\n\nThis test session only checks release information. It cannot download or install updates."
            alert.alertStyle = failed ? .warning : .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        // The release feed is fixed in production, even if a defaults or launch
        // argument attempts to override Sparkle's SUFeedURL preference.
        TypefieldUpdateConfiguration.feedURL
    }
}
#endif
