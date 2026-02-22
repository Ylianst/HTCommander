# The BSS Protocol

Handi-Talky Commander supports both APRS and BSS protcols. APRS is well documented, but BSS seems to be a propriatary protocol from Baofeng / BTech that is not documented. In this doocument, I made a early attempt at documenting this protocol and how it works.

BSS is a simple length encoded binary protocol send in AFSK frame. It always starts with 0x01 which makes it easy to seperate from AX.25 frames. Next you have a series of length/types/data elements.

A typical packet will look like this:

```
0107204B4B37565A540121062468656C6C6F072514C72DC7CDF1
```

However you can manually decode the packet easily. The first byte is 0x01, so it's a BSS packet. Next is the length of 0x07, so the next 7 bytes are going to be a type followed by data. The full decoding looks like this:

```
01                     // BSS protocol indicator
0720 4B4B37565A54      // Len = 0x07, Type = 0x20 (From), Data = "KK7VZT"
0121                   // Len = 0x01, Type = 0x21 (To), Data = ""
0624 68656C6C6F        // Len = 0x06, Type = 0x24 (Message), Data = "Message Text"
0725 xxxxxxxxxxxx      // Len = 0x07, Type = 0x25 (Location), Data = Latitude + Longitude
```

This is a text message with location and the "To" field is blank, which sometimes happens but generally is not present at all. There is an exception to this encoding, if the length field is 0x85 then the next 2 bytes are a message counter, like this:

```
01                     // BSS protocol indicator
0720 4B4B37565A54      // Len = 0x07, Type = 0x20 (From), Data = "KK7VZT"
850007                 // Len = 0x85, Message Counter = 0x0007
0728 xxxxxxxxxxxx      // Len = 0x07, Type = 0x25 (Location), Data = Latitude + Longitude
```

The message counter is useful so if you get the same message twice, you can ignore the second one. The Message counter is generaly used for request like requesting a location or a ring.

Here is an example for a location request:

```
01                     // BSS protocol indicator
0720 4B4B37565A54      // From "KK7VZT"
85 0005                // Message count = 0x0005
0927 4B4B37565A542D37  // Location Request "KK7VZT-7"
```

Here is an example of a ring request, this will make the radio beep a bit like getting a phone call.

```
01                     // BSS protocol indicator
0720 4B4B37565A54      // From "KK7VZT"
850002                 // Message count
0928 4B4B37565A542D37  // Ring Request "KK7VZT-7"
```

The location command is 0x25 and follows with Latitude and Longitude and optionally altitude, speed and heading like this example:

```
01                     // BSS protocol indicator
0720 4B4B37565A54      // From "KK7VZT"
0D25 14C72DC7CDF1002A00000151  // Latitude, Longitude, Altitude, Speed, Heading
```

Here is the list of data type I know of:

- *Callsign = 0x20*: Source of the message, this is a callsign like "N0CALL" or "NOCALL-0"
- *Destination = 0x21*: Message distination, this is a callsign like "N0CALL" or "NOCALL-0"
- *Message = 0x24*: This is a UTF-8 encoded message
- *Location = 0x25*: This is the location of the sender (Lat, Lng, Alt, Spd, Hd)
- *LocationRequest = 0x27*: This requests the location of give station, contains a string like "N0CALL" or "NOCALL-0"
- *CallRequest = 0x28*: This will ring the requested station, contains a string like "N0CALL" or "NOCALL-0"

In addition to these, the message counter last a length of 0x85 followed by 2 bytes.

