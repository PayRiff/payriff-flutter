package com.payriff.flutter

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native half of the payriff plugin, channel `payriff/native` (CONTRACT §16.11):
 *
 * - `encryptCard` {card: bytes, spki: bytes} -> {encryptedMessage, wrappedKey} (Base64, §16.6)
 * - `appId` -> the package name, for `X-Client-App-Id`
 * - `setSecure` {secure: bool} -> null, reference-counted FLAG_SECURE on the activity window
 * - `openExternal` {url} -> bool, hardened hand-off to another app (§7.5, §16.0 item 5)
 * - `clearWebsiteData` {hosts, origins, urls} -> null when done: removes the website data of the
 *   sites a payment's 3-D Secure WebViews loaded (§9.1a)
 *
 * Nothing here logs. Error messages are fixed strings without input data.
 */
class PayriffPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private var channel: MethodChannel? = null
    private var applicationContext: Context? = null
    private var activity: Activity? = null

    /** Number of open `setSecure(true)` requests; protection is on while it is above zero. */
    private var secureCount = 0

    /** True when this plugin added FLAG_SECURE to the current window (it was not set before). */
    private var addedSecureFlag = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        secureCount = 0
        releaseWindow()
        applicationContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        applySecureFlag()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        releaseWindow()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        releaseWindow()
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        when (call.method) {
            "encryptCard" -> encryptCard(args, result)
            "appId" -> result.success(applicationContext?.packageName)
            "setSecure" -> {
                val secure = args?.get("secure") as? Boolean
                if (secure == null) {
                    result.error("invalid_argument", "setSecure expects {secure: bool}.", null)
                    return
                }
                setSecure(secure)
                result.success(null)
            }
            "openExternal" -> {
                val url = args?.get("url") as? String
                result.success(url != null && openExternal(url))
            }
            "clearWebsiteData" -> {
                val origins = (args?.get("origins") as? List<*>)?.filterIsInstance<String>()
                val urls = (args?.get("urls") as? List<*>)?.filterIsInstance<String>()
                if (origins == null || urls == null) {
                    result.error(
                        "invalid_argument",
                        "clearWebsiteData expects {origins: [String], urls: [String]}.",
                        null,
                    )
                    return
                }
                // WebView, CookieManager and WebStorage belong to the main thread.
                Handler(Looper.getMainLooper()).post { clearWebsiteData(origins, urls, result) }
            }
            else -> result.notImplemented()
        }
    }

    private fun encryptCard(args: Map<*, *>?, result: MethodChannel.Result) {
        val card = args?.get("card") as? ByteArray
        val spki = args?.get("spki") as? ByteArray
        try {
            if (card == null || spki == null) throw CardCrypto.EncryptionException()
            val output = CardCrypto.encrypt(card, spki)
            result.success(
                mapOf(
                    "encryptedMessage" to Base64.encodeToString(output.encryptedMessage, Base64.NO_WRAP),
                    "wrappedKey" to Base64.encodeToString(output.wrappedKey, Base64.NO_WRAP),
                ),
            )
        } catch (e: Exception) {
            // Fixed message only: the cause may describe the input.
            result.error(ENCRYPTION_FAILED, "Card encryption failed.", null)
        } finally {
            // This array is the codec's copy of the plaintext and belongs to this call.
            card?.fill(0)
        }
    }

    // Screen protection (§16.0 item 4) --------------------------------------------------------

    private fun setSecure(secure: Boolean) {
        secureCount = if (secure) secureCount + 1 else maxOf(0, secureCount - 1)
        applySecureFlag()
    }

    private fun applySecureFlag() {
        val window = activity?.window ?: return
        if (secureCount > 0) {
            if (!addedSecureFlag) {
                val alreadySecure =
                    (window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
                if (!alreadySecure) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    addedSecureFlag = true
                }
            }
        } else {
            releaseWindow()
        }
    }

    /** Removes FLAG_SECURE only when this plugin added it, so a host app's own flag stays. */
    private fun releaseWindow() {
        if (addedSecureFlag) {
            activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            addedSecureFlag = false
        }
    }

    // External launches (§7.5, §16.0 item 5) --------------------------------------------------

    private fun openExternal(url: String): Boolean {
        if (!ExternalUrlPolicy.mayLaunch(url)) return false
        val context: Context = activity ?: applicationContext ?: return false
        return try {
            val intent = if (ExternalUrlPolicy.schemeOf(url) == "intent") {
                Intent.parseUri(url, Intent.URI_INTENT_SCHEME)
            } else {
                Intent(Intent.ACTION_VIEW, Uri.parse(url))
            }
            harden(intent)
            // An intent: URL can carry its own data scheme (`;scheme=content;`).
            val dataScheme: String? = intent.scheme
            if (dataScheme != null && ExternalUrlPolicy.isRefusedScheme(dataScheme)) return false
            if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: Exception) {
            // URISyntaxException from parseUri, SecurityException and any other RuntimeException:
            // a launch failure must never crash the host app.
            false
        }
    }

    /**
     * Only activities that accept web links (BROWSABLE) may receive the intent. No explicit
     * component or selector, no URI permission grants from the host app, and only the launch
     * flags of [ExternalUrlPolicy.allowedLaunchFlags].
     */
    private fun harden(intent: Intent) {
        intent.addCategory(Intent.CATEGORY_BROWSABLE)
        intent.component = null
        intent.selector = null
        intent.clipData = null
        intent.flags = ExternalUrlPolicy.allowedLaunchFlags(intent.flags)
    }

    // 3-D Secure website data (§9.1a) ----------------------------------------------------------

    /**
     * WebView data is per app, so what the 3-D Secure pages left is removed per site: the web
     * storage of every origin, every cookie [CookieManager] returns for a visited URL (see
     * [WebsiteData]), and the WebView HTTP cache, which is the whole app's. Data of the same sites
     * that the app stored itself goes with it. Each step runs even when another one fails.
     */
    private fun clearWebsiteData(
        origins: List<String>,
        urls: List<String>,
        result: MethodChannel.Result,
    ) {
        var failed = false
        try {
            val storage = WebStorage.getInstance()
            origins.forEach { storage.deleteOrigin(it) }
        } catch (e: Exception) {
            failed = true
        }
        try {
            val cookies = CookieManager.getInstance()
            for (url in urls) {
                val host = Uri.parse(url).host ?: continue
                for (cookie in WebsiteData.expiredCookies(cookies.getCookie(url), host)) {
                    cookies.setCookie(url, cookie)
                }
            }
            cookies.flush()
        } catch (e: Exception) {
            failed = true
        }
        try {
            val context = applicationContext
            if (context != null) {
                val webView = WebView(context)
                try {
                    webView.clearCache(true)
                } finally {
                    webView.destroy()
                }
            }
        } catch (e: Exception) {
            failed = true
        }
        if (failed) {
            // Fixed message only: the cause may quote a URL.
            result.error(WEBSITE_DATA_FAILED, "Removing the 3-D Secure website data failed.", null)
        } else {
            result.success(null)
        }
    }

    private companion object {
        const val CHANNEL = "payriff/native"
        const val ENCRYPTION_FAILED = "encryption_failed"
        const val WEBSITE_DATA_FAILED = "website_data_failed"
    }
}
