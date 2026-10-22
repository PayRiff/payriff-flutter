package com.payriff.flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** CONTRACT §16.16 on Android: every signal, the debug-build and emulator rules, and caching. */
class DeviceIntegrityTest {
    private class FakeProbes : DeviceIntegrity.Probes {
        val files = mutableSetOf<String>()
        val packages = mutableSetOf<String>()
        val classes = mutableSetOf<String>()
        val texts = mutableMapOf<String, String>()
        var threads = listOf("main", "RenderThread", "1.ui")
        var fridaServer = false
        var debuggerConnected = false
        override var isAppDebuggable = false

        /** Every probe call, in order, for the caching tests. */
        val calls = mutableListOf<String>()

        override fun fileExists(path: String): Boolean {
            calls += "file $path"
            return path in files
        }

        override fun isPackageInstalled(packageName: String): Boolean {
            calls += "package $packageName"
            return packageName in packages
        }

        override fun isClassLoadable(className: String): Boolean {
            calls += "class $className"
            return className in classes
        }

        override fun fileContainsAny(path: String, needles: List<String>): Boolean {
            calls += "lines $path"
            val text = texts[path] ?: return false
            return text.lineSequence().any { line -> needles.any { line.contains(it, true) } }
        }

        override fun readText(path: String): String? {
            calls += "read $path"
            return texts[path]
        }

        override fun threadNames(): List<String> {
            calls += "threads"
            return threads
        }

        override fun acceptsTcpConnection(host: String, port: Int, timeoutMillis: Int): Boolean {
            calls += "tcp $host:$port in $timeoutMillis ms"
            return fridaServer
        }

        override fun isDebuggerConnected(): Boolean {
            calls += "debugger"
            return debuggerConnected
        }
    }

    private fun signals(setUp: FakeProbes.() -> Unit): List<String> =
        DeviceIntegrity(FakeProbes().apply(setUp)).signals()

    @Test
    fun aCleanDeviceHasNoSignal() {
        val probes = FakeProbes()
        assertEquals(emptyList<String>(), DeviceIntegrity(probes).signals())
        // frida-server is looked for on the loopback port within 100 ms.
        assertTrue(probes.calls.contains("tcp 127.0.0.1:27042 in 100 ms"))
    }

    @Test
    fun anSuBinaryInEveryListedPlace() {
        assertEquals(12, DeviceIntegrity.SU_PATHS.size)
        for (path in DeviceIntegrity.SU_PATHS) {
            assertEquals(path, listOf("su binary"), signals { files += path })
        }
    }

    @Test
    fun magiskKernelSuAndAPatchFiles() {
        val expected =
            mapOf(
                "/sbin/.magisk" to "Magisk",
                "/data/adb/magisk" to "Magisk",
                "/cache/.disable_magisk" to "Magisk",
                "/dev/.magisk.unblock" to "Magisk",
                "/data/adb/ksu" to "KernelSU",
                "/data/adb/ap" to "APatch",
            )
        assertEquals(expected, DeviceIntegrity.ROOT_FILES.toMap())
        for ((path, signal) in expected) {
            assertEquals(path, listOf(signal), signals { files += path })
        }
    }

    @Test
    fun anInstalledRootManagerApp() {
        assertEquals(11, DeviceIntegrity.ROOT_MANAGER_PACKAGES.size)
        for (name in DeviceIntegrity.ROOT_MANAGER_PACKAGES) {
            assertEquals(name, listOf("root manager app"), signals { packages += name })
        }
    }

    @Test
    fun xposedOrLsposed() {
        assertEquals(
            listOf("Xposed"),
            signals { classes += "de.robv.android.xposed.XposedBridge" },
        )
        for (name in listOf("de.robv.android.xposed.installer", "org.lsposed.manager")) {
            assertEquals(name, listOf("Xposed"), signals { packages += name })
        }
    }

    @Test
    fun fridaInTheMapsAThreadOrAServer() {
        for (library in listOf(
            "7f3c000000-7f3c100000 r-xp 00000000 fd:00 42 /data/local/tmp/re.frida.server/frida-agent-64.so",
            "7f3c000000-7f3c100000 r-xp 00000000 fd:00 42 /data/app/x/lib/arm64/libFrida-Gadget.so",
        )) {
            assertEquals(
                library,
                listOf("Frida"),
                signals { texts["/proc/self/maps"] = "7f00-7f01 r--p 0 0 0 /system/lib64/libc.so\n$library\n" },
            )
        }
        assertEquals(listOf("Frida"), signals { threads = listOf("main", "gum-js-loop\n") })
        assertEquals(listOf("frida-server"), signals { fridaServer = true })
        // Similar names are not Frida.
        assertEquals(
            emptyList<String>(),
            signals {
                texts["/proc/self/maps"] = "7f00-7f01 r--p 0 0 0 /data/app/x/lib/libfridge.so\n"
                threads = listOf("gum-js-loop-2", "js-loop")
            },
        )
    }

    @Test
    fun aDebuggerCountsOnlyInAReleaseApp() {
        val traced = "Name:\tpayriff.example\nState:\tS (sleeping)\nTracerPid:\t4321\nUid:\t10123\n"
        assertEquals(listOf("debugger"), signals { texts["/proc/self/status"] = traced })
        assertEquals(listOf("debugger"), signals { debuggerConnected = true })
        assertEquals(
            emptyList<String>(),
            signals { texts["/proc/self/status"] = traced.replace("4321", "0") },
        )
        // Development builds are debuggable, and debugged all the time.
        val debuggable = FakeProbes().apply {
            isAppDebuggable = true
            texts["/proc/self/status"] = traced
            debuggerConnected = true
        }
        assertEquals(emptyList<String>(), DeviceIntegrity(debuggable).signals())
        assertTrue(debuggable.calls.none { it == "debugger" || it == "read /proc/self/status" })
    }

    @Test
    fun readsTheTracerPid() {
        assertEquals(0, DeviceIntegrity.tracerPid("Name:\tx\nTracerPid:\t0\nUid:\t1\n"))
        assertEquals(4321, DeviceIntegrity.tracerPid("TracerPid:  4321"))
        assertNull(DeviceIntegrity.tracerPid("Name:\tx\n"))
        assertNull(DeviceIntegrity.tracerPid("TracerPid:\tnone"))
        assertNull(DeviceIntegrity.tracerPid(null))
    }

    @Test
    fun emulatorsAndTestKeysBuildsAreNotSignals() {
        assertEquals(
            emptyList<String>(),
            signals {
                files += listOf(
                    "/dev/qemu_pipe",
                    "/dev/goldfish_pipe",
                    "/dev/socket/qemud",
                    "/system/bin/qemu-props",
                    "/system/lib/libc_malloc_debug_qemu.so",
                    "/sys/qemu_trace",
                )
                texts["/system/build.prop"] =
                    "ro.build.tags=test-keys\nro.debuggable=1\nro.kernel.qemu=1\nro.product.model=sdk_gphone64_arm64\n"
                isAppDebuggable = true
            },
        )
    }

    @Test
    fun allSignalsTogetherInOrder() {
        assertEquals(
            listOf("su binary", "Magisk", "root manager app", "Xposed", "Frida", "frida-server", "debugger"),
            signals {
                files += listOf("/system/xbin/su", "/data/adb/magisk")
                packages += listOf("com.topjohnwu.magisk", "org.lsposed.manager")
                threads = listOf("gum-js-loop")
                fridaServer = true
                debuggerConnected = true
            },
        )
    }

    @Test
    fun rootChecksAreKeptHookingAndDebuggerChecksRunEveryTime() {
        val probes = FakeProbes()
        val integrity = DeviceIntegrity(probes)
        assertEquals(emptyList<String>(), integrity.signals())
        val first = probes.calls.toList()
        assertTrue(first.any { it.startsWith("file ") })
        assertTrue(first.contains("package com.topjohnwu.magisk"))

        // Rooted and hooked after the first check: only the hooking tool is seen.
        probes.calls.clear()
        probes.files += "/system/xbin/su"
        probes.packages += "com.topjohnwu.magisk"
        probes.threads = listOf("gum-js-loop")
        probes.debuggerConnected = true
        assertEquals(listOf("Frida", "debugger"), integrity.signals())
        val second = probes.calls.toList()
        assertTrue(second.none { it.startsWith("file ") })
        assertTrue(second.none { it == "package com.topjohnwu.magisk" })
        for (runtime in listOf(
            "class de.robv.android.xposed.XposedBridge",
            "package org.lsposed.manager",
            "lines /proc/self/maps",
            "threads",
            "tcp 127.0.0.1:27042 in 100 ms",
            "read /proc/self/status",
            "debugger",
        )) {
            assertTrue(runtime, second.contains(runtime))
        }

        // A root signal, once found, stays for the instance.
        val rooted = FakeProbes().apply { files += "/sbin/su" }
        val kept = DeviceIntegrity(rooted)
        assertEquals(listOf("su binary"), kept.signals())
        rooted.files.clear()
        assertEquals(listOf("su binary"), kept.signals())
    }
}
