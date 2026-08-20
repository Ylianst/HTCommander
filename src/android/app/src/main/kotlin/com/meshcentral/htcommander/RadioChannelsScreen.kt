package com.meshcentral.htcommander

import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Root car screen: lists the preferred radio's channels and lets the driver
 * switch the active channel with a single tap. A header action opens the
 * [AprsMessagesScreen].
 *
 * The screen mirrors [AndroidAutoBridge] state and re-renders whenever that
 * state changes by registering a listener for the duration of its lifecycle.
 */
class RadioChannelsScreen(carContext: CarContext) :
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
        val channels = AndroidAutoBridge.channels
        val currentId = AndroidAutoBridge.currentChannelId

        if (channels.isEmpty()) {
            listBuilder.setNoItemsMessage(
                if (AndroidAutoBridge.connected) {
                    "No channels available"
                } else {
                    "Open HTCommander and connect a radio"
                },
            )
        } else {
            // The host caps how many rows a list may contain; never exceed it or
            // the template is rejected at runtime.
            val limit = carContext.getCarService(ConstraintManager::class.java)
                .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
            for (channel in channels.take(limit)) {
                val title = channel.name.ifBlank { "Channel ${channel.id + 1}" }
                val row = Row.Builder().setTitle(title)
                if (channel.id == currentId) {
                    row.addText("Current")
                }
                row.setOnClickListener {
                    AndroidAutoBridge.requestChannel(channel.id)
                    CarToast.makeText(
                        carContext,
                        "Switching to $title",
                        CarToast.LENGTH_SHORT,
                    ).show()
                }
                listBuilder.addItem(row.build())
            }
        }

        val title = AndroidAutoBridge.radioName.ifBlank { "HTCommander" }

        return ListTemplate.Builder()
            .setTitle(title)
            .setHeaderAction(Action.APP_ICON)
            .setActionStrip(
                ActionStrip.Builder()
                    .addAction(
                        Action.Builder()
                            .setTitle("Messages")
                            .setOnClickListener {
                                screenManager.push(AprsMessagesScreen(carContext))
                            }
                            .build(),
                    )
                    .build(),
            )
            .setSingleList(listBuilder.build())
            .build()
    }
}
