// Public-key-only Ed25519 verification; never needs the release signing key.
import CryptoKit
import Foundation

do {
    guard CommandLine.arguments.count == 5,
          let publicKey = Data(base64Encoded: CommandLine.arguments[1]), publicKey.count == 32,
          let signature = Data(base64Encoded: CommandLine.arguments[2]), signature.count == 64,
          let length = Int(CommandLine.arguments[4]), length >= 0 else {
        throw NSError(domain: "TypefieldSignature", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid signature verification arguments"])
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]), options: .mappedIfSafe)
    guard data.count >= length else {
        throw NSError(domain: "TypefieldSignature", code: 2, userInfo: [NSLocalizedDescriptionKey: "Signed length exceeds the file size"])
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    guard key.isValidSignature(signature, for: data.prefix(length)) else {
        throw NSError(domain: "TypefieldSignature", code: 3, userInfo: [NSLocalizedDescriptionKey: "Ed25519 signature does not match the app's public key"])
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
