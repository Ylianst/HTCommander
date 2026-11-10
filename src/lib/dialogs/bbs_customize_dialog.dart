/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../handlers/bbs_files.dart';
import '../handlers/bbs_games.dart';
import '../handlers/bbs_settings.dart';
import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';
import '../utils/callsign_format.dart';
import 'bbs_files_dialog.dart';
import 'dialog_utils.dart';

Future<void> showBbsCustomizeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const BbsCustomizeDialog(),
  );
}

/// Lets the sysop customize what the BBS offers to connecting stations.
class BbsCustomizeDialog extends StatefulWidget {
  const BbsCustomizeDialog({super.key});

  @override
  State<BbsCustomizeDialog> createState() => _BbsCustomizeDialogState();
}

class _BbsCustomizeDialogState extends State<BbsCustomizeDialog>
    with SingleTickerProviderStateMixin {
  final _broker = DataBrokerClient();
  late final TabController _tabController;
  late final BbsSettings _settings;
  late final TextEditingController _welcome;
  late final TextEditingController _announcement;
  late final TextEditingController _maxUploadKb;
  final _newStation = TextEditingController();
  late bool _uploadsEnabled;
  bool _maxUploadInvalid = false;
  bool _newStationInvalid = false;

  static const int _maxUploadKbLimit = BbsSettings.maxUploadBytesLimit ~/ 1024;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _settings = BbsSettings.load();
    _welcome = TextEditingController(text: _settings.welcomeMessage);
    _announcement = TextEditingController(text: _settings.announcementText);
    _maxUploadKb = TextEditingController(
      text: (_settings.maxUploadBytes / 1024).ceil().toString(),
    );
    _uploadsEnabled =
        (_broker.getValue<int>(0, BbsFileStore.uploadsSetting, 1) ?? 1) == 1;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _welcome.dispose();
    _announcement.dispose();
    _maxUploadKb.dispose();
    _newStation.dispose();
    _broker.dispose();
    super.dispose();
  }

  void _save() {
    final kb = int.tryParse(_maxUploadKb.text.trim());
    if (kb == null || kb < 1 || kb > _maxUploadKbLimit) {
      setState(() => _maxUploadInvalid = true);
      _tabController.animateTo(1);
      return;
    }
    _settings
      ..welcomeMessage = _welcome.text
      ..announcementText = _announcement.text
      ..maxUploadBytes = kb * 1024;
    _settings.save(_broker);
    _broker.dispatch(
      deviceId: 0,
      name: BbsFileStore.uploadsSetting,
      data: _uploadsEnabled ? 1 : 0,
    );
    Navigator.of(context).pop();
  }

  // ---- styling helpers ------------------------------------------------------

  TextStyle _hintStyle() => TextStyle(
    fontSize: 12,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );

  Widget _section(String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool>? onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _tab(List<Widget> children) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  // ---- tabs -----------------------------------------------------------------

  Widget _buildGeneralTab(AppLocalizations l10n) {
    return _tab([
      _section(l10n.bbsWelcomeMessage, [
        TextField(
          controller: _welcome,
          minLines: 2,
          maxLines: 5,
          maxLength: 500,
          decoration: DialogStyles.inputDecoration(context),
        ),
        Text(l10n.bbsWelcomeMessageHelp, style: _hintStyle()),
      ]),
      _section(l10n.bbsAnnouncement, [
        _switch(
          l10n.bbsAnnouncementEnable,
          _settings.announcementEnabled,
          (v) => setState(() => _settings.announcementEnabled = v),
        ),
        TextField(
          controller: _announcement,
          enabled: _settings.announcementEnabled,
          minLines: 3,
          maxLines: 8,
          maxLength: 2000,
          decoration: DialogStyles.inputDecoration(
            context,
            hintText: l10n.bbsAnnouncementText,
          ),
        ),
        Text(l10n.bbsAnnouncementHelp, style: _hintStyle()),
      ]),
      _section(l10n.bbsCallsignLookup, [
        _switch(
          l10n.bbsCallsignLookupEnable,
          _settings.callsignLookupEnabled,
          (v) => setState(() => _settings.callsignLookupEnabled = v),
        ),
        Text(l10n.bbsCallsignLookupHelp, style: _hintStyle()),
      ]),
    ]);
  }

  Widget _buildFilesTab(AppLocalizations l10n) {
    return _tab([
      _section(l10n.bbsUploads, [
        _switch(
          l10n.bbsFilesAllowUploads,
          _uploadsEnabled,
          (v) => setState(() => _uploadsEnabled = v),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _maxUploadKb,
          enabled: _uploadsEnabled,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) {
            if (_maxUploadInvalid) setState(() => _maxUploadInvalid = false);
          },
          decoration: DialogStyles.inputDecoration(
            context,
            labelText: l10n.bbsMaxUploadSize,
            errorText: _maxUploadInvalid
                ? l10n.bbsMaxUploadSizeInvalid(_maxUploadKbLimit)
                : null,
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.bbsUploadsHelp, style: _hintStyle()),
      ]),
      _section(l10n.bbsDownloads, [
        Text(l10n.bbsDownloadsHelp, style: _hintStyle()),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: () => BbsFilesDialog.show(context),
          child: Text(l10n.bbsManageFiles),
        ),
      ]),
    ]);
  }

  String _gameName(AppLocalizations l10n, String key, String name) =>
      switch (key) {
        'GUESS' => l10n.bbsGameGuess,
        'HANGMAN' => l10n.bbsGameHangman,
        'MORSE' => l10n.bbsGameMorse,
        'TTT' => l10n.bbsGameTtt,
        _ => name,
      };

  Widget _buildGamesTab(AppLocalizations l10n) {
    return _tab([
      _section(l10n.bbsCustomizeGames, [
        _switch(
          l10n.bbsGamesEnable,
          _settings.gamesEnabled,
          (v) => setState(() => _settings.gamesEnabled = v),
        ),
        Text(l10n.bbsGamesHelp, style: _hintStyle()),
        const SizedBox(height: 8),
        for (final game in BbsGames.all)
          CheckboxListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 16),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(_gameName(l10n, game.key, game.name)),
            value: !_settings.disabledGames.contains(game.key),
            onChanged: _settings.gamesEnabled
                ? (v) => setState(() {
                    if (v == true) {
                      _settings.disabledGames.remove(game.key);
                    } else {
                      _settings.disabledGames.add(game.key);
                    }
                  })
                : null,
          ),
      ]),
    ]);
  }

  Widget _buildAprsTab(AppLocalizations l10n) {
    return _tab([
      _section(l10n.bbsCustomizeAprs, [
        _switch(
          l10n.bbsAprsMessagesEnable,
          _settings.aprsMessagesEnabled,
          (v) => setState(() => _settings.aprsMessagesEnabled = v),
        ),
        Text(l10n.bbsAprsMessagesHelp, style: _hintStyle()),
        const SizedBox(height: 8),
        _switch(
          l10n.bbsAprsLookupEnable,
          _settings.aprsLookupEnabled,
          (v) => setState(() => _settings.aprsLookupEnabled = v),
        ),
        Text(l10n.bbsAprsLookupHelp, style: _hintStyle()),
        const SizedBox(height: 8),
        _switch(
          l10n.bbsAprsHeardEnable,
          _settings.aprsHeardEnabled,
          (v) => setState(() => _settings.aprsHeardEnabled = v),
        ),
        Text(l10n.bbsAprsHeardHelp, style: _hintStyle()),
      ]),
    ]);
  }

  Widget _buildWinlinkTab(AppLocalizations l10n) {
    return _tab([
      _section(l10n.bbsWinlinkGateway, [
        _switch(
          l10n.bbsWinlinkGatewayEnable,
          _settings.winlinkGatewayEnabled,
          (v) => setState(() => _settings.winlinkGatewayEnabled = v),
        ),
        Text(l10n.bbsWinlinkGatewayHelp, style: _hintStyle()),
      ]),
    ]);
  }

  List<String> get _accessList => _settings.allowListOnly
      ? _settings.allowedStations
      : _settings.deniedStations;

  void _addStation() {
    final call = normalizeAmateurCallsign(_newStation.text);
    if (call == null) {
      setState(() => _newStationInvalid = true);
      return;
    }
    final station = BbsSettings.normalizeStation(call);
    setState(() {
      if (!_accessList.contains(station)) _accessList.add(station);
      _newStation.clear();
      _newStationInvalid = false;
    });
  }

  Widget _buildAccessTab(AppLocalizations l10n) {
    final list = _accessList;
    return _tab([
      _section(l10n.bbsAccessMode, [
        RadioGroup<bool>(
          groupValue: _settings.allowListOnly,
          onChanged: (v) => setState(() {
            _settings.allowListOnly = v ?? false;
            _newStationInvalid = false;
          }),
          child: Column(
            children: [
              RadioListTile<bool>(
                value: false,
                title: Text(l10n.bbsAccessOpen),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              RadioListTile<bool>(
                value: true,
                title: Text(l10n.bbsAccessAllowListOnly),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ),
        ),
        Text(l10n.bbsAccessHelp, style: _hintStyle()),
      ]),
      _section(_settings.allowListOnly ? l10n.bbsAllowList : l10n.bbsDenyList, [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _newStation,
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) {
                  if (_newStationInvalid) {
                    setState(() => _newStationInvalid = false);
                  }
                },
                onSubmitted: (_) => _addStation(),
                decoration: DialogStyles.inputDecoration(
                  context,
                  hintText: l10n.bbsAccessCallsign,
                  errorText: _newStationInvalid
                      ? l10n.bbsAccessInvalidCallsign
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _addStation,
              child: Text(l10n.bbsAccessAdd),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Text(l10n.bbsAccessEmpty, style: _hintStyle())
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final station in list)
                InputChip(
                  label: Text(station),
                  deleteButtonTooltipMessage: l10n.bbsAccessRemove,
                  onDeleted: () => setState(() => list.remove(station)),
                ),
            ],
          ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.bbsCustomizeTitle, style: DialogStyles.titleStyle),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                labelColor: scheme.primary,
                unselectedLabelColor: scheme.onSurfaceVariant,
                indicatorColor: scheme.primary,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(text: l10n.bbsCustomizeGeneral),
                  Tab(text: l10n.bbsFiles),
                  Tab(text: l10n.bbsCustomizeGames),
                  Tab(text: l10n.bbsCustomizeAprs),
                  Tab(text: l10n.bbsCustomizeWinlink),
                  Tab(text: l10n.bbsCustomizeAccess),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildGeneralTab(l10n),
                    _buildFilesTab(l10n),
                    _buildGamesTab(l10n),
                    _buildAprsTab(l10n),
                    _buildWinlinkTab(l10n),
                    _buildAccessTab(l10n),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: Text(l10n.commonCancel),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _save,
                    style: DialogStyles.primaryButtonStyle(context),
                    child: Text(l10n.commonOk),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
