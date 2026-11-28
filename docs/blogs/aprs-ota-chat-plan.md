# APRS OTA: Turning a Bot Conversation Into a Little On-Air Adventure

*Originally a research and design proposal, November 28, 2026, based on the
live [APRS OTA website](https://aprsota.org/) and its handbook. The design
below remains a roadmap; the implementation update distinguishes what is
available from what is proposed.*

## Implementation update

HTCommander now has an OTA-only conversation panel: an automatic radio avatar,
editable command preparation, machine-readable discovery/details, reported
activity and host QSL controls, raw-chat fallback, single-message validation,
local cooldowns, and explicit RF-only HOST/QSL requests through the existing
outbox. Other conversations and All APRS Messages have no OTA controls.

There is no automatic beaconing, polling, chasing, QSL transmission, score
calculation, or downloaded card/achievement enrichment. Beacon settings and
the independent beacon path must still be checked by the operator.
Confirmations are displayed without replay-triggered animation. See
[the operating instructions](../APRS.md#aprs-ota-conversation).

APRS already lets us send short messages through a radio. [APRS
OTA](https://aprsota.org/) gives those messages a purpose: go on the air,
find another operator, exchange a contact, and collect a logbook of places
and people you have worked.

The interesting integration is not a new modem or a replacement website.
It is making the existing APRS conversation addressed to **`OTA`** feel like
a small activity console: a recognizable avatar, a list of stations to
chase, a clear reminder to beacon, and a satisfying indication when the
contact is confirmed.

The actual destination is `OTA`. All commands and replies stay in that
APRS chat thread, including messages the bot relays from other operators.
The proposed enhancements belong there, not in a new network or a separate
Comms protocol.

## What APRS OTA actually does

There are three participants:

| Participant | Job |
|-------------|-----|
| Host | Runs an operation, or **op**, and answers chasers using RF. |
| Chaser | Finds a host and calls them through the bot; RF or APRS-IS is allowed. |
| `OTA` | Receives commands, relays the exchange, logs contacts, and maintains the website. |

No account or additional application is required to start. Sending a
message to `OTA` gets you into the activity. The website provides operator
pages, live operation maps, timelines, logbooks, digital QSL cards,
leaderboards, stamps, and achievements.

The radio path still depends on internet infrastructure:

```text
HTCommander + radio -> RF -> iGate -> APRS-IS -> OTA bot
HTCommander + radio <- RF <- suitable transmit iGate <- APRS-IS <- OTA bot
```

You can participate without internet access on your own phone or computer,
but an iGate path and a return path are still needed. Hearing APRS packets
does not, by itself, prove that bidirectional bot messaging will work.
An internet-only chaser can instead connect through APRS-IS.

OTA borrows the activation feel of POTA and SOTA, but it is an independent
activity. A host can operate from anywhere. Park and summit references in
an op description can link to those sites; this does **not** make an OTA
contact a qualifying POTA or SOTA contact.

## First, check the messaging path

Send `PING` to `OTA`. A reply beginning `PONG heard on RF` means the bot saw
the outgoing message arrive through RF. `PONG heard on APRS-IS` means it
arrived directly through the internet instead.

Both are successful messaging tests. Only the first is suitable evidence
for a host's outgoing message path. Neither proves the beacon path:
messages and position reports may use different settings.

That distinction deserves a small status card, rather than making the user
interpret a line of text. Label it **"OTA reports your message arrived via
RF"**, not "RF verified" or "secure bot": it is a report about that test,
not authentication or a permanent guarantee.

## Chasing: a contact in four steps

The [contact workflow](https://aprsota.org/handbook/make-a-contact) is simple,
but there is an important intermediate step that an ordinary chat view hides.

1. Send `CQ` to discover hosts currently on the air.
2. Send `CHASE <host> [greeting]` to `OTA`.
3. Send a **native APRS position report within five minutes**, using the
   same local callsign **and SSID** that sent CHASE.
4. Wait for the host's QSL, relayed by OTA.

For illustration, a chaser might send `CHASE K7ABC-6 Hello from the trail`.
OTA first asks for a position report. After receiving it, the bot confirms
the chase and gives the operation's web address. It then relays the
chaser's callsign, grid, and greeting to the host.

The host answers `QSL <chaser> [reply]`, again addressed to `OTA`, and the
chaser receives a relay beginning `DE <host> QSL`. That completes the QSO.

**"Now chasing" is not "contact complete."** It means the chaser has done
their half and the host still needs to confirm. An APRS ACK is different
again: it acknowledges receipt of the command, not acceptance of the
chase or completion of the QSO.

Typing a grid square into the chat does not replace the position report.
The bot needs a real APRS position packet containing usable coordinates.
The target host's SSID is optional in CHASE and QSL, but the sender's
message/beacon identity must match exactly.

## Hosting: work the pileup, not the keyboard

Send `HOST [description]` and then beacon a valid position within five
minutes. Both the HOST message and the confirming beacon must reach OTA
over RF. The host's QSL messages must also use RF, from the station running
the op. The [hosting handbook](https://aprsota.org/handbook/host-an-op)
recommends beaconing at least every 15 minutes to keep local iGates aware
of the station; that is guidance, not a guarantee of return delivery.

Once on the air, the useful commands are:

| Command | Purpose |
|---------|---------|
| `INFO` | Your chasing count, QSOs, points, and time remaining. |
| `TIME` | Time until the op ends, and time until the hard cap. |
| `CHASERS` | Stations still waiting for your QSL, longest waiting first. |
| `QSL <chaser> [reply]` | Confirm a relayed chase. |
| `STAY` | Add up to 30 minutes, without exceeding the hard cap. |
| `BLAST [text]` | Send an announcement to the op's other participants. |
| `DONE [signoff]` | End your op; save the sign-off to its log. |

An op begins with 60 minutes. Completed contacts keep it alive until at
least 15 minutes after the latest QSO, and STAY can extend it further.
Nothing extends an op past 120 minutes from its start. A contact therefore
does not necessarily add 15 minutes to the current countdown.

A chaser can send `BLAST <host> <text>` after their beacon has been accepted,
even before receiving a QSL. This is a fan-out announcement, not an
unrestricted group chat. Each blast may create many RF messages.

There is also a subtle DONE trap: a non-host can send `DONE <host>` to stop
receiving that op's blasts. But **while hosting, every DONE ends your own
op**, regardless of the following text. A "Mute blasts" button must not
offer that command while the local operator is hosting.

## Points, cards, and the fun part

[Points](https://aprsota.org/handbook/score-points) come from stamps on
confirmed contacts, not from time spent hosting. Both operators receive
the contact's full score.

Only the first confirmed contact between the same operators during an op
earns stamps and points. Repeats still count as QSOs and get QSL cards.
Changing SSIDs does not create a new scoring operator.

For example, the handbook describes one point for the host's RF stamp,
two points when both parties use RF, and three when those two RF operators
are also in different countries. The website owns the scoring rules.
HTCommander should display reported scores, not infer stamps or award
points from a PONG, a grid square, or a locally observed packet.

A lightweight "QSO confirmed" celebration would be appropriate. A
fabricated score or guessed QSL-card URL would not. Open the operation or
operator page unless an actual contact-specific URL is available.

## The key discovery: a machine-readable API over APRS

We do not have to parse every English sentence to build useful cards.
OTA documents an [API over RF](https://aprsota.org/handbook/api-radio).
Four read-only commands have machine forms:

| Request | Reply fields, in order |
|---------|------------------------|
| `CQ!` | Page/total-pages, total op count, then repeating station/grid/minutes-left triples. |
| `INFO! [host]` | Station, grid, minutes left, confirmed QSOs, incomplete contacts, points, latitude, longitude. |
| `TIME!` | Minutes left, then minutes to the two-hour cap. |
| `CHASERS!` | Page/total-pages, total waiting count, then station callsigns. |

Replies start with the same command token, including `!`. A space before
the bang is not equivalent: use `CQ!`, not `CQ !`. The bang applies to
these command names, not their Q-code aliases.

Illustrative records:

```text
CQ! 1/1 1 K7ABC-6 DN40fb 22
INFO! K7ABC-6 DN40fb 22 5 3 5 40.0542 -111.5250
TIME! 22 82
CHASERS! 1/1 2 W1XYZ-5 N0CALL-7
```

There are several details a decoder must preserve:

- `_` means null, not zero. Unknown coordinates occupy two fields: `_ _`.
- `INFO! <call> NIL` means no active op was found.
- `INFO! <station> DESC <text>` is a separate description message.
  Its text extends to the end; it may arrive before or after the record.
- Time fields are **whole minutes remaining**, not Unix timestamps,
  despite the handbook naming the op field `expires_at`.
- INFO's coordinates describe the position that established the op,
  not necessarily the moving host's latest location.
- CQ! and CHASERS! can span up to three messages. A record never crosses
  a page boundary. The reported total can exceed the records returned.
- Fields added to the end of a response must be tolerated. CQ's current
  repeated record width is three fields; do not guess a future per-record
  width or reinterpret unknown trailing data as valid additional ops.

Changing commands such as HOST, CHASE, and QSL have **no machine form**.
Their confirmations, relays, and errors still need conservative text
recognition, always with the original message available.

## Proposed OTA conversation panel

### 1. A distinctive default avatar

Use an automatic **radio-beacon/activity** avatar for OTA instead of the
generic callsign initials. Start with a built-in radio or location icon;
an original composite beacon/map-pin badge could be a later visual polish.
Do not copy the service's artwork without permission.

The avatar should appear consistently in the conversation list, the
conversation's corner overlay, and Contacts. Existing precedence remains:
**user image > user-selected icon > automatic service icon > initials**.
Tapping the corner avatar should still edit the contact, not silently
change into a website button.

Identify the special panel using the canonical APRS peer `OTA`, including
the existing `OTA-0` normalization. Do not select it from a display name,
a substring, or an arbitrary nonzero SSID. The existing automatic-avatar
helper strips SSIDs for known services; special command behavior needs
the narrower check even if avatar matching follows that shared convention.

### 2. A small action strip, with ordinary chat underneath

At the top of the OTA thread, offer:

- **Check setup**: PING.
- **Find ops**: CQ!, then selectable host cards.
- **Host an op**: an optional description and RF/beacon preflight.
- **My activity** and **Handbook**: browser links, opened only on request.

Each discovered host card can show its callsign, grid, estimated minutes
left, **Details** using INFO!, and **Chase** with an editable greeting.
Keep the bot's soonest-to-expire ordering rather than sorting alphabetically.
Show "received 2 of 3 pages" and "showing 6 of 10 ops" when appropriate.
Do not call a partial list complete or show an empty-success result when
the query has not received an answer.

The composer remains available for raw commands. Actions prepare a visible
command and let the user send it; they do not automatically chase every
station, beacon, QSL a pileup, or repeatedly poll OTA.

### 3. A beacon checklist instead of a mysterious timeout

After a recognized HOST or CHASE position prompt, show:

```text
Waiting for your position
Station: your exact callsign-SSID
Deadline: approximately five minutes from the request
[Review beacon settings] [Send position...]
```

The countdown is approximate: the bot started its window before the prompt
arrived. Never reset it merely because a duplicate prompt was received.
Show elapsed/uncertain state if delivery was delayed.

The position action must check a usable, sufficiently fresh fix, the exact
station identity, transmit permission, the selected radio/channel, and the
beacon path independently of the message path. It should explain that the
position becomes public on APRS and OTA before the user sends it.

Only OTA's receipt advances the activity to "Chasing" or "Hosting".
"Position submitted locally" does not mean "Position accepted by OTA".
Show wrong-path, unusable-position, and expired-window replies explicitly,
with a retry action that the user controls.

### 4. Relay cards and a host work queue

Recognize `DE <chaser> <grid> <greeting>` as a pending chase for the host.
Give it an editable **QSL** action that sends to OTA, not directly to the
displayed chaser. Recognize `DE <host> QSL <reply>` as a confirmation for
the appropriate chase, not as another pending chaser.

Keep the packet sender labeled **OTA**, with "relayed from <station>"
inside the card. A relayed callsign must not replace the actual sender
or gain an authentication badge.

CHASERS! provides a recovery queue when individual DE relays were missed.
Refresh it on request, retaining longest-waiting-first order. Sending a QSL
changes a row to "QSL submitted"; an ACK alone does not prove the service
logged it. Reconcile with a later queue or op summary.

A hosting summary can show reported QSOs, points, incomplete contacts, and
an approximate countdown, with TIME!, INFO!, STAY, BLAST, and a confirmed
**End op** action. BLAST needs an audience/airtime warning. Do not present
it as an ordinary reply button.

### 5. Make progress enjoyable without inventing results

Use a compact progress trail: **Requested -> Beacon accepted -> Waiting
for QSL -> Confirmed**. Hosting has its own trail and pending-chaser queue.
Allow hosting and chasing to coexist; a single global "OTA mode" would
lose track of simultaneous activity.

Celebrate each genuinely new confirmation once, with accessible text and
optional reduced-motion-friendly animation. Replayed history, duplicate
packets, and reopening a window must not trigger celebrations again.
Offer the received op link and the operator's website page for maps,
cards, stamps, and achievements. Opening the web page requires internet
access; working the bot over RF does not require internet on this device.

## Decoding and state: deliberately conservative

The future parser should be a small, testable APRS-specific component,
separate from widget rendering. Preserve every raw message and derive
typed events such as op-list page, op info, description, beacon prompt,
chase receipt, pending chaser, QSL relay, blast, and error.

Only incoming messages from the actual OTA peer to the local station
should drive activity state. Traffic in the all-messages view addressed
to another operator is not our receipt. Outgoing commands establish
intent, not successful service state. Unknown or malformed replies remain
ordinary visible chat and must not overwrite valid state.

Validate page bounds, record completeness, callsign syntax, Maidenhead
grids, nonnegative counts/minutes, and latitude/longitude ranges. Handle
documented nullable fields before numeric conversion. Preserve description,
greeting, and blast text without treating embedded command words as events.
Keep raw message details, copying, route coloring, and authentication UX.

The API identifies a response family, **not a request ID**. CQ! and
CHASERS! pages do not identify a snapshot, and INFO! does not provide an
operation ID. Avoid overlapping same-family queries, use bounded assembly
windows, and never merge uncertain late pages into a newer snapshot.
Reordered pages may be assembled; duplicates must not add records twice.
When provenance is ambiguous, show uncertainty and let the user refresh.

Track hosting by the exact local station and chasing by host/op link where
available. Without an op ID, a later op by the same host cannot safely be
assumed to be the old one. Missing context should result in a readable
standalone card, not a guessed QSO association.

Use existing persisted APRS history and the outbox as the source of truth.
Reconstruct display summaries where possible; add only minimal persisted
metadata if needed for unresolved activity and celebration deduplication.
Historical messages can restore context, but must not start timers as if
new, send commands, or revive an old op as "on air". Expired estimates mean
"status needs refresh", not a confirmed service-side end.

## Traffic budgets and transport safety

The handbook's current command limits are:

| Command family | Limits |
|----------------|--------|
| PING | 2/minute and 5/10 minutes |
| CQ, INFO, TIME, CHASERS, STAY | Each 1/3 minutes and 3/15 minutes |
| HOST | 2/minute and 3/10 minutes |
| CHASE | 4/minute and 8/10 minutes, across the operator's SSIDs |
| BLAST | 4/10 minutes and 8/hour; also 6 per sender per op and 12 per op overall |

Machine and human forms share their family budget. Rate-limit hints may be
followed by silence even though subsequent commands receive APRS ACKs.
Expose an estimated cooldown and distinguish **no service response** from
delivery failure. A local budget is advisory because another client or
SSID may also be using it; an explicit bot cooldown takes precedence.

Keep generated commands in **one APRS message**. The ordinary composer can
split long text into numbered parts, but splitting a bot command would
produce independent commands or meaningless fragments. Count the complete
ASCII payload, including keyword, target, spaces, and any authentication
overhead; reject oversize text visibly rather than truncating or splitting.
Do not assume OTA supports HTCommander's authentication extension.

For HOST and host QSL, select an explicit RF-only message policy. "Automatic"
can include direct APRS-IS submission in the current worktree and is not a
safe hosting default. Never silently broaden the path on retry or change
the application's global settings just to make an OTA action work.

The beacon action needs equivalent guarantees. The existing software beacon
handler emits APRS frames eligible for internet up-gating; RF-only message
policy alone does not constrain those beacons. A safe position action needs
a verified policy-aware path before it can be offered for hosting. Until
that exists, link to beacon settings and explain the requirement instead
of displaying a success-shaped shortcut.

Use the existing outbox for transport ACKs, retries, cancellation, and
host/browser forwarding. Do not add a second OTA retransmission loop.
Expired HOST/CHASE position windows also need explicit recovery: an old
queued command must not be automatically resumed as a fresh activity
without reviewing the deadline and identity.

## Where this fits in HTCommander

The current worktree already provides useful integration points:

| Existing component | Planned use |
|--------------------|-------------|
| [`contact_avatar.dart`](../../src/lib/widgets/contact_avatar.dart) | Shared automatic service icon and custom-avatar precedence. |
| [`aprs_tab.dart`](../../src/lib/widgets/aprs_tab.dart) | Canonical peer selection, OTA-only action strip, summaries, and existing send/error UX. |
| [`chat_widget.dart`](../../src/lib/widgets/chat_widget.dart) | Preserve shared chat behavior; add only a narrow optional rich-content hook if necessary. |
| [`aprs_events.dart`](../../src/lib/aprs/aprs_events.dart) | Existing SendAprsMessage request and cross-window serialization. |
| [`aprs_link_policy.dart`](../../src/lib/aprs/aprs_link_policy.dart) and [`aprs_outbox.dart`](../../src/lib/aprs/aprs_outbox.dart) | Explicit transport choice and one reliable outgoing-message pipeline. |
| [`software_beacon_handler.dart`](../../src/lib/handlers/software_beacon_handler.dart) | Review position submission, station identity, and independent beacon routing before adding a shortcut. |
| [`app_en.arb`](../../src/lib/l10n/app_en.arb) and other locale resources | Localized labels and explanations; OTA wire keywords stay unchanged. |

No new backend, modem, website scraper, or copied OTA database is needed
for the first version. The public website remains the richer destination
for cards and achievements. Internet-backed enrichment can be evaluated
separately against the service's documented API and usage rules; it is not
required for the APRS panel.

## A staged implementation plan, not an implementation

1. **Identity and protocol foundation.** Add the automatic avatar through
   the shared helper, exact OTA peer detection, and a pure decoder with
   fixtures from the documented machine grammar and prose confirmations.
2. **Discovery and chasing.** Add PING/CQ!/INFO! actions, paged host cards,
   one-message command validation, editable CHASE, beacon guidance, and
   distinct delivery/activity states. No automatic beaconing or polling.
3. **Hosting.** Verify explicit RF-only messages and a safe beacon path,
   then add host preflight, pending-chaser cards, CHASERS!, QSL, timers,
   STAY, BLAST warnings, and confirmed DONE.
4. **Polish and recovery.** Add replay-safe celebrations, op/operator
   links, stale/partial indicators, localization, and consistent behavior
   in detached and hosted windows. Defer internet enrichment.

Before shipping, focused tests should demonstrate:

- OTA gets its default avatar, custom avatars still win, OTA-0 selects the
  same panel, and unrelated APRS/MeshCore/Comms conversations stay unchanged.
- All four machine replies decode; nulls, NIL, DESC, appended fields,
  malformed/truncated records, missing/reordered/duplicate pages, and
  ambiguous delayed snapshots behave conservatively.
- DE chase relays and DE QSL relays remain distinct; embedded keywords in
  free text do not trigger actions. Unrelated recipients cannot update state.
- ACK, beacon acceptance, waiting for QSL, and confirmation are separate;
  duplicate/history replay neither double-counts nor celebrates again.
- Exact-SSID mismatch, missing/stale fix, disabled transmit, wrong beacon
  path, and bot RF refusals are visible. RF-only remains RF-only through
  queueing, restart, and retries.
- Command byte boundaries are tested at the actual allowed limit and one
  byte over, including prefixes/overhead; no bot command is multipart.
- Partial discovery is not empty discovery; simultaneous host/chase state
  survives navigation; uncertain timers do not manufacture completed ops.
- A hosting operator cannot issue a misleading targeted DONE through a
  "Mute" action; BLAST and End op require deliberate confirmation.
- Two windows produce one outgoing request, not duplicate transmissions.

Finally, exercise a deliberate RF PING, chase, and host/QSL exchange against
the service with a suitable radio/iGate setup. A parser test alone cannot
prove the bot sees the intended RF path or accepts the beacon.

The goal is a friendly guide beside the real conversation: fewer commands
to memorize, fewer missed beacon windows, and a clearer little victory when
the other operator comes back. APRS still does the work; the panel makes the
experience understandable.

## Sources

Service behavior was checked against these primary pages on November 28,
2026. Commands, reply grammar, and budgets can change; recheck them before
implementation.

- [APRS OTA overview](https://aprsota.org/) and [handbook](https://aprsota.org/handbook).
- [Chase an op](https://aprsota.org/handbook/chase-an-op), [make a contact](https://aprsota.org/handbook/make-a-contact), and [host an op](https://aprsota.org/handbook/host-an-op).
- [API over RF](https://aprsota.org/handbook/api-radio), [CQ](https://aprsota.org/handbook/cq), [INFO](https://aprsota.org/handbook/info), [TIME](https://aprsota.org/handbook/time), and [CHASERS](https://aprsota.org/handbook/chasers).
- [PING](https://aprsota.org/handbook/ping), [HOST](https://aprsota.org/handbook/host), [CHASE](https://aprsota.org/handbook/chase), and [QSL](https://aprsota.org/handbook/qsl).
- [STAY](https://aprsota.org/handbook/stay), [BLAST](https://aprsota.org/handbook/blast), [DONE](https://aprsota.org/handbook/done), and [score points](https://aprsota.org/handbook/score-points).
