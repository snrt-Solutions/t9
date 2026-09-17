package io.aesms.app.crypto

import android.util.Base64
import org.bouncycastle.crypto.agreement.X25519Agreement
import org.bouncycastle.crypto.digests.SHA256Digest
import org.bouncycastle.crypto.generators.HKDFBytesGenerator
import org.bouncycastle.crypto.params.HKDFParameters
import org.bouncycastle.crypto.params.X25519PrivateKeyParameters
import org.bouncycastle.crypto.params.X25519PublicKeyParameters
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.zip.Deflater
import java.util.zip.Inflater
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** X25519 identity + sealed-box message crypto matching the iOS CryptoKit client. */
class KeyStore(private val secrets: SecureSecrets) {
    data class Identity(
        val privateKeyRaw: ByteArray,
        val publicKeyB64: String,
    )

    fun loadOrCreateIdentity(): Identity {
        val existing = secrets.get(PRIV_KEY)
        if (existing != null) {
            val privRaw = Base64.decode(existing, Base64.DEFAULT)
            val priv = X25519PrivateKeyParameters(privRaw, 0)
            val pub = Base64.encodeToString(priv.generatePublicKey().encoded, Base64.NO_WRAP)
            secrets.set(PUB_KEY, pub)
            return Identity(privRaw, pub)
        }
        val priv = X25519PrivateKeyParameters(SecureRandom())
        val privB64 = Base64.encodeToString(priv.encoded, Base64.NO_WRAP)
        val pub = Base64.encodeToString(priv.generatePublicKey().encoded, Base64.NO_WRAP)
        secrets.set(PRIV_KEY, privB64)
        secrets.set(PUB_KEY, pub)
        return Identity(priv.encoded, pub)
    }

    fun publicKeyB64(): String = loadOrCreateIdentity().publicKeyB64

    fun seal(plaintext: String, toRecipientPubB64: String): ByteArray {
        val theirPub = X25519PublicKeyParameters(Base64.decode(toRecipientPubB64, Base64.DEFAULT), 0)
        val ephemeral = X25519PrivateKeyParameters(SecureRandom())
        val shared = agree(ephemeral, theirPub)
        val sym = hkdf(shared, MSG_V2_SALT)
        val utf8 = plaintext.toByteArray(Charsets.UTF_8)
        val compressed = zlibCompress(utf8)
        val useCompress = compressed.size < utf8.size
        val inner = ByteArray(1 + if (useCompress) compressed.size else utf8.size)
        inner[0] = if (useCompress) 1 else 0
        System.arraycopy(if (useCompress) compressed else utf8, 0, inner, 1, inner.size - 1)
        val nonce = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val sealed = aesGcmEncrypt(sym, nonce, inner)
        return V2_MAGIC + ephemeral.generatePublicKey().encoded + nonce + sealed
    }

    fun open(ciphertext: ByteArray): String {
        if (ciphertext.size >= V2_MAGIC.size && ciphertext.copyOfRange(0, V2_MAGIC.size).contentEquals(V2_MAGIC)) {
            return openV2(ciphertext.copyOfRange(V2_MAGIC.size, ciphertext.size))
        }
        return openV1(ciphertext)
    }

    private fun openV2(body: ByteArray): String {
        require(body.size > 32 + 12 + 16) { "bad cipher" }
        val id = loadOrCreateIdentity()
        val ephPub = X25519PublicKeyParameters(body.copyOfRange(0, 32), 0)
        val nonce = body.copyOfRange(32, 44)
        val ctAndTag = body.copyOfRange(44, body.size)
        val shared = agree(X25519PrivateKeyParameters(id.privateKeyRaw, 0), ephPub)
        val sym = hkdf(shared, MSG_V2_SALT)
        val plain = aesGcmDecrypt(sym, nonce, ctAndTag)
        require(plain.isNotEmpty()) { "bad cipher" }
        val payload = plain.copyOfRange(1, plain.size)
        val utf8 = if (plain[0] == 1.toByte()) zlibDecompress(payload) else payload
        return utf8.toString(Charsets.UTF_8)
    }

    private fun openV1(ciphertext: ByteArray): String {
        require(ciphertext.size > 32 + 12 + 16) { "bad cipher" }
        val id = loadOrCreateIdentity()
        val ephPub = X25519PublicKeyParameters(ciphertext.copyOfRange(0, 32), 0)
        val nonce = ciphertext.copyOfRange(32, 44)
        val ctAndTag = ciphertext.copyOfRange(44, ciphertext.size)
        val shared = agree(X25519PrivateKeyParameters(id.privateKeyRaw, 0), ephPub)
        val sym = hkdf(shared, MSG_V1_SALT)
        val plain = aesGcmDecrypt(sym, nonce, ctAndTag)
        return plain.toString(Charsets.UTF_8)
    }

    companion object {
        private const val PRIV_KEY = "identity_x25519_priv"
        private const val PUB_KEY = "identity_x25519_pub"
        private val V2_MAGIC = "AESMS2".toByteArray(Charsets.UTF_8)
        private val MSG_V1_SALT = "aesms-msg-v1".toByteArray(Charsets.UTF_8)
        private val MSG_V2_SALT = "aesms-msg-v2".toByteArray(Charsets.UTF_8)

        fun agree(priv: X25519PrivateKeyParameters, pub: X25519PublicKeyParameters): ByteArray {
            val agreement = X25519Agreement()
            agreement.init(priv)
            val out = ByteArray(agreement.agreementSize)
            agreement.calculateAgreement(pub, out, 0)
            return out
        }

        fun hkdf(ikm: ByteArray, salt: ByteArray, info: ByteArray = ByteArray(0), len: Int = 32): ByteArray {
            val out = ByteArray(len)
            val hkdf = HKDFBytesGenerator(SHA256Digest())
            hkdf.init(HKDFParameters(ikm, salt, info))
            hkdf.generateBytes(out, 0, len)
            return out
        }

        fun aesGcmEncrypt(key: ByteArray, nonce: ByteArray, plaintext: ByteArray): ByteArray {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
            return cipher.doFinal(plaintext) // ct || tag
        }

        fun aesGcmDecrypt(key: ByteArray, nonce: ByteArray, ctAndTag: ByteArray): ByteArray {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
            return cipher.doFinal(ctAndTag)
        }

        fun zlibCompress(src: ByteArray): ByteArray {
            if (src.isEmpty()) return src
            val deflater = Deflater(Deflater.DEFAULT_COMPRESSION, false)
            deflater.setInput(src)
            deflater.finish()
            val buf = ByteArray(src.size + maxOf(src.size / 4, 64) + 32)
            val n = deflater.deflate(buf)
            deflater.end()
            return buf.copyOf(n)
        }

        fun zlibDecompress(src: ByteArray): ByteArray {
            if (src.isEmpty()) return src
            val inflater = Inflater(false)
            inflater.setInput(src)
            var capacity = maxOf(src.size * 8, 256)
            while (capacity <= 1_048_576) {
                val out = ByteArray(capacity)
                try {
                    val n = inflater.inflate(out)
                    if (n > 0 || inflater.finished()) {
                        inflater.end()
                        return out.copyOf(n)
                    }
                } catch (_: Exception) {
                    // grow
                }
                capacity *= 2
                inflater.reset()
                inflater.setInput(src)
            }
            inflater.end()
            error("decompress failed")
        }

        /** MVP backup KDF: iterated SHA-256 (120k), matching iOS. */
        fun deriveBackupKey(passphrase: String, salt: ByteArray): ByteArray {
            var block = passphrase.toByteArray(Charsets.UTF_8) + salt
            val md = MessageDigest.getInstance("SHA-256")
            repeat(120_000) {
                block = md.digest(block)
            }
            return block
        }
    }
}

fun ByteArray.base64Url(): String =
    Base64.encodeToString(this, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)

fun decodeBase64UrlOrStd(s: String): ByteArray? {
    return try {
        Base64.decode(s, Base64.DEFAULT)
    } catch (_: Exception) {
        try {
            var padded = s.replace('-', '+').replace('_', '/')
            val pad = (4 - padded.length % 4) % 4
            if (pad > 0) padded += "=".repeat(pad)
            Base64.decode(padded, Base64.DEFAULT)
        } catch (_: Exception) {
            null
        }
    }
}
