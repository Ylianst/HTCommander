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
 * Region picker: lists the preferred radio's regions and switches to the tapped
 * one. The current region is marked. Mirrors [AndroidAutoBridge] state.
 */
class RegionListScreen(carContext: CarContext) :
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
        val regions = AndroidAutoBridge.regions
        val currentIndex = AndroidAutoBridge.regionIndex

        if (regions.isEmpty()) {
            listBuilder.setNoItemsMessage("No regions available")
        } else {
            val limit = carContext.getCarService(ConstraintManager::class.java)
                .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
            for (region in regions.take(limit)) {
                val row = Row.Builder().setTitle(region.name.ifBlank { "Region ${region.index + 1}" })
                if (region.index == currentIndex) {
                    row.addText("Current")
                }
                row.setOnClickListener {
                    AndroidAutoBridge.requestRegion(region.index)
                    CarToast.makeText(
                        carContext,
                        "Switching to ${region.name}",
                        CarToast.LENGTH_SHORT,
                    ).show()
                    screenManager.pop()
                }
                listBuilder.addItem(row.build())
            }
        }

        return ListTemplate.Builder()
            .setTitle("Region")
            .setHeaderAction(Action.BACK)
            .setSingleList(listBuilder.build())
            .build()
    }
}
