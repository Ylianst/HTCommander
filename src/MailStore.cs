/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

using System;
using System.IO;
using System.Threading;
using System.Data.SQLite;
using System.Collections.Generic;

namespace HTCommander
{
    /// <summary>
    /// SQLite-based implementation of IMailStore for Windows.
    /// Stores mail metadata in a SQLite database and attachments as separate files.
    /// Supports multi-instance synchronization via FileSystemWatcher.
    /// </summary>
    public class MailStore : IMailStore
    {
        private readonly string _dbPath;
        private readonly string _attachmentsPath;
        private readonly string _signalFilePath;
        private readonly SQLiteConnection _connection;
        private readonly FileSystemWatcher _watcher;
        private readonly object _lock = new object();
        private List<WinLinkMail> _cachedMails;
        private DateTime _lastSignalTime = DateTime.MinValue;
        private bool _disposed = false;
        private readonly SynchronizationContext _syncContext;

        public event EventHandler MailsChanged;

        /// <summary>
        /// Creates a new MailStore instance with the default storage location in AppData.
        /// </summary>
        public MailStore() : this(GetDefaultStoragePath())
        {
        }

        /// <summary>
        /// Creates a new MailStore instance with a custom storage path.
        /// </summary>
        /// <param name="storagePath">The directory path for storing the database and attachments.</param>
        public MailStore(string storagePath)
        {
            _syncContext = SynchronizationContext.Current;
            
            // Ensure storage directory exists
            if (!Directory.Exists(storagePath))
            {
                Directory.CreateDirectory(storagePath);
            }

            _dbPath = Path.Combine(storagePath, "mails.db");
            _attachmentsPath = Path.Combine(storagePath, "attachments");
            _signalFilePath = Path.Combine(storagePath, "mails.signal");

            // Ensure attachments directory exists
            if (!Directory.Exists(_attachmentsPath))
            {
                Directory.CreateDirectory(_attachmentsPath);
            }

            // Initialize database connection with WAL mode for better concurrency
            string connectionString = $"Data Source={_dbPath};Version=3;Journal Mode=WAL;";
            _connection = new SQLiteConnection(connectionString);
            _connection.Open();

            // Initialize database schema
            InitializeDatabase();

            // Load initial data
            _cachedMails = LoadMailsFromDatabase();

            // Set up file watcher for multi-instance synchronization
            _watcher = new FileSystemWatcher(storagePath)
            {
                Filter = "mails.signal",
                NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.CreationTime
            };
            _watcher.Changed += OnSignalFileChanged;
            _watcher.Created += OnSignalFileChanged;
            _watcher.EnableRaisingEvents = true;
        }

        private static string GetDefaultStoragePath()
        {
            string appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            return Path.Combine(appDataPath, "HTCommander");
        }

        private void InitializeDatabase()
        {
            // Check if this is a new database or needs migration
            bool needsMigration = false;
            bool tableExists = false;
            
            using (var cmd = new SQLiteCommand("SELECT name FROM sqlite_master WHERE type='table' AND name='mails'", _connection))
            {
                using (var reader = cmd.ExecuteReader())
                {
                    tableExists = reader.HasRows;
                }
            }

            if (tableExists)
            {
                // Check if mailbox column is INTEGER (old schema) or TEXT (new schema)
                using (var cmd = new SQLiteCommand("PRAGMA table_info(mails)", _connection))
                {
                    using (var reader = cmd.ExecuteReader())
                    {
                        while (reader.Read())
                        {
                            string colName = reader.GetString(1);
                            string colType = reader.GetString(2);
                            if (colName == "mailbox" && colType.ToUpper() == "INTEGER")
                            {
                                needsMigration = true;
                                break;
                            }
                        }
                    }
                }
            }

            if (needsMigration)
            {
                MigrateMailboxToString();
            }
            else if (!tableExists)
            {
                // Create new tables with TEXT mailbox column
                string createMailsTable = @"
                    CREATE TABLE IF NOT EXISTS mails (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        mid TEXT UNIQUE NOT NULL,
                        datetime TEXT NOT NULL,
                        from_addr TEXT,
                        to_addr TEXT,
                        cc TEXT,
                        subject TEXT,
                        mbo TEXT,
                        body TEXT,
                        tag TEXT,
                        location TEXT,
                        flags INTEGER DEFAULT 0,
                        mailbox TEXT DEFAULT 'Inbox',
                        created_at TEXT DEFAULT CURRENT_TIMESTAMP
                    );
                    CREATE INDEX IF NOT EXISTS idx_mails_mid ON mails(mid);
                    CREATE INDEX IF NOT EXISTS idx_mails_mailbox ON mails(mailbox);
                ";

                using (var cmd = new SQLiteCommand(createMailsTable, _connection))
                {
                    cmd.ExecuteNonQuery();
                }
            }

            string createAttachmentsTable = @"
                CREATE TABLE IF NOT EXISTS attachments (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    mail_mid TEXT NOT NULL,
                    filename TEXT NOT NULL,
                    filepath TEXT NOT NULL,
                    FOREIGN KEY (mail_mid) REFERENCES mails(mid) ON DELETE CASCADE
                );
                CREATE INDEX IF NOT EXISTS idx_attachments_mail ON attachments(mail_mid);
            ";

            using (var cmd = new SQLiteCommand(createAttachmentsTable, _connection))
            {
                cmd.ExecuteNonQuery();
            }

            // Enable foreign keys
            using (var cmd = new SQLiteCommand("PRAGMA foreign_keys = ON;", _connection))
            {
                cmd.ExecuteNonQuery();
            }
        }

        private void MigrateMailboxToString()
        {
            // Migrate from INTEGER mailbox to TEXT mailbox with string names
            string[] defaultMailboxes = { "Inbox", "Outbox", "Draft", "Sent", "Archive", "Trash" };

            using (var transaction = _connection.BeginTransaction())
            {
                try
                {
                    // Create new table with TEXT mailbox column
                    string createNewTable = @"
                        CREATE TABLE mails_new (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            mid TEXT UNIQUE NOT NULL,
                            datetime TEXT NOT NULL,
                            from_addr TEXT,
                            to_addr TEXT,
                            cc TEXT,
                            subject TEXT,
                            mbo TEXT,
                            body TEXT,
                            tag TEXT,
                            location TEXT,
                            flags INTEGER DEFAULT 0,
                            mailbox TEXT DEFAULT 'Inbox',
                            created_at TEXT DEFAULT CURRENT_TIMESTAMP
                        )";
                    
                    using (var cmd = new SQLiteCommand(createNewTable, _connection))
                    {
                        cmd.ExecuteNonQuery();
                    }

                    // Copy data with mailbox conversion
                    string copyData = @"
                        INSERT INTO mails_new (id, mid, datetime, from_addr, to_addr, cc, subject, mbo, body, tag, location, flags, mailbox, created_at)
                        SELECT id, mid, datetime, from_addr, to_addr, cc, subject, mbo, body, tag, location, flags,
                            CASE mailbox
                                WHEN 0 THEN 'Inbox'
                                WHEN 1 THEN 'Outbox'
                                WHEN 2 THEN 'Draft'
                                WHEN 3 THEN 'Sent'
                                WHEN 4 THEN 'Archive'
                                WHEN 5 THEN 'Trash'
                                ELSE 'Inbox'
                            END,
                            created_at
                        FROM mails";
                    
                    using (var cmd = new SQLiteCommand(copyData, _connection))
                    {
                        cmd.ExecuteNonQuery();
                    }

                    // Drop old table and rename new one
                    using (var cmd = new SQLiteCommand("DROP TABLE mails", _connection))
                    {
                        cmd.ExecuteNonQuery();
                    }

                    using (var cmd = new SQLiteCommand("ALTER TABLE mails_new RENAME TO mails", _connection))
                    {
                        cmd.ExecuteNonQuery();
                    }

                    // Recreate indexes
                    using (var cmd = new SQLiteCommand("CREATE INDEX IF NOT EXISTS idx_mails_mid ON mails(mid)", _connection))
                    {
                        cmd.ExecuteNonQuery();
                    }

                    using (var cmd = new SQLiteCommand("CREATE INDEX IF NOT EXISTS idx_mails_mailbox ON mails(mailbox)", _connection))
                    {
                        cmd.ExecuteNonQuery();
                    }

                    transaction.Commit();
                }
                catch
                {
                    transaction.Rollback();
                    throw;
                }
            }
        }

        private void OnSignalFileChanged(object sender, FileSystemEventArgs e)
        {
            try
            {
                // Debounce: ignore changes within 500ms
                DateTime signalTime = File.GetLastWriteTime(_signalFilePath);
                if ((signalTime - _lastSignalTime).TotalMilliseconds < 500)
                {
                    return;
                }
                _lastSignalTime = signalTime;

                // Refresh data from database
                Refresh();

                // Fire event on the UI thread if possible
                if (_syncContext != null)
                {
                    _syncContext.Post(_ => MailsChanged?.Invoke(this, EventArgs.Empty), null);
                }
                else
                {
                    MailsChanged?.Invoke(this, EventArgs.Empty);
                }
            }
            catch
            {
                // Ignore errors during signal file processing
            }
        }

        private void NotifyChange()
        {
            try
            {
                // Update the signal file to notify other instances
                File.WriteAllText(_signalFilePath, DateTime.UtcNow.Ticks.ToString());
                _lastSignalTime = DateTime.Now;
            }
            catch
            {
                // Ignore errors when updating signal file
            }
        }

        public int Count
        {
            get
            {
                lock (_lock)
                {
                    return _cachedMails.Count;
                }
            }
        }

        public List<WinLinkMail> GetAllMails()
        {
            lock (_lock)
            {
                // Return a copy to prevent external modification
                return new List<WinLinkMail>(_cachedMails);
            }
        }

        public WinLinkMail GetMail(string mid)
        {
            lock (_lock)
            {
                return _cachedMails.Find(m => m.MID == mid);
            }
        }

        public bool MailExists(string mid)
        {
            lock (_lock)
            {
                return _cachedMails.Exists(m => m.MID == mid);
            }
        }

        public void AddMail(WinLinkMail mail)
        {
            if (mail == null) throw new ArgumentNullException(nameof(mail));
            if (string.IsNullOrEmpty(mail.MID)) mail.MID = WinLinkMail.GenerateMID();

            lock (_lock)
            {
                // Save attachments to files first
                SaveAttachments(mail);

                // Insert into database
                InsertMailToDatabase(mail);

                // Update cache
                _cachedMails.Add(mail);

                // Notify other instances
                NotifyChange();
            }
        }

        public void UpdateMail(WinLinkMail mail)
        {
            if (mail == null) throw new ArgumentNullException(nameof(mail));
            if (string.IsNullOrEmpty(mail.MID)) throw new ArgumentException("Mail MID cannot be empty", nameof(mail));

            lock (_lock)
            {
                // Update attachments
                DeleteAttachmentFiles(mail.MID);
                SaveAttachments(mail);

                // Update database
                UpdateMailInDatabase(mail);

                // Update cache
                int index = _cachedMails.FindIndex(m => m.MID == mail.MID);
                if (index >= 0)
                {
                    _cachedMails[index] = mail;
                }
                else
                {
                    _cachedMails.Add(mail);
                }

                // Notify other instances
                NotifyChange();
            }
        }

        public void DeleteMail(string mid)
        {
            if (string.IsNullOrEmpty(mid)) return;

            lock (_lock)
            {
                // Delete attachment files
                DeleteAttachmentFiles(mid);

                // Delete from database (cascades to attachments table)
                using (var cmd = new SQLiteCommand("DELETE FROM mails WHERE mid = @mid", _connection))
                {
                    cmd.Parameters.AddWithValue("@mid", mid);
                    cmd.ExecuteNonQuery();
                }

                // Update cache
                _cachedMails.RemoveAll(m => m.MID == mid);

                // Notify other instances
                NotifyChange();
            }
        }

        public void AddMails(IEnumerable<WinLinkMail> mails)
        {
            if (mails == null) return;

            lock (_lock)
            {
                using (var transaction = _connection.BeginTransaction())
                {
                    try
                    {
                        foreach (var mail in mails)
                        {
                            if (string.IsNullOrEmpty(mail.MID)) mail.MID = WinLinkMail.GenerateMID();
                            SaveAttachments(mail);
                            InsertMailToDatabase(mail);
                            _cachedMails.Add(mail);
                        }
                        transaction.Commit();
                        NotifyChange();
                    }
                    catch
                    {
                        transaction.Rollback();
                        throw;
                    }
                }
            }
        }

        public void Refresh()
        {
            lock (_lock)
            {
                _cachedMails = LoadMailsFromDatabase();
            }
        }

        private List<WinLinkMail> LoadMailsFromDatabase()
        {
            var mails = new List<WinLinkMail>();

            string query = "SELECT mid, datetime, from_addr, to_addr, cc, subject, mbo, body, tag, location, flags, mailbox FROM mails";
            using (var cmd = new SQLiteCommand(query, _connection))
            using (var reader = cmd.ExecuteReader())
            {
                while (reader.Read())
                {
                    var mail = new WinLinkMail
                    {
                        MID = reader.GetString(0),
                        DateTime = DateTime.Parse(reader.GetString(1)),
                        From = reader.IsDBNull(2) ? null : reader.GetString(2),
                        To = reader.IsDBNull(3) ? null : reader.GetString(3),
                        Cc = reader.IsDBNull(4) ? null : reader.GetString(4),
                        Subject = reader.IsDBNull(5) ? null : reader.GetString(5),
                        Mbo = reader.IsDBNull(6) ? null : reader.GetString(6),
                        Body = reader.IsDBNull(7) ? null : reader.GetString(7),
                        Tag = reader.IsDBNull(8) ? null : reader.GetString(8),
                        Location = reader.IsDBNull(9) ? null : reader.GetString(9),
                        Flags = reader.GetInt32(10),
                        Mailbox = reader.IsDBNull(11) ? "Inbox" : reader.GetString(11)
                    };

                    // Load attachments
                    mail.Attachments = LoadAttachments(mail.MID);

                    mails.Add(mail);
                }
            }

            return mails;
        }

        private void InsertMailToDatabase(WinLinkMail mail)
        {
            string insertQuery = @"
                INSERT INTO mails (mid, datetime, from_addr, to_addr, cc, subject, mbo, body, tag, location, flags, mailbox)
                VALUES (@mid, @datetime, @from_addr, @to_addr, @cc, @subject, @mbo, @body, @tag, @location, @flags, @mailbox)";

            using (var cmd = new SQLiteCommand(insertQuery, _connection))
            {
                cmd.Parameters.AddWithValue("@mid", mail.MID);
                cmd.Parameters.AddWithValue("@datetime", mail.DateTime.ToString("o"));
                cmd.Parameters.AddWithValue("@from_addr", (object)mail.From ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@to_addr", (object)mail.To ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@cc", (object)mail.Cc ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@subject", (object)mail.Subject ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@mbo", (object)mail.Mbo ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@body", (object)mail.Body ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@tag", (object)mail.Tag ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@location", (object)mail.Location ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@flags", mail.Flags);
                cmd.Parameters.AddWithValue("@mailbox", mail.Mailbox);
                cmd.ExecuteNonQuery();
            }

            // Insert attachment references
            if (mail.Attachments != null)
            {
                foreach (var attachment in mail.Attachments)
                {
                    string filePath = GetAttachmentFilePath(mail.MID, attachment.Name);
                    string relativePath = Path.GetFileName(filePath);

                    using (var cmd = new SQLiteCommand("INSERT INTO attachments (mail_mid, filename, filepath) VALUES (@mid, @filename, @filepath)", _connection))
                    {
                        cmd.Parameters.AddWithValue("@mid", mail.MID);
                        cmd.Parameters.AddWithValue("@filename", attachment.Name);
                        cmd.Parameters.AddWithValue("@filepath", relativePath);
                        cmd.ExecuteNonQuery();
                    }
                }
            }
        }

        private void UpdateMailInDatabase(WinLinkMail mail)
        {
            string updateQuery = @"
                UPDATE mails SET 
                    datetime = @datetime, 
                    from_addr = @from_addr, 
                    to_addr = @to_addr, 
                    cc = @cc, 
                    subject = @subject, 
                    mbo = @mbo, 
                    body = @body, 
                    tag = @tag, 
                    location = @location, 
                    flags = @flags, 
                    mailbox = @mailbox
                WHERE mid = @mid";

            using (var cmd = new SQLiteCommand(updateQuery, _connection))
            {
                cmd.Parameters.AddWithValue("@mid", mail.MID);
                cmd.Parameters.AddWithValue("@datetime", mail.DateTime.ToString("o"));
                cmd.Parameters.AddWithValue("@from_addr", (object)mail.From ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@to_addr", (object)mail.To ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@cc", (object)mail.Cc ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@subject", (object)mail.Subject ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@mbo", (object)mail.Mbo ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@body", (object)mail.Body ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@tag", (object)mail.Tag ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@location", (object)mail.Location ?? DBNull.Value);
                cmd.Parameters.AddWithValue("@flags", mail.Flags);
                cmd.Parameters.AddWithValue("@mailbox", mail.Mailbox);
                cmd.ExecuteNonQuery();
            }

            // Delete old attachment references and re-insert
            using (var cmd = new SQLiteCommand("DELETE FROM attachments WHERE mail_mid = @mid", _connection))
            {
                cmd.Parameters.AddWithValue("@mid", mail.MID);
                cmd.ExecuteNonQuery();
            }

            if (mail.Attachments != null)
            {
                foreach (var attachment in mail.Attachments)
                {
                    string filePath = GetAttachmentFilePath(mail.MID, attachment.Name);
                    string relativePath = Path.GetFileName(filePath);

                    using (var cmd = new SQLiteCommand("INSERT INTO attachments (mail_mid, filename, filepath) VALUES (@mid, @filename, @filepath)", _connection))
                    {
                        cmd.Parameters.AddWithValue("@mid", mail.MID);
                        cmd.Parameters.AddWithValue("@filename", attachment.Name);
                        cmd.Parameters.AddWithValue("@filepath", relativePath);
                        cmd.ExecuteNonQuery();
                    }
                }
            }
        }

        private void SaveAttachments(WinLinkMail mail)
        {
            if (mail.Attachments == null) return;

            foreach (var attachment in mail.Attachments)
            {
                if (attachment.Data == null) continue;
                string filePath = GetAttachmentFilePath(mail.MID, attachment.Name);
                File.WriteAllBytes(filePath, attachment.Data);
            }
        }

        private List<WinLinkMailAttachement> LoadAttachments(string mid)
        {
            var attachments = new List<WinLinkMailAttachement>();

            string query = "SELECT filename, filepath FROM attachments WHERE mail_mid = @mid";
            using (var cmd = new SQLiteCommand(query, _connection))
            {
                cmd.Parameters.AddWithValue("@mid", mid);
                using (var reader = cmd.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        string filename = reader.GetString(0);
                        string relativePath = reader.GetString(1);
                        string fullPath = Path.Combine(_attachmentsPath, relativePath);

                        var attachment = new WinLinkMailAttachement { Name = filename };

                        if (File.Exists(fullPath))
                        {
                            attachment.Data = File.ReadAllBytes(fullPath);
                        }

                        attachments.Add(attachment);
                    }
                }
            }

            return attachments.Count > 0 ? attachments : null;
        }

        private void DeleteAttachmentFiles(string mid)
        {
            string query = "SELECT filepath FROM attachments WHERE mail_mid = @mid";
            using (var cmd = new SQLiteCommand(query, _connection))
            {
                cmd.Parameters.AddWithValue("@mid", mid);
                using (var reader = cmd.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        string relativePath = reader.GetString(0);
                        string fullPath = Path.Combine(_attachmentsPath, relativePath);
                        if (File.Exists(fullPath))
                        {
                            try { File.Delete(fullPath); } catch { }
                        }
                    }
                }
            }
        }

        private string GetAttachmentFilePath(string mid, string filename)
        {
            // Sanitize filename to remove invalid characters
            string safeName = string.Join("_", filename.Split(Path.GetInvalidFileNameChars()));
            return Path.Combine(_attachmentsPath, $"{mid}_{safeName}");
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                _disposed = true;
                _watcher?.Dispose();
                _connection?.Close();
                _connection?.Dispose();
            }
        }
    }
}
