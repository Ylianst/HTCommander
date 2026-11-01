#!/usr/bin/env node
// MCP server (stdio) that lets an AI agent observe and drive one or more
// HTCommander stations through their agent API. Zero dependencies; Node 22+.
//
//   HTC_STATIONS="bbs=ws://192.168.1.20:8080/websocket.aspx,term=ws://192.168.1.21:8080/websocket.aspx"
//   HTC_TOKEN_BBS=...  HTC_TOKEN_TERM=...
//   node htc_agent_mcp.mjs            # MCP server on stdin/stdout
//   node htc_agent_mcp.mjs --check    # connect to every station and print a summary
//
// Copyright 2026 Ylian Saint-Hilaire
// Licensed under the Apache License, Version 2.0 (the "License");
// http://www.apache.org/licenses/LICENSE-2.0

import { createInterface } from 'node:readline';
import { stationsFromEnv, timeline, tokenVar } from './htc_agent.mjs';

const SERVER = { name: 'htc-agent', version: '1.0.0' };
const PROTOCOLS = ['2025-06-18', '2025-03-26', '2024-11-05'];

const stations = await stationsFromEnv();
const names = [...stations.keys()];

function station(name) {
  const s = stations.get(name);
  if (!s) throw new Error(`unknown station "${name}"; configured: ${names.join(', ') || 'none'}`);
  return s;
}

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

const stationArg = {
  type: 'string',
  description: 'Configured station name',
  ...(names.length ? { enum: names } : {}),
};
const radioArg = { type: 'integer', description: 'Radio device id (see list_stations)' };

function tool(name, description, properties, required, run) {
  return { name, description, inputSchema: { type: 'object', properties, required }, run };
}

/** Runs an agent command and returns its reply plus the event cursor. */
function commandTool(name, command, description, properties, required, toArgs) {
  return tool(name, description, { station: stationArg, ...properties }, ['station', ...required], async (a) => {
    const s = station(a.station);
    const r = await s.command(command, toArgs(a));
    return { ...strip(r), cursor: s.cursor };
  });
}

function strip(reply) {
  const { id, ok, ...rest } = reply;
  return rest;
}

const tools = [
  tool(
    'list_stations',
    'Connect to every configured HTCommander station and report its callsign, radios ' +
      '(device id, name, state), whether transmitting is allowed, the transmit-time limit, ' +
      'and the clock offset to the host.',
    {},
    [],
    async () => {
      const out = [];
      for (const s of stations.values()) {
        try {
          const h = await s.open();
          out.push({
            name: s.name,
            url: s.url,
            connected: true,
            station: h.station,
            app: h.app,
            radios: h.radios,
            allowTransmit: h.allowTransmit === 1,
            txSecondsPerMinute: h.txSecondsPerMinute,
            clockOffsetMs: Math.round(s.clockOffsetMs),
            cursor: s.cursor,
          });
        } catch (e) {
          out.push({ name: s.name, url: s.url, connected: false, error: e.message });
        }
      }
      return { stations: out };
    },
  ),
  tool(
    'get_packets',
    'Recent packet capture of one station, as shown in its packet capture tab: time, RX/TX, ' +
      'radio, channel, modem/encoding label, summary and over-the-air hex. XARA frames include ' +
      'bandwidth, level, SNR and control-code verdicts. Set details for full decode sections.',
    {
      station: stationArg,
      since: { type: 'string', description: 'ISO time; only newer packets' },
      limit: { type: 'integer', description: 'Max packets (default 200)' },
      details: { type: 'boolean', description: 'Include decode sections' },
    },
    ['station'],
    async (a) => {
      const r = await station(a.station).call('packets', pick(a, ['since', 'limit', 'details']));
      return { packets: r.packets };
    },
  ),
  tool(
    'get_timeline',
    'Packet captures of several stations merged into one timeline using clock-corrected ' +
      'times, so a frame sent by one station lines up with its reception on the other. ' +
      '`t` is seconds from the first row.',
    {
      stations: { type: 'array', items: stationArg, description: 'Stations (default all)' },
      since: { type: 'string', description: 'ISO time; only newer packets' },
      limit: { type: 'integer', description: 'Max packets per station (default 500)' },
    },
    [],
    async (a) => {
      const list = (a.stations?.length ? a.stations : names).map(station);
      return { timeline: await timeline(list, pick(a, ['since', 'limit'])) };
    },
  ),
  tool(
    'get_logs',
    "A station's application log (the Debug tab).",
    {
      station: stationArg,
      since: { type: 'string', description: 'ISO time; only newer lines' },
      level: { type: 'string', enum: ['all', 'error'], description: 'error = errors only' },
      limit: { type: 'integer', description: 'Max lines (default 500)' },
    },
    ['station'],
    async (a) => {
      const args = pick(a, ['since', 'limit']);
      if (a.level === 'error') args.level = 'error';
      return { logs: (await station(a.station).call('logs', args)).logs };
    },
  ),
  tool(
    'get_value',
    'Read one value. device 0: settings (secrets are refused); device 1: ConnectedRadios, ' +
      'SelectedRadioDeviceId, TerminalState; a radio device id: State, LockState, HtStatus, XaraLinkState, ' +
      'FriendlyName, Channels, RegionNames, AudioState.',
    { station: stationArg, device: { type: 'integer' }, name: { type: 'string' } },
    ['station', 'device', 'name'],
    async (a) => {
      const r = await station(a.station).call('get', { device: a.device, name: a.name });
      return { value: r.value };
    },
  ),
  tool(
    'get_events',
    'Events buffered from a station since a cursor: PacketStored, LogInfo, LogError, ' +
      'XaraEvent, XaraLinkState, BbsControlMessage, BbsTraffic, BbsError, LockState, State, ' +
      'HtStatus, TerminalState, TerminalText, TerminalNotice, AgentLimit, AgentStopped. ' +
      'Returns the new cursor.',
    {
      station: stationArg,
      after: { type: 'integer', description: 'Cursor from a previous call (default 0)' },
      names: { type: 'array', items: { type: 'string' }, description: 'Event names to keep' },
      contains: { type: 'string', description: 'Text the event data must contain' },
      limit: { type: 'integer', description: 'Max events (default 200)' },
    },
    ['station'],
    async (a) => {
      const s = station(a.station);
      await s.open();
      const events = s.eventsAfter(a.after ?? 0, pick(a, ['names', 'contains', 'limit']));
      return { events, cursor: s.cursor };
    },
  ),
  tool(
    'wait_for',
    'Wait until a station reports a matching event after a cursor, e.g. XaraEvent containing ' +
      '"connected", or PacketStored containing "open source". Returns the event, or ' +
      'timedOut: true.',
    {
      station: stationArg,
      names: { type: 'array', items: { type: 'string' }, description: 'Event names to match' },
      contains: { type: 'string', description: 'Text the event data must contain' },
      after: { type: 'integer', description: 'Cursor; only newer events count (default: now)' },
      timeout_s: { type: 'number', description: 'Seconds to wait (default 60, max 600)' },
    },
    ['station'],
    async (a) => {
      const s = station(a.station);
      await s.open();
      const event = await s.waitFor({
        after: a.after ?? s.cursor,
        names: a.names,
        contains: a.contains,
        timeoutMs: Math.min(Math.max(a.timeout_s ?? 60, 0), 600) * 1000,
      });
      return event ? { event, cursor: s.cursor } : { timedOut: true, cursor: s.cursor };
    },
  ),
  commandTool(
    'radio_lock',
    'radio.lock',
    'Lock a radio to a channel for the agent (transmits only when a link is driven). Use ' +
      'modem "XARA" (and xara_wide) to drive XARA links with xara_connect.',
    {
      radio: radioArg,
      channel: { type: ['string', 'integer'], description: 'Channel name or id' },
      region: { type: ['string', 'integer'], description: 'Region name or index' },
      modem: { type: 'string', enum: ['Hardware', 'AFSK1200', 'PSK2400', 'DART', 'XARA'] },
      xara_wide: { type: 'boolean' },
      usage: { type: 'string', enum: ['Agent', 'Terminal'] },
    },
    ['radio'],
    (a) => ({ ...pick(a, ['radio', 'channel', 'region', 'modem', 'usage']), ...(a.xara_wide !== undefined ? { xaraWide: a.xara_wide } : {}) }),
  ),
  commandTool('radio_unlock', 'radio.unlock', 'Abort XARA and release a radio the agent locked.', { radio: radioArg }, ['radio'], (a) => pick(a, ['radio'])),
  commandTool(
    'bbs_start',
    'bbs.start',
    "Start the BBS on a radio (it answers AX.25 and, in XARA mode, XARA). Channel defaults to the radio's current channel A.",
    { radio: radioArg, channel: { type: ['string', 'integer'], description: 'Channel name or id' } },
    ['radio'],
    (a) => pick(a, ['radio', 'channel']),
  ),
  commandTool('bbs_stop', 'bbs.stop', 'Stop a BBS the agent started.', { radio: radioArg }, ['radio'], (a) => pick(a, ['radio'])),
  commandTool(
    'xara_connect',
    'xara.connect',
    'Open a XARA (VARA FM) link from an agent-held radio to a remote callsign.',
    {
      radio: radioArg,
      remote: { type: 'string', description: 'Remote callsign, e.g. N0CALL-1' },
      vias: { type: 'array', items: { type: 'string' }, description: 'Up to 2 digipeaters' },
    },
    ['radio', 'remote'],
    (a) => pick(a, ['radio', 'remote', 'vias']),
  ),
  commandTool(
    'xara_send',
    'xara.send',
    'Send text (e.g. a BBS command ending in \\r) or hex bytes over the XARA link.',
    { radio: radioArg, text: { type: 'string' }, hex: { type: 'string' } },
    ['radio'],
    (a) => pick(a, ['radio', 'text', 'hex']),
  ),
  commandTool('xara_disconnect', 'xara.disconnect', 'Gracefully close the XARA link.', { radio: radioArg }, ['radio'], (a) => pick(a, ['radio'])),
  commandTool('xara_abort', 'xara.abort', 'Abort the XARA link immediately.', { radio: radioArg }, ['radio'], (a) => pick(a, ['radio'])),
  commandTool(
    'terminal_connect',
    'terminal.connect',
    "Connect the station's Terminal (the same engine as its Terminal tab) to a terminal contact " +
      'from its address book, or to an ad-hoc station. The protocol (raw AX.25, AX.25 session, ' +
      'APRS, XARA narrow/wide) and channel come from the contact. Watch TerminalState, ' +
      'TerminalText and TerminalNotice events.',
    {
      radio: radioArg,
      contact: { type: 'string', description: 'Callsign of a terminal contact in the address book' },
      station_info: {
        type: 'object',
        description:
          'Ad-hoc station instead of contact: {Callsign, TerminalProtocol (0 raw AX.25, 1 AX.25 ' +
          'session, 2 APRS, 4 XARA narrow, 5 XARA wide), Channel, AX25Destination, AX25Path}',
      },
    },
    ['radio'],
    (a) => ({ ...pick(a, ['radio', 'contact']), ...(a.station_info ? { station: a.station_info } : {}) }),
  ),
  commandTool(
    'terminal_wait',
    'terminal.wait',
    "Make the station's Terminal wait for an incoming AX.25 session on a radio's current channel.",
    { radio: radioArg },
    ['radio'],
    (a) => pick(a, ['radio']),
  ),
  commandTool(
    'terminal_send',
    'terminal.send',
    'Send a line of text over the Terminal link this agent started, as if typed in the Terminal tab (a line ending is added).',
    { text: { type: 'string' } },
    ['text'],
    (a) => pick(a, ['text']),
  ),
  commandTool('terminal_disconnect', 'terminal.disconnect', 'Gracefully disconnect the Terminal link this agent started.', {}, [], () => ({})),
  commandTool('terminal_abort', 'terminal.abort', 'Drop the Terminal link this agent started immediately and release the radio.', {}, [], () => ({})),
  commandTool('clear_packets', 'packets.clear', "Clear the station's packet capture.", {}, [], () => ({})),
  commandTool(
    'set_setting',
    'setting.set',
    'Change a modem setting live: SoftwareModemMode, SoftwareModemFec, DartTxMode, XaraWide, ' +
      'XaraTxLatencyMs, XaraTxKeyUpMs. Changing XARA settings rebuilds the modem and drops links.',
    {
      name: { type: 'string', enum: ['SoftwareModemMode', 'SoftwareModemFec', 'DartTxMode', 'XaraWide', 'XaraTxLatencyMs', 'XaraTxKeyUpMs'] },
      value: { description: 'New value' },
    },
    ['name', 'value'],
    (a) => pick(a, ['name', 'value']),
  ),
  tool(
    'stop_all',
    'Emergency stop: on every station, abort XARA, stop agent BBSes and release agent radio locks.',
    {},
    [],
    async () => {
      const out = {};
      for (const s of stations.values()) {
        try {
          out[s.name] = (await s.call('stop')).released;
        } catch (e) {
          out[s.name] = { error: e.message };
        }
      }
      return { released: out };
    },
  ),
];

const byName = new Map(tools.map((t) => [t.name, t]));

function pick(obj, keys) {
  const out = {};
  for (const k of keys) if (obj[k] !== undefined) out[k] = obj[k];
  return out;
}

// ---------------------------------------------------------------------------
// MCP over stdio (newline-delimited JSON-RPC 2.0)
// ---------------------------------------------------------------------------

function send(message) {
  process.stdout.write(JSON.stringify(message) + '\n');
}

async function handle(msg) {
  const { id, method, params } = msg;
  const isRequest = id !== undefined && id !== null;
  try {
    let result;
    switch (method) {
      case 'initialize': {
        const asked = params?.protocolVersion;
        result = {
          protocolVersion: PROTOCOLS.includes(asked) ? asked : PROTOCOLS[0],
          capabilities: { tools: {} },
          serverInfo: SERVER,
          instructions:
            'Tools drive real radios. Clear captures, act, then read get_timeline. ' +
            'Always finish with stop_all or by unlocking radios you locked.',
        };
        break;
      }
      case 'ping':
        result = {};
        break;
      case 'tools/list':
        result = { tools: tools.map(({ run, ...t }) => t) };
        break;
      case 'tools/call': {
        const t = byName.get(params?.name);
        if (!t) throw rpcError(-32602, `unknown tool "${params?.name}"`);
        try {
          const value = await t.run(params.arguments ?? {});
          result = { content: [{ type: 'text', text: JSON.stringify(value, null, 1) }] };
        } catch (e) {
          result = { content: [{ type: 'text', text: e.message }], isError: true };
        }
        break;
      }
      default:
        if (!isRequest) return; // notifications (e.g. notifications/initialized)
        throw rpcError(-32601, `method not found: ${method}`);
    }
    if (isRequest) send({ jsonrpc: '2.0', id, result });
  } catch (e) {
    if (isRequest) {
      send({ jsonrpc: '2.0', id, error: { code: e.code ?? -32603, message: e.message } });
    }
  }
}

function rpcError(code, message) {
  return Object.assign(new Error(message), { code });
}

async function check() {
  if (!names.length) {
    console.error('No stations configured. Set HTC_STATIONS (and HTC_TOKEN_<NAME>) or HTC_AGENT_CONFIG.');
    process.exit(2);
  }
  let failed = false;
  for (const s of stations.values()) {
    try {
      const h = await s.open();
      const radios = h.radios.map((r) => `${r.id} ${r.name} (${r.state})`).join(', ') || 'none';
      console.log(`${s.name}: ${h.station} at ${s.url}, clock offset ${Math.round(s.clockOffsetMs)} ms, radios: ${radios}`);
    } catch (e) {
      failed = true;
      console.log(`${s.name}: ${e.message}${s.token ? '' : ` (set ${tokenVar(s.name)})`}`);
    } finally {
      s.close();
    }
  }
  process.exit(failed ? 1 : 0);
}

if (process.argv.includes('--check')) {
  await check();
} else {
  const inFlight = new Set();
  const rl = createInterface({ input: process.stdin });
  rl.on('line', (line) => {
    if (!line.trim()) return;
    let msg;
    try {
      msg = JSON.parse(line);
    } catch {
      send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'parse error' } });
      return;
    }
    const p = handle(msg).finally(() => inFlight.delete(p));
    inFlight.add(p);
  });
  // Closing stdin ends the session: finish pending calls, then close the
  // sockets so each host releases everything this agent held.
  rl.on('close', async () => {
    await Promise.allSettled([...inFlight]);
    for (const s of stations.values()) s.close();
    process.exit(0);
  });
}
