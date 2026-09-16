import Foundation
import Compression
import CryptoKit
import Security

final class LocalStore {
    private let contactsURL: URL
    private let messagesURL: URL
    private let contactsLegacyURL: URL
    private let messagesLegacyURL: URL
    private static let fileMagic = Data("AESMSL1".utf8)
    private static let storeKeyAccount = "local_store_aes_key"

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AeSMS", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        contactsLegacyURL = dir.appendingPathComponent("contacts.json")
        messagesLegacyURL = dir.appendingPathComponent("kept-messages.json")
        contactsURL = dir.appendingPathComponent("contacts.sealed")
        messagesURL = dir.appendingPathComponent("kept-messages.sealed")
        Self.excludeFromBackup(dir)
    }

    func loadContacts() -> [Contact] {
        if let items: [Contact] = loadSealed(from: contactsURL) {
            return items
        }
        // Migrate plaintext MVP files once.
        if let data = try? Data(contentsOf: contactsLegacyURL),
           let items = try? JSONDecoder().decode([Contact].self, from: data) {
            saveContacts(items)
            try? FileManager.default.removeItem(at: contactsLegacyURL)
            return items
        }
        return []
    }

    func saveContacts(_ items: [Contact]) {
        saveSealed(items, to: contactsURL)
        try? FileManager.default.removeItem(at: contactsLegacyURL)
    }

    func loadKeptMessages() -> [LocalMessage] {
        if let items: [LocalMessage] = loadSealed(from: messagesURL) {
            return items
        }
        if let data = try? Data(contentsOf: messagesLegacyURL),
           let items = try? JSONDecoder().decode([LocalMessage].self, from: data) {
            saveKeptMessages(items)
            try? FileManager.default.removeItem(at: messagesLegacyURL)
            return items
        }
        return []
    }

    func saveKeptMessages(_ items: [LocalMessage]) {
        saveSealed(items, to: messagesURL)
        try? FileManager.default.removeItem(at: messagesLegacyURL)
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
        let compressed = (try? PayloadCodec.zlibCompress(json)) ?? json
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let key = deriveKey(passphrase: passphrase, salt: salt)
        let sealed = try AES.GCM.seal(compressed, using: key)
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
        let opened = try AES.GCM.open(box, using: key)
        let plain = (try? PayloadCodec.zlibDecompress(opened)) ?? opened
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

    private func saveSealed<T: Encodable>(_ value: T, to url: URL) {
        guard let json = try? JSONEncoder().encode(value) else { return }
        let compressed = (try? PayloadCodec.zlibCompress(json)) ?? json
        guard let key = storeKey(),
              let sealed = try? AES.GCM.seal(compressed, using: key),
              let combined = sealed.combined else { return }
        var out = Self.fileMagic
        out.append(combined) // nonce || ct || tag
        try? out.write(to: url, options: .atomic)
        Self.excludeFromBackup(url)
    }

    private func loadSealed<T: Decodable>(from url: URL) -> T? {
        guard let raw = try? Data(contentsOf: url),
              raw.count > Self.fileMagic.count + 12 + 16,
              raw.starts(with: Self.fileMagic),
              let key = storeKey() else { return nil }
        let sealed = raw.dropFirst(Self.fileMagic.count)
        guard let box = try? AES.GCM.SealedBox(combined: Data(sealed)),
              let opened = try? AES.GCM.open(box, using: key) else { return nil }
        let json = (try? PayloadCodec.zlibDecompress(opened)) ?? opened
        return try? JSONDecoder().decode(T.self, from: json)
    }

    private func storeKey() -> SymmetricKey? {
        if let b64 = Keychain.get(Self.storeKeyAccount),
           let data = Data(base64Encoded: b64),
           data.count == 32 {
            return SymmetricKey(data: data)
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { return nil }
        let data = Data(bytes)
        Keychain.set(Self.storeKeyAccount, value: data.base64EncodedString())
        return SymmetricKey(data: data)
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
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

/// zlib (deflate) helpers for pre-seal / pre-encrypt compression.
enum PayloadCodec {
    static func zlibCompress(_ src: Data) throws -> Data {
        guard !src.isEmpty else { return src }
        let capacity = src.count + max(src.count / 4, 64) + 32
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { dst.deallocate() }
        let written = src.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(dst, capacity, base, src.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { throw CodecError.failed }
        return Data(bytes: dst, count: written)
    }

    static func zlibDecompress(_ src: Data) throws -> Data {
        guard !src.isEmpty else { return src }
        var capacity = max(src.count * 8, 256)
        while capacity <= 1_048_576 {
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { dst.deallocate() }
            let written = src.withUnsafeBytes { raw -> Int in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dst, capacity, base, src.count, nil, COMPRESSION_ZLIB)
            }
            if written > 0 {
                return Data(bytes: dst, count: written)
            }
            capacity *= 2
        }
        throw CodecError.failed
    }

    enum CodecError: Error { case failed }
}
