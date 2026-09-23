// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Typefield", platforms: [.macOS(.v13)], products: [.executable(name: "Typefield", targets: ["Typefield"])], targets: [.executableTarget(name: "Typefield", path: "Sources")])
