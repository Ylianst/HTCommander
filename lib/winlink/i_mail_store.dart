/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'winlink_mail.dart';

/// Interface for mail storage. This abstraction allows for different
/// implementations on different platforms while keeping the same API.
abstract class IMailStore {
  /// Called when mails are changed by an external source.
  set onMailsChanged(void Function()? handler);

  /// Gets all mails from the store.
  List<WinLinkMail> getAllMails();

  /// Gets a specific mail by its Message ID, or null if not found.
  WinLinkMail? getMail(String mid);

  /// Adds a new mail to the store.
  void addMail(WinLinkMail mail);

  /// Updates an existing mail in the store.
  void updateMail(WinLinkMail mail);

  /// Deletes a mail from the store by its Message ID.
  void deleteMail(String mid);

  /// Checks if a mail with the given Message ID exists.
  bool mailExists(String mid);

  /// Adds multiple mails to the store in a batch operation.
  void addMails(Iterable<WinLinkMail> mails);

  /// Gets the count of mails in the store.
  int get count;

  /// Forces a refresh of the mail list from the underlying storage.
  void refresh();

  /// Releases resources held by the store.
  void dispose();
}
