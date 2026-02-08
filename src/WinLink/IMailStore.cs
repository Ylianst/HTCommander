/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Collections.Generic;

namespace HTCommander
{
    /// <summary>
    /// Interface for mail storage. This abstraction allows for different implementations
    /// on different platforms (Windows, Linux, etc.) while keeping the same API.
    /// </summary>
    public interface IMailStore : IDisposable
    {
        /// <summary>
        /// Event fired when mails are changed by an external source (another application instance).
        /// </summary>
        event EventHandler MailsChanged;

        /// <summary>
        /// Gets all mails from the store.
        /// </summary>
        /// <returns>List of all mails.</returns>
        List<WinLinkMail> GetAllMails();

        /// <summary>
        /// Gets a specific mail by its Message ID.
        /// </summary>
        /// <param name="mid">The Message ID.</param>
        /// <returns>The mail if found, null otherwise.</returns>
        WinLinkMail GetMail(string mid);

        /// <summary>
        /// Adds a new mail to the store. Attachments are saved to separate files.
        /// </summary>
        /// <param name="mail">The mail to add.</param>
        void AddMail(WinLinkMail mail);

        /// <summary>
        /// Updates an existing mail in the store.
        /// </summary>
        /// <param name="mail">The mail to update.</param>
        void UpdateMail(WinLinkMail mail);

        /// <summary>
        /// Deletes a mail from the store by its Message ID.
        /// Also deletes associated attachments.
        /// </summary>
        /// <param name="mid">The Message ID of the mail to delete.</param>
        void DeleteMail(string mid);

        /// <summary>
        /// Checks if a mail with the given Message ID exists.
        /// </summary>
        /// <param name="mid">The Message ID to check.</param>
        /// <returns>True if the mail exists, false otherwise.</returns>
        bool MailExists(string mid);

        /// <summary>
        /// Adds multiple mails to the store in a batch operation.
        /// </summary>
        /// <param name="mails">The mails to add.</param>
        void AddMails(IEnumerable<WinLinkMail> mails);

        /// <summary>
        /// Gets the count of mails in the store.
        /// </summary>
        int Count { get; }

        /// <summary>
        /// Forces a refresh of the mail list from the underlying storage.
        /// Used after external changes are detected.
        /// </summary>
        void Refresh();
    }
}
