package com.payriff.flutter

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Asserts every case of `card_crypto.json` (CONTRACT §16.6). */
class CardCryptoTest {
    private val vectors = TestVectors.load("card_crypto.json")

    private fun b64(key: String): ByteArray = Base64.getDecoder().decode(vectors[key] as String)

    private val aesKey = b64("aesKey")
    private val iv = b64("iv")
    private val keyIv = b64("keyIv")
    private val testSpki = b64("testPublicKeySpki")
    private val testPrivateKey: PrivateKey = KeyFactory.getInstance("RSA")
        .generatePrivate(PKCS8EncodedKeySpec(b64("testPrivateKeyPkcs8")))

    @Suppress("UNCHECKED_CAST")
    private val aesGcmCases = vectors["aesGcm"] as List<Map<String, Any?>>

    private fun unwrap(wrappedKey: ByteArray): ByteArray {
        val rsa = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
        rsa.init(Cipher.DECRYPT_MODE, testPrivateKey, CardCrypto.oaepParameters())
        return rsa.doFinal(wrappedKey)
    }

    private fun gcmOpen(key: ByteArray, iv: ByteArray, sealed: ByteArray): ByteArray {
        val aes = Cipher.getInstance("AES/GCM/NoPadding")
        aes.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv))
        return aes.doFinal(sealed)
    }

    @Test
    fun vectorFixedKeyAndIvAreConsistent() {
        assertEquals(CardCrypto.KEY_BYTES, aesKey.size)
        assertEquals(CardCrypto.IV_BYTES, iv.size)
        assertArrayEquals(keyIv, aesKey + iv)
        assertTrue(aesGcmCases.size >= 4)
    }

    @Test
    fun vectorWrapDecryptsWithTestPrivateKey() {
        // Proves the test harness uses OAEP SHA-256 / MGF1-SHA-256 like the vectors.
        assertArrayEquals(keyIv, unwrap(b64("rsaWrappedKeyIv")))
    }

    @Test
    fun everyAesGcmCaseMatchesWithFixedKeyAndIv() {
        for ((index, case) in aesGcmCases.withIndex()) {
            val cardJson = (case["cardJson"] as String).toByteArray(Charsets.UTF_8)
            val expected = case["encryptedMessage"] as String
            val output = CardCrypto.encrypt(cardJson.copyOf(), testSpki, aesKey.copyOf(), iv.copyOf())
            assertEquals("aesGcm[$index] encryptedMessage", expected, Base64.getEncoder().encodeToString(output.encryptedMessage))
            assertEquals("aesGcm[$index] ciphertext||tag length", cardJson.size + 16, output.encryptedMessage.size)
            assertArrayEquals("aesGcm[$index] wrappedKey unwraps to aesKey||iv", keyIv, unwrap(output.wrappedKey))
            assertArrayEquals("aesGcm[$index] round trip", cardJson, gcmOpen(aesKey, iv, output.encryptedMessage))
        }
    }

    @Test
    fun randomKeyAndIvAreFreshAndRoundTrip() {
        val cardJson = (aesGcmCases[0]["cardJson"] as String).toByteArray(Charsets.UTF_8)
        val first = CardCrypto.encrypt(cardJson, testSpki)
        val second = CardCrypto.encrypt(cardJson, testSpki)
        val firstKeyIv = unwrap(first.wrappedKey)
        val secondKeyIv = unwrap(second.wrappedKey)
        assertEquals(CardCrypto.KEY_BYTES + CardCrypto.IV_BYTES, firstKeyIv.size)
        assertFalse(firstKeyIv.contentEquals(secondKeyIv))
        assertFalse(first.encryptedMessage.contentEquals(second.encryptedMessage))
        for ((output, unwrapped) in listOf(first to firstKeyIv, second to secondKeyIv)) {
            val key = unwrapped.copyOfRange(0, CardCrypto.KEY_BYTES)
            val nonce = unwrapped.copyOfRange(CardCrypto.KEY_BYTES, unwrapped.size)
            assertArrayEquals(cardJson, gcmOpen(key, nonce, output.encryptedMessage))
        }
    }

    @Test
    fun oaepIsRandomizedAndUsesTheKeySize() {
        val one = CardCrypto.encrypt("{}".toByteArray(), testSpki, aesKey, iv)
        val two = CardCrypto.encrypt("{}".toByteArray(), testSpki, aesKey, iv)
        assertEquals(256, one.wrappedKey.size)
        assertNotEquals(Base64.getEncoder().encodeToString(one.wrappedKey), Base64.getEncoder().encodeToString(two.wrappedKey))
        assertArrayEquals(one.encryptedMessage, two.encryptedMessage)
    }

    @Test
    fun payriffProductionKeyParsesAndMatchesItsPin() {
        val spki = b64("payriffPublicKeySpki")
        val sha256 = MessageDigest.getInstance("SHA-256").digest(spki).joinToString("") { "%02x".format(it) }
        assertEquals(vectors["payriffPublicKeySha256"], sha256)
        val output = CardCrypto.encrypt("{}".toByteArray(), spki)
        assertTrue(output.wrappedKey.size >= 256)
    }

    @Test
    fun rejectsBadInputWithoutLeakingIt() {
        val card = "{\"pan\":\"4111111111111111\"}".toByteArray()
        val cases = listOf(
            "empty card" to { CardCrypto.encrypt(ByteArray(0), testSpki, aesKey, iv) },
            "short key" to { CardCrypto.encrypt(card, testSpki, ByteArray(16), iv) },
            "long iv" to { CardCrypto.encrypt(card, testSpki, aesKey, ByteArray(16)) },
            "garbage spki" to { CardCrypto.encrypt(card, byteArrayOf(1, 2, 3)) },
            "empty spki" to { CardCrypto.encrypt(card, ByteArray(0)) },
            "truncated spki" to { CardCrypto.encrypt(card, testSpki.copyOf(testSpki.size - 10)) },
            "pkcs8 instead of spki" to { CardCrypto.encrypt(card, b64("testPrivateKeyPkcs8")) },
        )
        for ((name, block) in cases) {
            try {
                block()
                fail("$name: expected EncryptionException")
            } catch (e: CardCrypto.EncryptionException) {
                assertEquals(name, "Card encryption failed.", e.message)
            }
        }
    }

    @Test
    fun outputToStringIsRedacted() {
        val output = CardCrypto.encrypt("{}".toByteArray(), testSpki, aesKey, iv)
        assertEquals("CardCrypto.Output(<redacted>)", output.toString())
    }
}
