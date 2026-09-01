import CryptoKit
import Foundation

/// Pro unlocking.
///
/// A licence key is an Ed25519 signature over the buyer's email address, made
/// with a private key that never leaves the vendor. The app carries only the
/// public half, so keys verify offline — no account, no phone-home, and the app
/// keeps working if the licence server ever goes away.
///
/// What this deliberately cannot do is enforce a per-machine limit: an offline
/// signature is valid wherever it is pasted. Counting activations needs a
/// server, which is a trade against working offline. This picks offline.
public final class LicenseStore {
    public static let shared = LicenseStore()

    /// The public half of the signing pair. The private half lives outside the
    /// repository — see `scripts/make-license.swift`.
    private static let publicKeyBase64 = "Ko34e652FFRzkRFLmzbUWYibgpWJG+LRaUW4F/X0qkM="

    private static let emailKey = "licenseEmail"
    private static let keyKey = "licenseKey"

    private init() {}

    /// Features held back until a licence is present.
    public enum ProFeature: String, CaseIterable, Sendable {
        case forcedHiDPI

        public var title: String {
            switch self {
            case .forcedHiDPI:
                return L10n.t("让外接屏的文字和内建屏一样锐利",
                              "Make an external display's text as sharp as the built-in one")
            }
        }

        public var explanation: String {
            switch self {
            case .forcedHiDPI:
                return L10n.t("你的显示器像素足够多，缺的只是 macOS 愿意用 2 倍渲染的那几档模式。Lumen 把它们补进系统，重启后就多出「看起来像 2560×1440」这样的选项 —— 和 Retina 屏同一种渲染方式，而不是被拉伸过的近似值。",
                              "Your monitor has the pixels. What it lacks are the modes macOS will render at 2× into. Lumen writes them into the system, and after a restart you get options like \u{201C}looks like 2560×1440\u{201D} — rendered the way a Retina screen is, instead of a stretched approximation.")
            }
        }

        /// The one-line promise, for places with no room for the full pitch.
        public var headline: String {
            switch self {
            case .forcedHiDPI:
                return L10n.t("补上 macOS 没给你的那几档 Retina 分辨率",
                              "Adds the Retina resolutions macOS never offered you")
            }
        }
    }

    // MARK: - State

    public var licensedEmail: String? {
        Defaults.shared.string(forKey: Self.emailKey)
    }

    /// Re-verified on every read rather than cached as a boolean, so editing
    /// the stored defaults does not unlock anything.
    public var isPro: Bool {
        guard let email = Defaults.shared.string(forKey: Self.emailKey),
              let key = Defaults.shared.string(forKey: Self.keyKey)
        else { return false }
        return verify(email: email, key: key)
    }

    public func isUnlocked(_ feature: ProFeature) -> Bool { isPro }

    // MARK: - Activation

    public enum ActivationResult {
        case activated
        case invalid
        case malformed

        public var message: String {
            switch self {
            case .activated: return L10n.t("已解锁 Lumen Pro，谢谢支持。", "Lumen Pro unlocked — thank you.")
            case .invalid: return L10n.t("这个密钥和邮箱对不上。", "That key does not match this email address.")
            case .malformed: return L10n.t("密钥格式不对，请完整粘贴。", "That key is not in the right format — paste the whole thing.")
            }
        }
    }

    @discardableResult
    public func activate(email: String, key: String) -> ActivationResult {
        let normalized = Self.normalize(email)
        guard !normalized.isEmpty, Data(base64Encoded: Self.compact(key)) != nil else {
            return .malformed
        }
        guard verify(email: normalized, key: key) else { return .invalid }

        Defaults.shared.set(normalized, forKey: Self.emailKey)
        Defaults.shared.set(Self.compact(key), forKey: Self.keyKey)
        Log.info("pro licence activated")
        return .activated
    }

    public func deactivate() {
        Defaults.shared.removeObject(forKey: Self.emailKey)
        Defaults.shared.removeObject(forKey: Self.keyKey)
    }

    // MARK: - Verification

    /// Email is normalised the same way at signing and checking time, so
    /// capitalisation or a stray space in the licence email is not a failure.
    static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Keys are shown in groups for readability; whitespace is not part of them.
    static func compact(_ key: String) -> String {
        key.filter { !$0.isWhitespace }
    }

    public func verify(email: String, key: String) -> Bool {
        guard let publicKeyData = Data(base64Encoded: Self.publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData),
              let signature = Data(base64Encoded: Self.compact(key))
        else { return false }
        let payload = Data(Self.normalize(email).utf8)
        return publicKey.isValidSignature(signature, for: payload)
    }
}
