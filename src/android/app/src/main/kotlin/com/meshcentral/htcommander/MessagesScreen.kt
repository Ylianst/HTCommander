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
 * Car screen listing recent messages addressed to our station, newest first.
 * Mixes on-air chat (APRS and other) with Winlink Inbox mail; each row is
 * prefixed with its source. Read-only; mirrors [AndroidAutoBridge] state and
 * re-renders as new messages arrive.
 */
class MessagesScreen(carContext: CarContext) :
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
            listBuilder.setNoItemsMessage("No messages")
        } else {
            val limit = carContext.getCarService(ConstraintManager::class.java)
                .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
            for (message in messages.take(limit)) {
                val time = timeFormat.format(Date(message.time))
                // Header: "<source> · <kind> · <time>", dropping empty parts.
                val header = listOfNotNull(
                    message.from.ifBlank { null },
                    message.kind.ifBlank { null },
                    time,
                ).joinToString(" · ")
                listBuilder.addItem(
                    Row.Builder()
                        .setTitle(header)
                        .addText(message.text)
                        .build(),
                )
            }
        }

        return ListTemplate.Builder()
            .setTitle("Messages")
            .setHeaderAction(Action.BACK)
            .setSingleList(listBuilder.build())
            .build()
    }
}
