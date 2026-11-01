// HTCommander agent client: connects to one or more HTCommander instances over
// the web server's WebSocket using the `agent:` protocol (see
// docs/blogs/ai-agent-radio-testing.md). Zero dependencies; needs Node 22+ for
// the built-in WebSocket client.
//
// Copyright 2026 Ylian Saint-Hilaire
// Licensed under the Apache License, Version 2.0 (the "License");
// http://www.apache.org/licenses/LICENSE-2.0

const REQUEST_TIMEOUT_MS = 15000;
const EVENT_BUFFER = 5000;

/** One HTCommander station. Connects lazily and reconnects when needed. */
export class Station {
  /**
   * @param {string} name   short name used by tools, e.g. "bbs"
   * @param {string} url    ws://host:port/websocket.aspx
   * @param {string} token  the station's AgentApiToken
   */
  constructor(name, url, token) {
    this.name = name;
    this.url = url;
    this.token = token;
    /** Host clock minus local clock, in ms (estimated at hello). */
    this.clockOffsetMs = 0;
    /** Reply of the last successful hello. */
    this.info = null;
    /** Buffered events: {seq, received, event, device, time, data}. */
    this.events = [];
    this._seq = 0;
    this._nextId = 1;
    this._pending = new Map();
    this._waiters = new Set();
    this._ws = null;
    this._opening = null;
  }

  get connected() {
    return this._ws !== null && this._ws.readyState === WebSocket.OPEN && this.info !== null;
  }

  /** Connects and authenticates if needed. Returns the hello reply. */
  async open() {
    if (this.connected) return this.info;
    if (!this._opening) {
      this._opening = this._connect().finally(() => {
        this._opening = null;
      });
    }
    return this._opening;
  }

  async _connect() {
    if (!this.token) throw new Error(`${this.name}: no token configured`);
    // A session the host dropped (e.g. operator Stop) needs a fresh socket.
    if (this._ws) this.close();
    const ws = new WebSocket(this.url);
    await new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`${this.name}: connect timed out (${this.url})`)),
        REQUEST_TIMEOUT_MS,
      );
      ws.addEventListener('open', () => {
        clearTimeout(timer);
        resolve();
      });
      ws.addEventListener('error', () => {
        clearTimeout(timer);
        reject(new Error(`${this.name}: cannot connect to ${this.url}`));
      });
    });
    this._ws = ws;
    ws.addEventListener('message', (e) => this._onMessage(e.data));
    ws.addEventListener('close', () => {
      if (this._ws === ws) {
        this._ws = null;
        this.info = null;
      }
      for (const p of this._pending.values()) p.reject(new Error(`${this.name}: connection closed`));
      this._pending.clear();
    });
    const sent = Date.now();
    const hello = await this._request('hello', { token: this.token });
    const mid = (sent + Date.now()) / 2;
    this.clockOffsetMs = Date.parse(hello.hostTime) - mid;
    this.info = hello;
    // Buffer every event so tools can wait for things that already happened.
    await this._request('subscribe', { events: ['*'] });
    return hello;
  }

  /** Closes the connection. The host releases everything this agent held. */
  close() {
    const ws = this._ws;
    this._ws = null;
    this.info = null;
    if (ws) ws.close();
  }

  /** Sends one `agent:` request and resolves with the reply (throws on error). */
  async call(op, args = {}) {
    await this.open();
    return this._request(op, args);
  }

  /** Runs one allowlisted command. */
  command(command, args = {}) {
    return this.call('command', { command, args });
  }

  _request(op, args) {
    const ws = this._ws;
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      return Promise.reject(new Error(`${this.name}: not connected`));
    }
    const id = this._nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this._pending.delete(id);
        reject(new Error(`${this.name}: ${op} timed out`));
      }, REQUEST_TIMEOUT_MS);
      this._pending.set(id, {
        resolve: (r) => {
          clearTimeout(timer);
          if (r.ok) resolve(r);
          else reject(new Error(`${this.name}: ${r.error ?? 'request failed'}`));
        },
        reject: (e) => {
          clearTimeout(timer);
          reject(e);
        },
      });
      ws.send('agent:' + JSON.stringify({ id, op, ...args }));
    });
  }

  _onMessage(data) {
    // Binary frames (radio commands, audio) and web UI text are not for us.
    if (typeof data !== 'string' || !data.startsWith('agent:')) return;
    let body;
    try {
      body = JSON.parse(data.slice(6));
    } catch {
      return;
    }
    if (body.event !== undefined) {
      const e = { seq: ++this._seq, received: Date.now(), ...body };
      this.events.push(e);
      if (this.events.length > EVENT_BUFFER) this.events.splice(0, this.events.length - EVENT_BUFFER);
      for (const w of [...this._waiters]) w(e);
      // The operator (or a settings change) stopped agents; the session is gone.
      if (body.event === 'AgentStopped') this.info = null;
      return;
    }
    const p = this._pending.get(body.id);
    if (p) {
      this._pending.delete(body.id);
      p.resolve(body);
    }
  }

  /** Host time (ISO string, UTC) converted to local epoch ms. */
  toLocalMs(hostIso) {
    return Date.parse(hostIso) - this.clockOffsetMs;
  }

  /** Current event cursor: pass it as `after` to wait only for newer events. */
  get cursor() {
    return this._seq;
  }

  /**
   * Buffered events newer than [after] (a cursor), optionally filtered by event
   * name and by text contained in the JSON-encoded data.
   */
  eventsAfter(after = 0, { names, contains, limit = 200 } = {}) {
    const out = this.events.filter((e) => e.seq > after && matches(e, names, contains));
    return out.slice(-limit);
  }

  /**
   * Resolves with the first event after [after] that matches, waiting up to
   * [timeoutMs]. Resolves null on timeout.
   */
  async waitFor({ after = 0, names, contains, timeoutMs = 60000 } = {}) {
    await this.open();
    const hit = this.events.find((e) => e.seq > after && matches(e, names, contains));
    if (hit) return hit;
    return new Promise((resolve) => {
      const done = (value) => {
        clearTimeout(timer);
        this._waiters.delete(waiter);
        resolve(value);
      };
      const waiter = (e) => {
        if (e.seq > after && matches(e, names, contains)) done(e);
      };
      const timer = setTimeout(() => done(null), timeoutMs);
      this._waiters.add(waiter);
    });
  }
}

function matches(e, names, contains) {
  if (names && names.length && !names.includes(e.event)) return false;
  if (contains && !JSON.stringify(e.data ?? '').toLowerCase().includes(contains.toLowerCase())) {
    return false;
  }
  return true;
}

/**
 * Merges the packet captures of [stations] into one timeline ordered by
 * clock-corrected local time. `t` is seconds since the first row.
 */
export async function timeline(stations, { since, limit = 500 } = {}) {
  const rows = [];
  for (const s of stations) {
    const r = await s.call('packets', { ...(since ? { since } : {}), limit });
    for (const p of r.packets) {
      rows.push({ local: s.toLocalMs(p.time), station: s.name, ...p });
    }
  }
  rows.sort((a, b) => a.local - b.local);
  const t0 = rows.length ? rows[0].local : 0;
  return rows.map((r) => ({
    t: Math.round(r.local - t0) / 1000,
    at: new Date(r.local).toISOString(),
    station: r.station,
    dir: r.incoming ? 'RX' : 'TX',
    radio: r.radio,
    channel: r.channel,
    encoding: r.encoding,
    summary: r.summary,
    hex: r.hex,
  }));
}

/**
 * Reads station definitions. Either `HTC_AGENT_CONFIG` pointing at a JSON file
 * `{"stations": {"bbs": {"url": "...", "token": "..."}}}`, or
 * `HTC_STATIONS="bbs=ws://h:8080/websocket.aspx,term=..."` with tokens in
 * `HTC_TOKEN_BBS`, `HTC_TOKEN_TERM`, ...
 */
export async function stationsFromEnv(env = process.env) {
  const out = new Map();
  if (env.HTC_AGENT_CONFIG) {
    const { readFile } = await import('node:fs/promises');
    const cfg = JSON.parse(await readFile(env.HTC_AGENT_CONFIG, 'utf8'));
    for (const [name, s] of Object.entries(cfg.stations ?? {})) {
      out.set(name, new Station(name, s.url, s.token ?? env[tokenVar(name)] ?? ''));
    }
  }
  for (const part of (env.HTC_STATIONS ?? '').split(',')) {
    const i = part.indexOf('=');
    if (i <= 0) continue;
    const name = part.slice(0, i).trim();
    const url = part.slice(i + 1).trim();
    if (name && url) out.set(name, new Station(name, url, env[tokenVar(name)] ?? ''));
  }
  return out;
}

/** Environment variable holding the token for station [name]. */
export function tokenVar(name) {
  return 'HTC_TOKEN_' + name.toUpperCase().replace(/[^A-Z0-9]/g, '_');
}
