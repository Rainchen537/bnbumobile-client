package me.bnbu.app

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import kotlin.concurrent.thread

/** Installs only a newer, verified APK with this app's package and signing identity. */
class AndroidAppUpdater(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "ispace/android_app_update")
    private var permissionResult: MethodChannel.Result? = null
    private var busy = false
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "install" -> install(call, result)
                "requestInstallPermission" -> requestInstallPermission(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun install(call: MethodCall, result: MethodChannel.Result) {
        if (busy || permissionResult != null) {
            result.error("update_busy", "An update operation is already running.", null)
            return
        }
        busy = true
        thread(name = "bnbu-update-validation") {
            try {
                val file = validateArtifact(call)
                activity.runOnUiThread {
                    try {
                        check(!disposed && !activity.isFinishing)
                        if (!canInstall()) {
                            result.success("permissionRequired")
                        } else {
                            val uri = FileProvider.getUriForFile(
                                activity, "${activity.packageName}.fileprovider", file,
                            )
                            @Suppress("DEPRECATION")
                            val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                clipData = ClipData.newRawUri("App update", uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            activity.startActivity(intent)
                            result.success("installerOpened")
                        }
                    } catch (_: Exception) {
                        result.error("installer_unavailable", "Cannot open the system installer.", null)
                    } finally {
                        busy = false
                    }
                }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    busy = false
                    result.error("invalid_update", "The update package could not be verified.",
                        mapOf("reason" to ((error as? InvalidUpdate)?.reason ?: "unreadable")))
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun validateArtifact(call: MethodCall): File {
        val path = requireNotNull(call.argument<String>("path"))
        val digest = requireNotNull(call.argument<String>("sha256"))
        val size = requireNotNull(call.argument<Number>("size")).toLong()
        val build = requireNotNull(call.argument<Number>("buildNumber")).toLong()
        val version = requireNotNull(call.argument<String>("version"))
        verify(digest.matches(Regex("[a-f0-9]{64}")), "digest")
        verify(size in 1..(512L * 1024L * 1024L), "size")
        val root = File(activity.cacheDir, "app_updates").canonicalFile
        verify(root.parentFile == activity.cacheDir.canonicalFile, "path")
        val file = File(path).canonicalFile
        verify(file.parentFile == root && file.name == "$build-$digest.apk", "path")
        verify(file.isFile && file.length() == size, "size")
        val actualDigest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                actualDigest.update(buffer, 0, count)
            }
        }
        verify(actualDigest.digest().toHex() == digest, "digest")
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // Android 9 only collects archive certificates with the legacy flag.
            // Keep reading SigningInfo; never relax the signer comparison.
            PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val manager = activity.packageManager
        val candidate = manager.getPackageArchiveInfo(file.path, flags) ?: throw InvalidUpdate("invalid_apk")
        val installed = manager.getPackageInfo(activity.packageName, flags)
        verify(candidate.packageName == activity.packageName, "package")
        verify(candidate.versionName == version, "version")
        verify(versionCode(candidate) == build && build > versionCode(installed), "version_code")
        verify((candidate.applicationInfo?.minSdkVersion ?: Int.MAX_VALUE) <= Build.VERSION.SDK_INT, "minimum_sdk")
        // Fail closed on a changed signer; the system installer also verifies the APK.
        val installedSigners = signers(installed)
        verify(installedSigners.isNotEmpty() && signers(candidate) == installedSigners, "signer")
        return file
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.apkContentsSigners
        } else {
            info.signatures
        }
        return signatures?.map {
            MessageDigest.getInstance("SHA-256").digest(it.toByteArray()).toHex()
        }?.toSet().orEmpty()
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

    private class InvalidUpdate(val reason: String) : Exception()

    private fun verify(condition: Boolean, reason: String) {
        if (!condition) throw InvalidUpdate(reason)
    }

    private fun canInstall(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
        activity.packageManager.canRequestPackageInstalls()

    private fun requestInstallPermission(result: MethodChannel.Result) {
        if (busy || permissionResult != null) {
            result.error("update_busy", "An update operation is already running.", null)
            return
        }
        if (canInstall()) {
            result.success(true)
            return
        }
        try {
            permissionResult = result
            @Suppress("DEPRECATION")
            activity.startActivityForResult(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}")),
                PERMISSION_REQUEST,
            )
        } catch (_: Exception) {
            permissionResult = null
            result.error("installer_unavailable", "Cannot open installation settings.", null)
        }
    }

    fun onActivityResult(requestCode: Int) {
        if (requestCode != PERMISSION_REQUEST) return
        val result = permissionResult ?: return
        permissionResult = null
        result.success(canInstall())
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        permissionResult?.error("activity_detached", "Installation settings were interrupted.", null)
        permissionResult = null
    }

    companion object {
        private const val PERMISSION_REQUEST = 4110
    }
}
