/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import CarPlay
import Foundation

/// CarPlay audio-app entry point. Presents the radio as an audio experience: a
/// browsable channel list (the "stations") that opens the system Now Playing
/// screen for the selected channel, plus an Options screen for region, scan,
/// dual-watch and power. All state comes from [CarBridge.shared]; templates
/// rebuild whenever the bridge reports new state.
///
/// NOTE: CarPlay requires the com.apple.developer.carplay-audio entitlement,
/// granted by Apple. The CarPlay Simulator renders audio apps for development.
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
        CarBridge.shared.activateAudioSession()
        CarBridge.shared.updateNowPlayingInfo()
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
        root.trailingNavigationBarButtons =
            (bridge.connected && bridge.powerOn) ? [optionsBarButton()] : []
    }

    private func rootSections(_ bridge: CarBridge) -> [CPListSection] {
        if !bridge.connected {
            return [radioPickerSection(bridge)]
        }
        if !bridge.powerOn {
            return [poweredOffSection()]
        }
        return [channelSection(bridge)]
    }

    /// The browse list of channels; the active channel is marked as playing and
    /// selecting one opens the Now Playing screen.
    private func channelSection(_ bridge: CarBridge) -> CPListSection {
        let named = bridge.channels.filter { !$0.name.isEmpty }
        if named.isEmpty {
            let detail = "\(bridge.vfoA.title)  \(bridge.vfoA.subtitle)".trimmingCharacters(in: .whitespaces)
            let item = CPListItem(text: "VFO A", detailText: detail)
            item.isPlaying = true
            item.handler = { [weak self] _, completion in
                self?.showNowPlaying()
                completion()
            }
            return CPListSection(items: [item], header: "Now Playing", sectionIndexTitle: nil)
        }
        let items = named.map { channel -> CPListItem in
            let item = CPListItem(text: channel.name, detailText: channel.frequency)
            item.isPlaying = channel.id == bridge.vfoA.channelId
            item.handler = { [weak self] _, completion in
                CarBridge.shared.requestChannel(channelId: channel.id, vfo: "A")
                self?.showNowPlaying()
                completion()
            }
            return item
        }
        return CPListSection(items: items, header: "Channels", sectionIndexTitle: nil)
    }

    // MARK: - Now Playing

    private func showNowPlaying() {
        guard let ic = interfaceController else { return }
        CarBridge.shared.updateNowPlayingInfo()
        if ic.topTemplate is CPNowPlayingTemplate { return }
        ic.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }

    // MARK: - Not-connected / powered-off sections

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
            return CPListSection(items: [CPListItem(text: "Searching for radios…", detailText: nil)])
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

    // MARK: - Options (region / scan / dual-watch / power)

    private func optionsBarButton() -> CPBarButton {
        return CPBarButton(title: "Options") { [weak self] _ in
            self?.pushOptions()
        }
    }

    private func pushOptions() {
        let bridge = CarBridge.shared
        var rows: [CPListItem] = []

        let regionRow = CPListItem(text: "Region", detailText: bridge.regionName.isEmpty ? "—" : bridge.regionName)
        regionRow.accessoryType = .disclosureIndicator
        regionRow.handler = { [weak self] _, completion in
            self?.pushRegionPicker()
            completion()
        }
        rows.append(regionRow)

        let scanRow = CPListItem(text: "Scan", detailText: bridge.scan ? "On" : "Off")
        scanRow.handler = { _, completion in
            CarBridge.shared.requestScan(!bridge.scan)
            completion()
        }
        rows.append(scanRow)

        let dualRow = CPListItem(text: "Dual Watch", detailText: bridge.dualWatch ? "On" : "Off")
        dualRow.handler = { _, completion in
            CarBridge.shared.requestDualWatch(!bridge.dualWatch)
            completion()
        }
        rows.append(dualRow)

        let powerOff = CPListItem(text: "Power off", detailText: nil)
        powerOff.handler = { [weak self] _, completion in
            CarBridge.shared.requestRadioPower(false)
            self?.interfaceController?.popTemplate(animated: true, completion: nil)
            completion()
        }
        rows.append(powerOff)

        let disconnect = CPListItem(text: "Disconnect", detailText: nil)
        disconnect.handler = { [weak self] _, completion in
            CarBridge.shared.requestDisconnect()
            self?.interfaceController?.popTemplate(animated: true, completion: nil)
            completion()
        }
        rows.append(disconnect)

        let template = CPListTemplate(title: "Options", sections: [CPListSection(items: rows)])
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
    }

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
}
