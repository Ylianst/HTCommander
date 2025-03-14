# Bulletin Board System (BBS)

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/ht-bbs.png?raw=true)

Handi-Talky Commander has a built-in BBS, a bit like the old modem days. This option is only available if you have a HAM radio license and you enabled the application to transmit. It's super easy to activate, just select a channel on the main or top channel and hit "Activate" on the top right of the BBS tab.

The BBS supports AX.25 sessions along with RAW AX.25, APRS and compressed packet formats right now. These are the same protocols the [terminal](https://github.com/Ylianst/HTCommander/blob/main/docs/Terminal.md) supports. An incoming packet needs to be directed at the station and the BBS will reply in the same packet format as it was received. The AX.25 session and APRS format has relay/ack support, RAW AX.25 does not.

Right now, the BBS acts as a private Winlink email gateway and has as support for a text adventure game called [The Adventurer](https://github.com/TheTextAdventurer/Adventurer). Any unconnected packets sent to the BBS will initiate the adventure and the adventure game is saved at each turn using the sender's callsign, so, many stations can play at the same time and each will see their own game. You can transmit "quit" at anytime to restart the game.

The BBS tab will show statistics in real-time on what stations are using the BBS and how many bytes and packets have been sent and received.
