import Foundation
import CryptoKit

/// X25519 identity + sealed-box style message crypto (CryptoKit).
final class KeyStore {
    private let privKey = "identity_x25519_priv"
    private let pubKey = "identity_x25519_pub"

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
            salt: Data("t9-msg-v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )
        let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: sym)
        // ephemeral_pub || nonce || ciphertext+tag
        var out = Data()
        out.append(ephemeral.publicKey.rawRepresentation)
        out.append(sealed.nonce.withUnsafeBytes { Data($0) })
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    func open(ciphertext: Data) throws -> String {
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
            salt: Data("t9-msg-v1".utf8),
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
