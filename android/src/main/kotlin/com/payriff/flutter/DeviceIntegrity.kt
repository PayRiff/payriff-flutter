package com.payriff.flutter

/**
 * Root, hooking and debugger checks for `deviceIntegrity` (CONTRACT §16.16). The decisions are
 * pure Kotlin behind [Probes] and unit tested; [AndroidIntegrityProbes] reads the device.
 *
 * The root files and root manager apps are looked up once per instance: a device does not become
 * rooted while the app runs. The hooking, Frida and debugger checks run at every call, because
 * such a tool can attach at any time.
 *
 * `test-keys` builds, `ro.debuggable` and emulators are not signals: a custom ROM or an emulator
 * is not rooted by itself. The checks are local and can be bypassed; they stop the common tools.
 */
internal class DeviceIntegrity(private val probes: Probes) {
    /** What the checks read. Each answers `false`, `null` or empty when it cannot tell. */
    interface Probes {
        fun fileExists(path: String): Boolean

        fun isPackageInstalled(packageName: String): Boolean

        fun isClassLoadable(className: String): Boolean

        /** Whether a line of the text file at [path] contains one of [needles], ignoring case. */
        fun fileContainsAny(path: String, needles: List<String>): Boolean

        fun readText(path: String): String?

        /** The names of this process's threads (`/proc/self/task/<tid>/comm`). */
        fun threadNames(): List<String>

        /** Whether something accepts a TCP connection on [host]:[port] within [timeoutMillis]. */
        fun acceptsTcpConnection(host: String, port: Int, timeoutMillis: Int): Boolean

        fun isDebuggerConnected(): Boolean

        /** Whether the host app is debuggable (`FLAG_DEBUGGABLE`), as in development builds. */
        val isAppDebuggable: Boolean
    }

    private var rootSignals: List<String>? = null

    /** The names of the signals that match now, for example `su binary`; empty when none does. */
    @Synchronized
    fun signals(): List<String> {
        val root = rootSignals ?: rootChecks().also { rootSignals = it }
        return (root + hookingChecks() + debuggerChecks()).distinct()
    }

    private fun rootChecks(): List<String> {
        val signals = mutableListOf<String>()
        if (SU_PATHS.any(probes::fileExists)) signals += SU_BINARY
        for ((path, signal) in ROOT_FILES) {
            if (signal !in signals && probes.fileExists(path)) signals += signal
        }
        if (ROOT_MANAGER_PACKAGES.any(probes::isPackageInstalled)) signals += ROOT_MANAGER_APP
        return signals
    }

    private fun hookingChecks(): List<String> {
        val signals = mutableListOf<String>()
        if (probes.isClassLoadable(XPOSED_BRIDGE) || XPOSED_PACKAGES.any(probes::isPackageInstalled)) {
            signals += XPOSED
        }
        if (probes.fileContainsAny(PROC_MAPS, FRIDA_LIBRARIES) ||
            probes.threadNames().any { it.trim() == FRIDA_THREAD }
        ) {
            signals += FRIDA
        }
        if (probes.acceptsTcpConnection(LOOPBACK, FRIDA_SERVER_PORT, FRIDA_SERVER_TIMEOUT_MILLIS)) {
            signals += FRIDA_SERVER
        }
        return signals
    }

    /** A debugger counts only in a release app: development builds are debugged all the time. */
    private fun debuggerChecks(): List<String> {
        if (probes.isAppDebuggable) return emptyList()
        val traced = tracerPid(probes.readText(PROC_STATUS)).let { it != null && it != 0 }
        return if (traced || probes.isDebuggerConnected()) listOf(DEBUGGER) else emptyList()
    }

    internal companion object {
        const val SU_BINARY = "su binary"
        const val MAGISK = "Magisk"
        const val KERNEL_SU = "KernelSU"
        const val APATCH = "APatch"
        const val ROOT_MANAGER_APP = "root manager app"
        const val XPOSED = "Xposed"
        const val FRIDA = "Frida"
        const val FRIDA_SERVER = "frida-server"
        const val DEBUGGER = "debugger"

        val SU_PATHS = listOf(
            "/system/bin/su",
            "/system/xbin/su",
            "/sbin/su",
            "/su/bin/su",
            "/system/su",
            "/data/local/su",
            "/data/local/bin/su",
            "/data/local/xbin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/cache/su",
            "/dev/su",
        )

        /** Magisk, KernelSU and APatch files, with the signal each one names. */
        val ROOT_FILES = listOf(
            "/sbin/.magisk" to MAGISK,
            "/data/adb/magisk" to MAGISK,
            "/cache/.disable_magisk" to MAGISK,
            "/dev/.magisk.unblock" to MAGISK,
            "/data/adb/ksu" to KERNEL_SU,
            "/data/adb/ap" to APATCH,
        )

        /** Root managers; the plugin's manifest declares them in `<queries>`. */
        val ROOT_MANAGER_PACKAGES = listOf(
            "com.topjohnwu.magisk",
            "io.github.huskydg.magisk",
            "me.weishu.kernelsu",
            "me.bmax.apatch",
            "eu.chainfire.supersu",
            "com.noshufou.android.su",
            "com.koushikdutta.superuser",
            "com.thirdparty.superuser",
            "com.yellowes.su",
            "com.kingroot.kinguser",
            "com.kingo.root",
        )

        const val XPOSED_BRIDGE = "de.robv.android.xposed.XposedBridge"

        /** Xposed and LSPosed managers; also in the manifest's `<queries>`. */
        val XPOSED_PACKAGES = listOf("de.robv.android.xposed.installer", "org.lsposed.manager")

        const val PROC_MAPS = "/proc/self/maps"
        const val PROC_STATUS = "/proc/self/status"
        val FRIDA_LIBRARIES = listOf("frida-agent", "frida-gadget")
        const val FRIDA_THREAD = "gum-js-loop"
        const val LOOPBACK = "127.0.0.1"
        const val FRIDA_SERVER_PORT = 27042
        const val FRIDA_SERVER_TIMEOUT_MILLIS = 100

        private val TRACER_PID = Regex("""^TracerPid:\s*(\d+)""", RegexOption.MULTILINE)

        /** The `TracerPid` of a `/proc/self/status` text, or null when it has none. */
        fun tracerPid(status: String?): Int? =
            status?.let { TRACER_PID.find(it)?.groupValues?.get(1)?.toIntOrNull() }
    }
}
