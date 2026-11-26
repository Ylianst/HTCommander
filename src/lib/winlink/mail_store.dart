/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show compute, debugPrint, kIsWeb;
import 'package:path_provider/path_provider.dart';

import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/db/app_database.dart';
import 'i_mail_store.dart';
import 'winlink_mail.dart';

/// Flutter-adapted implementation of [IMailStore].
///
/// Keeps synchronous protocol reads in memory and batches dirty-message writes
/// to SQLite. Legacy JSON is imported once, or used as an asynchronous fallback
/// when the application database is unavailable.
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
  Timer? _saveTimer;
  Future<void>? _saving;
  bool _dirty = false;
  bool _replaceAll = false;
  final Set<String> _dirtyMids = {};
  final Set<String> _deletedMids = {};

  @override
  set onMailsChanged(void Function()? handler) => _onMailsChanged = handler;

  /// Initializes storage, loads persisted mail, subscribes to broker events and
  /// registers this instance as the "MailStore" data handler.
  Future<void> initialize() async {
    Object? initializationError;
    // On the web there is no local filesystem; mail is kept in memory only.
    if (!kIsWeb) {
      try {
        final dao = AppDatabase.instance?.mails;
        if (dao != null && await dao.initialized) {
          _cachedMails.addAll(await dao.all());
        } else {
          if (_storagePath == null) {
            final dir = await getApplicationSupportDirectory();
            _storagePath = '${dir.path}${Platform.pathSeparator}HTCommander';
          }
          await Directory(_storagePath!).create(recursive: true);
          _mailsFilePath = '${_storagePath!}${Platform.pathSeparator}mails.txt';
          await _loadMailsFromFile();
          if (dao != null) {
            await dao.save(_cachedMails, <String>{}, replaceAll: true);
          }
        }
      } catch (e) {
        initializationError = e;
        _mailsFilePath = null;
      }
    }

    // Register as the global mail store data handler
    DataBroker.addDataHandler('MailStore', this);

    // Initialize the DataBroker client and subscribe to mail events
    _initializeBroker();
    if (initializationError != null) _reportError(initializationError);

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
    // Replaces the whole cache with a snapshot. Used by the hosted web build to
    // apply the desktop host's authoritative mail list received over the bridge.
    _broker!.subscribe(
      deviceId: 0,
      name: 'MailReplaceAll',
      callback: _onMailReplaceAll,
    );
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

  void _onMailReplaceAll(int deviceId, String name, Object? data) {
    if (_disposed) return;
    if (data is! List) return;
    _cachedMails.clear();
    addMails(data.whereType<WinLinkMail>());
    _queueSave(replaceAll: true);
    _notifyMailsChanged();
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
    _queueSave(changed: [mail.mid!]);
  }

  /// Publishes submitted mail only after it is safely stored, so a failed SMTP
  /// submission cannot become visible to a concurrent Winlink sync.
  Future<void> addMailDurably(WinLinkMail mail) async {
    await flush();
    if (_disposed) throw StateError('Mail store is closed');
    if (mail.mid == null || mail.mid!.isEmpty) {
      mail.mid = WinLinkMail.generateMID();
    }
    if (mailExists(mail.mid!)) throw StateError('Duplicate mail MID');
    final dao = AppDatabase.instance?.mails;
    final path = _mailsFilePath;
    if (dao == null && path == null) {
      throw StateError('Persistent mail storage is unavailable');
    }
    // Serialize this commit with timer-driven saves and other submissions.
    while (_saving != null) {
      await _saving;
    }
    _saving =
        (() async {
          if (dao != null) {
            await dao.save([mail], <String>{});
          } else {
            await compute(_writeMailSnapshot, (path!, [..._cachedMails, mail]));
          }
          _cachedMails.add(mail);
          _notifyMailsChanged();
        })().whenComplete(() {
          _saving = null;
          if (_dirty) unawaited(flush().catchError(_reportError));
        });
    await _saving;
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
    _queueSave(changed: [mail.mid!]);
  }

  @override
  void deleteMail(String mid) {
    if (mid.isEmpty) return;
    _cachedMails.removeWhere((m) => m.mid == mid);
    _queueSave(deleted: [mid]);
  }

  @override
  void addMails(Iterable<WinLinkMail> mails) {
    final added = <String>[];
    for (final mail in mails) {
      if (mail.mid == null || mail.mid!.isEmpty) {
        mail.mid = WinLinkMail.generateMID();
      }
      _cachedMails.add(mail);
      added.add(mail.mid!);
    }
    _queueSave(changed: added);
  }

  @override
  void refresh() {
    unawaited(_refresh().catchError(_reportError));
  }

  Future<void> _refresh() async {
    await flush();
    final dao = AppDatabase.instance?.mails;
    if (dao == null) {
      await _loadMailsFromFile();
    } else {
      final List<WinLinkMail> loaded = await dao.all();
      _cachedMails
        ..clear()
        ..addAll(loaded);
    }
    _notifyMailsChanged();
  }

  Future<void> _loadMailsFromFile() async {
    _cachedMails.clear();
    final path = _mailsFilePath;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) return;
    final content = await file.readAsString();
    _cachedMails.addAll(WinLinkMail.deserialize(content));
    for (final mail in _cachedMails) {
      if (mail.mid == null || mail.mid!.isEmpty) {
        mail.mid = WinLinkMail.generateMID();
      }
    }
  }

  void _queueSave({
    Iterable<String> changed = const [],
    Iterable<String> deleted = const [],
    bool replaceAll = false,
  }) {
    if (_mailsFilePath == null && AppDatabase.instance?.mails == null) return;
    _dirty = true;
    _replaceAll |= replaceAll;
    _dirtyMids.addAll(changed);
    _dirtyMids.removeAll(deleted);
    _deletedMids.addAll(deleted);
    _deletedMids.removeAll(changed);
    _saveTimer ??= Timer(const Duration(milliseconds: 150), () {
      _saveTimer = null;
      unawaited(flush().catchError(_reportError));
    });
  }

  /// Drains pending mutations on backgrounding and clean shutdown.
  Future<void> flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    return _saving ??= _flushPending().whenComplete(() => _saving = null);
  }

  Future<void> _flushPending() async {
    while (_dirty) {
      _dirty = false;
      final replaceAll = _replaceAll;
      _replaceAll = false;
      final changed = Set<String>.of(_dirtyMids);
      final deleted = Set<String>.of(_deletedMids);
      _dirtyMids.clear();
      _deletedMids.clear();
      try {
        final dao = AppDatabase.instance?.mails;
        if (dao != null) {
          await dao.save(
            _cachedMails
                .where((m) => replaceAll || changed.contains(m.mid))
                .toList(),
            deleted,
            replaceAll: replaceAll,
          );
        } else {
          await compute(_writeMailSnapshot, (
            _mailsFilePath!,
            List<WinLinkMail>.of(_cachedMails),
          ));
        }
      } catch (_) {
        _dirty = true;
        _replaceAll |= replaceAll;
        _dirtyMids.addAll(changed);
        _deletedMids.addAll(deleted);
        rethrow;
      }
    }
  }

  void _reportError(Object error) {
    debugPrint('MailStore: persistence failed: $error');
    _broker?.logError('MailStore: persistence failed: $error');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(flush().catchError(_reportError));
    DataBroker.removeDataHandler('MailStore');
    _broker?.dispose();
    _broker = null;
  }
}

Future<void> _writeMailSnapshot((String, List<WinLinkMail>) input) async {
  final (path, mails) = input;
  final temporary = File('$path.tmp');
  await temporary.writeAsString(WinLinkMail.serialize(mails), flush: true);
  await temporary.rename(path);
}
