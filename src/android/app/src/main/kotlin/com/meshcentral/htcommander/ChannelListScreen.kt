package com.meshcentral.htcommander

import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Channel picker for a single VFO ("A" or "B"): lists the preferred radio's
 * channels and assigns the tapped one to that VFO. The channel currently on the
 * VFO is marked. Mirrors [AndroidAutoBridge] state.
 */
class ChannelListScreen(
    carContext: CarContext,
    private val vfo: String,
    private val pageIndex: Int = 0,
) :
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
        val channels = AndroidAutoBridge.channels.filter { it.name.isNotBlank() }
        val currentId = if (vfo == "B") {
            AndroidAutoBridge.vfoB.channelId
        } else {
            AndroidAutoBridge.vfoA.channelId
        }

        if (channels.isEmpty()) {
            listBuilder.setNoItemsMessage("No channels available")
        } else {
            val limit = carContext.getCarService(ConstraintManager::class.java)
                .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
            val pageSize = if (channels.size > limit && limit > 1) limit - 1 else limit
            val pageStart = (pageIndex * pageSize).coerceAtMost(channels.lastIndex)
            val pageEnd = (pageStart + pageSize).coerceAtMost(channels.size)

            for (channel in channels.subList(pageStart, pageEnd)) {
                val name = channel.name
                val row = Row.Builder().setTitle(name)
                if (channel.id == currentId) {
                    row.addText("Current")
                }
                row.setOnClickListener {
                    AndroidAutoBridge.requestChannel(channel.id, vfo)
                    CarToast.makeText(
                        carContext,
                        "VFO $vfo → $name",
                        CarToast.LENGTH_SHORT,
                    ).show()
                    screenManager.popToRoot()
                }
                listBuilder.addItem(row.build())
            }

            if (pageEnd < channels.size) {
                listBuilder.addItem(
                    Row.Builder()
                        .setTitle("Next channels")
                        .addText("${pageEnd + 1}–${channels.size}")
                        .setBrowsable(true)
                        .setOnClickListener {
                            screenManager.push(
                                ChannelListScreen(carContext, vfo, pageIndex + 1),
                            )
                        }
                        .build(),
                )
            }
        }

        return ListTemplate.Builder()
            .setTitle("VFO $vfo")
            .setHeaderAction(Action.BACK)
            .setSingleList(listBuilder.build())
            .build()
    }
}
