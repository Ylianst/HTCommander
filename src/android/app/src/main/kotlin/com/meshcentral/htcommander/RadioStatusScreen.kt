package com.meshcentral.htcommander

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.constraints.ConstraintManager
import androidx.car.app.model.Action
import androidx.car.app.model.ActionStrip
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.model.Toggle
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/**
 * Root car screen showing the preferred radio's live status and the controls
 * to change it:
 *   - Region, VFO A and VFO B rows open a picker ([RegionListScreen] /
 *     [ChannelListScreen]) and show the current selection as their subtitle.
 *   - Scan and Dual-Watch rows carry a native toggle switch.
 *   - A "Messages" header action opens the [MessagesScreen].
 *
 * The screen mirrors [AndroidAutoBridge] state and re-renders whenever that
 * state changes by registering a listener for the duration of its lifecycle.
 */
class RadioStatusScreen(carContext: CarContext) :
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
        val title = AndroidAutoBridge.radioName.ifBlank { "HTCommander" }

        if (!AndroidAutoBridge.connected) {
            val listBuilder = ItemList.Builder()
            val radios = AndroidAutoBridge.availableRadios
            if (radios.isEmpty()) {
                listBuilder.setNoItemsMessage(
                    if (AndroidAutoBridge.scanningRadios) {
                        "Looking for paired radios…"
                    } else {
                        "No paired radios found. Open HTCommander to check Bluetooth access."
                    },
                )
            } else {
                val limit = carContext.getCarService(ConstraintManager::class.java)
                    .getContentLimit(ConstraintManager.CONTENT_LIMIT_TYPE_LIST)
                val pageSize = if (radios.size > limit && limit > 1) limit - 1 else limit
                for (radio in radios.take(pageSize)) {
                    val connecting = radio.id == AndroidAutoBridge.connectingRadioId
                    val failed = radio.id == AndroidAutoBridge.radioConnectionErrorId
                    val row = Row.Builder()
                        .setTitle(radio.name.ifBlank { radio.id })
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
                if (pageSize < radios.size) {
                    listBuilder.addItem(
                        Row.Builder()
                            .setTitle("More radios")
                            .setBrowsable(true)
                            .setOnClickListener {
                                screenManager.push(RadioPickerScreen(carContext, pageSize))
                            }
                            .build(),
                    )
                }
            }
            val refreshAction = Action.Builder()
                .setTitle("Refresh")
                .setOnClickListener { AndroidAutoBridge.requestRadioRefresh() }
                .build()
            return ListTemplate.Builder()
                .setTitle(title)
                .setHeaderAction(Action.APP_ICON)
                .setActionStrip(ActionStrip.Builder().addAction(refreshAction).build())
                .setSingleList(listBuilder.build())
                .build()
        }

        val listBuilder = ItemList.Builder()

        // VFO A
        listBuilder.addItem(
            Row.Builder()
                .setTitle("VFO A")
                .addText(AndroidAutoBridge.vfoA.name.ifBlank { "—" })
                .setBrowsable(true)
                .setOnClickListener {
                    screenManager.push(ChannelListScreen(carContext, "A"))
                }
                .build(),
        )

        if (AndroidAutoBridge.scan || AndroidAutoBridge.dualWatch) {
            // VFO B
            listBuilder.addItem(
                Row.Builder()
                    .setTitle("VFO B")
                    .addText(AndroidAutoBridge.vfoB.name.ifBlank { "—" })
                    .setBrowsable(true)
                    .setOnClickListener {
                        screenManager.push(ChannelListScreen(carContext, "B"))
                    }
                    .build(),
            )
        }

        // Scan (toggle)
        listBuilder.addItem(
            Row.Builder()
                .setTitle("Scan")
                .setToggle(
                    Toggle.Builder { checked -> AndroidAutoBridge.requestScan(checked) }
                        .setChecked(AndroidAutoBridge.scan)
                        .build(),
                )
                .build(),
        )

        // Dual-Watch (toggle)
        listBuilder.addItem(
            Row.Builder()
                .setTitle("Dual-Watch")
                .setToggle(
                    Toggle.Builder { checked -> AndroidAutoBridge.requestDualWatch(checked) }
                        .setChecked(AndroidAutoBridge.dualWatch)
                        .build(),
                )
                .build(),
        )

        // Region
        listBuilder.addItem(
            Row.Builder()
                .setTitle("Region")
                .addText(AndroidAutoBridge.regionName.ifBlank { "—" })
                .setBrowsable(true)
                .setOnClickListener {
                    screenManager.push(RegionListScreen(carContext))
                }
                .build(),
        )

        val messagesAction = Action.Builder()
            .setTitle("Messages")
            .setOnClickListener {
                screenManager.push(MessagesScreen(carContext))
            }
            .build()

        return ListTemplate.Builder()
            .setTitle(title)
            .setHeaderAction(Action.APP_ICON)
            .setActionStrip(ActionStrip.Builder().addAction(messagesAction).build())
            .setSingleList(listBuilder.build())
            .build()
    }
}
