package net.specta.app

import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

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
    }

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
