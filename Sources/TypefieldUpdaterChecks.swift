import Foundation

/// Pure configuration regressions: never creates Sparkle, accesses the Keychain,
/// changes preferences, or starts a network request.
enum TypefieldUpdaterChecks {
    static func run() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "Typefield.UpdaterChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let appURL = URL(fileURLWithPath: "/Applications/Typefield.app")
        let executableURL = appURL.appendingPathComponent("Contents/MacOS/Typefield")
        let validInfo: [String: Any] = [
            "CFBundleIdentifier": "local.typefield.app", "CFBundlePackageType": "APPL", "CFBundleExecutable": "Typefield",
            "CFBundleShortVersionString": "0.60.0", "CFBundleVersion": "102",
            "SUFeedURL": "https://typefield.app/updates/appcast.xml",
            "SUPublicEDKey": Data((1...32).map(UInt8.init)).base64EncodedString(),
            "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true, "SUSignedFeedFailureExpirationInterval": 0
        ]
        func reason(_ info: [String: Any], arguments: [String] = ["Typefield"], direct: Bool = true,
                    bundle: URL? = nil, executable: URL? = nil) -> String? {
            TypefieldUpdateConfiguration.unavailableReason(info: info, bundleURL: bundle ?? appURL,
                executableURL: executable ?? executableURL, arguments: arguments, directDistribution: direct)
        }
        try require(reason(validInfo) == nil, "A configured direct application can initialize its updater")
        try require(reason(validInfo, arguments: ["Typefield", "-psn_0_12345"]) == nil, "Normal macOS launch arguments do not disable updates")
        try require(reason(validInfo, direct: false)?.contains("App Store") == true, "Store builds cannot initialize an external updater")
        try require(reason(validInfo, arguments: ["Typefield", "--updater-qa"], direct: false) != nil, "Updater QA cannot enable the updater in a Store build")
        for argument in ["--self-test", "--window-self-test", "--window-qa", "--spaces-interaction-qa", "--font-available",
                         "--integration-check", "--handoff-fixture", "--font-lab-artwork-fixtures", "--performance-audit",
                         "--starter-quality-audit", "--stress-regression-check", "--future-feature-qa"] {
            try require(reason(validInfo, arguments: ["Typefield", argument])?.contains("test session") == true,
                        "\(argument) must not initialize Sparkle or change user defaults")
            try require(reason(validInfo, arguments: ["Typefield", argument, "--updater-qa"]) == nil,
                        "Dedicated updater QA opts into update initialization: \(argument)")
        }
        for (key, replacement) in [
            ("CFBundleIdentifier", "local.typefield.test"), ("CFBundlePackageType", "BNDL"),
            ("CFBundleExecutable", "Fixture"), ("CFBundleShortVersionString", " "), ("CFBundleVersion", "0"),
            ("CFBundleVersion", "unknown"), ("SUFeedURL", "http://typefield.app/updates/appcast.xml"),
            ("SUFeedURL", "https://example.com/appcast.xml"), ("SUFeedURL", "https://typefield.app/updates/appcast.xml?test=true"),
            ("SUPublicEDKey", "placeholder"), ("SUPublicEDKey", Data(repeating: 0, count: 32).base64EncodedString()),
            ("SUPublicEDKey", Data(repeating: 1, count: 31).base64EncodedString())
        ] {
            var invalidInfo = validInfo
            invalidInfo[key] = replacement
            try require(reason(invalidInfo) != nil, "Invalid \(key) must prevent updater startup")
            try require(reason(invalidInfo, arguments: ["Typefield", "--updater-qa"]) != nil,
                        "Updater QA cannot bypass validation of \(key)")
        }
        try require(TypefieldUpdateConfiguration.permitsInstallation(arguments: ["Typefield"]), "Normal direct launches permit signed installation")
        try require(!TypefieldUpdateConfiguration.permitsInstallation(arguments: ["Typefield", "--updater-qa"]), "Updater QA cannot install or relaunch without fixture arguments")
        for informationOnly in [false, true] {
            try require(TypefieldUpdateConfiguration.permitsUpdateCheck(informationOnly: informationOnly, arguments: ["Typefield"]),
                        "Normal launches retain all Sparkle check modes")
            try require(TypefieldUpdateConfiguration.permitsUpdateCheck(informationOnly: informationOnly, arguments: ["Typefield", "--updater-qa"]) == informationOnly,
                        "Updater QA permits only information checks, before pending-install resume")
        }
        for (key, replacement) in [("SURequireSignedFeed", false as Any), ("SUVerifyUpdateBeforeExtraction", false as Any),
                                   ("SUSignedFeedFailureExpirationInterval", 1 as Any)] {
            var insecureInfo = validInfo
            insecureInfo[key] = replacement
            try require(reason(insecureInfo) != nil, "Security policy cannot be weakened: \(key)")
            insecureInfo.removeValue(forKey: key)
            try require(reason(insecureInfo) != nil, "Security policy cannot be omitted: \(key)")
        }
        var missingKey = validInfo
        missingKey.removeValue(forKey: "SUPublicEDKey")
        try require(reason(missingKey) != nil, "An unsigned update configuration must be rejected")
        try require(reason(validInfo, bundle: URL(fileURLWithPath: "/tmp/Typefield")) != nil, "A bare CLI cannot initialize the updater")
        try require(reason(validInfo, executable: URL(fileURLWithPath: "/tmp/Typefield")) != nil, "An executable outside the application cannot initialize the updater")
        try require(TypefieldUpdateConfiguration.unavailableReason(info: validInfo, bundleURL: appURL, executableURL: nil,
            arguments: ["Typefield"], directDistribution: true) != nil, "Missing executable cannot initialize the updater")
        print("Updater checks passed: direct/Store isolation, diagnostic launch guards, explicit updater QA, bundled executable/version, pinned HTTPS feed, verification-key configuration, fail-closed signed feeds, and information-only QA that blocks resumed installation.")
    }
}
