# htc-agent: drive HTCommander stations from an AI agent

`htc_agent_mcp.mjs` is an [MCP](https://modelcontextprotocol.io) server that
lets an AI agent (GitHub Copilot, Claude, ...) observe and control one or more
HTCommander stations over the network. Typical use: two PCs, each running
HTCommander with a radio, and one agent running a real over-the-air test
between them while it reads both packet captures.

It talks to each station's **agent API** over the web server WebSocket
(`ws://<pc>:<port>/websocket.aspx`). See
[Two Radios, One Agent](../../../docs/blogs/ai-agent-radio-testing.md) for the
design and the protocol reference.

- **Zero dependencies.** Needs Node.js 22 or later (built-in WebSocket). Nothing
  to `npm install`.
- `htc_agent.mjs` is the reusable client library (`Station`, `timeline`).
- `htc_agent_mcp.mjs` is the MCP server (stdio).

## 1. Prepare each HTCommander

On every PC:

1. **Settings → Servers**: enable **Web Server** (note the port, default 8080),
   then tick **Allow test agents (automation API)**.
2. Copy the **token** shown under it (one token per station).
3. **Settings → General**: transmitting must be allowed for the agent to lock
   radios, run the BBS or open XARA links.
4. Make sure the agent machine can reach the port (firewall), and keep it on
   your LAN or a VPN. Never expose it to the internet.

While an agent is connected, HTCommander shows a red banner with a
**Stop & disable** button. That button releases everything the agent holds and
turns agent access off.

## 2. Configure the stations

Name each station and give its URL and token, either in environment variables:

```text
HTC_STATIONS=bbs=ws://192.168.1.20:8080/websocket.aspx,term=ws://192.168.1.21:8080/websocket.aspx
HTC_TOKEN_BBS=<token from the BBS PC>
HTC_TOKEN_TERM=<token from the terminal PC>
```

or in a JSON file named by `HTC_AGENT_CONFIG` (keep it out of source control):

```json
{
  "stations": {
    "bbs": { "url": "ws://192.168.1.20:8080/websocket.aspx", "token": "..." },
    "term": { "url": "ws://192.168.1.21:8080/websocket.aspx", "token": "..." }
  }
}
```

Check the setup from a terminal:

```text
node src/tools/htc_agent/htc_agent_mcp.mjs --check
bbs: N0CALL at ws://192.168.1.20:8080/websocket.aspx, clock offset 3 ms, radios: 101 UV-Pro (Connected)
term: N0CALL at ws://192.168.1.21:8080/websocket.aspx, clock offset -12 ms, radios: 101 UV-Pro (Connected)
```

## 3. Add it to your agent

**VS Code** (`.vscode/mcp.json` in your workspace, or your user MCP
configuration). The tokens are prompted for and stored by VS Code, not written
to the file:

```json
{
  "inputs": [
    { "type": "promptString", "id": "htcBbsToken", "description": "HTCommander BBS agent token", "password": true },
    { "type": "promptString", "id": "htcTermToken", "description": "HTCommander terminal agent token", "password": true }
  ],
  "servers": {
    "htc-agent": {
      "type": "stdio",
      "command": "node",
      "args": ["${workspaceFolder}/src/tools/htc_agent/htc_agent_mcp.mjs"],
      "env": {
        "HTC_STATIONS": "bbs=ws://192.168.1.20:8080/websocket.aspx,term=ws://192.168.1.21:8080/websocket.aspx",
        "HTC_TOKEN_BBS": "${input:htcBbsToken}",
        "HTC_TOKEN_TERM": "${input:htcTermToken}"
      }
    }
  }
}
```

**Other MCP clients** use the same command and environment. Most accept an
`mcpServers` entry like:

```json
{
  "mcpServers": {
    "htc-agent": {
      "command": "node",
      "args": ["/path/to/HTCommander/src/tools/htc_agent/htc_agent_mcp.mjs"],
      "env": { "HTC_AGENT_CONFIG": "/path/to/htc-stations.json" }
    }
  }
}
```

## Tools

| Tool | What it does |
|---|---|
| `list_stations` | Connects to every station: callsign, radios (device ids), transmit allowed, transmit limit, clock offset |
| `get_packets` | One station's packet capture (summary, modem label, over-the-air hex; `details` for decode sections) |
| `get_timeline` | All stations' captures merged by clock-corrected time |
| `get_logs` | A station's debug log (`level: "error"` for errors) |
| `get_value` | Read lock state, link state, radio status, channels, settings (no secrets) |
| `get_events` / `wait_for` | Buffered events since a cursor / wait for the next matching one |
| `radio_lock` / `radio_unlock` | Lock a radio to a channel, optionally with the XARA modem (`modem: "XARA"`, `xara_wide`) |
| `bbs_start` / `bbs_stop` | Run the BBS on a radio |
| `xara_connect` / `xara_send` / `xara_disconnect` / `xara_abort` | Drive a XARA link from an agent-held radio |
| `terminal_connect` / `terminal_wait` | Use the station's Terminal (same engine as its Terminal tab) with an address-book terminal contact (`contact`) or an ad-hoc `station_info`; any protocol, including XARA Narrow/Wide |
| `terminal_send` / `terminal_disconnect` / `terminal_abort` | Type into, or close, the Terminal link the agent started; watch `TerminalText`, `TerminalNotice`, `TerminalState` |
| `clear_packets` | Clear a station's packet capture |
| `set_setting` | Change `SoftwareModemMode`, `SoftwareModemFec`, `DartTxMode`, `XaraWide`, `XaraTxLatencyMs`, `XaraTxKeyUpMs` live |
| `stop_all` | Release everything agents hold on every station |

Every command returns a `cursor`; pass it as `after` to `wait_for` to wait only
for events that follow that command.

## Example: XARA terminal to BBS

A prompt like *"Use htc-agent to connect the term station to the BBS on the bbs
station over XARA Narrow, send S, and show me both captures"* lets the agent
run roughly:

1. `list_stations`, then `clear_packets` on both stations.
2. `set_setting` `SoftwareModemMode` = `XARA` on `bbs`, then `bbs_start` (radio 101).
3. `radio_lock` on `term` (radio 101, channel "BBS", modem "XARA").
4. `xara_connect` on `term` to the BBS callsign, then `wait_for` `XaraEvent`
   containing `connected`.
5. `xara_send` `S\r`, then `wait_for` `PacketStored` containing `open source`.
6. `get_timeline` to see both stations' frames in order, including XARA
   control-code verdicts such as `dropped: late`.
7. `stop_all`.

**Through the Terminal instead.** When `term` has a terminal contact for the
BBS (XARA Narrow or Wide) in its address book, steps 3�5 become:
. `terminal_connect` on `term` (radio 101, `contact` = the BBS callsign).
   The terminal locks the radio, tunes the contact's channel and connects.. `wait_for` `TerminalState` containing `connected`.. `terminal_send` `S`, then `wait_for` `TerminalText` containing `open source`.. `terminal_disconnect`.
 tests exactly what an operator does in the Terminal tab, and the tab on PC shows the session live.

## Safety

These tools key real transmitters.

- The control operator must be present and able to stop the test. The
  **Stop & disable** banner button, or turning agent access off, stops
  everything immediately.
- Transmissions follow the station's identification rules and band plan. Rules
  for automatic control differ by country.
- Each station limits agent transmit time (`AgentApiTxSecondsPerMinute`,
  default 45 s per minute per radio).
- If the MCP server exits or loses its connection, each station releases what
  the agent held.

## Tests

`src/test/htc_agent_mcp_test.dart` runs this server against a real HTCommander
web server and agent API (skipped when Node 22+ is not installed):

```text
cd src
flutter test test/htc_agent_mcp_test.dart
```
