# Signing the Airwaves: Authenticating APRS Messages Without Encryption

*How HTCommander proves an APRS message really came from who it says — and isn't
a replay of an old one — using HMAC-SHA256, a shared password, and six extra
characters, all while staying legal on amateur radio.*

---

## The problem

APRS messaging has a trust gap. The protocol was never designed to prove who
sent a packet: the source callsign lives in plain text in the AX.25 header, and
anyone can put anything there. On the open airwaves that means a message
claiming to be from `KK7VZT-7` might be from `KK7VZT-7`… or from someone with a
radio and a grudge. And because APRS frames fly around unprotected, a packet you
sent an hour ago can be captured and *replayed* to trigger the same action
twice.

For casual position beacons, nobody cares. But the moment you use APRS messages
to *do* something — flip a relay, arm an alert, command a remote station — you
want two guarantees:

1. **Authenticity.** This message really came from the station that shares my
   secret.
2. **Freshness.** This is a new message, not a recording of an old one.

The catch: amateur radio rules **forbid encryption** meant to obscure meaning.
So we can't just wrap the payload in a cipher. What we *can* do is leave the
message in the clear and attach a short *proof* — a value only someone with the
shared secret could have computed. That's a Message Authentication Code, and
it's exactly what HTCommander adds.

## Design goals

The scheme is deliberately small and boring, which is what you want from
security:

- **No encryption.** The message text stays fully readable over the air. We only
  *append* a proof; we never hide anything.
- **Backward compatible.** A radio or app that has never heard of authentication
  still shows the message in a readable form. The proof degrades into harmless
  trailing characters.
- **Cheap on the wire.** APRS message fields are tiny, so the proof is just
  **six characters**.
- **Shared-secret based.** Both stations already know a common password. *How*
  they agreed on that password — in person, over a secure channel, on a slip of
  paper — is out of scope here.
- **Replay-resistant.** The proof is bound to the current time, so an old
  captured packet stops verifying after a few minutes.

## Where the token goes

A plain APRS message with a message ID looks like this:

```
:KK7VZT-7 :This is a test{556
```

The `{556` at the end is the APRS message ID (used for ACK tracking). We insert
a six-character token after a `}` character, *before* the message ID:

```
:KK7VZT-7 :This is a test}YwwuFt{556
```

Two things make this work nicely:

- Keeping `{556` at the very end preserves the standard message-ID position, so
  ordinary APRS software still parses the ID and can ACK the message.
- Software that doesn't understand authentication simply shows
  `This is a test}YwwuFt` — a little noise on the end, but the message still
  reads.

ACKs get the same treatment. A normal ACK:

```
:KK7VZT-6 :ack556
```

becomes an authenticated ACK by appending `}` and a freshly computed token:

```
:KK7VZT-6 :ack556}eL8OYs
```

## Computing the token

The token is an HMAC-SHA256 over a string that ties together *who*, *what*, and
*when*, keyed by the shared secret. Four ingredients go in.

**1. Derive the key from the password.** The shared secret is a UTF-8 string.
Hash it with SHA-256 to get a fixed-size key:

```
SecretKey = SHA256(UTF8(SharedSecret))
```

Keeping the password in UTF-8 before hashing matters — both ends must encode it
identically or the keys won't match.

**2. Grab the current time as a minute counter.** Take the number of whole
minutes since the Unix epoch (1 January 1970, UTC):

```
MinutesUtc = floor(UnixTimeUTC / 60)
```

A one-minute resolution is coarse on purpose: it gives every message a short
lifetime without needing the two radios' clocks to agree to the second.

**3. Build the string to sign.** Concatenate the minute counter, the source and
destination stations (in `CALLSIGN-SSID` form), and the message. When the
message carries an ID, the ID is included so the proof is bound to that specific
message:

```
HashMessage = MinutesUtc ":" SourceStation ":" DestinationStation ":" Message "{" MsgId
```

For a message with no ID, the same string is built without the trailing
`{MsgId`. The **SourceStation** is the callsign in the second position of the
AX.25 header; the **DestinationStation** is the addressee from the APRS message
body, with its padding spaces trimmed off.

**4. Sign and truncate.** Run HMAC-SHA256 over that string with `SecretKey`,
Base64-encode the result, and keep the first six characters:

```
Token = Base64(HMAC-SHA256(SecretKey, HashMessage))[0:6]
```

Six Base64 characters is 36 bits of proof. That's not a bank vault, but it's far
more than enough to stop casual spoofing on a radio channel — an attacker who
can't compute the HMAC has to *guess*, and one in tens of billions per try, with
a fresh target every minute, is a losing game.

## A worked example

Say `KK7VZT-7` sends *"This is a test"* to `KK7VZT-6` at minute `28901234`, and
both share a password. The station builds:

```
28901234:KK7VZT-7:KK7VZT-6:This is a test{556
```

signs it with `SHA256(password)`, Base64-encodes the HMAC, takes the first six
characters — `YwwuFt` — and transmits:

```
:KK7VZT-6 :This is a test}YwwuFt{556
```

`KK7VZT-6` receives it, recomputes the same string from what it sees on the air
plus its own copy of the password, and compares tokens. Match ⇒ authentic and
fresh.

## Freshness without synchronized clocks

Because the token is bound to `MinutesUtc`, a captured packet replayed later
produces a *different* expected token and fails. But real radios have drifting
clocks and real networks add delay, so demanding an exact-minute match would
reject good messages.

The fix is a small tolerance window. On receipt, the verifier doesn't just try
the current minute — it recomputes the token for a handful of adjacent minutes
and accepts the message if **any** of them match. HTCommander checks five
one-minute windows: the current minute, the two before it, and the two after.
That gives a message roughly a few-minute window to arrive, absorbing clock skew
and propagation delay, while still slamming the door on a replay that shows up an
hour later. If conditions routinely delay traffic further, a receiver is free to
widen how far back it looks.

## ACKs have to be re-signed

Here's the subtle part that trips people up: **you cannot ACK a message by
echoing back the token you received.** The token is bound to a specific
sender→receiver direction and a specific minute. When `KK7VZT-6` acknowledges
`KK7VZT-7`, the source and destination are now *swapped* and the clock has
likely ticked, so the ACK needs a brand-new token computed for
`KK7VZT-6 → KK7VZT-7` at the ACK's own timestamp. Only a station that actually
holds the shared secret can produce that — which means a valid authenticated ACK
proves the *other* end is genuine too, closing the loop in both directions.

## What the operator sees

Security nobody can see is security nobody trusts. Software implementing this
scheme should surface the result plainly: mark each message as **sent or
received with authentication**, and show whether the check **passed**. A green
check next to a received command, a broken-lock icon on a message whose token
didn't verify — the point is that the human can tell, at a glance, whether the
message on screen actually came from the station it claims.

## What's in scope, and what isn't

This is intentionally a *messaging* authentication layer, not a full security
system. A few honest boundaries:

- **Key exchange is out of scope.** The whole thing rests on both stations
  already sharing a password. Distributing and rotating that secret safely is a
  separate problem this spec doesn't try to solve.
- **It authenticates, it doesn't hide.** The message text is in the clear by
  design — that's what keeps it legal on the amateur bands. Anyone can read your
  message; they just can't *forge* it or *replay* it.
- **Six characters is a deliberate trade.** More proof bits would be stronger but
  eat scarce APRS payload. Thirty-six bits was chosen as the sweet spot between
  wire cost and forgery resistance for a radio channel.

For the amateur operator who wants to send a command over APRS and *know* it
will only be honored if it truly came from them, that's a solid deal: a readable
message, a six-character signature, and a few minutes of freshness — no
encryption required.

---

**Related:** [APRS Authentication specification](../Aprs-Auth-Specification.md) ·
[APRS Auth overview](../APRS-Auth.md) ·
[Planning APRS-IS for HTCommander](aprs-is-integration.md)
