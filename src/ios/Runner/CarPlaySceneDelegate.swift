/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import CarPlay
import Foundation

/// CarPlay entry point. Builds the radio-status dashboard and its picker
/// screens from CarPlay list templates, mirroring the Android Auto screens
/// (`RadioStatusScreen`, `RegionListScreen`, `ChannelListScreen`,
/// `MessagesScreen`, `RadioOptionsScreen`, `RadioPickerScreen`).
///
/// All state comes from [CarBridge.shared]; every template is rebuilt whenever
/// the bridge reports new state so the UI stays in sync with the radio. Control
/// taps are forwarded to Dart through the bridge.
///
/// NOTE: CarPlay requires a com.apple.developer.carplay-* entitlement granted
/// by Apple. Without it this scene will not be created on device; the CarPlay
/// Simulator in Xcode can be used for development.
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var rootTemplate: CPListTemplate?
    private var listenerToken: Int?

    // MARK: - Scene lifecycle

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let root = CPListTemplate(title: "HTCommander", sections: [])
        rootTemplate = root
        interfaceController.setRootTemplate(root, animated: false, completion: nil)
        rebuildRoot()

        // Re-render on every state change and let Dart know the car is active.
        listenerToken = CarBridge.shared.addListener { [weak self] in
            self?.rebuildRoot()
        }
        CarBridge.shared.setCarConnected(true)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        if let token = listenerToken { CarBridge.shared.removeListener(token) }
        listenerToken = nil
        CarBridge.shared.setCarConnected(false)
        self.interfaceController = nil
        rootTemplate = nil
    }

    // MARK: - Root: radio status dashboard

    private func rebuildRoot() {
        guard let root = rootTemplate else { return }
        let bridge = CarBridge.shared
        root.updateSections(rootSections(bridge))
        // Refresh the "Messages" trailing bar button count/state.
        root.trailingNavigationBarButtons = [messagesBarButton()]
    }

    private func rootSections(_ bridge: CarBridge) -> [CPListSection] {
        if !bridge.connected {
            return [radioPickerSection(bridge)]
        }
        if !bridge.powerOn {
            return [poweredOffSection()]
        }

        var rows: [CPListItem] = []

        // Region row -> region picker.
        let regionRow = CPListItem(text: "Region", detailText: bridge.regionName.isEmpty ? "—" : bridge.regionName)
        regionRow.accessoryType = .disclosureIndicator
        regionRow.handler = { [weak self] _, completion in
            self?.pushRegionPicker()
            completion()
        }
        rows.append(regionRow)

        // VFO A row -> channel picker for VFO A.
        rows.append(vfoRow(title: "VFO A", vfo: bridge.vfoA, vfoId: "A"))

        // VFO B row (shown when scan or dual-watch make it meaningful).
        if bridge.scan || bridge.dualWatch {
            rows.append(vfoRow(title: "VFO B", vfo: bridge.vfoB, vfoId: "B"))
        }

        // Scan toggle.
        let scanRow = CPListItem(text: "Scan", detailText: bridge.scan ? "On" : "Off")
        scanRow.handler = { _, completion in
            CarBridge.shared.requestScan(!bridge.scan)
            completion()
        }
        rows.append(scanRow)

        // Dual-watch toggle.
        let dualRow = CPListItem(text: "Dual Watch", detailText: bridge.dualWatch ? "On" : "Off")
        dualRow.handler = { _, completion in
            CarBridge.shared.requestDualWatch(!bridge.dualWatch)
            completion()
        }
        rows.append(dualRow)

        // Radio options (power off / disconnect).
        let optionsRow = CPListItem(text: "Radio options", detailText: nil)
        optionsRow.accessoryType = .disclosureIndicator
        optionsRow.handler = { [weak self] _, completion in
            self?.pushRadioOptions()
            completion()
        }
        rows.append(optionsRow)

        return [CPListSection(items: rows)]
    }

    private func vfoRow(title: String, vfo: CarBridge.CarVfo, vfoId: String) -> CPListItem {
        let row = CPListItem(text: title, detailText: "\(vfo.title)  \(vfo.subtitle)".trimmingCharacters(in: .whitespaces))
        row.accessoryType = .disclosureIndicator
        row.handler = { [weak self] _, completion in
            self?.pushChannelPicker(vfo: vfoId)
            completion()
        }
        return row
    }

    // MARK: - Powered off / picker sections

    private func poweredOffSection() -> CPListSection {
        let powerOn = CPListItem(text: "Power on", detailText: nil)
        powerOn.handler = { _, completion in
            CarBridge.shared.requestRadioPower(true)
            completion()
        }
        let disconnect = CPListItem(text: "Disconnect", detailText: nil)
        disconnect.handler = { _, completion in
            CarBridge.shared.requestDisconnect()
            completion()
        }
        return CPListSection(items: [powerOn, disconnect])
    }

    private func radioPickerSection(_ bridge: CarBridge) -> CPListSection {
        if bridge.scanningRadios && bridge.availableRadios.isEmpty {
            let scanning = CPListItem(text: "Searching for radios…", detailText: nil)
            return CPListSection(items: [scanning])
        }
        if bridge.availableRadios.isEmpty {
            let refresh = CPListItem(text: "Search for radios", detailText: "No radios found")
            refresh.handler = { _, completion in
                CarBridge.shared.requestRadioRefresh()
                completion()
            }
            return CPListSection(items: [refresh])
        }
        let items = bridge.availableRadios.map { radio -> CPListItem in
            let connecting = radio.id == bridge.connectingRadioId
            let failed = radio.id == bridge.radioConnectionErrorId
            let detail = connecting ? "Connecting…" : (failed ? "Connection failed" : nil)
            let item = CPListItem(text: radio.name.isEmpty ? radio.id : radio.name, detailText: detail)
            item.handler = { _, completion in
                if bridge.connectingRadioId.isEmpty {
                    CarBridge.shared.requestRadioConnection(id: radio.id)
                }
                completion()
            }
            return item
        }
        return CPListSection(items: items)
    }

    // MARK: - Pushed templates

    private func pushRegionPicker() {
        let bridge = CarBridge.shared
        let items = bridge.regions.map { region -> CPListItem in
            let item = CPListItem(text: region.name, detailText: region.index == bridge.regionIndex ? "Current" : nil)
            item.handler = { [weak self] _, completion in
                CarBridge.shared.requestRegion(region.index)
                self?.interfaceController?.popTemplate(animated: true, completion: nil)
                completion()
            }
            return item
        }
        let template = CPListTemplate(title: "Region", sections: [CPListSection(items: items)])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func pushChannelPicker(vfo: String) {
        let bridge = CarBridge.shared
        let currentId = vfo == "B" ? bridge.vfoB.channelId : bridge.vfoA.channelId
        let items = bridge.channels.filter { !$0.name.isEmpty }.map { channel -> CPListItem in
            let item = CPListItem(text: channel.name, detailText: channel.id == currentId ? "Current" : channel.frequency)
            item.handler = { [weak self] _, completion in
                CarBridge.shared.requestChannel(channelId: channel.id, vfo: vfo)
                self?.interfaceController?.popTemplate(animated: true, completion: nil)
                completion()
            }
            return item
        }
        let template = CPListTemplate(title: "VFO \(vfo)", sections: [CPListSection(items: items)])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func pushRadioOptions() {
        let powerOff = CPListItem(text: "Power off", detailText: nil)
        powerOff.handler = { [weak self] _, completion in
            CarBridge.shared.requestRadioPower(false)
            self?.interfaceController?.popTemplate(animated: true, completion: nil)
            completion()
        }
        let disconnect = CPListItem(text: "Disconnect", detailText: nil)
        disconnect.handler = { [weak self] _, completion in
            CarBridge.shared.requestDisconnect()
            self?.interfaceController?.popTemplate(animated: true, completion: nil)
            completion()
        }
        let template = CPListTemplate(title: "Radio options", sections: [CPListSection(items: [powerOff, disconnect])])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func pushMessages() {
        let bridge = CarBridge.shared
        let items = bridge.messages.map { message -> CPListItem in
            let from = message.from.isEmpty ? message.kind : "\(message.from) (\(message.kind))"
            return CPListItem(text: from, detailText: message.text)
        }
        let sections = items.isEmpty
            ? [CPListSection(items: [CPListItem(text: "No messages", detailText: nil)])]
            : [CPListSection(items: items)]
        let template = CPListTemplate(title: "Messages", sections: sections)
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

    private func messagesBarButton() -> CPBarButton {
        let count = CarBridge.shared.messages.count
        let title = count > 0 ? "Messages (\(count))" : "Messages"
        return CPBarButton(title: title) { [weak self] _ in
            self?.pushMessages()
        }
    }
}
