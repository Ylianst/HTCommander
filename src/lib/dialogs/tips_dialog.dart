import 'package:flutter/material.dart';

import '../aprs/aprs_util.dart';
import '../handlers/speech_to_text_engine.dart';
import '../l10n/app_localizations.dart';
import '../services/callsign_lookup_service.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/host_bridge.dart';
import '../services/winlink_gateway_service.dart';
import '../winlink/i_mail_store.dart';
import 'app_settings.dart';
import 'callsign_lookup_dialog.dart';
import 'dialog_utils.dart';

enum _Tip {
  license,
  winlink,
  aprsIs,
  push,
  satellite,
  fcc,
  gateways,
  speech,
  firstMail,
  weather,
  sms,
  location,
  contacts,
  packets,
}

class TipsDialog extends StatefulWidget {
  final Future<void> Function(String tab) onOpenSettings;
  final void Function(String tab) onOpenTab;

  const TipsDialog({
    super.key,
    required this.onOpenSettings,
    required this.onOpenTab,
  });

  static bool get showOnStart =>
      DataBroker.getValue<bool>(0, 'TipsShowOnStart', true) ?? true;

  @override
  State<TipsDialog> createState() => _TipsDialogState();
}

class _TipsDialogState extends State<TipsDialog> {
  final _broker = DataBrokerClient();
  int _index = 0;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    final next = DataBroker.getValue<String>(0, 'TipsNextId');
    final index = _Tip.values.indexWhere((tip) => tip.name == next);
    if (index >= 0) _index = index;
    _rememberNextTip();
    _broker.subscribeAll(
      deviceId: 0,
      callback: (_, _, _) {
        if (mounted) setState(() {});
      },
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'CommsHandlerState',
      callback: (_, _, _) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  void _rememberNextTip() {
    _broker.dispatch(
      deviceId: 0,
      name: 'TipsNextId',
      data: _Tip.values[(_index + 1) % _Tip.values.length].name,
    );
  }

  bool? _configured(_Tip tip) {
    final settings = AppSettings.loadFromDataBroker();
    final licensed =
        settings.callSign.trim().isNotEmpty &&
        settings.stationId >= 0 &&
        settings.stationId <= 15 &&
        settings.allowTransmit;
    switch (tip) {
      case _Tip.license:
        return licensed;
      case _Tip.winlink:
        return licensed && HostBridge.isCredentialSet('WinlinkPassword');
      case _Tip.aprsIs:
        return settings.callSign.trim().isNotEmpty &&
            settings.aprsIsEnabled &&
            (HostBridge.isHosted
                ? HostBridge.isCredentialSet('AprsIsPasscode')
                : settings.aprsIsPasscode.trim() ==
                      AprsUtil.aprsValidationCode(settings.callSign));
      case _Tip.push:
        return _configured(_Tip.aprsIs)! && settings.aprsCloudNotifications;
      case _Tip.satellite:
        return settings.satelliteSupport;
      case _Tip.fcc:
        return CallsignLookupService.instance.isSourceAvailable(
          CallsignDbSource.us,
        );
      case _Tip.gateways:
        return WinlinkGatewayService.instance.isAvailable;
      case _Tip.firstMail:
        return DataBroker.getDataHandler<IMailStore>(
              'MailStore',
            )?.getAllMails().any((mail) => mail.mailbox == 'Sent') ??
            false;
      case _Tip.speech:
        final state = DataBroker.getValueDynamic(1, 'CommsHandlerState');
        return isRadioSpeechSupported &&
            (DataBroker.getValue<bool>(0, 'SpeechToTextEnabled', true) ??
                true) &&
            state is Map &&
            state['engineReady'] == true;
      default:
        return null;
    }
  }

  (String, String, String?) _content(
    _Tip tip,
    AppLocalizations l10n,
  ) => switch (tip) {
    _Tip.license => (l10n.tipsLicenseTitle, l10n.tipsLicenseBody, 'License'),
    _Tip.winlink => (l10n.tipsWinlinkTitle, l10n.tipsWinlinkBody, 'Winlink'),
    _Tip.aprsIs => (l10n.tipsAprsIsTitle, l10n.tipsAprsIsBody, 'APRS'),
    _Tip.push => (l10n.tipsPushTitle, l10n.tipsPushBody, 'APRS'),
    _Tip.satellite => (
      l10n.tipsSatelliteTitle,
      l10n.tipsSatelliteBody,
      'Application',
    ),
    _Tip.fcc => (l10n.tipsFccTitle, l10n.tipsFccBody, null),
    _Tip.gateways => (l10n.tipsGatewaysTitle, l10n.tipsGatewaysBody, 'Winlink'),
    _Tip.speech => (l10n.tipsSpeechTitle, l10n.tipsSpeechBody, 'Comms'),
    _Tip.firstMail => (l10n.tipsFirstMailTitle, l10n.tipsFirstMailBody, null),
    _Tip.weather => (l10n.tipsWeatherTitle, l10n.tipsWeatherBody, null),
    _Tip.sms => (l10n.tipsSmsTitle, l10n.tipsSmsBody, null),
    _Tip.location => (l10n.tipsLocationTitle, l10n.tipsLocationBody, 'License'),
    _Tip.contacts => (l10n.tipsContactsTitle, l10n.tipsContactsBody, null),
    _Tip.packets => (l10n.tipsPacketsTitle, l10n.tipsPacketsBody, null),
  };

  String _tabLabel(String tab, AppLocalizations l10n) => switch (tab) {
    'License' => l10n.settingsTabLicense,
    'Winlink' => l10n.settingsTabWinlink,
    'APRS' => l10n.settingsTabAprs,
    'Application' => l10n.settingsTabApplication,
    'Comms' => l10n.settingsTabComms,
    _ => throw StateError('Unknown settings tab: $tab'),
  };

  void _move(int delta) {
    setState(() => _index = (_index + delta) % _Tip.values.length);
    _rememberNextTip();
  }

  Future<void> _openSettings(String tab) async {
    setState(() => _opening = true);
    try {
      await widget.onOpenSettings(tab);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _openFeature(String tab) {
    widget.onOpenTab(tab);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tip = _Tip.values[_index];
    final (title, body, settingsTab) = _content(tip, l10n);
    final configured = _configured(tip);
    final done =
        configured ??
        (DataBroker.getValue<bool>(0, 'TipDone.${tip.name}', false) ?? false);
    final feature = switch (tip) {
      _Tip.firstMail => ('Mail', l10n.tabMail),
      _Tip.weather || _Tip.sms => ('APRS', l10n.tabAprs),
      _Tip.contacts => ('Contacts', l10n.tabContacts),
      _Tip.packets => ('Packets', l10n.tabPackets),
      _ => null,
    };
    final navigationStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      minimumSize: const Size(0, 48),
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 12),
    );
    return HTDialog(
      maxWidth: 600,
      maxHeight: 620,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                l10n.tipsPosition(_index + 1),
                style: DialogStyles.titleStyle,
              ),
              if (configured == null)
                InkWell(
                  onTap: () => _broker.dispatch(
                    deviceId: 0,
                    name: 'TipDone.${tip.name}',
                    data: !done,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        key: const ValueKey('tipCompletion'),
                        visualDensity: VisualDensity.compact,
                        value: done,
                        activeColor: Colors.green,
                        onChanged: (value) => _broker.dispatch(
                          deviceId: 0,
                          name: 'TipDone.${tip.name}',
                          data: value ?? false,
                        ),
                      ),
                      Text(
                        done ? l10n.tipsDone : l10n.tipsTodo,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              else if (done)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_box, color: Colors.green, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      l10n.tipsDone,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              key: ValueKey(tip),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text(body, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 20),
                  if (settingsTab != null)
                    FilledButton.icon(
                      onPressed:
                          _opening ||
                              (tip == _Tip.speech && !isRadioSpeechSupported)
                          ? null
                          : () => _openSettings(settingsTab),
                      icon: const Icon(Icons.settings),
                      label: Text(
                        l10n.tipsOpenSettings(_tabLabel(settingsTab, l10n)),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        textStyle: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(fontSize: 18),
                      ),
                    ),
                  if (tip == _Tip.fcc &&
                      CallsignLookupService.instance.isSupported)
                    FilledButton.icon(
                      onPressed: () async {
                        await CallsignLookupDialog.show(context);
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.search),
                      label: Text(l10n.tipsOpenFeature(l10n.cslTitle)),
                    ),
                  if (feature != null)
                    FilledButton.icon(
                      onPressed:
                          tip == _Tip.firstMail && !_configured(_Tip.winlink)!
                          ? null
                          : () => _openFeature(feature.$1),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(l10n.tipsOpenFeature(feature.$2)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              InkWell(
                onTap: () => _broker.dispatch(
                  deviceId: 0,
                  name: 'TipsShowOnStart',
                  data: !TipsDialog.showOnStart,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      visualDensity: VisualDensity.compact,
                      value: TipsDialog.showOnStart,
                      onChanged: (value) => _broker.dispatch(
                        deviceId: 0,
                        name: 'TipsShowOnStart',
                        data: value ?? false,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        l10n.tipsShowOnStart,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    style: navigationStyle,
                    onPressed: _opening ? null : () => _move(-1),
                    child: Text(l10n.tipsPrevious),
                  ),
                  TextButton(
                    style: navigationStyle,
                    onPressed: _opening ? null : () => _move(1),
                    child: Text(l10n.tipsNext),
                  ),
                  TextButton(
                    style: navigationStyle,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.commonClose),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
