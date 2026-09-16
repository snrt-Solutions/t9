import Foundation
import CryptoKit

/// X25519 identity + sealed-box style message crypto (CryptoKit).
///
/// Wire formats:
/// - v1: `eph_pub(32) || nonce(12) || ct||tag` over raw UTF-8 (HKDF salt `aesms-msg-v1`)
/// - v2: `AESMS2` + same layout over zlib(UTF-8) (HKDF salt `aesms-msg-v2`) — smaller on the wire
final class KeyStore {
    private let privKey = "identity_x25519_priv"
    private let pubKey = "identity_x25519_pub"
    private static let v2Magic = Data("AESMS2".utf8)

    struct Identity {
        var privateKey: Curve25519.KeyAgreement.PrivateKey
        var publicKeyB64: String
    }

    @discardableResult
    func loadOrCreateIdentity() -> Identity {
        if let privB64 = Keychain.get(privKey),
           let data = Data(base64Encoded: privB64),
           let priv = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
            let pub = priv.publicKey.rawRepresentation.base64EncodedString()
            Keychain.set(pubKey, value: pub)
            return Identity(privateKey: priv, publicKeyB64: pub)
        }
        let priv = Curve25519.KeyAgreement.PrivateKey()
        Keychain.set(privKey, value: priv.rawRepresentation.base64EncodedString())
        let pub = priv.publicKey.rawRepresentation.base64EncodedString()
        Keychain.set(pubKey, value: pub)
        return Identity(privateKey: priv, publicKeyB64: pub)
    }

    func publicKeyB64() -> String { loadOrCreateIdentity().publicKeyB64 }

    func seal(plaintext: String, toRecipientPubB64: String) throws -> Data {
        guard let pubData = Data(base64Encoded: toRecipientPubB64) else {
            throw CryptoError.badKey
        }
        let theirPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pubData)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: theirPub)
        let sym = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("aesms-msg-v2".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )
        let utf8 = Data(plaintext.utf8)
        let compressed = (try? PayloadCodec.zlibCompress(utf8)) ?? utf8
        let useCompress = compressed.count < utf8.count
        var inner = Data()
        inner.append(useCompress ? 1 : 0)
        inner.append(useCompress ? compressed : utf8)

        let sealed = try AES.GCM.seal(inner, using: sym)
        var out = Self.v2Magic
        out.append(ephemeral.publicKey.rawRepresentation)
        out.append(sealed.nonce.withUnsafeBytes { Data($0) })
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    func open(ciphertext: Data) throws -> String {
        if ciphertext.starts(with: Self.v2Magic) {
            return try openV2(ciphertext.dropFirst(Self.v2Magic.count))
        }
        return try openV1(ciphertext)
    }

    private func openV2(_ body: Data) throws -> String {
        let id = loadOrCreateIdentity()
        guard body.count > 32 + 12 + 16 else { throw CryptoError.badCipher }
        let ephPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: body.prefix(32))
        let rest = body.dropFirst(32)
        let nonce = try AES.GCM.Nonce(data: rest.prefix(12))
        let ctAndTag = rest.dropFirst(12)
        let tag = ctAndTag.suffix(16)
        let ct = ctAndTag.dropLast(16)
        let shared = try id.privateKey.sharedSecretFromKeyAgreement(with: ephPub)
        let sym = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("aesms-msg-v2".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
        let plain = try AES.GCM.open(box, using: sym)
        guard let flag = plain.first else { throw CryptoError.badCipher }
        let payload = plain.dropFirst()
        let utf8: Data
        if flag == 1 {
            utf8 = try PayloadCodec.zlibDecompress(Data(payload))
        } else {
            utf8 = Data(payload)
        }
        guard let s = String(data: utf8, encoding: .utf8) else { throw CryptoError.badCipher }
        return s
    }

    private func openV1(_ ciphertext: Data) throws -> String {
        let id = loadOrCreateIdentity()
        guard ciphertext.count > 32 + 12 + 16 else { throw CryptoError.badCipher }
        let ephPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ciphertext.prefix(32))
        let rest = ciphertext.dropFirst(32)
        let nonce = try AES.GCM.Nonce(data: rest.prefix(12))
        let ctAndTag = rest.dropFirst(12)
        let tag = ctAndTag.suffix(16)
        let ct = ctAndTag.dropLast(16)
        let shared = try id.privateKey.sharedSecretFromKeyAgreement(with: ephPub)
        let sym = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("aesms-msg-v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
        let plain = try AES.GCM.open(box, using: sym)
        guard let s = String(data: plain, encoding: .utf8) else { throw CryptoError.badCipher }
        return s
    }

    enum CryptoError: Error { case badKey, badCipher }
}

enum Grapheme {
    static func count(_ s: String) -> Int {
        s.count // Swift Character ≈ extended grapheme cluster
    }
}

extension Data {
    /// Compact URL-safe base64 without padding (matches server RawURLEncoding).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLOrStdEncoded string: String) {
        if let d = Data(base64Encoded: string) {
            self = d
            return
        }
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        if pad > 0 { s.append(String(repeating: "=", count: pad)) }
        guard let d = Data(base64Encoded: s) else { return nil }
        self = d
    }
}
