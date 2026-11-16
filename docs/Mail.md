# Mail

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/ht-mail.png?raw=true)

Handi-Talky Commander has built-in support for WinLink. You can send and receive emails when contacting any packet radio email gateways. Then checking or sending emails, the radio with switch to the frequency of the Winlink gateway, sync-up and return back when it's done. You can compose and read emails within the application and add, save or drag & drop attachements making authoring easy.

To use this feature, you will need to setup your Winlink account on [Winlink.org](https://winlink.org) and find your nearest gateway. You will also need to enter your Winlink password in the Handi-Talky Commander settings panel to correctly authenticate.

You can also sync mail directly from the Map tab: turn on **Show Winlink Gateways**, select a gateway and press **Sync mail**. The sync runs on the gateway's frequency without adding it to your contacts. See [Offline Winlink Gateway Directory](Winlink-Gateways.md) for details.

## Local Storage

Native builds store mail incrementally in the application's SQLite database.
Metadata and binary attachments are separate: changing read flags or moving a
message no longer base64-encodes and rewrites every attachment in the mailbox.
Unchanged attachment rows are not rewritten. Bursts of edits share a 150 ms
save window; backgrounding and clean shutdown explicitly drain pending saves.

Existing `HTCommander/mails.txt` mail is imported once. The legacy file remains
as a backup and is not re-imported after messages have been deleted. JSON mail
backup/restore remains compatible. If the application database is unavailable,
the legacy file path uses coalesced worker-side serialization and a temporary
file rename instead. Persistence failures are reported in diagnostics and
failed writes remain pending for an explicit retry.
