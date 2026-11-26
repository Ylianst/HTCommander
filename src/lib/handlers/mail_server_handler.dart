// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';

import '../services/data_broker_client.dart';
import '../winlink/mail_store.dart';
import '../winlink/pop3_server.dart';
import '../winlink/smtp_server.dart';

/// Desktop mail server lifecycle, serialized across settings changes.
class MailServerHandler {
  MailServerHandler(this._store);
  final MailStore _store;
  final _broker = DataBrokerClient();
  SmtpServer? _smtp;
  Pop3Server? _pop3;
  Future<void> _pending = Future.value();
  Object? _configuration;
  bool _disposed = false;

  bool get smtpRunning => _smtp?.isRunning ?? false;
  bool get pop3Running => _pop3?.isRunning ?? false;
  Future<void> get settled => _pending;

  void init() {
    _broker.subscribeMultiple(
      deviceId: 0,
      names: [
        'smtpServerEnabled',
        'smtpServerPort',
        'pop3ServerEnabled',
        'pop3ServerPort',
        'MailServerPassword',
        'CallSign',
        'StationId',
        'WinlinkUseStationId',
      ],
      callback: (_, _, _) => _schedule(),
    );
    _schedule();
  }

  void _schedule() {
    if (_disposed) return;
    _pending = _pending.then((_) => _apply()).catchError((Object error) {
      _broker.logError('[MailServerHandler] Cannot update servers: $error');
    });
  }

  Future<void> _apply() async {
    if (_disposed) return;
    final smtpEnabled =
        (_broker.getValue<int>(0, 'smtpServerEnabled', 0) ?? 0) == 1;
    final popEnabled =
        (_broker.getValue<int>(0, 'pop3ServerEnabled', 0) ?? 0) == 1;
    final smtpPort = _broker.getValue<int>(0, 'smtpServerPort', 8025) ?? 8025;
    final popPort = _broker.getValue<int>(0, 'pop3ServerPort', 8110) ?? 8110;
    var account = (_broker.getValue<String>(0, 'CallSign', '') ?? '')
        .trim()
        .toUpperCase();
    final stationId = _broker.getValue<int>(0, 'StationId', 0) ?? 0;
    if ((_broker.getValue<int>(0, 'WinlinkUseStationId', 0) ?? 0) == 1 &&
        stationId > 0) {
      account += '-$stationId';
    }
    final password =
        _broker.getValue<String>(0, 'MailServerPassword', '') ?? '';
    final configuration = (
      smtpEnabled,
      smtpPort,
      popEnabled,
      popPort,
      account,
      password,
    );
    if (configuration == _configuration) return;
    _configuration = configuration;
    await _stop();
    if (_disposed || (!smtpEnabled && !popEnabled)) return;
    if (!RegExp(r'^[A-Z0-9]+(?:-\d{1,2})?$').hasMatch(account) ||
        password.length < 12 ||
        !RegExp(r'^[\x20-\x7e]+$').hasMatch(password) ||
        (smtpEnabled && (smtpPort < 1 || smtpPort > 65535)) ||
        (popEnabled && (popPort < 1 || popPort > 65535)) ||
        (smtpEnabled && popEnabled && smtpPort == popPort)) {
      _broker.logError('[MailServerHandler] Invalid mail server settings');
      return;
    }
    if (smtpEnabled) {
      _smtp = SmtpServer(
        smtpPort,
        store: _store,
        account: account,
        password: password,
      );
      await _smtp!.start();
    }
    if (popEnabled && !_disposed) {
      _pop3 = Pop3Server(
        popPort,
        store: _store,
        account: account,
        password: password,
      );
      await _pop3!.start();
    }
    if (_disposed) await _stop();
  }

  Future<void> _stop() async {
    await _smtp?.stop();
    _smtp?.dispose();
    _smtp = null;
    await _pop3?.stop();
    _pop3?.dispose();
    _pop3 = null;
  }

  void dispose() {
    _disposed = true;
    _broker.dispose();
    _pending = _pending.then((_) => _stop());
  }
}
