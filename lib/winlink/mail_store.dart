/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import 'i_mail_store.dart';
import 'winlink_mail.dart';

/// Flutter-adapted implementation of [IMailStore].
///
/// The original Windows implementation used SQLite plus a FileSystemWatcher for
/// multi-instance synchronization. SQLite is not available here, so this version
/// keeps an in-memory cache (for synchronous reads, which the Winlink protocol
/// code relies on) and persists the whole list to a single text file using
/// [WinLinkMail.serialize] / [WinLinkMail.deserialize].
///
/// It registers itself as the DataBroker data handler named "MailStore" and
/// subscribes to the same broker events as the original.
class MailStore implements IMailStore {
  // ignore: prefer_initializing_formals
  MailStore({String? storagePath}) : _storagePath = storagePath;

  // Resolved lazily in initialize() when not provided by the caller.
  String? _storagePath;
  String? _mailsFilePath;
  final List<WinLinkMail> _cachedMails = <WinLinkMail>[];
  bool _disposed = false;
  DataBrokerClient? _broker;
  void Function()? _onMailsChanged;
  Future<void> _saveChain = Future<void>.value();

  @override
  set onMailsChanged(void Function()? handler) => _onMailsChanged = handler;

  /// Initializes storage, loads persisted mail, subscribes to broker events and
  /// registers this instance as the "MailStore" data handler.
  Future<void> initialize() async {
    // On the web there is no local filesystem; mail is kept in memory only.
    // Leaving _mailsFilePath null makes _loadMailsFromFile/_saveToFile no-ops.
    if (!kIsWeb) {
      try {
        if (_storagePath == null) {
          final dir = await getApplicationSupportDirectory();
          _storagePath = '${dir.path}${Platform.pathSeparator}HTCommander';
        }

        final storageDir = Directory(_storagePath!);
        if (!storageDir.existsSync()) {
          storageDir.createSync(recursive: true);
        }
        _mailsFilePath = '${_storagePath!}${Platform.pathSeparator}mails.txt';

        // Load initial data
        _loadMailsFromFile();
      } catch (e) {
        // Filesystem unavailable - fall back to an in-memory store.
        _mailsFilePath = null;
      }
    }

    // Register as the global mail store data handler
    DataBroker.addDataHandler('MailStore', this);

    // Initialize the DataBroker client and subscribe to mail events
    _initializeBroker();

    // Notify that MailStore is ready (after broker is initialized)
    _broker?.dispatch(
      deviceId: 0,
      name: 'MailStoreReady',
      data: true,
      store: false,
    );
  }

  void _initializeBroker() {
    _broker = DataBrokerClient();

    // Subscribe to mail operations (device 0 for persistent/global operations)
    _broker!.subscribe(deviceId: 0, name: 'MailAdd', callback: _onMailAdd);
    _broker!.subscribe(
      deviceId: 0,
      name: 'MailUpdate',
      callback: _onMailUpdate,
    );
    _broker!.subscribe(
      deviceId: 0,
      name: 'MailDelete',
      callback: _onMailDelete,
    );
    _broker!.subscribe(deviceId: 0, name: 'MailMove', callback: _onMailMove);
    _broker!.subscribe(
      deviceId: 0,
      name: 'MailGetAll',
      callback: _onMailGetAll,
    );
    _broker!.subscribe(deviceId: 0, name: 'MailGet', callback: _onMailGet);
    _broker!.subscribe(
      deviceId: 0,
      name: 'MailExists',
      callback: _onMailExists,
    );
  }

  void _onMailAdd(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! WinLinkMail) return;
    try {
      if (!mailExists(data.mid ?? '')) {
        addMail(data);
        _notifyMailsChanged();
      }
    } catch (_) {
      // Ignore errors - mail might already exist
    }
  }

  void _onMailUpdate(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! WinLinkMail) return;
    try {
      updateMail(data);
      _notifyMailsChanged();
    } catch (_) {
      // Ignore errors
    }
  }

  void _onMailDelete(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final mid = data is String ? data : null;
    if (mid == null || mid.isEmpty) return;
    try {
      deleteMail(mid);
      _notifyMailsChanged();
    } catch (_) {
      // Ignore errors
    }
  }

  void _onMailMove(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! Map) return;
    try {
      final mid = data['MID'] as String?;
      final mailbox = data['Mailbox'] as String?;
      if (mid == null || mid.isEmpty || mailbox == null || mailbox.isEmpty) {
        return;
      }
      final mail = getMail(mid);
      if (mail != null) {
        mail.mailbox = mailbox;
        updateMail(mail);
        _notifyMailsChanged();
      }
    } catch (_) {
      // Ignore errors
    }
  }

  void _onMailGetAll(int deviceId, String name, Object? data) {
    if (_disposed) return;
    try {
      _broker?.dispatch(
        deviceId: 0,
        name: 'MailList',
        data: getAllMails(),
        store: false,
      );
    } catch (_) {
      _broker?.dispatch(
        deviceId: 0,
        name: 'MailList',
        data: <WinLinkMail>[],
        store: false,
      );
    }
  }

  void _onMailGet(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final mid = data is String ? data : null;
    if (mid == null || mid.isEmpty) {
      _broker?.dispatch(deviceId: 0, name: 'Mail', data: null, store: false);
      return;
    }
    try {
      _broker?.dispatch(
        deviceId: 0,
        name: 'Mail',
        data: getMail(mid),
        store: false,
      );
    } catch (_) {
      _broker?.dispatch(deviceId: 0, name: 'Mail', data: null, store: false);
    }
  }

  void _onMailExists(int deviceId, String name, Object? data) {
    if (_disposed) return;
    final mid = data is String ? data : null;
    bool exists = false;
    if (mid != null && mid.isNotEmpty) {
      try {
        exists = mailExists(mid);
      } catch (_) {
        exists = false;
      }
    }
    _broker?.dispatch(
      deviceId: 0,
      name: 'MailExistsResult',
      data: {'MID': mid, 'Exists': exists},
      store: false,
    );
  }

  void _notifyMailsChanged() {
    if (_disposed) return;
    _broker?.dispatch(
      deviceId: 0,
      name: 'MailsChanged',
      data: null,
      store: false,
    );
    _onMailsChanged?.call();
  }

  @override
  int get count => _cachedMails.length;

  @override
  List<WinLinkMail> getAllMails() => List<WinLinkMail>.from(_cachedMails);

  @override
  WinLinkMail? getMail(String mid) {
    for (final m in _cachedMails) {
      if (m.mid == mid) return m;
    }
    return null;
  }

  @override
  bool mailExists(String mid) => _cachedMails.any((m) => m.mid == mid);

  @override
  void addMail(WinLinkMail mail) {
    if (mail.mid == null || mail.mid!.isEmpty) {
      mail.mid = WinLinkMail.generateMID();
    }
    _cachedMails.add(mail);
    _saveToFile();
  }

  @override
  void updateMail(WinLinkMail mail) {
    if (mail.mid == null || mail.mid!.isEmpty) {
      throw ArgumentError('Mail MID cannot be empty');
    }
    final index = _cachedMails.indexWhere((m) => m.mid == mail.mid);
    if (index >= 0) {
      _cachedMails[index] = mail;
    } else {
      _cachedMails.add(mail);
    }
    _saveToFile();
  }

  @override
  void deleteMail(String mid) {
    if (mid.isEmpty) return;
    _cachedMails.removeWhere((m) => m.mid == mid);
    _saveToFile();
  }

  @override
  void addMails(Iterable<WinLinkMail> mails) {
    for (final mail in mails) {
      if (mail.mid == null || mail.mid!.isEmpty) {
        mail.mid = WinLinkMail.generateMID();
      }
      _cachedMails.add(mail);
    }
    _saveToFile();
  }

  @override
  void refresh() {
    _loadMailsFromFile();
  }

  void _loadMailsFromFile() {
    _cachedMails.clear();
    final path = _mailsFilePath;
    if (path == null) return;
    final file = File(path);
    if (!file.existsSync()) return;
    try {
      final content = file.readAsStringSync();
      _cachedMails.addAll(WinLinkMail.deserialize(content));
    } catch (_) {
      // Ignore load errors - start with an empty store
    }
  }

  /// Persists the current cache to disk. Saves are serialized so that
  /// overlapping mutations cannot corrupt the file.
  void _saveToFile() {
    final path = _mailsFilePath;
    if (path == null) return;
    final snapshot = List<WinLinkMail>.from(_cachedMails);
    _saveChain = _saveChain.then((_) async {
      try {
        await File(
          path,
        ).writeAsString(WinLinkMail.serialize(snapshot), flush: true);
      } catch (_) {
        // Ignore write errors
      }
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    DataBroker.removeDataHandler('MailStore');
    _broker?.dispose();
    _broker = null;
  }
}
