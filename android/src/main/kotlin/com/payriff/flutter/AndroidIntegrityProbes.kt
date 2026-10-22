package com.payriff.flutter

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Debug
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket

/**
 * The device side of [DeviceIntegrity.Probes]. Every probe catches its own failures (missing
 * files, SELinux denials, hidden packages) and answers "not found". It reads names and flags
 * only; file contents never leave this class. Blocking: call it off the main thread.
 */
internal class AndroidIntegrityProbes(private val context: Context) : DeviceIntegrity.Probes {
    override fun fileExists(path: String): Boolean =
        try {
            File(path).exists()
        } catch (e: Exception) {
            false
        }

    override fun isPackageInstalled(packageName: String): Boolean =
        try {
            val packages = context.packageManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packages.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packages.getPackageInfo(packageName, 0)
            }
            true
        } catch (e: Exception) {
            // NameNotFoundException: not installed, or not visible to this app.
            false
        }

    override fun isClassLoadable(className: String): Boolean =
        listOfNotNull(javaClass.classLoader, ClassLoader.getSystemClassLoader()).any { loader ->
            try {
                Class.forName(className, false, loader)
                true
            } catch (e: Throwable) {
                // ClassNotFoundException, or a LinkageError of a broken class.
                false
            }
        }

    override fun fileContainsAny(path: String, needles: List<String>): Boolean =
        try {
            File(path).bufferedReader().useLines { lines ->
                lines.any { line -> needles.any { line.contains(it, ignoreCase = true) } }
            }
        } catch (e: Exception) {
            false
        }

    override fun readText(path: String): String? =
        try {
            File(path).readText()
        } catch (e: Exception) {
            null
        }

    override fun threadNames(): List<String> =
        try {
            File("/proc/self/task").listFiles().orEmpty().mapNotNull { task ->
                try {
                    File(task, "comm").readText()
                } catch (e: Exception) {
                    null
                }
            }
        } catch (e: Exception) {
            emptyList()
        }

    override fun acceptsTcpConnection(host: String, port: Int, timeoutMillis: Int): Boolean =
        try {
            Socket().use { it.connect(InetSocketAddress(host, port), timeoutMillis) }
            true
        } catch (e: Exception) {
            false
        }

    override fun isDebuggerConnected(): Boolean = Debug.isDebuggerConnected()

    override val isAppDebuggable: Boolean
        get() = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
}
