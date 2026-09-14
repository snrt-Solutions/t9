import Foundation
import CryptoKit

final class LocalStore {
    private let contactsURL: URL
    private let messagesURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("T9", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        contactsURL = dir.appendingPathComponent("contacts.json")
        messagesURL = dir.appendingPathComponent("kept-messages.json")
    }

    func loadContacts() -> [Contact] {
        guard let data = try? Data(contentsOf: contactsURL) else { return [] }
        return (try? JSONDecoder().decode([Contact].self, from: data)) ?? []
    }

    func saveContacts(_ items: [Contact]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: contactsURL, options: .atomic)
    }

    func loadKeptMessages() -> [LocalMessage] {
        guard let data = try? Data(contentsOf: messagesURL) else { return [] }
        return (try? JSONDecoder().decode([LocalMessage].self, from: data)) ?? []
    }

    func saveKeptMessages(_ items: [LocalMessage]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: messagesURL, options: .atomic)
    }

    /// Passphrase-protected backup of keys + contacts (Argon2-like via CryptoKit slow hash + AES-GCM).
    func exportBackup(passphrase: String, identityPrivB64: String, identityPubB64: String, contacts: [Contact]) throws -> Data {
        let payload: [String: Any] = [
            "v": 1,
            "priv": identityPrivB64,
            "pub": identityPubB64,
            "contacts": try JSONEncoder().encode(contacts).base64EncodedString(),
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let key = deriveKey(passphrase: passphrase, salt: salt)
        let sealed = try AES.GCM.seal(json, using: key)
        var out = Data("T9BK1".utf8)
        out.append(salt)
        out.append(sealed.nonce.withUnsafeBytes { Data($0) })
        out.append(sealed.ciphertext)
        out.append(sealed.tag)
        return out
    }

    func importBackup(data: Data, passphrase: String) throws -> (priv: String, pub: String, contacts: [Contact]) {
        guard data.count > 5 + 16 + 12 + 16, String(data: data.prefix(5), encoding: .utf8) == "T9BK1" else {
            throw BackupError.badFormat
        }
        let salt = data.subdata(in: 5..<21)
        let nonce = try AES.GCM.Nonce(data: data.subdata(in: 21..<33))
        let rest = data.subdata(in: 33..<data.count)
        let tag = rest.suffix(16)
        let ct = rest.dropLast(16)
        let key = deriveKey(passphrase: passphrase, salt: salt)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
        let plain = try AES.GCM.open(box, using: key)
        guard let obj = try JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let priv = obj["priv"] as? String,
              let pub = obj["pub"] as? String,
              let cB64 = obj["contacts"] as? String,
              let cData = Data(base64Encoded: cB64),
              let contacts = try? JSONDecoder().decode([Contact].self, from: cData) else {
            throw BackupError.badFormat
        }
        return (priv, pub, contacts)
    }

    private func deriveKey(passphrase: String, salt: Data) -> SymmetricKey {
        // MVP KDF: iterated SHA256 (documented as interim; Argon2 preferred when available).
        var block = Data(passphrase.utf8) + salt
        for _ in 0..<120_000 {
            block = Data(SHA256.hash(data: block))
        }
        return SymmetricKey(data: block)
    }

    enum BackupError: Error { case badFormat }
}
