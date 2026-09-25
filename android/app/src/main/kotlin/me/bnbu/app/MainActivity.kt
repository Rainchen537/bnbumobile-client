package me.bnbu.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.CookieManager
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.URLUtil
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebViewDatabase
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.annotation.RequiresApi
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import androidx.webkit.ProfileStore
import androidx.webkit.WebStorageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLConnection
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import javax.net.ssl.HttpsURLConnection
import kotlin.concurrent.thread

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val PREF_NAME = "ispace_credentials"
        private const val KEY_USERNAME = "saved_username"
        private const val KEY_PASSWORD = "saved_password"
        private const val CREDENTIAL_STATE_PREF_NAME = "ispace_credential_state"
        private const val LOGOUT_TOMBSTONE_KEY = "logout_tombstone"
        private const val SECURE_PREF_NAME = "FlutterSecureStorage"
        private const val SECURE_CREDENTIAL_KEY =
            "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_bnbu.credentials.v1"
        private const val LEGACY_SECURE_USERNAME_KEY =
            "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_bnbu.credentials.username"
        private const val LEGACY_SECURE_PASSWORD_KEY =
            "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg_bnbu.credentials.password"
        private const val LEGACY_DOWNLOAD_PERMISSION_REQUEST = 4107
        private const val SHARE_CACHE_MAX_AGE_MILLIS = 24L * 60L * 60L * 1000L
        private const val MAX_REMOTE_FILE_BYTES = 1024L * 1024L * 1024L
    }

    private data class PendingLegacyStorageAction(
        val result: MethodChannel.Result,
        val action: () -> Unit,
        val deniedAction: () -> Unit,
        val failureCode: String,
    )

    private var pendingLegacyStorageAction: PendingLegacyStorageAction? = null
    private var ecardOriginalBrightness: Float? = null
    private var appUpdater: AndroidAppUpdater? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (resources.configuration.smallestScreenWidthDp < 600) {
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appUpdater = AndroidAppUpdater(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bnbu/update_environment")
            .setMethodCallHandler { call, result ->
                if (call.method == "systemVersion") result.success(android.os.Build.VERSION.RELEASE)
                else result.notImplemented()
            }
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            WebView.setWebContentsDebuggingEnabled(true)
        }
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "ispace/native_webview",
                IspaceNativeWebViewFactory(
                    flutterEngine.dartExecutor.binaryMessenger,
                ) { result, action, deniedAction ->
                    runWithLegacyStoragePermission(
                        result = result,
                        failureCode = "login_code_failed",
                        deniedAction = deniedAction,
                        action = action,
                    )
                },
            )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ispace/ecard_brightness")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "begin" -> {
                        beginEcardBrightness()
                        result.success(true)
                    }
                    "end" -> {
                        restoreEcardBrightness()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ispace/credential_store")
            .setMethodCallHandler { call, result ->
                val preferences = getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                when (call.method) {
                    "readSecureCredentials" -> {
                        runCredentialStoreOperation(result) {
                            secureCredentialPreferences().getString(
                                SECURE_CREDENTIAL_KEY,
                                null,
                            )
                        }
                    }
                    "writeSecureCredentials" -> {
                        val value = call.argument<String>("value")
                        if (value.isNullOrBlank()) {
                            result.error("bad_args", "Missing credential value", null)
                            return@setMethodCallHandler
                        }
                        runCredentialStoreOperation(result) {
                            if (
                                !secureCredentialPreferences()
                                    .edit()
                                    .putString(SECURE_CREDENTIAL_KEY, value)
                                    .commit()
                            ) {
                                throw IllegalStateException(
                                    "Unable to durably write secure credentials"
                                )
                            }
                            true
                        }
                    }
                    "clearSecureCredentials" -> {
                        runCredentialStoreOperation(result) {
                            clearSecureCredentialPreferences(includePrimary = true)
                            true
                        }
                    }
                    "clearLegacySecureCredentials" -> {
                        runCredentialStoreOperation(result) {
                            clearSecureCredentialPreferences(includePrimary = false)
                            true
                        }
                    }
                    "readLogoutTombstone" -> {
                        runCredentialStoreOperation(result) {
                            getSharedPreferences(
                                CREDENTIAL_STATE_PREF_NAME,
                                Context.MODE_PRIVATE,
                            ).getBoolean(LOGOUT_TOMBSTONE_KEY, false)
                        }
                    }
                    "setLogoutTombstone" -> {
                        val blocked = call.argument<Boolean>("blocked")
                        if (blocked == null) {
                            result.error("bad_args", "Missing logout state", null)
                            return@setMethodCallHandler
                        }
                        runCredentialStoreOperation(result) {
                            val state = getSharedPreferences(
                                CREDENTIAL_STATE_PREF_NAME,
                                Context.MODE_PRIVATE,
                            )
                            val editor = state.edit()
                            if (blocked) {
                                editor.putBoolean(LOGOUT_TOMBSTONE_KEY, true)
                            } else {
                                editor.remove(LOGOUT_TOMBSTONE_KEY)
                            }
                            if (!editor.commit()) {
                                throw IllegalStateException(
                                    "Unable to durably update logout state"
                                )
                            }
                            true
                        }
                    }
                    "readLegacyCredentials" -> {
                        val username = preferences.getString(KEY_USERNAME, "").orEmpty()
                        val password = preferences.getString(KEY_PASSWORD, "").orEmpty()
                        if (username.isBlank() || password.isBlank()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        result.success(
                            mapOf(
                                "username" to username,
                                "password" to password,
                            )
                        )
                    }
                    "clearLegacyCredentials" -> {
                        if (preferences.edit().clear().commit()) {
                            result.success(true)
                        } else {
                            result.error(
                                "legacy_clear_failed",
                                "Unable to durably clear legacy credentials",
                                null,
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ispace/device_identity")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPlatformIdentity" -> {
                        val androidId = Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ANDROID_ID,
                        )
                        if (androidId.isNullOrBlank()) {
                            result.error(
                                "device_identity_unavailable",
                                "Android device identity is unavailable",
                                null,
                            )
                        } else {
                            result.success(androidId)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ispace/native_actions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "downloadFile" -> {
                        val url = call.argument<String>("url")
                        val preferredFileName = call.argument<String>("filename").orEmpty()
                        val cookieHeader = call.argument<String>("cookieHeader").orEmpty()
                        val cookieOrigin = call.argument<String>("cookieOrigin").orEmpty()
                        if (url.isNullOrBlank()) {
                            result.error("bad_args", "Missing url", null)
                            return@setMethodCallHandler
                        }
                        if (!isHttpUrl(url)) {
                            result.error("bad_args", "Only HTTP(S) downloads are supported", null)
                            return@setMethodCallHandler
                        }
                        runWithLegacyStoragePermission(result) {
                            val canSendCookies =
                                cookieHeader.isNotBlank() &&
                                    urlsHaveSameOrigin(url, cookieOrigin)
                            downloadAuthenticatedFile(
                                remoteUrl = url,
                                preferredFileName = preferredFileName,
                                cookieHeader = if (canSendCookies) cookieHeader else "",
                                cookieOrigin = if (canSendCookies) cookieOrigin else "",
                                result = result,
                            )
                        }
                    }
                    "openExternalUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank() || !isHttpUrl(url)) {
                            result.error(
                                "bad_args",
                                "Only HTTP(S) external links are supported",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("open_failed", error.message, null)
                        }
                    }
                    "shareUrl" -> {
                        val url = call.argument<String>("url")
                        val title = call.argument<String>("title").orEmpty()
                        val preferredFileName = call.argument<String>("filename").orEmpty()
                        val cookieHeader = call.argument<String>("cookieHeader").orEmpty()
                        val cookieOrigin = call.argument<String>("cookieOrigin").orEmpty()
                        if (url.isNullOrBlank() || !isHttpUrl(url)) {
                            result.error(
                                "bad_args",
                                "Only HTTP(S) links can be shared",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        if (shouldShareAsFile(url)) {
                            shareRemoteFile(
                                remoteUrl = url,
                                preferredFileName = preferredFileName,
                                title = title,
                                cookieHeader = cookieHeader,
                                cookieOrigin = cookieOrigin,
                                result = result,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                if (title.isNotBlank()) {
                                    putExtra(Intent.EXTRA_SUBJECT, title)
                                }
                                putExtra(Intent.EXTRA_TEXT, url)
                            }
                            startActivity(
                                Intent.createChooser(shareIntent, "分享")
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("share_failed", error.message, null)
                        }
                    }
                    "shareFile" -> {
                        val url = call.argument<String>("url")
                        val preferredFileName = call.argument<String>("filename").orEmpty()
                        val title = call.argument<String>("title").orEmpty()
                        val cookieHeader = call.argument<String>("cookieHeader").orEmpty()
                        val cookieOrigin = call.argument<String>("cookieOrigin").orEmpty()
                        if (url.isNullOrBlank()) {
                            result.error("bad_args", "Missing url", null)
                            return@setMethodCallHandler
                        }
                        shareRemoteFile(
                            remoteUrl = url,
                            preferredFileName = preferredFileName,
                            title = title,
                            cookieHeader = cookieHeader,
                            cookieOrigin = cookieOrigin,
                            result = result,
                        )
                    }
                    "clearWebSession" -> {
                        NativeWebSessionRegistry.clearAll {
                            WebStorage.getInstance().deleteAllData()
                            WebViewDatabase.getInstance(applicationContext).apply {
                                clearFormData()
                                clearHttpAuthUsernamePassword()
                            }
                            WebView(this@MainActivity).apply {
                                clearCache(true)
                                clearHistory()
                                clearFormData()
                                destroy()
                            }
                            val cookieManager = CookieManager.getInstance()
                            cookieManager.removeAllCookies {
                                cookieManager.flush()
                                result.success(true)
                            }
                        }
                    }
                    "getMailAttachmentCacheDir" -> {
                        val dir = File(applicationContext.cacheDir, "mail_attachments")
                        dir.mkdirs()
                        result.success(dir.absolutePath)
                    }
                    "shareLocalFile" -> {
                        val path = call.argument<String>("path") ?: ""
                        if (isFinishing || isDestroyed || !hasWindowFocus()) {
                            result.error("no_presenter", "Return to the app and try again", null)
                            return@setMethodCallHandler
                        }
                        thread {
                            var destination: File? = null
                            try {
                                val source = File(path)
                                require(source.isFile)
                                val root = File(cacheDir, "shared_files")
                                pruneStaleShareCache(root)
                                val directory = File(root, UUID.randomUUID().toString())
                                require(directory.mkdirs())
                                destination = directory
                                val name = sanitizeFileName(call.argument<String>("filename") ?: source.name)
                                val file = File(directory, name)
                                source.inputStream().use { input ->
                                    FileOutputStream(file).use { output -> copyStreamWithLimit(input, output) }
                                }
                                val uri = FileProvider.getUriForFile(applicationContext, "${applicationContext.packageName}.fileprovider", file)
                                runOnUiThread {
                                    try {
                                        check(!isFinishing && !isDestroyed && hasWindowFocus())
                                        val intent = Intent(Intent.ACTION_SEND).apply {
                                            type = call.argument<String>("mimeType") ?: "application/octet-stream"
                                            putExtra(Intent.EXTRA_STREAM, uri)
                                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        }
                                        startActivity(Intent.createChooser(intent, "分享"))
                                        result.success(true)
                                    } catch (error: Exception) {
                                        directory.deleteRecursively()
                                        result.error("share_failed", "Unable to share file", null)
                                    }
                                }
                            } catch (error: Exception) {
                                destination?.deleteRecursively()
                                runOnUiThread { result.error("share_failed", "Unable to share file", null) }
                            }
                        }
                    }
                    "openFile" -> {
                        val filePath = call.argument<String>("path") ?: run {
                            result.error("INVALID_PATH", "path required", null)
                            return@setMethodCallHandler
                        }
                        val mimeType = call.argument<String>("mimeType") ?: "*/*"
                        openLocalFile(filePath, mimeType, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onPause() {
        restoreEcardBrightness()
        super.onPause()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        appUpdater?.onActivityResult(requestCode)
    }

    override fun onDestroy() {
        appUpdater?.dispose()
        restoreEcardBrightness()
        super.onDestroy()
    }

    private fun beginEcardBrightness() {
        val attributes = window.attributes
        if (ecardOriginalBrightness == null) {
            ecardOriginalBrightness = attributes.screenBrightness
        }
        attributes.screenBrightness = 1.0f
        window.attributes = attributes
    }

    private fun restoreEcardBrightness() {
        val originalBrightness = ecardOriginalBrightness ?: return
        val attributes = window.attributes
        attributes.screenBrightness = originalBrightness
        window.attributes = attributes
        ecardOriginalBrightness = null
    }

    private fun runCredentialStoreOperation(
        result: MethodChannel.Result,
        operation: () -> Any?,
    ) {
        thread {
            try {
                val value = operation()
                runOnUiThread { result.success(value) }
            } catch (_: Exception) {
                runOnUiThread {
                    result.error(
                        "credential_store_failed",
                        "Credential store operation failed",
                        null,
                    )
                }
            }
        }
    }

    private fun secureCredentialPreferences() = EncryptedSharedPreferences.create(
        applicationContext,
        SECURE_PREF_NAME,
        MasterKey.Builder(applicationContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    private fun clearSecureCredentialPreferences(includePrimary: Boolean) {
        val encryptedEditor = secureCredentialPreferences().edit()
            .remove(LEGACY_SECURE_USERNAME_KEY)
            .remove(LEGACY_SECURE_PASSWORD_KEY)
        if (includePrimary) {
            encryptedEditor.remove(SECURE_CREDENTIAL_KEY)
        }
        if (!encryptedEditor.commit()) {
            throw IllegalStateException("Unable to durably clear secure credentials")
        }

        val fallbackEditor = getSharedPreferences(SECURE_PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(SECURE_CREDENTIAL_KEY)
            .remove(LEGACY_SECURE_USERNAME_KEY)
            .remove(LEGACY_SECURE_PASSWORD_KEY)
        if (!fallbackEditor.commit()) {
            throw IllegalStateException("Unable to durably clear fallback credentials")
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != LEGACY_DOWNLOAD_PERMISSION_REQUEST) {
            return
        }
        val pending = pendingLegacyStorageAction ?: return
        pendingLegacyStorageAction = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            executeLegacyStorageAction(pending)
        } else {
            try {
                pending.deniedAction()
            } catch (error: Exception) {
                pending.result.error(pending.failureCode, error.message, null)
            }
        }
    }

    private fun runWithLegacyStoragePermission(
        result: MethodChannel.Result,
        failureCode: String = "download_failed",
        deniedAction: (() -> Unit)? = null,
        action: () -> Unit,
    ) {
        val pending = PendingLegacyStorageAction(
            result = result,
            action = action,
            deniedAction = deniedAction ?: {
                result.error(
                    "storage_permission_denied",
                    "Storage permission is required to save files on this Android version",
                    null,
                )
            },
            failureCode = failureCode,
        )
        if (
            Build.VERSION.SDK_INT > Build.VERSION_CODES.P ||
                ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ) == PackageManager.PERMISSION_GRANTED
        ) {
            executeLegacyStorageAction(pending)
            return
        }
        if (pendingLegacyStorageAction != null) {
            result.error(
                "storage_permission_in_progress",
                "Another download is waiting for storage permission",
                null,
            )
            return
        }
        pendingLegacyStorageAction = pending
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            LEGACY_DOWNLOAD_PERMISSION_REQUEST,
        )
    }

    private fun executeLegacyStorageAction(pending: PendingLegacyStorageAction) {
        try {
            pending.action()
        } catch (error: Exception) {
            pending.result.error(pending.failureCode, error.message, null)
        }
    }

    private fun downloadAuthenticatedFile(
        remoteUrl: String,
        preferredFileName: String,
        cookieHeader: String,
        cookieOrigin: String,
        result: MethodChannel.Result,
    ) {
        thread {
            try {
                val connection = openDownloadConnection(
                    remoteUrl = remoteUrl,
                    cookieHeader = cookieHeader,
                    cookieOrigin = cookieOrigin,
                )
                val destination = try {
                    val fileName = responseFileName(
                        connection = connection,
                        remoteUrl = remoteUrl,
                        preferredFileName = preferredFileName,
                    )
                    if (isUnexpectedHtmlResponse(connection, fileName)) {
                        throw IllegalStateException(
                            "Download returned a login page instead of the requested file"
                        )
                    }
                    connection.inputStream.use { input ->
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            publishDownloadWithMediaStore(input, fileName)
                        } else {
                            writeLegacyAuthenticatedDownload(input, fileName)
                        }
                    }
                } finally {
                    connection.disconnect()
                }
                runOnUiThread {
                    result.success(destination)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("download_failed", error.message, null)
                }
            }
        }
    }

    private fun openLocalFile(
        filePath: String,
        mimeType: String,
        result: MethodChannel.Result,
    ) {
        thread {
            var stagedDirectory: File? = null
            try {
                val source = File(filePath).canonicalFile
                if (!source.isFile) {
                    throw IllegalStateException("The requested file does not exist")
                }
                val libraryRoot = File(
                    applicationInfo.dataDir,
                    "app_flutter/SmallU Resources",
                ).canonicalFile
                // Flutter's documents directory is outside FileProvider's cache
                // roots. Copy only an owner's ZIP, never expose app data or the
                // resource manifest through a broad root-path declaration.
                val isLibraryZip = source.parentFile?.parentFile == libraryRoot &&
                    source.extension.equals("zip", ignoreCase = true)
                val viewFile = if (isLibraryZip) {
                    val cacheRoot = File(cacheDir, "shared_files")
                    pruneStaleShareCache(cacheRoot)
                    val destinationDirectory = File(cacheRoot, UUID.randomUUID().toString())
                    if (!destinationDirectory.mkdirs()) {
                        throw IllegalStateException("Unable to prepare the file for viewing")
                    }
                    stagedDirectory = destinationDirectory
                    val target = File(destinationDirectory, sanitizeFileName(source.name))
                    source.inputStream().use { input ->
                        target.outputStream().use { output ->
                            copyStreamWithLimit(input, output)
                        }
                    }
                    target
                } else {
                    source
                }
                val uri = FileProvider.getUriForFile(
                    applicationContext,
                    "${applicationContext.packageName}.fileprovider",
                    viewFile,
                )
                val cleanupDirectory = stagedDirectory
                runOnUiThread {
                    try {
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mimeType)
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_ACTIVITY_NEW_TASK
                            )
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (error: ActivityNotFoundException) {
                        cleanupDirectory?.deleteRecursively()
                        result.error("no_app", "没有可以打开此类型文件的应用", null)
                    } catch (error: Exception) {
                        cleanupDirectory?.deleteRecursively()
                        result.error("open_failed", error.message, null)
                    }
                }
            } catch (error: Exception) {
                stagedDirectory?.deleteRecursively()
                runOnUiThread {
                    result.error("open_failed", error.message, null)
                }
            }
        }
    }

    private fun responseFileName(
        connection: HttpURLConnection,
        remoteUrl: String,
        preferredFileName: String,
    ): String {
        if (preferredFileName.isNotBlank()) {
            return sanitizeFileName(preferredFileName)
        }
        return sanitizeFileName(
            URLUtil.guessFileName(
                connection.url?.toString() ?: remoteUrl,
                connection.getHeaderField("Content-Disposition"),
                connection.contentType,
            )
        )
    }

    private fun isUnexpectedHtmlResponse(
        connection: HttpURLConnection,
        fileName: String,
    ): Boolean {
        val mimeType = connection.contentType
            ?.substringBefore(';')
            ?.trim()
            ?.lowercase()
            .orEmpty()
        if (mimeType != "text/html" && mimeType != "application/xhtml+xml") {
            return false
        }
        if (connection.url?.path?.lowercase()?.contains("/login") == true) {
            return true
        }
        val extension = fileName.substringAfterLast('.', "").lowercase()
        return extension.isNotEmpty() && extension !in setOf("html", "htm", "xhtml")
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun publishDownloadWithMediaStore(
        input: InputStream,
        originalName: String,
    ): String {
        val fileName = sanitizeFileName(originalName)
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(
                MediaStore.Downloads.MIME_TYPE,
                URLConnection.guessContentTypeFromName(fileName)
                    ?: "application/octet-stream",
            )
            put(
                MediaStore.Downloads.RELATIVE_PATH,
                Environment.DIRECTORY_DOWNLOADS,
            )
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            values,
        ) ?: throw IllegalStateException("Unable to create the download destination")
        try {
            contentResolver.openOutputStream(uri, "w").use { output ->
                if (output == null) {
                    throw IllegalStateException("Unable to open the download destination")
                }
                copyStreamWithLimit(input, output)
            }
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            if (contentResolver.update(uri, values, null, null) != 1) {
                throw IllegalStateException("Unable to publish the downloaded file")
            }
            return uri.toString()
        } catch (error: Exception) {
            contentResolver.delete(uri, null, null)
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun writeLegacyAuthenticatedDownload(
        input: InputStream,
        originalName: String,
    ): String {
        val targetDir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        )
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            throw IllegalStateException("Unable to create the public Downloads directory")
        }
        val targetFile = File(targetDir, uniquePublicDownloadName(originalName))
        val partialFile = File(
            targetDir,
            ".${targetFile.name}.${UUID.randomUUID()}.partial",
        )
        try {
            FileOutputStream(partialFile).use { output ->
                copyStreamWithLimit(input, output)
            }
            if (!partialFile.renameTo(targetFile)) {
                throw IllegalStateException("Unable to finalize downloaded file")
            }
            MediaScannerConnection.scanFile(
                this,
                arrayOf(targetFile.absolutePath),
                null,
                null,
            )
            return targetFile.absolutePath
        } finally {
            if (partialFile.exists()) {
                partialFile.delete()
            }
        }
    }

    private fun openDownloadConnection(
        remoteUrl: String,
        cookieHeader: String,
        cookieOrigin: String,
    ): HttpURLConnection {
        var currentUrl = URL(remoteUrl)
        var liveCookieHeader = cookieHeader
        val initialScheme = currentUrl.protocol.lowercase()
        repeat(6) {
            val connection = currentUrl.openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.setRequestProperty(
                "User-Agent",
                "Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 " +
                    "(KHTML, like Gecko) Chrome/123.0.0.0 Mobile Safari/537.36"
            )
            if (
                liveCookieHeader.isNotBlank() &&
                    urlsHaveSameOrigin(currentUrl.toString(), cookieOrigin)
            ) {
                connection.setRequestProperty("Cookie", liveCookieHeader)
            }

            val statusCode = connection.responseCode
            if (urlsHaveSameOrigin(currentUrl.toString(), cookieOrigin)) {
                liveCookieHeader = mergeCookieHeader(
                    liveCookieHeader,
                    connection.headerFields,
                )
            }
            // This client never requests byte ranges. A 204 or unsolicited 206
            // cannot be published as a complete downloaded (or shared) file.
            if (statusCode == HttpURLConnection.HTTP_OK) {
                val contentLength = connection.contentLengthLong
                if (contentLength > MAX_REMOTE_FILE_BYTES) {
                    connection.disconnect()
                    throw IllegalStateException("Remote file exceeds the 1 GB size limit")
                }
                return connection
            }
            if (statusCode !in 300..399) {
                connection.disconnect()
                throw IllegalStateException("Download failed with HTTP $statusCode")
            }

            val location = connection.getHeaderField("Location")
            connection.disconnect()
            if (location.isNullOrBlank()) {
                throw IllegalStateException("Download redirect is missing a target")
            }
            val nextUrl = URL(currentUrl, location)
            val nextScheme = nextUrl.protocol.lowercase()
            if (
                (nextScheme != "http" && nextScheme != "https") ||
                    !isHttpUrl(nextUrl.toString())
            ) {
                throw IllegalStateException("Download redirect uses an unsupported scheme")
            }
            if (initialScheme == "https" && nextScheme != "https") {
                throw IllegalStateException("HTTPS download cannot redirect to HTTP")
            }
            currentUrl = nextUrl
        }
        throw IllegalStateException("Download exceeded the redirect limit")
    }

    private fun mergeCookieHeader(
        currentHeader: String,
        responseHeaders: Map<String?, List<String>>,
    ): String {
        val values = linkedMapOf<String, String>()
        currentHeader.split(';').forEach { part ->
            val separator = part.indexOf('=')
            if (separator > 0) {
                val name = part.substring(0, separator).trim()
                val value = part.substring(separator + 1).trim()
                if (name.isNotEmpty()) {
                    values[name] = value
                }
            }
        }
        responseHeaders.entries
            .filter { it.key.equals("Set-Cookie", ignoreCase = true) }
            .flatMap { it.value }
            .forEach { header ->
                val pair = header.substringBefore(';')
                val separator = pair.indexOf('=')
                if (separator <= 0) {
                    return@forEach
                }
                val name = pair.substring(0, separator).trim()
                val value = pair.substring(separator + 1).trim()
                val removesCookie = value.isEmpty() ||
                    header.contains("Max-Age=0", ignoreCase = true)
                if (removesCookie) {
                    values.remove(name)
                } else if (name.isNotEmpty()) {
                    values[name] = value
                }
            }
        return values.entries.joinToString("; ") { (name, value) -> "$name=$value" }
    }

    private fun uniquePublicDownloadName(originalName: String): String {
        val safeName = sanitizeFileName(originalName)
        val dotIndex = safeName.lastIndexOf('.')
        val base = if (dotIndex > 0) safeName.substring(0, dotIndex) else safeName
        val ext = if (dotIndex > 0) safeName.substring(dotIndex) else ""
        val suffix = UUID.randomUUID().toString().substring(0, 8)
        return "${base}_$suffix$ext"
    }

    private fun copyStreamWithLimit(
        input: InputStream,
        output: OutputStream,
        maximumBytes: Long = MAX_REMOTE_FILE_BYTES,
    ) {
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0L
        while (true) {
            val read = input.read(buffer)
            if (read < 0) {
                return
            }
            total += read
            if (total > maximumBytes) {
                throw IllegalStateException("Remote file exceeds the 1 GB size limit")
            }
            output.write(buffer, 0, read)
        }
    }

    private fun pruneStaleShareCache(root: File) {
        val cutoff = System.currentTimeMillis() - SHARE_CACHE_MAX_AGE_MILLIS
        root.listFiles()?.forEach { entry ->
            if (entry.lastModified() < cutoff) {
                entry.deleteRecursively()
            }
        }
    }

    private fun shareRemoteFile(
        remoteUrl: String,
        preferredFileName: String,
        title: String,
        cookieHeader: String,
        cookieOrigin: String,
        result: MethodChannel.Result,
    ) {
        if (!isHttpUrl(remoteUrl)) {
            result.error("bad_args", "Only HTTP(S) file sharing is supported", null)
            return
        }
        thread {
            var targetDir: File? = null
            try {
                val connection = openDownloadConnection(
                    remoteUrl = remoteUrl,
                    cookieHeader = cookieHeader,
                    cookieOrigin = cookieOrigin,
                )
                val fileName = responseFileName(
                    connection = connection,
                    remoteUrl = remoteUrl,
                    preferredFileName = preferredFileName,
                )
                if (isUnexpectedHtmlResponse(connection, fileName)) {
                    connection.disconnect()
                    throw IllegalStateException(
                        "Download returned a login page instead of the requested file"
                    )
                }
                val shareCacheRoot = File(cacheDir, "shared_files")
                pruneStaleShareCache(shareCacheRoot)
                val destinationDir = File(
                    shareCacheRoot,
                    UUID.randomUUID().toString(),
                )
                if (!destinationDir.mkdirs()) {
                    connection.disconnect()
                    throw IllegalStateException("Unable to create the share cache directory")
                }
                targetDir = destinationDir
                val targetFile = File(destinationDir, fileName)
                val partialFile = File(destinationDir, ".partial")

                try {
                    connection.inputStream.use { input ->
                        FileOutputStream(partialFile).use { output ->
                            copyStreamWithLimit(input, output)
                        }
                    }
                    if (!partialFile.renameTo(targetFile)) {
                        throw IllegalStateException("Unable to finalize shared file")
                    }
                } finally {
                    connection.disconnect()
                    if (partialFile.exists()) {
                        partialFile.delete()
                    }
                }

                val fileUri = FileProvider.getUriForFile(
                    this,
                    "${packageName}.fileprovider",
                    targetFile,
                )
                val mimeType =
                    URLConnection.guessContentTypeFromName(targetFile.name)
                        ?: "application/octet-stream"

                runOnUiThread {
                    try {
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, fileUri)
                            if (title.isNotBlank()) {
                                putExtra(Intent.EXTRA_SUBJECT, title)
                            }
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(
                            Intent.createChooser(shareIntent, "分享")
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    } catch (error: Exception) {
                        destinationDir.deleteRecursively()
                        result.error("share_failed", error.message, null)
                    }
                }
            } catch (error: Exception) {
                targetDir?.deleteRecursively()
                runOnUiThread {
                    result.error("share_failed", error.message, null)
                }
            }
        }
    }

    private fun isHttpUrl(value: String): Boolean {
        val uri = Uri.parse(value)
        val scheme = uri.scheme?.lowercase()
        return (scheme == "http" || scheme == "https") &&
            !uri.host.isNullOrBlank() &&
            uri.userInfo.isNullOrEmpty() &&
            !value.any { character -> character.code <= 0x1f || character.code == 0x7f }
    }

    private fun urlsHaveSameOrigin(first: String, second: String): Boolean {
        if (!isHttpUrl(first) || !isHttpUrl(second)) {
            return false
        }
        val left = Uri.parse(first)
        val right = Uri.parse(second)
        return left.scheme.equals(right.scheme, ignoreCase = true) &&
            left.host.equals(right.host, ignoreCase = true) &&
            effectivePort(left) == effectivePort(right)
    }

    private fun effectivePort(uri: Uri): Int {
        if (uri.port != -1) {
            return uri.port
        }
        return when (uri.scheme?.lowercase()) {
            "http" -> 80
            "https" -> 443
            else -> -1
        }
    }

    private fun sanitizeFileName(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) {
            return "shared_file.bin"
        }
        val sanitized = trimmed.replace(Regex("[\\\\/:*?\"<>|\\x00-\\x1F]"), "_")
        val safeName = if (sanitized.isEmpty() || sanitized == "." || sanitized == "..") {
            "shared_file.bin"
        } else {
            sanitized
        }
        return truncateFileNameUtf8(safeName, 200)
    }

    private fun truncateFileNameUtf8(fileName: String, maxBytes: Int): String {
        if (fileName.toByteArray(Charsets.UTF_8).size <= maxBytes) {
            return fileName
        }
        val dotIndex = fileName.lastIndexOf('.')
        val hasExtension = dotIndex > 0 && dotIndex < fileName.length - 1
        val extension = if (hasExtension) fileName.substring(dotIndex) else ""
        val extensionBytes = extension.toByteArray(Charsets.UTF_8).size
        if (extensionBytes >= maxBytes) {
            return truncateUtf8(fileName, maxBytes)
        }
        val baseName = if (hasExtension) fileName.substring(0, dotIndex) else fileName
        return truncateUtf8(baseName, maxBytes - extensionBytes) + extension
    }

    private fun truncateUtf8(value: String, maxBytes: Int): String {
        val output = StringBuilder()
        var byteCount = 0
        var index = 0
        while (index < value.length) {
            val codePoint = value.codePointAt(index)
            val character = String(Character.toChars(codePoint))
            val characterBytes = character.toByteArray(Charsets.UTF_8).size
            if (byteCount + characterBytes > maxBytes) {
                break
            }
            output.append(character)
            byteCount += characterBytes
            index += Character.charCount(codePoint)
        }
        return output.toString()
    }

    private fun shouldShareAsFile(url: String): Boolean {
        val lower = url.lowercase()
        if (
            lower.contains("/pluginfile.php") ||
                lower.contains("/webservice/pluginfile.php") ||
                lower.contains("/mod/resource/view.php") ||
                lower.contains("/mod/folder/download_folder.php")
        ) {
            return true
        }
        return Regex(
            "\\.(pdf|ppt|pptx|doc|docx|xls|xlsx|zip|rar|7z|jpg|jpeg|png|gif|webp|mp4|mp3)(\\?|$)"
        ).containsMatchIn(lower)
    }
}

private class IspaceNativeWebViewFactory(
    private val messenger: BinaryMessenger,
    private val legacyStoragePermissionRunner: (
        MethodChannel.Result,
        () -> Unit,
        () -> Unit,
    ) -> Unit,
) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return IspaceNativeWebView(
            context,
            viewId,
            params,
            messenger,
            legacyStoragePermissionRunner,
        )
    }
}

private data class WebOrigin(
    val scheme: String,
    val host: String,
    val port: Int,
) {
    companion object {
        fun from(uri: Uri): WebOrigin? {
            val scheme = uri.scheme?.lowercase().orEmpty()
            val host = uri.host?.lowercase().orEmpty()
            if ((scheme != "https" && scheme != "http") || host.isEmpty() || !uri.userInfo.isNullOrEmpty()) {
                return null
            }
            val port = if (uri.port == -1) {
                if (scheme == "https") 443 else 80
            } else uri.port
            return WebOrigin(scheme, host, port)
        }
    }
}

private class WebUrlPolicy private constructor(
    private val allowedOrigins: Set<WebOrigin>,
    private val allowedDomains: Set<String>,
    private val resourceOnlyDomains: Set<String>,
    private val allowExternalHttpsNavigation: Boolean,
) {
    fun allows(uri: Uri): Boolean {
        val origin = WebOrigin.from(uri) ?: return false
        if (allowedOrigins.contains(origin)) {
            return true
        }
        if (allowExternalHttpsNavigation) {
            return true
        }
        if (origin.scheme != "https" || origin.port != 443) {
            return false
        }
        return allowedDomains.any { domain ->
            origin.host == domain || origin.host.endsWith(".$domain")
        }
    }

    fun allowsResource(uri: Uri): Boolean {
        return when (uri.scheme?.lowercase()) {
            "data", "blob", "about" -> true
            else -> {
                if (allows(uri)) {
                    true
                } else {
                    val origin = WebOrigin.from(uri) ?: return false
                    origin.port == 443 && resourceOnlyDomains.any { domain ->
                        origin.host == domain || origin.host.endsWith(".$domain")
                    }
                }
            }
        }
    }

    companion object {
        fun from(params: Map<String, Any?>): WebUrlPolicy {
            val origins = (params["allowedOrigins"] as? List<*>)
                ?.filterIsInstance<String>()
                ?.mapNotNull { value -> WebOrigin.from(Uri.parse(value)) }
                ?.toSet()
                ?: emptySet()
            val domains = (params["allowedDomains"] as? List<*>)
                ?.filterIsInstance<String>()
                ?.map { value -> value.trim().lowercase().trim('.') }
                ?.filter { value -> value.isNotEmpty() }
                ?.toSet()
                ?: emptySet()
            val resourceDomains = (params["resourceOnlyDomains"] as? List<*>)
                ?.filterIsInstance<String>()
                ?.map { value -> value.trim().lowercase().trim('.') }
                ?.filter { value -> value.isNotEmpty() }
                ?.toSet()
                ?: emptySet()
            return WebUrlPolicy(
                origins,
                domains,
                resourceDomains,
                params["allowExternalHttpsNavigation"] as? Boolean == true,
            )
        }
    }
}

private fun blockedWebResponse(): WebResourceResponse {
    return WebResourceResponse(
        "text/plain",
        "utf-8",
        403,
        "Blocked",
        emptyMap(),
        ByteArrayInputStream("Blocked untrusted web address.".toByteArray()),
    )
}

private object NativeWebSessionRegistry {
    private val views = mutableSetOf<IspaceNativeWebView>()

    fun register(view: IspaceNativeWebView) {
        views.add(view)
    }

    fun unregister(view: IspaceNativeWebView) {
        views.remove(view)
    }

    fun clearAll(completion: () -> Unit) {
        val activeViews = views.toList()
        if (activeViews.isEmpty()) {
            completion()
            return
        }
        var remaining = activeViews.size
        for (view in activeViews) {
            view.clearSession {
                remaining--
                if (remaining == 0) {
                    completion()
                }
            }
        }
    }
}

private object NativeWebProfileCleanup {
    private const val MAX_DELETE_ATTEMPTS = 8
    private const val DELETE_RETRY_DELAY_MILLIS = 250L
    private val mainHandler = Handler(Looper.getMainLooper())

    fun schedule(profileName: String, attempt: Int = 1) {
        mainHandler.postDelayed(
            {
                try {
                    ProfileStore.getInstance().deleteProfile(profileName)
                } catch (_: IllegalStateException) {
                    if (attempt < MAX_DELETE_ATTEMPTS) {
                        schedule(profileName, attempt + 1)
                    }
                }
            },
            DELETE_RETRY_DELAY_MILLIS,
        )
    }
}

private class IspaceNativeWebView(
    context: Context,
    viewId: Int,
    params: Map<String, Any?>,
    messenger: BinaryMessenger,
    private val legacyStoragePermissionRunner: (
        MethodChannel.Result,
        () -> Unit,
        () -> Unit,
    ) -> Unit,
) : PlatformView {
    private val appContext = context
    private val isMailContent = params["isMailContent"] as? Boolean == true
    private val isHtmlContent = params["contentType"] == "html" && !isMailContent
    private val viewChannel =
        MethodChannel(messenger, "ispace/native_webview/$viewId")
    private val useEphemeralSession =
        params["useEphemeralSession"] as? Boolean == true
    private val participatesInSessionCleanup =
        params["participatesInSessionCleanup"] as? Boolean != false
    private val persistentProfileName = (params["persistentProfileName"] as? String)
        ?.trim()
        ?.takeIf { value -> value.matches(Regex("[A-Za-z0-9_-]{1,64}")) }
    private val observeLoginCodes = !isHtmlContent && params["observeLoginCodes"] as? Boolean == true
    private val loginCodeObserverOrigin = (params["loginCodeObserverOrigin"] as? String)
        ?.let { value -> WebOrigin.from(Uri.parse(value)) }
    private val upgradeInsecureResourceHosts =
        (params["upgradeInsecureResourceHosts"] as? List<*>)
            ?.filterIsInstance<String>()
            ?.map { value -> value.trim().lowercase().trim('.') }
            ?.filter { value -> value.isNotEmpty() }
            ?.toSet()
            ?: emptySet()
    private val urlPolicy = if (isMailContent) null else WebUrlPolicy.from(params)
    @SuppressLint("RequiresFeature")
    private val isolatedProfileName: String? = if (
        !isMailContent &&
        (useEphemeralSession || persistentProfileName != null) &&
        WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)
    ) {
        persistentProfileName
            ?: "handsbnbu_${UUID.randomUUID().toString().replace("-", "")}"
    } else {
        null
    }
    @SuppressLint("RequiresFeature")
    private val webView: WebView = WebView(context).also { view ->
        isolatedProfileName?.let { profileName ->
            WebViewCompat.setProfile(view, profileName)
        }
    }
    @SuppressLint("RequiresFeature")
    private val isolatedProfileWebStorage = isolatedProfileName?.let {
        WebViewCompat.getProfile(webView).webStorage
    }
    @SuppressLint("RequiresFeature")
    private val cookieManager: CookieManager =
        isolatedProfileName?.let {
            WebViewCompat.getProfile(webView).cookieManager
        } ?: CookieManager.getInstance()
    private val sessionBaseUrl = (params["baseUrl"] as? String).orEmpty()
    private val sessionBaseHost = Uri.parse(sessionBaseUrl).host.orEmpty().lowercase()
    private val initialSessionCookieMetadata =
        (params["cookies"] as? List<*>)
            ?.filterIsInstance<Map<*, *>>()
            ?.mapNotNull { raw ->
                val name = raw["name"] as? String ?: return@mapNotNull null
                name to raw
            }
            ?.toMap()
            ?: emptyMap()
    private val cleanupCallbacks = mutableListOf<() -> Unit>()
    private var sessionInvalidated = false
    private var pendingCookieOperations = 0
    private var cleanupStarted = false
    private var cleanupDataRemovalStarted = false
    private var cleanupFinished = false
    private var platformBindingsDetached = false
    private var lastMailCollapsedState = false
    private var loadFailure: String? = null
    private var reloadHtmlDocument: (() -> Unit)? = null
    @Volatile private var lastLoginCodeSource = ""

    init {
        viewChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getLoadFailure" -> result.success(loadFailure)
                "reload" -> {
                    if (isHtmlContent) reloadHtmlDocument?.invoke() else webView.reload()
                    result.success(true)
                }
                "goBack" -> {
                    if (webView.canGoBack()) {
                        webView.goBack()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "clearSiteData" -> clearCurrentSiteData(result)
                "extractVisibleText" -> webView.evaluateJavascript(
                    "(document.body && document.body.innerText) || ''"
                ) { value -> result.success(value ?: "") }
                "evaluateJavascript" -> {
                    val source = call.arguments as? String
                    if (source == null) {
                        result.error("INVALID_ARGUMENT", "JavaScript source is required", null)
                    } else {
                        webView.evaluateJavascript(source) { value -> result.success(value) }
                    }
                }
                "saveLoginCodeAndOpenWechat" ->
                    saveLoginCodeAndOpenWechat(result)
                else -> result.notImplemented()
            }
        }
        if (observeLoginCodes && loginCodeObserverOrigin != null) {
            webView.addJavascriptInterface(
                LoginCodeSourceBridge(),
                "HandsBnbuLoginCodeBridge",
            )
        }
        webView.settings.javaScriptEnabled = !isMailContent && !isHtmlContent
        webView.settings.domStorageEnabled = !isMailContent && !isHtmlContent
        webView.settings.javaScriptCanOpenWindowsAutomatically = false
        webView.settings.setSupportMultipleWindows(false)
        webView.settings.allowFileAccess = false
        webView.settings.allowContentAccess = false
        webView.settings.allowFileAccessFromFileURLs = false
        webView.settings.allowUniversalAccessFromFileURLs = false
        webView.settings.mediaPlaybackRequiresUserGesture = true
        webView.settings.saveFormData = false
        webView.settings.useWideViewPort = true
        webView.settings.loadWithOverviewMode = true
        if (isMailContent) {
            webView.setBackgroundColor(
                if (params["mailDarkMode"] as? Boolean == true)
                    android.graphics.Color.rgb(24, 25, 27)
                else android.graphics.Color.rgb(247, 248, 250),
            )
            webView.setOnScrollChangeListener { _, _, scrollY, _, _ ->
                val collapsed = scrollY > 18
                if (collapsed != lastMailCollapsedState) {
                    lastMailCollapsedState = collapsed
                    viewChannel.invokeMethod(
                        "mailScrollStateChanged",
                        mapOf("collapsed" to collapsed),
                    )
                }
            }
        }
        if (params["useEphemeralSession"] as? Boolean == true) {
            webView.settings.cacheMode = WebSettings.LOAD_NO_CACHE
        }
        webView.settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        @SuppressLint("MissingOnRenderProcessGone")
        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                if (!isMailContent && !sessionInvalidated) {
                    viewChannel.invokeMethod("pageStarted", null)
                }
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                if (!isMailContent && !sessionInvalidated) {
                    emitSessionCookies()
                    if (!isHtmlContent) installPageEnhancementsIfAllowed()
                    viewChannel.invokeMethod("pageFinished", null)
                }
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?,
            ) {
                super.onReceivedError(view, request, error)
                if (
                    !isMailContent &&
                    !sessionInvalidated &&
                    request?.isForMainFrame == true
                ) {
                    viewChannel.invokeMethod("pageError", null)
                }
            }

            @RequiresApi(Build.VERSION_CODES.O)
            override fun onRenderProcessGone(
                view: WebView,
                detail: RenderProcessGoneDetail,
            ): Boolean {
                if (!isMailContent && !sessionInvalidated) {
                    viewChannel.invokeMethod(
                        "pageError",
                        mapOf("rendererCrashed" to detail.didCrash()),
                    )
                }
                handleRenderProcessGone()
                return true
            }

            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?,
            ): Boolean {
                val target = request?.url ?: return true
                if (isMailContent) {
                    if (request.isForMainFrame) {
                        // The isolated mail document is delivered once via
                        // loadDataWithBaseURL, which does not invoke this
                        // callback. Any main-frame navigation that reaches here
                        // is therefore triggered after load — a tapped link or a
                        // content-driven redirect such as a surviving meta
                        // refresh — and must never navigate the mail view. Only
                        // a user-activated web link is handed to the browser.
                        if (request.hasGesture() &&
                            (target.scheme == "http" || target.scheme == "https")
                        ) {
                            try {
                                context.startActivity(
                                    Intent(Intent.ACTION_VIEW, target)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                            } catch (_: ActivityNotFoundException) {
                                // No external handler; drop the navigation
                                // rather than load it in the mail WebView.
                            }
                        }
                        return true
                    }
                    return false
                }
                if (isHtmlContent && request.isForMainFrame) {
                    if (request.hasGesture() && WebOrigin.from(target) != null) {
                        viewChannel.invokeMethod("htmlLinkActivated", target.toString())
                    }
                    // App-owned loadDataWithBaseURL does not need a new URL
                    // navigation. Links leave the passive document via Flutter.
                    return true
                }
                val shouldBlock =
                    request.isForMainFrame && urlPolicy?.allows(target) != true
                if (shouldBlock && !sessionInvalidated) {
                    viewChannel.invokeMethod("navigationBlocked", target.toString())
                }
                if (shouldBlock && !request.hasGesture() && !sessionInvalidated) {
                    viewChannel.invokeMethod("authenticationRequired", null)
                }
                return shouldBlock
            }

            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?,
            ): WebResourceResponse? {
                if (isMailContent) {
                    return super.shouldInterceptRequest(view, request)
                }
                val target = request?.url ?: return blockedWebResponse()
                if (urlPolicy?.allowsResource(target) == true) {
                    return super.shouldInterceptRequest(view, request)
                }
                return blockedWebResponse()
            }
        }

        cookieManager.setAcceptCookie(true)
        cookieManager.setAcceptThirdPartyCookies(webView, false)
        if (!isMailContent && participatesInSessionCleanup) {
            NativeWebSessionRegistry.register(this)
        }

        val initialUrl = (params["initialUrl"] as? String).orEmpty()
        val htmlContent = (params["htmlContent"] as? String).orEmpty()
        val baseUrl = sessionBaseUrl
        val fallbackCookieUrl = baseUrl.ifBlank { initialUrl }
        val fallbackCookieHost = Uri.parse(fallbackCookieUrl).host.orEmpty()
        val cookies = if (isMailContent) {
            emptyList()
        } else {
            (params["cookies"] as? List<*>)
                ?.filterIsInstance<Map<*, *>>()
                ?: emptyList()
        }
        val cookieStrings = mutableListOf<String>()
        for (cookie in cookies) {
            val name = cookie["name"] as? String ?: continue
            val value = cookie["value"] as? String ?: continue
            if (!isValidCookieName(name) || containsCookieControl(value)) {
                continue
            }
            val domain = (cookie["domain"] as? String)
                ?.trim()
                ?.trimStart('.')
                .orEmpty()
            val path = (cookie["path"] as? String)?.trim().orEmpty().ifEmpty { "/" }
            val hostOnly = cookie["hostOnly"] as? Boolean == true
            val secure = cookie["secure"] as? Boolean == true
            val httpOnly = cookie["httpOnly"] as? Boolean == true
            val sameSite = (cookie["sameSite"] as? String)
                ?.trim()
                ?.lowercase()
                ?.takeIf { it == "lax" || it == "strict" || it == "none" }
            val expiresAt = (cookie["expiresAt"] as? Number)?.toLong()
            if (
                domain.isEmpty() ||
                fallbackCookieHost.isEmpty() ||
                !domain.equals(fallbackCookieHost, ignoreCase = true) ||
                !path.startsWith('/') ||
                path.contains(';') ||
                containsCookieControl(path) ||
                (sameSite == "none" && !secure) ||
                (expiresAt != null && expiresAt <= System.currentTimeMillis())
            ) {
                continue
            }
            val domainPart = if (hostOnly) "" else "Domain=$domain; "
            val securePart = if (secure) "Secure; " else ""
            val httpOnlyPart = if (httpOnly) "HttpOnly; " else ""
            val sameSitePart = sameSite?.let {
                "SameSite=${it.replaceFirstChar { character -> character.uppercaseChar() }}; "
            }.orEmpty()
            val expiresPart = expiresAt?.let {
                "Expires=${formatCookieExpires(it)}; "
            }.orEmpty()
            cookieStrings.add(
                "$name=$value; ${domainPart}Path=$path; " +
                    "$securePart$httpOnlyPart$sameSitePart$expiresPart"
            )
        }

        val loadPage = {
            if (!sessionInvalidated) {
                if (!isMailContent && (
                    params["contentType"] !in listOf("url", "html") ||
                    (isHtmlContent && (initialUrl.isNotEmpty() ||
                        htmlContent.isBlank() ||
                        WebOrigin.from(Uri.parse(baseUrl))?.scheme != "https" ||
                        urlPolicy?.allows(Uri.parse(baseUrl)) != true)) ||
                    (!isHtmlContent && htmlContent.isNotEmpty())
                )) {
                    rejectLoad("invalid_content")
                } else if (isMailContent || isHtmlContent) {
                    webView.loadDataWithBaseURL(
                        baseUrl.ifBlank { null },
                        htmlContent,
                        "text/html",
                        "utf-8",
                        null,
                    )
                } else if (initialUrl.isNotBlank()) {
                    val initialUri = Uri.parse(initialUrl)
                    if (urlPolicy?.allows(initialUri) == true) {
                        webView.loadUrl(initialUrl)
                    } else {
                        rejectLoad("initial_url")
                    }
                }
            }
        }
        val installCookiesAndLoad = {
            if (!sessionInvalidated) {
                if (cookieStrings.isEmpty()) {
                    loadPage()
                } else {
                    var remaining = cookieStrings.size
                    var allSucceeded = true
                    pendingCookieOperations += cookieStrings.size
                    for (cookieString in cookieStrings) {
                        cookieManager.setCookie(fallbackCookieUrl, cookieString) { succeeded ->
                            allSucceeded = allSucceeded && succeeded
                            remaining--
                            if (remaining == 0 && !sessionInvalidated) {
                                cookieManager.flush()
                                if (allSucceeded) {
                                    loadPage()
                                } else {
                                    rejectLoad("cookie_setup")
                                }
                            }
                            finishPendingCookieOperation()
                        }
                    }
                }
            }
        }
        if (isHtmlContent) reloadHtmlDocument = loadPage
        val usesFallbackEphemeralStore =
            !isMailContent && useEphemeralSession && isolatedProfileName == null
        if (usesFallbackEphemeralStore) {
            pendingCookieOperations++
            cookieManager.removeAllCookies {
                cookieManager.flush()
                WebStorage.getInstance().deleteAllData()
                if (!sessionInvalidated) {
                    installCookiesAndLoad()
                }
                finishPendingCookieOperation()
            }
        } else {
            installCookiesAndLoad()
        }
    }

    private fun isValidCookieName(value: String): Boolean {
        if (value.isBlank()) {
            return false
        }
        val separators = "()<>@,;:\\\"/[]?={} \t"
        return value.none { character ->
            character.code <= 0x20 || character.code >= 0x7f || separators.contains(character)
        }
    }

    private fun containsCookieControl(value: String): Boolean {
        return value.any { character -> character == '\r' || character == '\n' }
    }

    private fun emitSessionCookies() {
        if (
            sessionInvalidated ||
                sessionBaseUrl.isBlank() ||
                sessionBaseHost.isBlank() ||
                Uri.parse(sessionBaseUrl).scheme?.lowercase() != "https"
        ) {
            return
        }
        val header = cookieManager.getCookie(sessionBaseUrl).orEmpty()
        if (header.isBlank()) {
            return
        }
        val cookies = header.split(';').mapNotNull { segment ->
            val separator = segment.indexOf('=')
            if (separator <= 0) {
                return@mapNotNull null
            }
            val name = segment.substring(0, separator).trim()
            val value = segment.substring(separator + 1).trim()
            if (!isValidCookieName(name) || containsCookieControl(value)) {
                return@mapNotNull null
            }
            val metadata = initialSessionCookieMetadata[name]
            val path = (metadata?.get("path") as? String)
                ?.trim()
                ?.takeIf { candidate ->
                    candidate.startsWith('/') &&
                        !candidate.contains(';') &&
                        !containsCookieControl(candidate)
                }
                ?: "/"
            buildMap<String, Any?> {
                put("name", name)
                put("value", value)
                put("domain", sessionBaseHost)
                put("path", path)
                put("hostOnly", true)
                put("secure", true)
                put("httpOnly", metadata?.get("httpOnly") as? Boolean == true)
                (metadata?.get("sameSite") as? String)?.let { sameSite ->
                    put("sameSite", sameSite)
                }
                (metadata?.get("expiresAt") as? Number)?.let { expiresAt ->
                    put("expiresAt", expiresAt.toLong())
                }
            }
        }
        if (cookies.isNotEmpty()) {
            viewChannel.invokeMethod("sessionCookiesChanged", cookies)
        }
    }

    private inner class LoginCodeSourceBridge {
        @JavascriptInterface
        fun postLoginCodeSource(rawSource: String?) {
            val source = normalizeLoginCodeSource(rawSource.orEmpty()) ?: return
            if (
                sessionInvalidated ||
                    !observeLoginCodes ||
                    source == lastLoginCodeSource ||
                    !isPageEnhancementAllowed()
            ) {
                return
            }
            lastLoginCodeSource = source
            webView.post {
                if (!sessionInvalidated && isPageEnhancementAllowed()) {
                    viewChannel.invokeMethod("loginCodeDetected", null)
                }
            }
        }
    }

    private fun isPageEnhancementAllowed(): Boolean {
        val expected = loginCodeObserverOrigin ?: return false
        val current = webView.url?.let { value -> WebOrigin.from(Uri.parse(value)) }
        return current == expected
    }

    private fun installPageEnhancementsIfAllowed() {
        if (
            (!observeLoginCodes && upgradeInsecureResourceHosts.isEmpty()) ||
                !isPageEnhancementAllowed()
        ) {
            return
        }
        val upgradeHostsJson = org.json.JSONArray(
            upgradeInsecureResourceHosts.toList().sorted(),
        ).toString()
        val observeLoginCode = observeLoginCodes
        val script = """
            (() => {
              if (window.__handsBnbuDuoduoEnhancementsInstalled) {
                window.__handsBnbuUpgradeInsecureResources?.();
                window.__handsBnbuScanLoginCode?.();
                return;
              }
              window.__handsBnbuDuoduoEnhancementsInstalled = true;
              const upgradeHosts = new Set($upgradeHostsJson);
              const normalizeUrl = (value) => {
                if (!value || typeof value !== 'string') return value;
                try {
                  const url = new URL(value, location.href);
                  if (url.protocol === 'http:' && upgradeHosts.has(url.hostname.toLowerCase())) {
                    url.protocol = 'https:';
                    url.port = '';
                    return url.href;
                  }
                } catch (_) {
                  return value;
                }
                return value;
              };
              const upgradeSrcset = (value) => (value || '').split(',').map((entry) => {
                const trimmed = entry.trim();
                if (!trimmed) return trimmed;
                const split = trimmed.search(/\s/);
                if (split < 0) return normalizeUrl(trimmed);
                return normalizeUrl(trimmed.slice(0, split)) + trimmed.slice(split);
              }).join(', ');
              const upgradeInlineStyle = (value) => {
                if (!value || typeof value !== 'string') return value;
                return value.replace(/url\((['"]?)(http:\/\/[^)'"\s]+)\1\)/gi, (all, quote, rawUrl) => {
                  const upgraded = normalizeUrl(rawUrl);
                  return upgraded === rawUrl ? all : 'url(' + quote + upgraded + quote + ')';
                });
              };
              const upgradeElement = (element) => {
                if (!(element instanceof Element)) return;
                for (const attribute of ['src', 'poster']) {
                  const current = element.getAttribute(attribute);
                  const upgraded = normalizeUrl(current);
                  if (current && upgraded !== current) element.setAttribute(attribute, upgraded);
                }
                const srcset = element.getAttribute('srcset');
                if (srcset) {
                  const upgraded = upgradeSrcset(srcset);
                  if (upgraded !== srcset) element.setAttribute('srcset', upgraded);
                }
                const style = element.getAttribute('style');
                if (style) {
                  const upgraded = upgradeInlineStyle(style);
                  if (upgraded !== style) element.setAttribute('style', upgraded);
                }
              };
              const upgradeAll = () => {
                document.querySelectorAll('[src], [srcset], [poster], [style]').forEach(upgradeElement);
              };
              window.__handsBnbuUpgradeInsecureResources = upgradeAll;
              const emitLoginCode = async (image) => {
                let source = image.currentSrc || image.src || '';
                if (!source) return;
                if (source.startsWith('blob:')) {
                  try {
                    const blob = await fetch(source).then((response) => response.blob());
                    source = await new Promise((resolve, reject) => {
                      const reader = new FileReader();
                      reader.onload = () => resolve(String(reader.result || ''));
                      reader.onerror = reject;
                      reader.readAsDataURL(blob);
                    });
                  } catch (_) {
                    return;
                  }
                }
                source = normalizeUrl(source);
                if (source) HandsBnbuLoginCodeBridge.postLoginCodeSource(source);
              };
              const findLoginCodeContainer = () => {
                const marker = Array.from(document.querySelectorAll('div, span, p, h1, h2, h3'))
                  .find((element) => (element.innerText || element.textContent || '').trim() === '微信扫码授权登录');
                let container = marker;
                for (let depth = 0; container && depth < 8; depth += 1, container = container.parentElement) {
                  const text = (container.innerText || '').replace(/\s+/g, ' ');
                  const hasCodeImage = Array.from(container.querySelectorAll('img')).some((image) => {
                    const rect = image.getBoundingClientRect();
                    return rect.width >= 120 && rect.height >= 120;
                  });
                  if (hasCodeImage && text.includes('扫描上方小程序码')) return container;
                }
                return null;
              };
              const scanLoginCode = () => {
                if (!$observeLoginCode) return;
                try {
                  const container = findLoginCodeContainer();
                  const target = Array.from(container?.querySelectorAll('img') || []).find((image) => {
                    const rect = image.getBoundingClientRect();
                    return rect.width >= 120 && rect.height >= 120;
                  });
                  if (target) void emitLoginCode(target);
                } catch (_) {}
              };
              window.__handsBnbuScanLoginCode = scanLoginCode;
              new MutationObserver((records) => {
                for (const record of records) {
                  if (record.target instanceof Element) upgradeElement(record.target);
                  for (const node of record.addedNodes || []) {
                    if (!(node instanceof Element)) continue;
                    upgradeElement(node);
                    node.querySelectorAll?.('[src], [srcset], [poster], [style]').forEach(upgradeElement);
                  }
                }
                scanLoginCode();
              }).observe(document.documentElement, {
                subtree: true,
                childList: true,
                attributes: true,
                attributeFilter: ['src', 'srcset', 'poster', 'style', 'class']
              });
              upgradeAll();
              scanLoginCode();
            })();
        """.trimIndent()
        webView.evaluateJavascript(script, null)
    }

    private data class LoginCodeImage(
        val bytes: ByteArray,
        val mimeType: String,
    )

    private fun normalizeLoginCodeSource(raw: String): String? {
        val source = raw.trim()
        if (source.isEmpty() || source.length > 7_000_000) {
            return null
        }
        if (source.startsWith("data:image/", ignoreCase = true)) {
            return source
        }
        val uri = Uri.parse(source)
        val host = uri.host?.lowercase().orEmpty()
        val normalized = if (
            uri.scheme?.lowercase() == "http" &&
                host in upgradeInsecureResourceHosts &&
                (uri.port == -1 || uri.port == 80) &&
                uri.userInfo.isNullOrEmpty()
        ) {
            uri.buildUpon().scheme("https").encodedAuthority(host).build()
        } else {
            uri
        }
        return if (
            normalized.scheme?.lowercase() == "https" &&
                normalized.userInfo.isNullOrEmpty() &&
                urlPolicy?.allowsResource(normalized) == true
        ) {
            normalized.toString()
        } else {
            null
        }
    }

    private fun loadLoginCodeImage(source: String): LoginCodeImage? {
        if (source.startsWith("data:image/", ignoreCase = true)) {
            val separator = source.indexOf(',')
            if (separator <= 0 || !source.substring(0, separator).contains(";base64")) {
                return null
            }
            val mimeType = source.substringAfter("data:").substringBefore(';').lowercase()
            if (!mimeType.startsWith("image/")) {
                return null
            }
            val bytes = android.util.Base64.decode(
                source.substring(separator + 1),
                android.util.Base64.DEFAULT,
            )
            if (bytes.isEmpty() || bytes.size > 5 * 1024 * 1024) {
                return null
            }
            return LoginCodeImage(bytes, mimeType)
        }
        val uri = Uri.parse(source)
        if (
            uri.scheme?.lowercase() != "https" ||
                !uri.userInfo.isNullOrEmpty() ||
                urlPolicy?.allowsResource(uri) != true
        ) {
            return null
        }
        val connection = URL(source).openConnection() as? HttpsURLConnection
            ?: return null
        return try {
            connection.connectTimeout = 8_000
            connection.readTimeout = 8_000
            connection.instanceFollowRedirects = false
            connection.setRequestProperty("User-Agent", webView.settings.userAgentString)
            val status = connection.responseCode
            if (status !in 200..299) {
                return null
            }
            val mimeType = connection.contentType
                ?.substringBefore(';')
                ?.trim()
                ?.lowercase()
                .orEmpty()
            if (!mimeType.startsWith("image/")) {
                return null
            }
            val bytes = connection.inputStream.use { input ->
                readLimitedBytes(input, 5 * 1024 * 1024)
            }
            LoginCodeImage(bytes, mimeType)
        } finally {
            connection.disconnect()
        }
    }

    private fun readLimitedBytes(input: InputStream, maxBytes: Int): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        var total = 0
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            total += read
            if (total > maxBytes) {
                throw IllegalArgumentException("Login code image is too large")
            }
            output.write(buffer, 0, read)
        }
        return output.toByteArray()
    }

    private fun saveLoginCodeAndOpenWechat(result: MethodChannel.Result) {
        val source = lastLoginCodeSource
        if (source.isBlank() || sessionInvalidated) {
            result.success(mapOf("saved" to false, "openedWechat" to false))
            return
        }
        legacyStoragePermissionRunner(
            result,
            { performLoginCodeSave(source, result) },
            {
                result.success(
                    mapOf(
                        "saved" to false,
                        "openedWechat" to if (sessionInvalidated) false else openWechat(),
                    )
                )
            },
        )
    }

    private fun performLoginCodeSave(
        source: String,
        result: MethodChannel.Result,
    ) {
        thread(name = "handsbnbu-login-code-save") {
            val image = try {
                loadLoginCodeImage(source)
            } catch (_: Exception) {
                null
            }
            val saved = image?.let(::saveLoginCodeToGallery) == true
            webView.post {
                val openedWechat = if (sessionInvalidated) false else openWechat()
                result.success(
                    mapOf(
                        "saved" to saved,
                        "openedWechat" to openedWechat,
                    )
                )
            }
        }
    }

    private fun saveLoginCodeToGallery(image: LoginCodeImage): Boolean {
        val extension = when (image.mimeType) {
            "image/jpeg" -> "jpg"
            "image/webp" -> "webp"
            else -> "png"
        }
        val displayName = "duoduo-login-${System.currentTimeMillis()}.$extension"
        val resolver = appContext.contentResolver
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Images.Media.MIME_TYPE, image.mimeType)
                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    "${Environment.DIRECTORY_PICTURES}/BNBU.ME",
                )
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val target = resolver.insert(
                MediaStore.Images.Media.getContentUri(
                    MediaStore.VOLUME_EXTERNAL_PRIMARY,
                ),
                values,
            ) ?: return false
            return try {
                val output = resolver.openOutputStream(target, "w")
                    ?: throw IllegalStateException("Unable to open gallery destination")
                output.use {
                    output.write(image.bytes)
                }
                val ready = ContentValues().apply {
                    put(MediaStore.Images.Media.IS_PENDING, 0)
                }
                if (resolver.update(target, ready, null, null) != 1) {
                    throw IllegalStateException("Unable to publish login code image")
                }
                true
            } catch (_: Exception) {
                resolver.delete(target, null, null)
                false
            }
        }
        if (
            ContextCompat.checkSelfPermission(
                appContext,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            "BNBU.ME",
        )
        if (!directory.exists() && !directory.mkdirs()) {
            return false
        }
        val file = File(directory, displayName)
        return try {
            FileOutputStream(file).use { output -> output.write(image.bytes) }
            MediaScannerConnection.scanFile(
                appContext,
                arrayOf(file.absolutePath),
                arrayOf(image.mimeType),
                null,
            )
            true
        } catch (_: Exception) {
            file.delete()
            false
        }
    }

    private fun openWechat(): Boolean {
        return try {
            val launchIntent = appContext.packageManager
                .getLaunchIntentForPackage("com.tencent.mm")
                ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ?: Intent(Intent.ACTION_VIEW, Uri.parse("weixin://"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            appContext.startActivity(launchIntent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun clearCurrentSiteData(result: MethodChannel.Result) {
        if (sessionInvalidated || sessionBaseUrl.isBlank() || sessionBaseHost.isBlank()) {
            result.success(false)
            return
        }
        val clearScript = """
            (() => {
              try { localStorage.clear(); } catch (_) {}
              try { sessionStorage.clear(); } catch (_) {}
              try {
                if ('caches' in window) caches.keys().then(keys => keys.forEach(key => caches.delete(key)));
              } catch (_) {}
              return true;
            })();
        """.trimIndent()
        webView.evaluateJavascript(clearScript) {
            cookieManager.removeAllCookies {
                cookieManager.flush()
                clearCurrentWebStorage { result.success(true) }
            }
        }
    }

    @SuppressLint("RequiresFeature")
    private fun clearCurrentWebStorage(completion: () -> Unit) {
        val profileWebStorage = isolatedProfileWebStorage
        if (
            profileWebStorage != null &&
                WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)
        ) {
            WebStorageCompat.deleteBrowsingData(profileWebStorage, completion)
            return
        }
        // Old WebView releases do not expose profile-scoped browsing data.
        // The explicit user action therefore clears the shared fallback store.
        WebStorage.getInstance().deleteAllData()
        completion()
    }

    private fun rejectLoad(reason: String) {
        if (sessionInvalidated) {
            return
        }
        loadFailure = reason
        viewChannel.invokeMethod("loadRejected", reason)
    }

    private fun formatCookieExpires(epochMilliseconds: Long): String {
        val formatter = SimpleDateFormat(
            "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
            Locale.US,
        )
        formatter.timeZone = TimeZone.getTimeZone("GMT")
        return formatter.format(Date(epochMilliseconds))
    }

    override fun getView(): View = webView

    fun clearSession(completion: () -> Unit) {
        if (cleanupFinished) {
            completion()
            return
        }
        cleanupCallbacks.add(completion)
        invalidateSession()
        detachPlatformBindings()
        if (cleanupStarted) {
            return
        }
        cleanupStarted = true
        webView.stopLoading()
        continueCleanupIfReady()
    }

    private fun invalidateSession() {
        sessionInvalidated = true
    }

    private fun handleRenderProcessGone() {
        invalidateSession()
        detachPlatformBindings()
        if (cleanupFinished || cleanupDataRemovalStarted) {
            return
        }
        cleanupStarted = true
        cleanupDataRemovalStarted = true
        (webView.parent as? ViewGroup)?.removeView(webView)
        webView.destroy()
        if (!useEphemeralSession) {
            finishCleanup()
            return
        }
        cookieManager.removeAllCookies {
            cookieManager.flush()
            clearIsolatedProfileData()
        }
    }

    private fun detachPlatformBindings() {
        if (platformBindingsDetached) {
            return
        }
        platformBindingsDetached = true
        viewChannel.setMethodCallHandler(null)
        webView.setOnScrollChangeListener(null)
        if (observeLoginCodes) {
            webView.removeJavascriptInterface("HandsBnbuLoginCodeBridge")
        }
    }

    private fun finishPendingCookieOperation() {
        if (pendingCookieOperations > 0) {
            pendingCookieOperations--
        }
        continueCleanupIfReady()
    }

    private fun continueCleanupIfReady() {
        if (
            !cleanupStarted ||
                cleanupFinished ||
                cleanupDataRemovalStarted ||
                pendingCookieOperations != 0
        ) {
            return
        }
        cleanupDataRemovalStarted = true
        webView.clearHistory()
        webView.clearCache(true)
        webView.destroy()
        cookieManager.removeAllCookies {
            cookieManager.flush()
            clearIsolatedProfileData()
        }
    }

    @SuppressLint("RequiresFeature")
    private fun clearIsolatedProfileData() {
        val profileName = isolatedProfileName
        if (profileName == null) {
            if (useEphemeralSession) {
                WebStorage.getInstance().deleteAllData()
            }
            finishCleanup()
            return
        }
        val finishAndDeleteProfile = {
            finishCleanup()
            NativeWebProfileCleanup.schedule(profileName)
        }
        if (
            isolatedProfileWebStorage != null &&
                WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)
        ) {
            WebStorageCompat.deleteBrowsingData(
                isolatedProfileWebStorage,
                finishAndDeleteProfile,
            )
        } else {
            finishAndDeleteProfile()
        }
    }

    private fun finishCleanup() {
        if (cleanupFinished) {
            return
        }
        cleanupFinished = true
        detachPlatformBindings()
        if (participatesInSessionCleanup) {
            NativeWebSessionRegistry.unregister(this)
        }
        val callbacks = cleanupCallbacks.toList()
        cleanupCallbacks.clear()
        for (callback in callbacks) {
            callback()
        }
    }

    override fun dispose() {
        invalidateSession()
        detachPlatformBindings()
        if (isMailContent) {
            webView.stopLoading()
            webView.destroy()
            return
        }
        if (cleanupStarted || cleanupFinished) {
            clearSession {}
            return
        }
        if (!useEphemeralSession) {
            if (participatesInSessionCleanup) {
                NativeWebSessionRegistry.unregister(this)
            }
            webView.stopLoading()
            webView.destroy()
            return
        }
        clearSession {}
    }
}
