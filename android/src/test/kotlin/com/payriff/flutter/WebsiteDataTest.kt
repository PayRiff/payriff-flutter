package com.payriff.flutter

import org.junit.Assert.assertEquals
import org.junit.Test

class WebsiteDataTest {
    @Test
    fun readsTheCookieNamesOfACookieHeader() {
        assertEquals(listOf("sid", "lang"), WebsiteData.cookieNames("sid=abc; lang=az; sid=def"))
        assertEquals(listOf("a", "b"), WebsiteData.cookieNames(" a = 1 ;b=;=x;novalue; "))
        assertEquals(emptyList<String>(), WebsiteData.cookieNames(null))
        assertEquals(emptyList<String>(), WebsiteData.cookieNames(""))
    }

    @Test
    fun cookieDomainsAreTheHostAndItsParentsWithTwoLabels() {
        assertEquals(
            listOf("acs.secure.bank.az", "secure.bank.az", "bank.az"),
            WebsiteData.cookieDomains("ACS.Secure.Bank.az."),
        )
        assertEquals(listOf("bank.az"), WebsiteData.cookieDomains("bank.az"))
        assertEquals(listOf("localhost"), WebsiteData.cookieDomains("localhost"))
        assertEquals(listOf("10.0.0.1"), WebsiteData.cookieDomains("10.0.0.1"))
        assertEquals(listOf("[::1]"), WebsiteData.cookieDomains("[::1]"))
        assertEquals(emptyList<String>(), WebsiteData.cookieDomains(""))
    }

    @Test
    fun cookiePathsAreRootAndEveryPrefixOfThePath() {
        assertEquals(
            listOf("/", "/acs", "/acs/", "/acs/challenge"),
            WebsiteData.cookiePaths("/acs/challenge"),
        )
        assertEquals(
            listOf("/", "/acs", "/acs/", "/acs/challenge", "/acs/challenge/"),
            WebsiteData.cookiePaths("/acs/challenge/"),
        )
        // Encoded, as cookies store paths.
        assertEquals(
            listOf("/", "/3ds%20v2", "/3ds%20v2/", "/3ds%20v2/step"),
            WebsiteData.cookiePaths("/3ds%20v2/step"),
        )
        assertEquals(listOf("/"), WebsiteData.cookiePaths("/"))
        assertEquals(listOf("/"), WebsiteData.cookiePaths(""))
        assertEquals(listOf("/"), WebsiteData.cookiePaths(null))
        assertEquals(listOf("/"), WebsiteData.cookiePaths("relative/path"))
    }

    @Test
    fun expiresEveryCookieHostOnlyAndForEachDomain() {
        assertEquals(
            listOf(
                "sid=; Max-Age=0; Path=/",
                "sid=; Max-Age=0; Path=/; Domain=acs.bank.example",
                "sid=; Max-Age=0; Path=/; Domain=bank.example",
                "lang=; Max-Age=0; Path=/",
                "lang=; Max-Age=0; Path=/; Domain=acs.bank.example",
                "lang=; Max-Age=0; Path=/; Domain=bank.example",
            ),
            WebsiteData.expiredCookies("sid=1; lang=az", "acs.bank.example", "/", secure = false),
        )
        assertEquals(
            emptyList<String>(),
            WebsiteData.expiredCookies(null, "acs.bank.example", "/acs", secure = true),
        )
    }

    @Test
    fun expiresEveryPathPrefixAndIsSecureForHttps() {
        val expected =
            listOf("/", "/acs", "/acs/", "/acs/challenge").flatMap { path ->
                listOf(
                    "sid=; Max-Age=0; Path=$path; Secure",
                    "sid=; Max-Age=0; Path=$path; Domain=acs.bank.example; Secure",
                    "sid=; Max-Age=0; Path=$path; Domain=bank.example; Secure",
                )
            }
        assertEquals(
            expected,
            WebsiteData.expiredCookies("sid=1", "acs.bank.example", "/acs/challenge", secure = true),
        )
        // http: no Secure attribute.
        assertEquals(
            listOf(
                "sid=; Max-Age=0; Path=/",
                "sid=; Max-Age=0; Path=/; Domain=acs.bank.example",
                "sid=; Max-Age=0; Path=/; Domain=bank.example",
                "sid=; Max-Age=0; Path=/acs",
                "sid=; Max-Age=0; Path=/acs; Domain=acs.bank.example",
                "sid=; Max-Age=0; Path=/acs; Domain=bank.example",
            ),
            WebsiteData.expiredCookies("sid=1", "acs.bank.example", "/acs", secure = false),
        )
    }

    @Test
    fun secureAndHostPrefixedCookies() {
        assertEquals(
            listOf(
                "__Host-sid=; Max-Age=0; Path=/; Secure",
                "__Secure-id=; Max-Age=0; Path=/; Secure",
                "__Secure-id=; Max-Age=0; Path=/; Domain=acs.bank.example; Secure",
                "__Secure-id=; Max-Age=0; Path=/; Domain=bank.example; Secure",
                "__Secure-id=; Max-Age=0; Path=/acs; Secure",
                "__Secure-id=; Max-Age=0; Path=/acs; Domain=acs.bank.example; Secure",
                "__Secure-id=; Max-Age=0; Path=/acs; Domain=bank.example; Secure",
            ),
            WebsiteData.expiredCookies(
                "__Host-sid=1; __Secure-id=2",
                "acs.bank.example",
                "/acs",
                secure = true,
            ),
        )
        // The prefix is matched without regard to case; such a cookie is only ever host-only.
        assertEquals(
            listOf("__host-x=; Max-Age=0; Path=/; Secure"),
            WebsiteData.expiredCookies("__host-x=1", "acs.bank.example", "/a/b", secure = true),
        )
    }
}
