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

/** Continuation pages for paired radios that exceed the host's list limit. */
class RadioPickerScreen(carContext: CarContext, private val pageStart: Int) :
    Screen(carContext), DefaultLifecycleObserver {

    private val stateListener: () -> Unit = {
        if (AndroidAutoBridge.connected) screenManager.popToRoot() else invalidate()
    }

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
        val radios = AndroidAutoBridge.availableRadios
        if (pageStart >= radios.size) {
            listBuilder.setNoItemsMessage("No more paired radios")
        } else {
            val limit = carContext.getCarService(ConstraintManager::class.java)
                .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
            val remaining = radios.size - pageStart
            val pageSize = if (remaining > limit && limit > 1) limit - 1 else limit
            val pageEnd = (pageStart + pageSize).coerceAtMost(radios.size)

            for (radio in radios.subList(pageStart, pageEnd)) {
                val connecting = radio.id == AndroidAutoBridge.connectingRadioId
                val failed = radio.id == AndroidAutoBridge.radioConnectionErrorId
                val row = Row.Builder().setTitle(radio.name.ifBlank { radio.id })
                when {
                    connecting -> row.addText("Connecting…")
                    failed -> row.addText("Connection failed. Tap to retry.")
                    radio.name.isNotBlank() -> row.addText(radio.id)
                }
                if (AndroidAutoBridge.connectingRadioId.isEmpty()) {
                    row.setOnClickListener {
                        AndroidAutoBridge.requestRadioConnection(radio.id)
                    }
                }
                listBuilder.addItem(row.build())
            }

            if (pageEnd < radios.size) {
                listBuilder.addItem(
                    Row.Builder()
                        .setTitle("More radios")
                        .setBrowsable(true)
                        .setOnClickListener {
                            screenManager.push(RadioPickerScreen(carContext, pageEnd))
                        }
                        .build(),
                )
            }
        }

        return ListTemplate.Builder()
            .setTitle("Select radio")
            .setHeaderAction(Action.BACK)
            .setSingleList(listBuilder.build())
            .build()
    }
}