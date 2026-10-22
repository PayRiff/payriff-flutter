package com.payriff.flutter

import java.util.Locale

/**
 * Cookie rules for `clearWebsiteData` (CONTRACT §9.1a). Pure Kotlin, unit tested.
 *
 * A cookie is identified by its name, domain and path, and `CookieManager` can only overwrite
 * one. Every cookie it returns for a visited URL is therefore expired for `Path=/` and for every
 * path prefix of the URL's path, once host-only and once for the host and each parent domain with
 * at least two labels. For an https URL the expiry is `Secure`, so `__Secure-` cookies go too; a
 * `__Host-` cookie can only be host-only with `Path=/` and `Secure`.
 */
internal object WebsiteData {
    private val IPV4 = Regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$")

    /** The cookie names in [header], a `CookieManager.getCookie` value such as `a=1; b=2`. */
    fun cookieNames(header: String?): List<String> =
        header.orEmpty()
            .split(';')
            .mapNotNull { part ->
                val equals = part.indexOf('=')
                if (equals < 0) null else part.substring(0, equals).trim().ifEmpty { null }
            }
            .distinct()

    /**
     * [host] (lower case, without a trailing dot) and each of its parent domains with at least
     * two labels: `acs.bank.example` -> `acs.bank.example`, `bank.example`. Only the host for an
     * IP address.
     */
    fun cookieDomains(host: String): List<String> {
        val name = host.trimEnd('.').lowercase(Locale.ROOT)
        if (name.isEmpty()) return emptyList()
        val labels = name.split('.')
        if (':' in name || IPV4.matches(name) || labels.any { it.isEmpty() }) return listOf(name)
        return listOf(name) + (1..labels.size - 2).map { labels.drop(it).joinToString(".") }
    }

    /**
     * The paths a cookie returned for a URL with [path] can have: `/` and every prefix of [path]
     * that ends at a `/` or at its end, with and without that `/` (`/acs/challenge` -> `/`,
     * `/acs`, `/acs/`, `/acs/challenge`). A cookie's path always path-matches the URL's path
     * (RFC 6265, 5.1.4), so it is one of these. [path] is the encoded path, as cookies store it.
     */
    fun cookiePaths(path: String?): List<String> {
        val paths = linkedSetOf("/")
        if (path.isNullOrEmpty() || !path.startsWith("/")) return paths.toList()
        for (i in 1 until path.length) {
            if (path[i] == '/') {
                paths += path.substring(0, i)
                paths += path.substring(0, i + 1)
            }
        }
        paths += path
        return paths.toList()
    }

    /**
     * The `Set-Cookie` values that expire every cookie in [header] for a URL on [host] with
     * [path]; [secure] for an https URL.
     */
    fun expiredCookies(header: String?, host: String, path: String?, secure: Boolean): List<String> {
        val domains = cookieDomains(host)
        val paths = cookiePaths(path)
        val attributes = if (secure) "; Secure" else ""
        return cookieNames(header).flatMap { name ->
            if (name.startsWith(HOST_PREFIX, ignoreCase = true)) {
                listOf("$name=; Max-Age=0; Path=/; Secure")
            } else {
                paths.flatMap { cookiePath ->
                    val expired = "$name=; Max-Age=0; Path=$cookiePath"
                    listOf("$expired$attributes") + domains.map { "$expired; Domain=$it$attributes" }
                }
            }
        }
    }

    private const val HOST_PREFIX = "__Host-"
}
