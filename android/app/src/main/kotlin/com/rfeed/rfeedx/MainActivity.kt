package com.rfeed.rfeedx

import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	companion object {
		private const val CHANNEL = "rfeed/android_network"
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"openWifiPicker" -> result.success(openWifiPicker())
					"openLocationSettings" -> result.success(openLocationSettings())
					"getWifiSsid" -> result.success(getWifiSsid())
					"isLocationEnabled" -> result.success(isLocationEnabled())
					else -> result.notImplemented()
				}
			}
	}

	private fun openWifiPicker(): Boolean {
		return try {
			val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
			} else {
				Intent(Settings.ACTION_WIFI_SETTINGS)
			}
			startActivity(intent)
			true
		} catch (_: Exception) {
			false
		}
	}

	private fun openLocationSettings(): Boolean {
		return try {
			startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
			true
		} catch (_: Exception) {
			false
		}
	}

	private fun getWifiSsid(): String {
		return try {
			val wifiManager =
				applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
			var ssid = wifiManager?.connectionInfo?.ssid ?: ""
			if (ssid.startsWith("\"") && ssid.endsWith("\"") && ssid.length >= 2) {
				ssid = ssid.substring(1, ssid.length - 1)
			}
			if (ssid.equals("<unknown ssid>", ignoreCase = true)) "" else ssid.trim()
		} catch (_: Exception) {
			""
		}
	}

	private fun isLocationEnabled(): Boolean {
		return try {
			val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager
			lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true ||
				lm?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true
		} catch (_: Exception) {
			false
		}
	}
}
