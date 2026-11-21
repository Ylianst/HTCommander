// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../winlink/winlink_mail.dart';

/// Mail metadata and binary attachments are persisted independently.
class MailDao {
  MailDao(this._db);
  final Database _db;

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS mail_messages (mid TEXT PRIMARY KEY, metadata TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS mail_attachments (mid TEXT NOT NULL, ordinal INTEGER NOT NULL, name TEXT NOT NULL, data BLOB NOT NULL, PRIMARY KEY (mid, ordinal))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS mail_state (initialized INTEGER NOT NULL)',
    );
  }

  Future<bool> get initialized async =>
      (await _db.query('mail_state', limit: 1)).isNotEmpty;

  Future<List<WinLinkMail>> all() async {
    return _db.transaction((txn) async {
      final rows = await txn.query('mail_messages', orderBy: 'rowid');
      final mails = <String, WinLinkMail>{};
      for (final row in rows) {
        final json =
            jsonDecode(row['metadata'] as String) as Map<String, dynamic>;
        final mail = WinLinkMail.fromJson(json);
        mails[row['mid'] as String] = mail;
      }
      for (final row in await txn.query(
        'mail_attachments',
        orderBy: 'mid, ordinal',
      )) {
        final mail = mails[row['mid']];
        if (mail == null) continue;
        (mail.attachments ??= []).add(
          WinLinkMailAttachement(
            name: row['name'] as String,
            data: row['data'] as Uint8List,
          ),
        );
      }
      return mails.values.toList(growable: false);
    });
  }

  Future<void> save(
    List<WinLinkMail> changed,
    Set<String> deleted, {
    bool replaceAll = false,
  }) {
    // Freeze only dirty messages before the first await. Callers may mutate
    // those same mail objects while the database transaction is in flight.
    final snapshots = [
      for (final mail in changed)
        (
          mail.mid!,
          jsonEncode(mail.toJson(includeAttachments: false)),
          [
            for (final attachment
                in mail.attachments ?? <WinLinkMailAttachement>[])
              (attachment.name, Uint8List.fromList(attachment.data)),
          ],
        ),
    ];
    return _db.transaction((txn) async {
      if (replaceAll) {
        await txn.delete('mail_attachments');
        await txn.delete('mail_messages');
      }
      for (final mid in deleted) {
        await txn.delete(
          'mail_attachments',
          where: 'mid = ?',
          whereArgs: [mid],
        );
        await txn.delete('mail_messages', where: 'mid = ?', whereArgs: [mid]);
      }
      for (final (mid, metadata, attachments) in snapshots) {
        await txn.rawInsert(
          'INSERT INTO mail_messages(mid, metadata) VALUES (?, ?) '
          'ON CONFLICT(mid) DO UPDATE SET metadata = excluded.metadata '
          'WHERE metadata != excluded.metadata',
          [mid, metadata],
        );
        await txn.delete(
          'mail_attachments',
          where: 'mid = ? AND ordinal >= ?',
          whereArgs: [mid, attachments.length],
        );
        for (var i = 0; i < attachments.length; i++) {
          final (name, bytes) = attachments[i];
          await txn.rawInsert(
            'INSERT INTO mail_attachments(mid, ordinal, name, data) VALUES (?, ?, ?, ?) '
            'ON CONFLICT(mid, ordinal) DO UPDATE SET name = excluded.name, data = excluded.data '
            'WHERE name != excluded.name OR data != excluded.data',
            [mid, i, name, bytes],
          );
        }
      }
      await txn.rawInsert(
        'INSERT INTO mail_state(initialized) SELECT 1 WHERE NOT EXISTS (SELECT 1 FROM mail_state)',
      );
    });
  }
}
