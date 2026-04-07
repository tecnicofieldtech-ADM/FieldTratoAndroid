package com.rfeedmirror

import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	companion object {
		private const val CHANNEL = "rfeed_pa/android_network"
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"openWifiPicker" -> result.success(openWifiPicker())
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
}

