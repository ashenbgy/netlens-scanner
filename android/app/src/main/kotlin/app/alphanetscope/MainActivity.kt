package app.alphanetscope

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Latest WifiInfo delivered by ConnectivityManager on API 31+, where
    // WifiManager.connectionInfo is deprecated and redacts identity fields.
    @Volatile
    private var latestWifiInfo: WifiInfo? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alpha_netscope/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getConnectedWifiSignal" -> {
                        try {
                            val reading = readConnectedWifi()
                            if (reading == null) {
                                result.error("WIFI_UNAVAILABLE", "No Wi-Fi connection", null)
                            } else {
                                result.success(reading)
                            }
                        } catch (error: Exception) {
                            result.error("WIFI_UNAVAILABLE", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Measuring means walking around with the phone in hand; don't let the
    // screen sleep and stop the readings mid-walk.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onStart() {
        super.onStart()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) registerWifiCallback()
    }

    override fun onStop() {
        unregisterWifiCallback()
        super.onStop()
    }

    // RSSI, frequency and link speed are read fresh on every call. On API 31+
    // the synchronous snapshot redacts SSID/BSSID, so identity comes from the
    // location-aware callback instead; the callback's own RSSI is stale
    // between capability updates, which is why it isn't used for the level.
    private fun readConnectedWifi(): Map<String, Any?>? {
        val live = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) snapshotWifiInfo() else legacyWifiInfo()
        val info = live ?: latestWifiInfo ?: return null
        val identity = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) latestWifiInfo ?: info else info
        return mapOf(
            "ssid" to identity.ssid,
            "bssid" to identity.bssid,
            "rssi" to info.rssi,
            "frequency" to info.frequency,
            "linkSpeed" to info.linkSpeed,
            "standard" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) info.wifiStandard else null,
        )
    }

    // Callback hasn't fired yet (or lacks location); the synchronous
    // capabilities snapshot still carries RSSI and frequency.
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun snapshotWifiInfo(): WifiInfo? {
        val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = connectivity.activeNetwork ?: return null
        val capabilities = connectivity.getNetworkCapabilities(network) ?: return null
        if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return null
        return capabilities.transportInfo as? WifiInfo
    }

    @Suppress("DEPRECATION")
    private fun legacyWifiInfo(): WifiInfo? {
        val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        return manager.connectionInfo
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun registerWifiCallback() {
        if (networkCallback != null) return
        val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val callback = object : ConnectivityManager.NetworkCallback(
            ConnectivityManager.NetworkCallback.FLAG_INCLUDE_LOCATION_INFO,
        ) {
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                    latestWifiInfo = capabilities.transportInfo as? WifiInfo
                }
            }

            override fun onLost(network: Network) {
                latestWifiInfo = null
            }
        }
        try {
            connectivity.registerNetworkCallback(
                NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build(),
                callback,
            )
            networkCallback = callback
        } catch (_: Exception) {
            // Without the callback the synchronous fallback still reports RSSI.
        }
    }

    private fun unregisterWifiCallback() {
        val callback = networkCallback ?: return
        networkCallback = null
        latestWifiInfo = null
        try {
            val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            connectivity.unregisterNetworkCallback(callback)
        } catch (_: Exception) {
        }
    }
}
