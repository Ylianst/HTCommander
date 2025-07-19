# Draft APRS Authentication

We describe an additon to APRS messages to perform message authentication using HMAC-SHA256. We wish to authenticate that a message is coming from the correct source and is not a relay of a previous message. We also want to keep the addition simple and comply with HAM radio no-encryption rules. This is intended to be used for messaging and we will assume that both the sending and receiving station have a shared secret password. How this password is exchanged is out of scope of this document.

A typical APRS message will look like this:

```
  :KK7VZT-7 :This is a test{556
```

We add a 6 character Base64 encoded token to the message after a } character, so the new message looks like this:

```
  :KK7VZT-7 :This is a test}YwwuFt{556
```

To compute the base64 token, we must first hash the shared secret with SHA256.

```
  SecretKey = SHA256(SharedSecret)
```

Note that that shared secret is a UTF-8 encoded string. The string much be kepts in UTF-8 format when hashed. We then compute the current number of minutes since January 1sh 1970 UTC. This gives us a long integer with the current approximate time. We then create a message string that contains the minutes counter, source and destination stations in "CallSign-StationID" format and the message and message ID.

```
  HashMessage = MinutesUtc + ":" + SourceStation + ":" + DestinationStation + ":" + aprsMessage + "{" + msgId
```

The SourceStation is the station encoded in the S25 packet header in the second position, and DestinationStation is the station encoded in the APRS message, but without added training spaces. We when HMAC-SHA256 on this string using the SecretKey, convert it to Base64 and keep the first 6 characters.

```
  Token = First 6 characters of Base64(HMAC-SHA256(HashMessage))
```

We take the token and insert it into the APRA message as shown above. When receiving a APRS message with an authentication code, we re-computer the token and check against the token that is included in the message. We perform 4 check trying the current minute, the 2 previor minutes and the next minute to see if any of the 4 auth tokens can be made to match. As a result, a message has a 4 minute window to arrive at it's destivation, however the receiver can also check prior minutes if network contidions would delay a message beyond 4 minutes.

Software that can verify the authentication of a message should send a ACK back that also includes a properly computed authentication token. You can't ACK with the received token, you have to compute a new one with the appropriate sender/receiver and time. Software should indicate to the user if a message is send or received with authentication and is the authentication test was succesful.

# Draft APRS Ring Notification

If a authenticated message started with the string `!RING!`, it should cause the receiving station to ACK the message and ring like a telephone, notifying the user that a station wished to call it. If the message starts with `!RING!Freq=xxx.xx`, this indicates that the caller wants to communicate on this frequency.
