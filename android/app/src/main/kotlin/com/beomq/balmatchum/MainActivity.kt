package com.beomq.balmatchum

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Remove only the app-controlled exit animation, once Flutter is ready.
            // Launcher-to-window animations remain under Android/launcher control.
            splashScreen.setOnExitAnimationListener { it.remove() }
        }
    }
}
