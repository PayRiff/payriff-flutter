package com.payriff.flutter

import android.content.Intent
import java.util.Locale

/**
 * Scheme rules for `openExternal` (CONTRACT §7.5, §16.0 item 5). Pure Kotlin, unit tested.
 *
 * Local-content and script schemes are never handed to another app. The same check is
 * applied to the data of a parsed `intent:` URL, so `intent:…;scheme=content;…` is refused too.
 */
internal object ExternalUrlPolicy {
    private val SCHEME = Regex("^([A-Za-z][A-Za-z0-9+.-]*):")

    private val REFUSED_SCHEMES = setOf("file", "content", "javascript", "data", "blob", "about")

    /**
     * The only launch flags a page may set through an `intent:` URL (`launchFlags=`), as in
     * Chrome. Everything else is dropped, including the URI-permission grants and
     * FLAG_ACTIVITY_FORWARD_RESULT (which would hand the host activity's result to the target).
     */
    private const val ALLOWED_LAUNCH_FLAGS: Int =
        Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP or
            Intent.FLAG_EXCLUDE_STOPPED_PACKAGES

    /** [flags] reduced to the ones a page may set. */
    fun allowedLaunchFlags(flags: Int): Int = flags and ALLOWED_LAUNCH_FLAGS

    /** The lowercased scheme, or null when [url] has no valid scheme. */
    fun schemeOf(url: String): String? =
        SCHEME.find(url)?.groupValues?.get(1)?.lowercase(Locale.ROOT)

    fun isRefusedScheme(scheme: String?): Boolean =
        scheme.isNullOrEmpty() || scheme.lowercase(Locale.ROOT) in REFUSED_SCHEMES

    /**
     * True when [url] may be launched: it has a scheme, the scheme is not refused, and it has
     * no whitespace or control characters (a WebView or Dart `Uri` always encodes those).
     */
    fun mayLaunch(url: String): Boolean {
        if (url.isEmpty() || url.any { it <= ' ' || it == '\u007F' }) return false
        return !isRefusedScheme(schemeOf(url))
    }
}
