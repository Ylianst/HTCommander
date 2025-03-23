# Torrent

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/ht-torrent.png?raw=true)

Handi-Talky Commander has it's own mini BitTorrent like many-to-many file sharing system. This protocol is only available in HT Commander right now so to try this, you will need two or more radios that support HT Commander. All farmes are sent as one-to-many multicast and so, many stations can run this at the same time.

To Use this, just select a clear frequency and hit "Activate" to lock the radio and activate torrent mode. Add or drag & drop files you want to share, you can also add a 200 character description to each file. The torrent protocol will discover other nodes on the frequency and trade file listings. If you want to download a file, right click on it and select "Request". If others are requesting files, your node will automatically store all received blocks and will participate in re-transmitting blocks. Once a file is fully downloaded, you can right click on it and hit "Save As..." to save a copy."

Right now, this is super experimental, I have more timing improvements to make. 1200 Baud is not fast, but this is intended to run the radio for a long time.