package net.specta.app

import android.app.Activity
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.StatFs
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.UUID

/**
 * Phase 2G-C: implements the `net.specta.app/environment` platform channel
 * the download system's DeviceEnvironment seam calls.
 *
 * Before this implementation the channel had NO native handler: every probe
 * threw MissingPluginException, the Dart side honestly answered "unknown",
 * and the Wi-Fi-only download policy conservatively blocked EVERY queued
 * download on a real device (the queue could never start). Device
 * verification exposed this; the tests could never catch it because they
 * inject a fake DeviceEnvironment.
 *
 * Answers (honest, conservative):
 * - networkAccess → "wifi" | "mobile" | "ethernet" | "none" | "other" |
 *   "unknown"; null is never returned (the string "unknown" covers
 *   anything unmapped). Uses NetworkCapabilities only — no deprecated
 *   networkInfo, no coarse location dependency.
 * - freeBytes → bytes free on the volume holding the given path, or -1
 *   when it cannot be determined (the Dart side maps that to null).
 *
 * Permissions: ACCESS_NETWORK_STATE is required for the connectivity probe
 * (declared in the manifest alongside INTERNET by this phase). StatFs needs
 * no permission.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "net.specta.app/environment"
        const val FILE_PICKER_CHANNEL = "net.specta.app/file_picker"

        /// Request code for the SAF document picker intent.
        const val REQUEST_PICK_FILE = 0x5A17

        /// Mirrors `maxPickedFileBytes` on the Dart side: the copy stops here
        /// so a huge document can never fill app-private storage.
        const val MAX_PICK_BYTES = 10L * 1024L * 1024L
    }

    /// The one in-flight picker reply. SAF answers arrive in `onActivityResult`,
    /// long after the method call that launched them.
    private var pendingPickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "networkAccess" -> result.success(networkAccessCode())
                "freeBytes" -> {
                    val path = call.argument<String>("path")
                    result.success(freeBytes(path))
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FILE_PICKER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFile" -> startPickFile(result)
                else -> result.notImplemented()
            }
        }
    }

    /// Launches the Storage Access Framework document picker.
    ///
    /// The `MethodChannel.Result` is parked until `onActivityResult` answers it;
    /// a second launch while one is pending is refused instead of leaking the
    /// first reply.
    private fun startPickFile(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("pick_in_progress", "A file picker is already open.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "application/javascript",
                    "text/javascript",
                    "text/plain",
                    "application/octet-stream",
                ),
            )
        }
        pendingPickResult = result
        startActivityForResult(intent, REQUEST_PICK_FILE)
    }

    /// SAF answered: cancel → `null`; selection → copy into app-private
    /// storage, hashing every byte on the way in, then report path + digest.
    ///
    /// The Dart side independently re-reads this copy and re-hashes it before
    /// the path may be used — neither side trusts the other's word.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_FILE) return
        val pending = pendingPickResult ?: return
        pendingPickResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending.success(null)
            return
        }
        try {
            val uri: Uri = data.data!!
            val displayName = queryDisplayName(uri) ?: "picked.js"
            val copyDir = File(filesDir, "picked")
            copyDir.mkdirs()
            val target = File(copyDir, "${UUID.randomUUID()}_${sanitizeName(displayName)}")
            val digest = MessageDigest.getInstance("SHA-256")
            var total = 0L
            val input = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Document stream unavailable.")
            input.use { stream ->
                target.outputStream().use { out ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = stream.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_PICK_BYTES) {
                            target.delete()
                            pending.error(
                                "file_too_large",
                                "That file is larger than $MAX_PICK_BYTES bytes.",
                                null,
                            )
                            return
                        }
                        digest.update(buffer, 0, read)
                        out.write(buffer, 0, read)
                    }
                }
            }
            val sha256 = digest.digest().joinToString("") { "%02x".format(it) }
            pending.success(
                mapOf(
                    "path" to target.absolutePath,
                    "displayName" to displayName,
                    "sizeBytes" to total,
                    "sha256" to sha256,
                ),
            )
        } catch (e: Exception) {
            pending.error("copy_failed", e.message ?: "Document copy failed.", null)
        }
    }

    /// Display name of a content URI, or null when the provider won't say.
    private fun queryDisplayName(uri: Uri): String? {
        return contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst() && !cursor.isNull(index)) {
                    cursor.getString(index)
                } else {
                    null
                }
            }
    }

    /// Keeps the provider-supplied name from becoming a path component or an
    /// oddity in app-private storage; falls back to a plain default.
    private fun sanitizeName(name: String): String {
        val cleaned = name.replace(Regex("[^A-Za-z0-9._-]"), "_").takeLast(64)
        return if (cleaned.isBlank() || cleaned.startsWith(".")) "picked.js" else cleaned
    }

    /** Maps the active network onto SPECTA's NetworkAccess codes. */
    private fun networkAccessCode(): String {
        val connectivity = getSystemService(ConnectivityManager::class.java)
            ?: return "unknown"
        val network = connectivity.activeNetwork ?: return "none"
        val capabilities = connectivity.getNetworkCapabilities(network)
            ?: return "unknown"
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ->
                "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ->
                "mobile"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ->
                "ethernet"
            capabilities.hasCapability(
                NetworkCapabilities.NET_CAPABILITY_INTERNET,
            ) -> "other"
            else -> "unknown"
        }
    }

    /** Bytes free on the volume holding [path]; -1 when undeterminable. */
    private fun freeBytes(path: String?): Long {
        if (path.isNullOrBlank()) return -1
        return try {
            val dir = File(path).parentFile ?: File(path)
            StatFs(dir.absolutePath).availableBytes
        } catch (_: Exception) {
            -1
        }
    }
}
