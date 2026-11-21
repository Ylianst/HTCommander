# Packet Chess: A Stateless Protocol for Playing Chess Over Radio

*A compact, transport-independent format for carrying a chess move — or a chat
message — over AFSK 1200, AX.25, XARA, DART, or another packet-capable radio
link.*

---

## A game that can survive missed packets

Radio links are inconvenient places to run a long, stateful conversation. A
station may hear move 1, miss moves 2 through 6, and reappear just as move 7 is
sent. Asking that station to reconstruct the board from a transcript it never
received is a bad start.

The solution is to make a move packet self-contained. Each packet carries:

- an identity for the game;
- the complete board position **before** the move;
- the information needed to validate special moves;
- the proposed move;
- a monotonically increasing move number.

The receiver does not need the preceding packets to validate and display the
move. If software kept missed history locally, it can also reconcile the new
position with that history. If it did not, it can simply adopt the fully
described position and continue from there.

The same envelope also carries short chat messages associated with the game.
Chat does not affect the board, and a chat sequence does not consume a chess
move number.

This is a proposed **Radio Chess Protocol (RCP)** format, deliberately separate
from the modem underneath it. AFSK 1200 and XARA only need to deliver the bytes
in order to give RCP something to work with.

## Design goals

The format is intended to be:

- **Small.** A complete move fits in 58 bytes before link-layer framing.
- **Self-contained.** A receiver can reconstruct a move from one packet.
- **Deterministic.** There are no optional text parsers in the critical path.
- **Replay-safe.** Duplicate packets are recognized by game ID and sequence.
- **Transport-neutral.** The protocol neither assumes AX.25 nor depends on a
  connected modem.
- **Extensible.** Unknown packet types can be skipped, and later versions can
  add new fields.
- **Readable where possible.** Amateur-radio use should not rely on hiding the
  contents. Integrity and authentication are separate from encryption.

## The common envelope

All multibyte integers use little-endian byte order. Every RCP packet begins
with the same 16-byte header:

```text
Offset  Size  Field
------  ----  -----------------------------------------------
0       2     Magic bytes: ASCII "RC"
2       1     Version/type byte
3       1     Flags
4       8     Game ID
12      4     Sequence number
```

The `version/type` byte packs two nibbles:

```text
bits 0-3: packet type
bits 4-7: protocol version, currently 1
```

Initial packet types are:

| Value | Type | Purpose |
| ---: | --- | --- |
| `0x1` | `MOVE` | A complete pre-move position and proposed move |
| `0x2` | `CHAT` | A UTF-8 message for the game |
| `0x3` | `ACK` | Acknowledges another packet |
| `0x4` | `CONTROL` | Resign, draw, abort, or similar game action |
| `0x5-0xD` | Reserved | Reserved for future packet types |
| `0xE` | `EXTENSION` | Versioned extension data |
| `0xF` | `ERROR` | Reports a rejected packet or unsupported version |

The first flag bits are reserved for common semantics:

```text
bit 0: acknowledgement requested
bit 1: packet contains an optional authentication trailer
bit 2: sender is the white side
bit 3: sender is the black side
bits 4-7: reserved, must be zero in version 1
```

Exactly one of the white/black role bits may be set for a normal two-player
game. A spectator or gateway announcement may set neither.

The eight-byte **game ID** is a randomly generated identifier. It need not be a
secret. Sixty-four bits provide enough space to avoid accidental collisions in
normal amateur use.

The meaning of `sequence` depends on the packet type:

- for `MOVE`, it is the chess ply number, starting at zero;
- for `CHAT`, it is a sender-local, monotonically increasing message number;
- for `ACK`, it is the acknowledged packet's sequence;
- for `CONTROL`, it is a sender-local control-event number.

The tuple `(game ID, packet type, sender, sequence)` identifies a transmission.
The sender normally comes from the transport, such as the AX.25 source address.
Applications must keep sequence state separately for each player and each
packet stream.

The last two bytes of every RCP packet are a CRC-16-CCITT-FALSE value, stored
little-endian. The sender calculates it over every byte from the magic field
through the byte immediately before the CRC, including an authentication trailer
when present. Receivers reject a packet with any trailing or missing bytes that
do not agree with the length required by the packet type and its fields.

## Packing the board into 32 bytes

A chessboard has 64 squares. One byte per square would be wasteful because the
only values needed are empty plus twelve piece types. Four bits are enough.

The piece codes are:

| Code | Meaning |
| ---: | --- |
| `0` | Empty |
| `1` | White pawn |
| `2` | White knight |
| `3` | White bishop |
| `4` | White rook |
| `5` | White queen |
| `6` | White king |
| `7` | Black pawn |
| `8` | Black knight |
| `9` | Black bishop |
| `10` | Black rook |
| `11` | Black queen |
| `12` | Black king |
| `13-15` | Reserved; invalid in a version 1 position |

Squares run from `a1 = 0` through `h8 = 63`, increasing by file and then rank.
Two squares fit in each byte:

```text
byte[i] = piece(square 2i) | piece(square 2i + 1) << 4
```

Thus the whole board occupies exactly **32 bytes**. This is nearly as compact
as an entropy-coded representation but much easier to implement, inspect, and
validate on small devices.

## Information that does not live on the board

Piece placement alone is not enough to determine legal moves. RCP adds six
bytes of position state:

```text
Offset  Size  Field
------  ----  -----------------------------------------------
0       1     Position flags
1       1     En-passant target square, or 0xFF
2       2     Halfmove clock
4       2     Fullmove number
```

Position flag bits are:

```text
bit 0: side to move (0 = white, 1 = black)
bit 1: white may castle king-side
bit 2: white may castle queen-side
bit 3: black may castle king-side
bit 4: black may castle queen-side
bits 5-7: reserved
```

The en-passant square is the actual target square. For example, after `e2e4`,
the target is `e3`, encoded as square number 20.

The halfmove clock is included for the fifty-move rule. The fullmove number is
included so a display can report a familiar chess notation state. The receiver
should reject reserved state values rather than silently guessing.

## A move takes only two bytes

RCP stores a move in a 16-bit word:

```text
bits 0-5:   source square
bits 6-11:  destination square
bits 12-14: promotion piece
bit 15:     reserved
```

Promotion values are:

```text
0 = no promotion
1 = knight
2 = bishop
3 = rook
4 = queen
5-7 = reserved
```

Castling is represented by the king moving two squares. En-passant is represented
by an ordinary pawn move to the empty target square. The move is interpreted
against the position in the packet; an external notation such as UCI or SAN is
not required on the air.

## The complete MOVE packet

A `MOVE` payload is:

```text
16-byte common header
32-byte board
 6-byte position state
 2-byte move
 2-byte CRC-16-CCITT-FALSE
-------------------------
58 bytes
```

In other words:

```text
MOVE(game, ply, board-before, state-before, proposed-move)
```

The position is explicitly the position **before** the move. Upon receipt, the
receiver:

1. checks the version, type, length, and CRC;
2. checks the sender's role and sequence;
3. validates the board: exactly one king of each color, legal piece codes, and
   plausible position metadata;
4. checks that the packet's side-to-move agrees with the move number;
5. validates the proposed move with a normal chess-rules engine;
6. applies it;
7. stores the resulting position;
8. sets the expected next ply to the received sequence plus one;
9. optionally sends an acknowledgement.

The CRC catches accidental damage. It is not authentication. A transport with
its own frame CRC may retain RCP's CRC because gateways can terminate and
recreate the underlying radio frame.

## Catching up and rejecting duplicates

Suppose White sends `ply = 17`. The packet contains a complete valid board and
White's proposed move. A receiver may have missed `ply = 15` and `ply = 16`, but
it does not need either packet to display what White just played.

A version 1 receiver treats sequence handling as follows:

- An identical packet already processed is a duplicate and is ignored.
- A lower move number is retained as history, if useful, but cannot replace the
  current position.
- A higher move number may synchronize the board after the complete packet has
  passed chess validation.
- The same game, sender, type, and sequence arriving with different contents
  is a conflict and must be reported to the operator.

The complete position permits recovery; it should not bypass the application's
trust policy. For an authenticated or tournament-style game, applications must
also require the expected peer and verify an integrity trailer before replacing
local state.

## Game chat

Chat is a first-class packet type rather than text hidden inside a move. Its
payload is:

```text
Offset  Size       Field
------  ---------  --------------------------------------
0       1          UTF-8 text length in bytes
1       text-len   UTF-8 text
...     2          CRC-16-CCITT-FALSE over the RCP packet
```

For example:

```text
RC 1/CHAT  game-id  chat-seq  "Good move!"
```

The total frame is `19 + text length` bytes. For a link whose application
payload limit is 256 bytes, the absolute version 1 chat body limit is 237
UTF-8 bytes. A conservative application profile can use a lower limit, such as
120 or 160 bytes, to favor shorter airtime and leave room for transport headers.
An authentication trailer consumes additional bytes, so authenticated chats
must reduce that maximum by the trailer's complete length.

The length is bytes, not characters. Emoji and other non-ASCII text consume
multiple bytes. A sender must not split a UTF-8 code point between packets.

Chat has its own sequence counter in each direction:

```text
game A: White CHAT 1
game A: White MOVE ply 21
game A: White CHAT 2
```

The chat sequence is still 2 after the move. This keeps commentary from
disturbing the chess clock.

Chats are inherently stateless: each one contains its complete text and ID.
Duplicate reception is harmless. For a missed longer conversation, the protocol
does not attempt to recover old chat automatically, but an operator can
request a recent-message replay from the peer if that application implements
it.

## ACKs are useful, not required for recovery

Not every packet needs an acknowledgement. The flag asks for one, and ACK
packets are especially useful for interactive game software.

A compact ACK payload contains:

```text
1 byte   acknowledged packet type
2 bytes  CRC-16 fragment of the acknowledged packet
```

The common sequence field identifies which packet is being acknowledged. The
CRC fragment confirms that both stations refer to the same bytes even in the
unlikely event of a sequence collision or conflicting retransmission.

On receiving a duplicate move that was already applied, the receiver can send
the same ACK again. This is the normal recovery path:

```text
White  -> Black  MOVE, game 9f..., ply 17
                    ACK is lost in noise
White  -> Black  identical MOVE, game 9f..., ply 17
Black  -> White  ACK, ply 17
```

Black applies the move once. No special connection state is needed.

## Optional game control

`CONTROL` packets use a one-byte operation followed by operation-specific data.
Suggested initial operations are:

| Value | Operation |
| ---: | --- |
| `0x01` | Draw offer |
| `0x02` | Draw accepted |
| `0x03` | Draw declined |
| `0x04` | Resign |
| `0x05` | Abort request |
| `0x06` | Abort accepted |
| `0x07` | Rematch request |
| `0x08` | Rematch accepted |
| `0x09` | Request current position |
| `0x0A` | Current position response |

Control packets also use sender-local sequence numbers. A result packet should
be persisted by both applications. `CURRENT POSITION` can be answered with the
next current move snapshot or a dedicated state packet in a future revision.

## How the packets sound on the available links

RCP deliberately avoids depending on a particular physical layer:

- **AX.25 / AFSK 1200:** send RCP in a UI-frame information field, using a PID
  or port convention that distinguishes it from APRS and ordinary text.
- **XARA:** send each RCP packet as a complete application datagram when the
  modem session exposes packet boundaries.
- **DART or another framed modem:** preserve the RCP packet boundary and its
  CRC.
- **Connected byte streams:** the outer application must add a length prefix
  because RCP currently describes one logical packet, not a streaming framing
  convention.

If a modem supports its own retransmission, RCP acknowledgements may be
disabled for that link. The protocol does not require them.

## Integrity, authentication, and amateur-radio legality

There are three different promises worth keeping separate:

1. **CRC integrity** means a damaged frame is unlikely to pass as valid.
2. **Authentication** means a station can show who authorized a move or chat.
3. **Encryption** means the content is hidden.

RCP's normal packets provide the first one. A game can add the third-party-free
second one with a public-key signature or a short keyed MAC agreed to by the
two players. Any such authentication field should cover the exact packet bytes,
including game ID, sequence, board, move, and chat text.

When common-header bit 1 is set, version 1 places an authentication trailer
after the packet payload and before the final CRC:

```text
1 byte  trailer value length
1 byte  authentication algorithm
N bytes authentication value
```

The authentication value covers the exact header and payload bytes before the
trailer. Algorithm `1` is defined as the first eight bytes of
`HMAC-SHA256(shared key, header || payload)`. A future profile can define a
longer public-key signature by advertising another algorithm and trailer
length. The receiver must reject an unknown authentication algorithm unless
the operator has explicitly configured that authentication is optional.

Authentication is optional and must be visible to the user. The payload should
remain readable. Encryption is out of scope for amateur-radio transmission and
is not needed to satisfy the chess protocol's goals.

The common CRC is not a defense against an intentionally forged move. A casual
game may accept packets only from the two configured peer callsigns; a more
important game should enable authentication.

## Why not just use FEN and UCI?

FEN plus UCI is an attractive interchange format because people can read it.
For example:

```text
rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1 e7e5
```

That is useful for export, debugging, and perhaps an optional terminal mode.
But even a compact position commonly takes 50-80 bytes, and variable-length text
parsing is harder to validate on every implementation.

RCP's fixed 32-byte board has a more direct property: it always uses the same
space and can be decoded without parsing delimiters. On the air, the move packet
uses 58 bytes. In a human-facing log or share string, an implementation can
still produce FEN, UCI, or PGN from the same internal state.

## Limits and open questions

No state snapshot, however complete, can reconstruct *all* chess history. RCP
includes castling rights, the en-passant target, and the halfmove clock. It
does not include prior position history, so threefold-repetition adjudication
requires the application to retain that history or for a later version to
carry a repetition-history commitment.

Other decisions are intentionally left to an implementation profile:

- whether a 58-byte move also carries an optional authentication trailer;
- how a transport announces RCP's application ID;
- the maximum chat length selected for a particular modem;
- how clocks are displayed and whether they are enforceable;
- whether spectators may observe games without being allowed to send chat;
- how a result is signed or countersigned.

Those are useful questions, but they are separate from the core wire format.
The essential idea stays small: a game ID, a sequence, a four-bit chessboard,
and a move. Add a parallel chat stream, and a radio operator can recover the
game, play a move, and exchange a short comment with a single, compact packet.

---

**Status:** Protocol design proposal; not yet an HTCommander implementation.
