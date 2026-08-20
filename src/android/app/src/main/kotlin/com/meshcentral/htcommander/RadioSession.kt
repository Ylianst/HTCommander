package com.meshcentral.htcommander

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Provides the root screen shown when the car UI is launched and reports the
 * car connection state to [AndroidAutoBridge] so incoming APRS messages are
 * only read aloud while Android Auto is projecting.
 */
class RadioSession : Session(), DefaultLifecycleObserver {
    init {
        lifecycle.addObserver(this)
    }

    override fun onCreate(owner: LifecycleOwner) {
        AndroidAutoBridge.setCarConnected(true)
    }

    override fun onDestroy(owner: LifecycleOwner) {
        AndroidAutoBridge.setCarConnected(false)
    }

    override fun onCreateScreen(intent: Intent): Screen =
        RadioStatusScreen(carContext)
}
