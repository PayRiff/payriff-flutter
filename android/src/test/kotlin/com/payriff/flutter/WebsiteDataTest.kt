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
            WebsiteData.expiredCookies("sid=1; lang=az", "acs.bank.example"),
        )
        assertEquals(emptyList<String>(), WebsiteData.expiredCookies(null, "acs.bank.example"))
    }
}
