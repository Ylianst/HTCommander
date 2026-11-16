# APRS

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/ht-aprs.png?raw=true)

The main tab in Handi-Talky Commander is the APRS tab. You can use this tab to see messages from others, send you own message and see a lot of telemetry messages. In general, if you set your radio right, the radio will always monitor the APRS channel even if you doing normal voice monitoring on a different non-APRS channel. So, don't be surprised if you set the radio to your favorite repeater and still see APRS messages coming in. When you send a APRS message out, we tell the radio this is a APRS packet and so, it should be transmitted on the correct frequency. To make this feature work, a channel called "APRS" will need to be setup. If you don't have such a channel, you will get a notice with a dialog box to help you create one.

On the upper right, you can click on the 3 bars to opt to not see telemetry messages. You can also send SMS message to normal phones which is great if you need to send a text message and don't have cell phone access.

In the "File" -> "Settings" -> "APRS" dialog box, you can add more APRS routes. Once you have more than one route configured, a drop-down box will show up on the upper right of the APRS tab and you can select what route you want to use when sending messages. This allows you messages to hit the digipeaters you want to get your message to the right destination.

APRS telemetry messages will show up on the [map tab](https://github.com/Ylianst/HTCommander/blob/main/docs/Map.md), and you can right click on any APRS message to get extra details or to show a mini-map of the location of the station.

## Live Window and Stored History

The live tab keeps up to 1,000 RF entries and 1,000 APRS-IS entries independently.
Evicting old entries removes only their bubbles; surviving messages keep stable
IDs and cached content instead of being rebuilt on every new internet packet.
This does not delete the persisted history.

Use the **Stored History** clock button inside a conversation or the combined
feed to browse the retained RF/APRS-IS archives. Choose the source in the dialog,
then use the left arrow for older 200-entry pages or the first-page button for
the newest stored page. The archive is separate from the selected conversation
and shows retained traffic, including individual stored retransmissions.
Cleared RF messages remain hidden in this browser.

The archive also works in detached windows and hosted web clients through the
host. Without a database (including stand-alone web), only the bounded live
window is available. Existing retention settings still govern on-disk history.

## Saving Messages

While a conversation or the "All Messages" view is open, use **Save as CSV...** or **Save as TXT...** from the APRS tab menu to save the messages currently shown (respecting the telemetry and internet-traffic filters). The options are grayed out on the conversation list. The file format is the same as the [Comms tab export](https://github.com/Ylianst/HTCommander/blob/main/docs/Voice.md#exporting-comms-conversations); the type column is `APRS`, `APRS-IS` or `MeshCore`.

Extra APRS Features:
- [APRS SMS](https://github.com/Ylianst/HTCommander/blob/main/docs/APRS-SMS.md)
- [APRS Weather](https://github.com/Ylianst/HTCommander/blob/main/docs/APRS-Weather.md)