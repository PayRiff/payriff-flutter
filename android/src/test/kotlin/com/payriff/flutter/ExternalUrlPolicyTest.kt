package com.payriff.flutter

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExternalUrlPolicyTest {
    @Test
    fun refusesLocalContentAndScriptSchemes() {
        for (url in listOf(
            "file:///data/data/com.example/shared_prefs/x.xml",
            "FILE:///sdcard/x",
            "content://com.example.provider/secret",
            "javascript:alert(1)",
            "JavaScript:alert(1)",
            "data:text/html,<script>1</script>",
            "blob:https://pay.payriff.com/uuid",
            "about:blank",
        )) {
            assertFalse(url, ExternalUrlPolicy.mayLaunch(url))
        }
    }

    @Test
    fun refusesMissingSchemeWhitespaceAndControlCharacters() {
        for (url in listOf("", "no-scheme", "/relative/path", "://x", "1abc:x", " https://x", "https://x\n", "bank://pay\u0000")) {
            assertFalse(url, ExternalUrlPolicy.mayLaunch(url))
        }
    }

    @Test
    fun allowsWebBankAndIntentUrls() {
        for (url in listOf(
            "https://bank.example/3ds",
            "http://bank.example/",
            "intent://pay#Intent;scheme=bankapp;package=az.bank.app;end",
            "bankapp://pay?id=1",
            "tel:+994000000000",
            "market://details?id=az.bank.app",
        )) {
            assertTrue(url, ExternalUrlPolicy.mayLaunch(url))
        }
    }

    @Test
    fun launchFlagsFromAPageAreLimitedToTheSafeSet() {
        val grants = Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
        val dangerous = grants or
            Intent.FLAG_ACTIVITY_FORWARD_RESULT or
            Intent.FLAG_ACTIVITY_CLEAR_TASK or
            Intent.FLAG_ACTIVITY_NO_HISTORY or
            Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
        assertEquals(0, ExternalUrlPolicy.allowedLaunchFlags(dangerous))
        val safe = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
        assertEquals(safe, ExternalUrlPolicy.allowedLaunchFlags(safe or dangerous))
        assertEquals(0, ExternalUrlPolicy.allowedLaunchFlags(0))
    }

    @Test
    fun schemeIsLowercasedAndValidated() {
        assertEquals("intent", ExternalUrlPolicy.schemeOf("INTENT://x#Intent;end"))
        assertEquals("bank+app.v2-x", ExternalUrlPolicy.schemeOf("Bank+App.V2-x://pay"))
        assertNull(ExternalUrlPolicy.schemeOf("://x"))
        assertTrue(ExternalUrlPolicy.isRefusedScheme(null))
        assertTrue(ExternalUrlPolicy.isRefusedScheme("Content"))
        assertFalse(ExternalUrlPolicy.isRefusedScheme("https"))
    }
}
