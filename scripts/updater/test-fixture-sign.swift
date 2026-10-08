// Public RFC 8032 test vector seed; exclusively for disposable regression fixtures.
// This well-known test key must never be used to sign a Typefield release.
import CryptoKit
import Foundation

let seed = Data([0x9d, 0x61, 0xb1, 0x9d, 0xef, 0xfd, 0x5a, 0x60,
                 0xba, 0x84, 0x4a, 0xf4, 0x92, 0xec, 0x2c, 0xc4,
                 0x44, 0x49, 0xc5, 0x69, 0x7b, 0x32, 0x69, 0x19,
                 0x70, 0x3b, 0xac, 0x03, 0x1c, 0xae, 0x7f, 0x60])
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let signature = try key.signature(for: data)
print(key.publicKey.rawRepresentation.base64EncodedString())
print(signature.base64EncodedString())
