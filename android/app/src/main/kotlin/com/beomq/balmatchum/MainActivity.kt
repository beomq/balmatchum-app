package com.beomq.balmatchum

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "balmatchum/ads_config")
            .setMethodCallHandler { call, result ->
                if (call.method == "appId") {
                    val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
                    result.success(info.metaData?.getString("com.google.android.gms.ads.APPLICATION_ID") ?: "")
                } else {
                    result.notImplemented()
                }
            }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Remove only the app-controlled exit animation, once Flutter is ready.
            // Launcher-to-window animations remain under Android/launcher control.
            splashScreen.setOnExitAnimationListener { it.remove() }
        }
    }
}
