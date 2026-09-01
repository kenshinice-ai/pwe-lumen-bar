#!/usr/bin/env swift
import CryptoKit
import Foundation

// Signs one PWE Lumen Bar Pro licence key.
//
//   swift tools/sign-license.swift --email buyer@example.com [--key-file <path>]
//
// The key is an Ed25519 signature over the buyer's email address, lower-cased
// and trimmed — the same bytes `LicenseStore` verifies against the public half
// embedded in the app. It prints the key and nothing else, so callers can
// capture it; `tools/issue.sh` is the thing you normally run.
//
// The private key lives in the vault at ~/.pwe-lumenbar-signing/signing-key and
// must never ship with the app. Lose it and no new keys can ever be issued;
// leak it and anyone can issue them.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

var email: String?
var keyPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".pwe-lumenbar-signing/signing-key").path

var arguments = Array(CommandLine.arguments.dropFirst())
while let flag = arguments.first {
    arguments.removeFirst()
    switch flag {
    case "--email":    email = arguments.first; arguments = Array(arguments.dropFirst())
    case "--key-file": keyPath = arguments.first ?? keyPath; arguments = Array(arguments.dropFirst())
    case "--help", "-h":
        print("usage: swift tools/sign-license.swift --email <address> [--key-file <path>]")
        exit(0)
    default:
        // Bare argument: treat it as the email, so the old form still works.
        if email == nil { email = flag } else { fail("unexpected argument: \(flag)") }
    }
}

guard let address = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      !address.isEmpty, address.contains("@") else {
    fail("usage: swift tools/sign-license.swift --email <address>")
}

guard let raw = try? String(contentsOfFile: keyPath, encoding: .utf8),
      let secret = Data(base64Encoded: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
      let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: secret) else {
    fail("cannot read a signing key from \(keyPath)")
}

guard let signature = try? privateKey.signature(for: Data(address.utf8)) else {
    fail("signing failed")
}

print(signature.base64EncodedString())
