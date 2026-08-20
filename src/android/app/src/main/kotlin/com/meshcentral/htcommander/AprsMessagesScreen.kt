package com.meshcentral.htcommander

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Car screen listing recent APRS text messages addressed to our station,
 * newest first. Read-only; mirrors [AndroidAutoBridge] state and re-renders as
 * new messages arrive.
 */
class AprsMessagesScreen(carContext: CarContext) :
    Screen(carContext), DefaultLifecycleObserver {

    private val timeFormat = SimpleDateFormat("HH:mm", Locale.getDefault())
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
        val messages = AndroidAutoBridge.messages

        if (messages.isEmpty()) {
            listBuilder.setNoItemsMessage("No APRS messages")
        } else {
            val limit = carContext.getCarService(ConstraintManager::class.java)
                .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
            for (message in messages.take(limit)) {
                val time = timeFormat.format(Date(message.time))
                val header = if (message.from.isBlank()) {
                    time
                } else {
                    "${message.from} · $time"
                }
                listBuilder.addItem(
                    Row.Builder()
                        .setTitle(header)
                        .addText(message.text)
                        .build(),
                )
            }
        }

        return ListTemplate.Builder()
            .setTitle("APRS Messages")
            .setHeaderAction(Action.BACK)
            .setSingleList(listBuilder.build())
            .build()
    }
}
