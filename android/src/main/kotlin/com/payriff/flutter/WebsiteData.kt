package com.payriff.flutter

import java.util.Locale

/**
 * Cookie rules for `clearWebsiteData` (CONTRACT §9.1a). Pure Kotlin, unit tested.
 *
 * A cookie is identified by its name, domain and path, and `CookieManager` can only overwrite
 * one. Every cookie it returns for a visited URL is therefore expired with `Path=/`, once
 * host-only and once for the host and each parent domain with at least two labels.
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

    /** The `Set-Cookie` values that expire every cookie in [header] for a URL on [host]. */
    fun expiredCookies(header: String?, host: String): List<String> {
        val domains = cookieDomains(host)
        return cookieNames(header).flatMap { name ->
            val expired = "$name=; Max-Age=0; Path=/"
            listOf(expired) + domains.map { "$expired; Domain=$it" }
        }
    }
}
