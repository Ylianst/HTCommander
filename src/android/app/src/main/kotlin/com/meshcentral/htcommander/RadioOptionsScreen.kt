package com.meshcentral.htcommander

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Extra options for the connected (powered-on) radio: turn it off or
 * disconnect. Both actions pop back to [RadioStatusScreen], which then reflects
 * the new state (powered-off view or the radio picker).
 */
class RadioOptionsScreen(carContext: CarContext) :
    Screen(carContext), DefaultLifecycleObserver {

    private val stateListener: () -> Unit = { invalidate() }

    init {
        lifecycle.addObserver(this)
    }

    override fun onStart(owner: LifecycleOwner) {
        AndroidAutoBridge.addListener(stateListener)
    }

    override fun onStop(owner: LifecycleOwner) {
        AndroidAutoBridge.removeListener(stateListener)
    }

    override fun onGetTemplate(): Template {
        val listBuilder = ItemList.Builder()
            .addItem(
                Row.Builder()
                    .setTitle("Power off")
                    .addText("Turn the radio off")
                    .setOnClickListener {
                        AndroidAutoBridge.requestRadioPower(false)
                        screenManager.pop()
                    }
                    .build(),
            )
            .addItem(
                Row.Builder()
                    .setTitle("Disconnect")
                    .addText("Disconnect from this radio")
                    .setOnClickListener {
                        AndroidAutoBridge.requestDisconnect()
                        screenManager.pop()
                    }
                    .build(),
            )

        return ListTemplate.Builder()
            .setTitle("Radio options")
            .setHeaderAction(Action.BACK)
            .setSingleList(listBuilder.build())
            .build()
    }
}
