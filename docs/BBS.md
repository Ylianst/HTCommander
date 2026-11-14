# Bulletin Board System (BBS)

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/ht-bbs.png?raw=true)

Handi-Talky Commander has a built-in BBS, a bit like the old modem days. This option is only available if you have a HAM radio license and you enabled the application to transmit. It's super easy to activate, just select a channel on the main or top channel and hit "Activate" on the top right of the BBS tab.

The BBS supports AX.25 sessions along with RAW AX.25, APRS and compressed packet formats right now. These are the same protocols the [terminal](https://github.com/Ylianst/HTCommander/blob/main/docs/Terminal.md) supports. An incoming packet needs to be directed at the station and the BBS will reply in the same packet format as it was received. The AX.25 session and APRS format has relay/ack support, RAW AX.25 does not.

Right now, the BBS acts as a private Winlink email gateway and has as support for a text adventure game called [The Adventurer](https://github.com/TheTextAdventurer/Adventurer). Any unconnected packets sent to the BBS will initiate the adventure and the adventure game is saved at each turn using the sender's callsign, so, many stations can play at the same time and each will see their own game. You can transmit "quit" at anytime to restart the game.

The BBS tab will show statistics in real-time on what stations are using the BBS and how many bytes and packets have been sent and received.

While a radio is locked to BBS, the VFO B area of its virtual display shows
that radio's latest session status, prefixed with the station's callsign.
Sessions on other radios, the local terminal, or the HTTP BBS do not affect it.
The area starts blank when locked and returns to normal VFO B when unlocked.

The **Traffic** panel at the bottom of the BBS tab shows the BBS conversations live. Next to "Traffic", a drop-down lists every active session, whatever the way the station is connected: AX.25 or XARA over a radio, the local terminal ("Local"), or the HTTP BBS ("Web"), with the time each session started. Pick "All Sessions" to see everything, or a session to follow only that station; a green dot marks sessions with new lines you have not seen yet. A session that just ended stays on screen, marked "ended", until you pick another one. You can also right-click a station in the list and choose "Show Session Traffic". The panel includes what was said before it was opened (the last 2,000 lines), including in a detached BBS window.

## Menu commands

Stations connected to the BBS (over AX.25, XARA or the HTTP BBS) can type the following commands. Commands are not case sensitive, and `[n]` is an optional number of entries to list (10 by default, at most 50).

| Command | Description |
|---|---|
| `M` | Show the main menu (`H` and `?` also work). |
| `B [n]` | List the last messages on the message board, with their number, poster and time. |
| `R <#>` | Read a single board message. |
| `P <text>` | Post a short message (up to 200 characters) on the board. |
| `K <#>` | Delete a board message. Only the poster (with any SSID) or the station running the BBS can delete a message. |
| `A [n]` | List the last APRS messages this station received, over the air or from APRS-IS. |
| `AM [n]` | List the last APRS messages received for the connected station (any SSID). |
| `AP <call>` | Show the last position, comment and weather heard from an APRS station (off by default). |
| `AH [n]` | List the APRS stations heard most recently (off by default). |
| `N` | Read the sysop's announcement, when one is enabled. |
| `L [n]` | List the last stations that connected to the BBS, with when they were last seen, how they connected and how many times. |
| `F [n]` | List the files in the BBS file area, with their number, size, date and uploader. |
| `DL <#>` | Download a file, by number or name (`GET` also works). See [File area](#file-area). |
| `UL` | Upload a file (`PUT` also works). See [File area](#file-area). |
| `FK <#>` | Delete a file. Only the uploader (with any SSID) or the station running the BBS can delete a file. |
| `C [call]` | Look up a callsign (the connected station's own callsign by default). Only offered when an offline callsign database is downloaded ("Help" -> "Callsign Lookup..."). |
| `S` | Software information. |
| `D` | Disconnect (`BYE` and `QUIT` also work). |

When a station connects it is greeted by callsign. Returning stations are told when they were last connected and how many new board messages and APRS messages for them have arrived since. APRS lists skip acknowledgements, bulletins and repeats of the same message, and show times in the BBS station's local time. The message board and the list of stations are shared by every radio BBS and the HTTP BBS, and are kept across restarts (the 500 most recent messages and stations).

Note that callsigns are not authenticated, over the radio or the web, so the board and deletions rely on stations using their own callsign.

## Customizing the BBS

Select **Customize...** in the BBS tab menu to choose what the BBS offers:

- **General**: the welcome message shown at the top of the main menu, an optional announcement (`N`, which stations are told about when they connect), and callsign lookup (`C`).
- **Files**: whether stations may upload files, the largest upload allowed (25 KB by default, up to 1024 KB), and **Manage Files...** to choose the files offered for download.
- **Games**: turn games off entirely or one by one.
- **APRS**: the APRS message lists (`A`, `AM`), the APRS station lookup (`AP`) and the list of heard stations (`AH`).

The settings apply to every radio BBS and the HTTP BBS. Commands that are turned off are removed from the menu.

## File area

The BBS offers a small file area that stations can list (`F`), download from (`DL`) and upload to (`UL`). Click **Files** in the BBS tab header (or "BBS Files..." in the tab menu) to see the files, add or delete files, open the folder, and choose whether stations may upload. Files can also be copied straight into the folder; they are picked up and numbered on the next listing. File numbers are never reused. The file area is shared by every radio BBS and the HTTP BBS.

- **Over the radio**, files are transferred with the YAPP protocol over an AX.25 connected session. In the Handy-Talky Commander terminal, `DL <#>` makes the BBS send the file and the terminal offers to save it when it arrives. To upload, type `UL` (optional) and use **Send File...**. Other YAPP-capable packet terminals work the same way. A station that does not answer the YAPP offer can just keep typing: the download is cancelled and its commands run. XARA connections can list files but not transfer them.
- **On the HTTP BBS**, `DL <#>` downloads the file in the browser, and the **Upload** button at the top of the page sends a file. Each web session has its own secret link, so files can only be transferred by connected visitors.

Uploads are limited to 25 KB per file by default (several minutes at 1200 baud, adjustable in "Customize...") and 20 MB in total, and can be turned off with "Allow stations to upload files to the BBS" in the Files window or in "File" -> "Settings", "Servers" tab. Uploaded file names are reduced to letters, digits, `.`, `_` and `-`, and a number is added if the name is taken. Large files added by the sysop can be downloaded, but they take a long time over the radio.

Disabling the BBS immediately drops its AX.25/XARA sessions and Winlink gateway connections, clears queued transmissions for that radio, and cancels active audio transmission. No disconnect handshake or final BBS message is sent. Incoming packets cannot restart the disabled BBS; enabling it again starts fresh sessions. Data already handed to the radio or transmitted over the air cannot be recalled.

## XARA (VARA FM compatible) sessions

When **XARA** is selected as the software modem (and the radio audio is enabled), the BBS also answers incoming XARA connections, so stations running VARA FM can use the menu and exchange Winlink mail just like over an AX.25 session (including relay to the Winlink CMS gateway). XARA stations can connect to your callsign with or without your station ID as the SSID (e.g. `N0CALL` or `N0CALL-1`). AX.25 packets carried by XARA are delivered to the BBS as usual. The BBS serves one connected station at a time; a second station connecting over AX.25 or XARA while another session is active is told the BBS is busy and disconnected. XARA connections show as "XARA" in the statistics.

Each incoming AX.25 connection keeps the modem encoding used by the connecting station for all replies, including the connection handshake and disconnect. For example, a 1200-baud packet connection received by the radio's hardware TNC is answered using hardware AFSK 1200 even when XARA is selected globally. The global modem setting is not changed, and incoming XARA connections still use XARA.

XARA session traffic (connect requests, control codes such as ACKs and connect replies, and data frames, including ones that failed their CRC) is shown in the packet capture tab so you can follow a connection attempt. Like DART, the modem column describes how each frame was sent, e.g. "Software XARA FM Narrow Level 5 (8PSK, 58 carriers, LDPC 2/3, 4252 bps), Session, SNR 18.4 dB, 3 LDPC iterations". The decode panel adds the frame's position in its burst, lead-in and burst airtime for sent frames, SNR, Es/N0, LDPC iterations, coherence and airtime for received frames, the session state, and the decoded frame header (payload, compression, last frame, level offer, lead report).

## HTTP BBS (web terminal)

On desktop, the BBS menu can also be offered over the Internet. In "File" -> "Settings", "Servers" tab, check "Enable HTTP BBS Server" and pick a port (default 8023). Browsers that open `http://<your-ip>:<port>/` get a fixed-width terminal with small / medium / large font sizes and a Disconnect button. **Clear** asks for OK/Cancel confirmation and clears only the displayed terminal text, without disconnecting or deleting command history. The visitor enters a callsign (checked for a valid amateur callsign format, with optional SSID -0 to -15, by both the page and the server) and is connected to the BBS menu over a WebSocket. No password is required, so anyone who can reach the port can connect.

Web sessions do not use a radio and work whether or not the radio BBS is active; several visitors can be connected at once. Only the text menu and the [file area](#file-area) are offered over the web: Winlink mail exchange and the Winlink CMS relay remain radio-only. Web visitors appear in the BBS tab traffic and statistics with the "Web" protocol. Connections are limited in number (32 total, 4 per IP address), message size and rate, and are dropped after 30 minutes without input. The server speaks plain HTTP; put it behind a TLS reverse proxy if you need HTTPS.
