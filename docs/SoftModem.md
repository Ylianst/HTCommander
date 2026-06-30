# Software Modem

![image](https://github.com/Ylianst/HTCommander/blob/main/docs/images/ht-softmodem.png?raw=true)

Handi-Talky Commander includes it's own AFSK 1200 baud software modem that you can use in addition to the radio's build in hardware modem. The software modem will transmit error correcting codes (ECC) when sending a packet and will attempt ECC decoding and many more error correction strategies when receiving the packet.

The software modem is enabled in the `Audio -> Software modem" menu and only works when the audio channel is enabled. The softmodem will listen to incoming Bluetooth audio to decode packets. Even if the channel is set to "mute" the softmodem will still work, but you will not hear anything.

On the trasnmit path, the software modem only transmits on VFO A. So, if you use the APRS panel to send data while VFO A is listening to a non-APRS channel, the hardware modem will be used on transmit. ECC codes are always sent when the software modem is used.

On the receive path, both software and hardware modems will work to decode packets at the same time and which ever can decode it first wins. You will not see any duplicate packets. Generally, the hardware modem does it first but if there are errors, the software modem may get a chance to decode it.

In the packet capture panel, you can see what modem was used to send/receive the data and, if the software modem decoded the data, you can see if ECC codes where included in the packet and how many error bits where present.

I don't think there is any drawback to enabling the soft-modem except extra processing being done on the comptuer.
