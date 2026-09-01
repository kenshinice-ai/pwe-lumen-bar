#!/usr/bin/env swift
import CryptoKit
import Foundation

// Issues a Lumen Pro licence key.
//
//   swift scripts/make-license.swift buyer@example.com
//
// Reads the private signing key from `.license-signing-key` in the repository
// root — that file is git-ignored and must never ship with the app. Losing it
// means no new keys can be issued; leaking it means anyone can issue them.

let arguments = Array(CommandLine.arguments.dropFirst())
guard let email = arguments.first else {
    print("usage: swift scripts/make-license.swift <email>")
    exit(1)
}

let keyPath = FileManager.default.currentDirectoryPath + "/.license-signing-key"
guard let raw = try? String(contentsOfFile: keyPath, encoding: .utf8),
      let secret = Data(base64Encoded: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
      let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: secret) else {
    print("cannot read a signing key from \(keyPath)")
    exit(1)
}

let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
guard let signature = try? privateKey.signature(for: Data(normalized.utf8)) else {
    print("signing failed")
    exit(1)
}

// Grouped for the buyer's benefit; the app strips whitespace before checking.
let key = signature.base64EncodedString()
let grouped = stride(from: 0, to: key.count, by: 22).map { offset -> String in
    let start = key.index(key.startIndex, offsetBy: offset)
    let end = key.index(start, offsetBy: min(22, key.count - offset))
    return String(key[start ..< end])
}.joined(separator: "\n")

print("email: \(normalized)")
print("key:")
print(grouped)
