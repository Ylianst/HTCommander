/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/l10n/app_localizations.dart';

Map<String, dynamic> readArb(String language) =>
    jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
        as Map<String, dynamic>;

Map<String, String> recentMessages(AppLocalizations l10n) => {
  'settingsEnableAgentApi': l10n.settingsEnableAgentApi,
  'agentControlActive': l10n.agentControlActive(2),
  'agentControlActiveRadios': l10n.agentControlActiveRadios(2, '101, 102'),
  'agentControlStop': l10n.agentControlStop,
  'settingsAgentApiToken': l10n.settingsAgentApiToken,
  'settingsAgentApiCopyToken': l10n.settingsAgentApiCopyToken,
  'settingsAgentApiNewToken': l10n.settingsAgentApiNewToken,
  'settingsAgentApiTokenCopied': l10n.settingsAgentApiTokenCopied,
  'settingsAgentApiWarning': l10n.settingsAgentApiWarning,
  'terminalBusy': l10n.terminalBusy,
  'terminalXaraRequiresAudio': l10n.terminalXaraRequiresAudio,
  'terminalXaraNoAnswer': l10n.terminalXaraNoAnswer,
  'terminalXaraLockTimeout': l10n.terminalXaraLockTimeout,
  'terminalXaraDisconnectTimeout': l10n.terminalXaraDisconnectTimeout,
  'terminalXaraPathInvalid': l10n.terminalXaraPathInvalid,
  'xaraSettingsTitle': l10n.xaraSettingsTitle,
  'xaraSettingsKeyUp': l10n.xaraSettingsKeyUp,
  'xaraSettingsKeyUpHelp': l10n.xaraSettingsKeyUpHelp,
  'xaraSettingsLatency': l10n.xaraSettingsLatency,
  'xaraSettingsLatencyHelp': l10n.xaraSettingsLatencyHelp,
  'xaraSettingsDefaultMs': l10n.xaraSettingsDefaultMs(300),
  'xaraSettingsTimingInvalid': l10n.xaraSettingsTimingInvalid,
  'xaraSettingsLinkWarning': l10n.xaraSettingsLinkWarning,
  'xaraSettingsRestoreDefaults': l10n.xaraSettingsRestoreDefaults,
  'xaraSettingsSave': l10n.xaraSettingsSave,
};

void main() {
  final englishArb = readArb('en');
  final messageKeys = englishArb.keys.where((key) => !key.startsWith('@'));

  for (final locale in AppLocalizations.supportedLocales) {
    test('${locale.languageCode} has every message and placeholder', () {
      final arb = readArb(locale.languageCode);
      for (final key in messageKeys) {
        expect(arb[key], isA<String>(), reason: key);
        final metadata = englishArb['@$key'] as Map<String, dynamic>?;
        final placeholders = metadata?['placeholders'] as Map<String, dynamic>?;
        for (final placeholder in placeholders?.keys ?? <String>[]) {
          expect(
            arb[key],
            matches(RegExp('\\{$placeholder\\s*[,}]')),
            reason: '$key must retain $placeholder',
          );
        }
      }
    });

    if (locale.languageCode == 'en') continue;

    test(
      '${locale.languageCode} translates automation and XARA messages',
      () async {
        final l10n = await AppLocalizations.delegate.load(locale);
        final english = recentMessages(
          await AppLocalizations.delegate.load(const Locale('en')),
        );
        final messages = recentMessages(l10n);
        expect(messages, hasLength(25));
        for (final entry in messages.entries) {
          expect(entry.value, isNotEmpty, reason: entry.key);
          // "Token" is also the local term in several languages.
          if (entry.key == 'settingsAgentApiToken') continue;
          expect(entry.value, isNot(english[entry.key]), reason: entry.key);
        }
        for (final count in [0, 1, 2, 5, 12, 22]) {
          expect(l10n.agentControlActive(count), isNotEmpty);
          expect(
            l10n.agentControlActiveRadios(count, '101, 102'),
            startsWith(l10n.agentControlActive(count)),
          );
          expect(
            l10n.agentControlActiveRadios(count, '101, 102'),
            endsWith('101, 102'),
          );
        }
        expect(l10n.xaraSettingsDefaultMs(300), contains('300'));
        expect(l10n.xaraSettingsDefaultMs(300), contains('0-5000'));
      },
    );
  }

  test('Polish agent counts use singular, few and many forms', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('pl'));
    expect(l10n.agentControlActive(1), 'Agent testowy steruje tą stacją');
    for (final count in [2, 22]) {
      expect(
        l10n.agentControlActive(count),
        '$count agenci testowi sterują tą stacją',
      );
    }
    for (final count in [0, 5, 12]) {
      expect(
        l10n.agentControlActive(count),
        '$count agentów testowych steruje tą stacją',
      );
    }
  });
}
