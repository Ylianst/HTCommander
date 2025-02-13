# Bulletin Board System (BBS)

Handi-Talky Commander has a built-in BBS, a bit like the old modem days. This option is only available if you have a HAM radio license and you enabled the application to transmit. It's super easy to activate, just select a channel on the main or top chaanel and hit "Activate" on the top right of the BBS tab.

The BBS only supports RAW AX.25 and APRS packet format right now. An incoming packet needs to be directed at the station and the BBS will relay in the same packet format as it was received.

Right now, the BBS only supports a text adventure game called [The Adventurer](https://github.com/TheTextAdventurer/Adventurer). Any text send to the BBS will initiate the adventure and the adventure game is saved at each turn using the sender's callsign, so, many stations can play at the same time and each will see their own game. You can transmit "quit" at anytime to restart the game.

THe BBS tab will show statistics on what stations are using the BBS and how many bytes and packets have been sent and received.