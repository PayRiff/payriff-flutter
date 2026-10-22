package com.payriff.flutter

import java.security.GeneralSecurityException
import java.security.KeyFactory
import java.security.SecureRandom
import java.security.interfaces.RSAPublicKey
import java.security.spec.MGF1ParameterSpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec

/**
 * CONTRACT §16.6 card encryption (vectors: `test/vectors/card_crypto.json`).
 *
 * - `encryptedMessage` = AES-256-GCM(aesKey, iv, cardJson): ciphertext || 16-byte tag, no IV prefix.
 * - `wrappedKey` = RSA-OAEP(SHA-256, MGF1-SHA-256, empty label)(publicKey, aesKey || iv).
 *
 * Pure JVM code (no Android APIs), so it runs in local unit tests. Raw bytes in, raw bytes
 * out; the plugin does the Base64. Nothing here logs, and no message carries input bytes.
 */
internal object CardCrypto {
    const val KEY_BYTES = 32
    const val IV_BYTES = 12
    private const val TAG_BITS = 128
    private const val MIN_RSA_BITS = 2048

    /**
     * The default MGF1 digest of the OAEP transformations is SHA-1 on Android and on the JDK,
     * so the full parameter set is always passed explicitly.
     */
    private val OAEP_SHA256: OAEPParameterSpec = OAEPParameterSpec(
        "SHA-256",
        "MGF1",
        MGF1ParameterSpec.SHA256,
        PSource.PSpecified.DEFAULT,
    )

    class Output(val encryptedMessage: ByteArray, val wrappedKey: ByteArray) {
        override fun toString(): String = "CardCrypto.Output(<redacted>)"
    }

    /** Thrown for every failure. The message is fixed and never contains input data. */
    class EncryptionException(cause: Throwable? = null) :
        Exception("Card encryption failed.", cause)

    /** Encrypts [card] with a fresh CSPRNG key and IV, which are zeroed before returning. */
    fun encrypt(card: ByteArray, spki: ByteArray, random: SecureRandom = SecureRandom()): Output {
        val aesKey = ByteArray(KEY_BYTES)
        val iv = ByteArray(IV_BYTES)
        try {
            random.nextBytes(aesKey)
            random.nextBytes(iv)
            return encrypt(card, spki, aesKey, iv)
        } finally {
            aesKey.fill(0)
            iv.fill(0)
        }
    }

    /**
     * Deterministic core with an injected [aesKey] and [iv] (tests only pass fixed values).
     * The caller owns and zeroes [card], [aesKey] and [iv]; the `aesKey || iv` buffer built
     * here is zeroed before returning.
     */
    fun encrypt(card: ByteArray, spki: ByteArray, aesKey: ByteArray, iv: ByteArray): Output {
        if (card.isEmpty() || aesKey.size != KEY_BYTES || iv.size != IV_BYTES) {
            throw EncryptionException()
        }
        val keyIv = ByteArray(KEY_BYTES + IV_BYTES)
        try {
            val publicKey = rsaPublicKey(spki)

            val aes = Cipher.getInstance("AES/GCM/NoPadding")
            aes.init(Cipher.ENCRYPT_MODE, SecretKeySpec(aesKey, "AES"), GCMParameterSpec(TAG_BITS, iv))
            val encryptedMessage = aes.doFinal(card)

            System.arraycopy(aesKey, 0, keyIv, 0, KEY_BYTES)
            System.arraycopy(iv, 0, keyIv, KEY_BYTES, IV_BYTES)
            val rsa = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
            rsa.init(Cipher.ENCRYPT_MODE, publicKey, OAEP_SHA256)
            val wrappedKey = rsa.doFinal(keyIv)

            return Output(encryptedMessage, wrappedKey)
        } catch (e: EncryptionException) {
            throw e
        } catch (e: GeneralSecurityException) {
            throw EncryptionException(e)
        } catch (e: RuntimeException) {
            throw EncryptionException(e)
        } finally {
            keyIv.fill(0)
        }
    }

    /** Parses a DER SubjectPublicKeyInfo. Only RSA keys of at least 2048 bits are accepted. */
    fun rsaPublicKey(spki: ByteArray): RSAPublicKey {
        try {
            val key = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(spki))
            if (key !is RSAPublicKey || key.modulus.bitLength() < MIN_RSA_BITS) {
                throw EncryptionException()
            }
            return key
        } catch (e: EncryptionException) {
            throw e
        } catch (e: GeneralSecurityException) {
            throw EncryptionException(e)
        } catch (e: RuntimeException) {
            throw EncryptionException(e)
        }
    }

    /** The OAEP parameters, exposed so tests decrypt with exactly the same set. */
    internal fun oaepParameters(): OAEPParameterSpec = OAEP_SHA256
}
