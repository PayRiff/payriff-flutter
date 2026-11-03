package com.payriff.flutter

import android.app.Activity
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.wallet.AutoResolveHelper
import com.google.android.gms.wallet.WalletConstants
import com.google.android.gms.wallet.button.ButtonConstants
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The Google Pay side's pure mappings (CONTRACT §17.5, §17.10): `wallet.json` → `buttonStyles`
 * and `googlePayEnvironments`, the corner radius in device pixels and the replies of the sheet's
 * activity result. The JSON requests themselves are built and tested in Dart.
 */
class GooglePayValuesTest {
    private val vectors = TestVectors.load("wallet.json")

    @Suppress("UNCHECKED_CAST")
    private fun section(map: Map<String, Any?>, key: String) = map[key] as Map<String, Any?>

    @Test
    fun everyButtonTypeAndThemeOfTheVectorsMapsToButtonConstants() {
        val google = section(section(vectors, "buttonStyles"), "googlePay")
        val constants =
            mapOf(
                "PLAIN" to ButtonConstants.ButtonType.PLAIN,
                "BUY" to ButtonConstants.ButtonType.BUY,
                "PAY" to ButtonConstants.ButtonType.PAY,
                "CHECKOUT" to ButtonConstants.ButtonType.CHECKOUT,
                "BOOK" to ButtonConstants.ButtonType.BOOK,
                "DONATE" to ButtonConstants.ButtonType.DONATE,
                "ORDER" to ButtonConstants.ButtonType.ORDER,
                "SUBSCRIBE" to ButtonConstants.ButtonType.SUBSCRIBE,
            )
        val types = section(google, "types")
        assertEquals(constants.keys, types.values.toSet())
        for (native in types.values) {
            assertEquals(native as String, constants[native], GooglePayValues.buttonType(native))
        }
        assertEquals(ButtonConstants.ButtonType.PLAIN, GooglePayValues.buttonType(null))
        assertEquals(ButtonConstants.ButtonType.PLAIN, GooglePayValues.buttonType("plain"))

        val themes = section(google, "themes")
        assertEquals(setOf("DARK", "LIGHT"), themes.values.toSet())
        assertEquals(ButtonConstants.ButtonTheme.DARK, GooglePayValues.buttonTheme("DARK"))
        assertEquals(ButtonConstants.ButtonTheme.LIGHT, GooglePayValues.buttonTheme("LIGHT"))
        // Dart resolves `automatic`; anything else is the default dark button.
        assertEquals(ButtonConstants.ButtonTheme.DARK, GooglePayValues.buttonTheme(null))
    }

    @Test
    fun theEnvironmentsOfTheVectors() {
        @Suppress("UNCHECKED_CAST")
        val cases = vectors["googlePayEnvironments"] as List<Map<String, Any?>>
        assertEquals(4, cases.size)
        for (case in cases) {
            val expected =
                if (case["expect"] == "TEST") {
                    WalletConstants.ENVIRONMENT_TEST
                } else {
                    WalletConstants.ENVIRONMENT_PRODUCTION
                }
            assertEquals(expected, GooglePayValues.environment(case["expect"] as String))
        }
        assertEquals(WalletConstants.ENVIRONMENT_PRODUCTION, GooglePayValues.environment(null))
    }

    @Test
    fun cornerRadiusInDevicePixels() {
        assertEquals(48, GooglePayValues.cornerRadiusPx(16.0, 3f))
        assertEquals(44, GooglePayValues.cornerRadiusPx(null, 2.75f))
        assertEquals(0, GooglePayValues.cornerRadiusPx(-4.0, 3f))
        assertEquals(0, GooglePayValues.cornerRadiusPx(Double.NaN, 3f))
    }

    @Test
    fun theSheetResults() {
        assertEquals(
            mapOf("status" to "ok", "token" to "{}"),
            GooglePayValues.resultFor(Activity.RESULT_OK, "{}", null),
        )
        // A missing token is reported as such; Dart makes it WALLET_FAILED.
        assertEquals(
            mapOf("status" to "ok", "token" to null),
            GooglePayValues.resultFor(Activity.RESULT_OK, null, null),
        )
        assertEquals(
            mapOf("status" to "cancelled"),
            GooglePayValues.resultFor(Activity.RESULT_CANCELED, "{}", null),
        )
        assertEquals(
            mapOf("status" to "error", "code" to CommonStatusCodes.DEVELOPER_ERROR),
            GooglePayValues.resultFor(
                AutoResolveHelper.RESULT_ERROR,
                null,
                CommonStatusCodes.DEVELOPER_ERROR,
            ),
        )
        assertEquals(
            mapOf("status" to "error", "code" to CommonStatusCodes.INTERNAL_ERROR),
            GooglePayValues.resultFor(AutoResolveHelper.RESULT_ERROR, null, null),
        )
        assertEquals(
            mapOf("status" to "error", "code" to CommonStatusCodes.INTERNAL_ERROR),
            GooglePayValues.resultFor(42, null, null),
        )
    }
}
