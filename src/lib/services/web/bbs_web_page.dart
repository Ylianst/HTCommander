/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

The single page served by the HTTP BBS server ([BbsWebServer]). The Connect
button prompts for a callsign (remembered in local storage), opens a WebSocket
to `/bbs?callsign=CALL`, and shows the BBS in a
fixed-width terminal with a small / medium / large font size drop-down, a
light / dark theme toggle, a confirmed Clear button and a disconnect button. Server output is plain text
with `\r` line endings; each line typed by the user is sent as one text message.
Server messages starting with \u0001 carry JSON for the page instead: the
session token used for file downloads / uploads, and download requests. The
Upload button posts a file to `/upload` (see BbsWebServer).
*/

/// HTML for the HTTP BBS terminal page.
///
/// `isValidCallsign` must stay in sync with utils/callsign_format.dart.
const String bbsWebPageHtml = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Handy-Talky Commander BBS</title>
<script>
  (function () {
    var t = null;
    try { t = localStorage.getItem('bbsTheme'); } catch (e) {}
    if (t !== 'light' && t !== 'dark') {
      t = window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches
        ? 'light' : 'dark';
    }
    document.documentElement.setAttribute('data-theme', t);
  })();
</script>
<style>
  :root, :root[data-theme="dark"] {
    color-scheme: dark;
    --bg: #101418; --fg: #d8dee4; --muted: #9aa7b2;
    --bar: #1b2229; --bar-border: #2c363f;
    --input-bg: #0d1115; --input-border: #3a4651;
    --btn: #2a3540; --btn-hover: #34424f;
    --menu-bg: #1b2229; --menu-hover: #2a3540;
    --term-bg: #000; --term-fg: #c9f7c9; --term-sent: #79c0ff; --term-info: #d29922;
    --err: #ff7b72; --ok: #56d364;
  }
  :root[data-theme="light"] {
    color-scheme: light;
    --bg: #f6f8fa; --fg: #1f2328; --muted: #59636e;
    --bar: #ffffff; --bar-border: #d0d7de;
    --input-bg: #ffffff; --input-border: #c3cbd3;
    --btn: #f0f2f4; --btn-hover: #e4e8ec;
    --menu-bg: #ffffff; --menu-hover: #eef1f4;
    --term-bg: #ffffff; --term-fg: #1a1f24; --term-sent: #0550ae; --term-info: #9a6700;
    --err: #cf222e; --ok: #1a7f37;
  }
  * { box-sizing: border-box; }
  html, body { height: 100%; margin: 0; }
  body {
    display: flex; flex-direction: column;
    background: var(--bg); color: var(--fg);
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  }
  header {
    display: flex; flex-wrap: wrap; align-items: center; gap: 8px;
    padding: 8px 12px; background: var(--bar); border-bottom: 1px solid var(--bar-border);
  }
  header h1 { font-size: 16px; margin: 0 12px 0 0; white-space: nowrap; }
  .grow { flex: 1; }
  form { display: flex; align-items: center; gap: 8px; margin: 0; }
  input, button {
    font: inherit; font-size: 14px; color: inherit;
    background: var(--input-bg); border: 1px solid var(--input-border); border-radius: 4px;
    padding: 5px 9px;
  }
  input:focus { outline: 2px solid #3b82f6; outline-offset: -1px; }
  input.invalid { border-color: #e5534b; }
  #callsign { width: 9em; text-transform: uppercase; }
  button { background: var(--btn); cursor: pointer; }
  button:hover:not(:disabled) { background: var(--btn-hover); }
  button:disabled { opacity: .5; cursor: default; }
  button.primary, button.primary:hover:not(:disabled) { background: #1f6feb; border-color: #1f6feb; color: #fff; }
  button.danger, button.danger:hover:not(:disabled) { background: #a1312b; border-color: #a1312b; color: #fff; }
  button.subtle {
    background: transparent; border-color: transparent; color: var(--muted);
    font-size: 13px; padding: 4px 8px;
  }
  button.subtle:hover:not(:disabled), button.subtle[aria-expanded="true"] {
    background: var(--btn-hover); color: var(--fg);
  }
  .fontsize { position: relative; }
  .fontsize ul {
    position: absolute; right: 0; top: calc(100% + 4px); z-index: 10;
    list-style: none; margin: 0; padding: 4px 0; min-width: 120px;
    background: var(--menu-bg); border: 1px solid var(--bar-border); border-radius: 6px;
    box-shadow: 0 6px 18px rgba(0, 0, 0, .25);
  }
  .fontsize li {
    padding: 6px 12px 6px 26px; font-size: 13px; cursor: pointer; position: relative;
  }
  .fontsize li:hover, .fontsize li:focus { background: var(--menu-hover); outline: none; }
  .fontsize li[aria-selected="true"]::before { content: "\2713"; position: absolute; left: 9px; }
  #status { font-size: 13px; color: var(--muted); white-space: nowrap; }
  #status.error { color: var(--err); }
  #status.ok { color: var(--ok); }
  #terminal {
    flex: 1; overflow-y: auto; margin: 0; padding: 10px 12px;
    background: var(--term-bg); color: var(--term-fg);
    font-family: "Cascadia Mono", Consolas, "DejaVu Sans Mono", Menlo, monospace;
    white-space: pre-wrap; word-break: break-all; line-height: 1.3;
  }
  #terminal.small { font-size: 12px; }
  #terminal.medium { font-size: 15px; }
  #terminal.large { font-size: 20px; }
  #terminal .sent { color: var(--term-sent); }
  #terminal .info { color: var(--term-info); }
  #inputbar {
    display: flex; gap: 8px; padding: 8px 12px;
    background: var(--bar); border-top: 1px solid var(--bar-border);
  }
  #line { flex: 1; font-family: "Cascadia Mono", Consolas, "DejaVu Sans Mono", Menlo, monospace; }
  #logindlg {
    background: var(--bar); color: var(--fg); padding: 18px 20px;
    border: 1px solid var(--bar-border); border-radius: 8px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, .35); width: min(320px, calc(100vw - 32px));
  }
  #logindlg::backdrop { background: rgba(0, 0, 0, .5); }
  #logindlg form { flex-direction: column; align-items: stretch; gap: 8px; }
  #logindlg h2 { font-size: 16px; margin: 0 0 4px; }
  #logindlg label { font-size: 13px; color: var(--muted); }
  #logindlg #callsign { width: 100%; }
  #logindlg .error { min-height: 1.2em; font-size: 13px; color: var(--err); }
  #logindlg .actions { display: flex; justify-content: flex-end; gap: 8px; }
  [hidden] { display: none !important; }
</style>
</head>
<body>
<header>
  <h1>Handy-Talky Commander BBS<span id="titlecall"></span></h1>
  <span id="status"></span>
  <span class="grow"></span>
  <button id="uploadbtn" type="button" title="Upload a file to the BBS" hidden>Upload</button>
  <input id="uploadfile" type="file" hidden>
  <button id="connect" class="primary" type="button">Connect</button>
  <button id="clearbtn" class="subtle" type="button" title="Clear terminal text">Clear</button>
  <span class="fontsize">
    <button id="sizebtn" class="subtle" type="button" title="Font size"
      aria-haspopup="listbox" aria-expanded="false">Medium &#9662;</button>
    <ul id="sizemenu" role="listbox" aria-label="Font size" hidden>
      <li role="option" tabindex="-1" data-size="small">Small</li>
      <li role="option" tabindex="-1" data-size="medium">Medium</li>
      <li role="option" tabindex="-1" data-size="large">Large</li>
    </ul>
  </span>
  <button id="themebtn" class="subtle" type="button"></button>
</header>
<pre id="terminal" class="medium" aria-live="polite"></pre>
<form id="inputbar" novalidate>
  <input id="line" maxlength="1000" autocomplete="off" spellcheck="false"
    placeholder="Type a command and press Enter" disabled>
  <button id="send" type="submit" disabled>Send</button>
</form>
<dialog id="logindlg" aria-labelledby="logintitle">
  <form id="login" novalidate>
    <h2 id="logintitle">Connect to BBS</h2>
    <label for="callsign">Callsign</label>
    <input id="callsign" maxlength="9" autocomplete="off" autocapitalize="characters"
      spellcheck="false" placeholder="N0CALL" required>
    <div id="loginerr" class="error" aria-live="polite"></div>
    <div class="actions">
      <button id="logincancel" type="button">Cancel</button>
      <button id="loginok" class="primary" type="submit">Connect</button>
    </div>
  </form>
</dialog>
<script>
(function () {
  'use strict';
  var MAX_CHARS = 200000;
  var $ = function (id) { return document.getElementById(id); };
  var terminal = $('terminal'), loginForm = $('login'), callInput = $('callsign');
  var connectBtn = $('connect'), statusEl = $('status'), titleCall = $('titlecall');
  var loginDlg = $('logindlg'), loginErr = $('loginerr'), loginCancel = $('logincancel');
  var inputBar = $('inputbar'), lineInput = $('line'), sendBtn = $('send');
  var socket = null, history = [], historyPos = 0;
  var uploadBtn = $('uploadbtn'), uploadFile = $('uploadfile');
  var fileToken = null, maxUpload = 0;

  function isValidCallsign(value) {
    var call = String(value || '').trim().toUpperCase();
    var m = /^([A-Z0-9]{1,3})[0-9][A-Z]{1,4}(?:-(?:[0-9]|1[0-5]))?$/.exec(call);
    if (!m) return false;
    if (call.split('-')[0].length > 6) return false;
    return /[A-Z]/.test(m[1]);
  }

  function store(key, value) { try { localStorage.setItem(key, value); } catch (e) {} }
  function load(key) { try { return localStorage.getItem(key); } catch (e) { return null; } }

  var sizeBtn = $('sizebtn'), sizeMenu = $('sizemenu'), themeBtn = $('themebtn');
  var sizeItems = sizeMenu.querySelectorAll('li');

  function setSize(size) {
    if (['small', 'medium', 'large'].indexOf(size) < 0) size = 'medium';
    terminal.className = size;
    for (var i = 0; i < sizeItems.length; i++) {
      var on = sizeItems[i].getAttribute('data-size') === size;
      sizeItems[i].setAttribute('aria-selected', on ? 'true' : 'false');
      if (on) sizeBtn.textContent = sizeItems[i].textContent + ' \u25BE';
    }
    store('bbsFontSize', size);
    terminal.scrollTop = terminal.scrollHeight;
  }

  function openSizeMenu(open) {
    sizeMenu.hidden = !open;
    sizeBtn.setAttribute('aria-expanded', open ? 'true' : 'false');
    if (open) {
      sizeMenu.style.left = '';
      sizeMenu.style.right = '';
      if (sizeMenu.getBoundingClientRect().left < 0) {
        sizeMenu.style.left = '0';
        sizeMenu.style.right = 'auto';
      }
      var sel = sizeMenu.querySelector('li[aria-selected="true"]') || sizeItems[0];
      sel.focus();
    }
  }

  function setTheme(theme) {
    if (theme !== 'light') theme = 'dark';
    document.documentElement.setAttribute('data-theme', theme);
    var next = theme === 'dark' ? 'light' : 'dark';
    themeBtn.textContent = theme === 'dark' ? '\u263E' : '\u2600';
    themeBtn.title = 'Switch to ' + next + ' mode';
    themeBtn.setAttribute('aria-label', 'Switch to ' + next + ' mode');
  }

  function setStatus(text, kind) {
    statusEl.textContent = text;
    statusEl.className = kind || '';
  }

  function append(text, cls) {
    var atBottom = terminal.scrollHeight - terminal.scrollTop - terminal.clientHeight < 40;
    var node;
    if (cls) {
      node = document.createElement('span');
      node.className = cls;
      node.textContent = text;
    } else {
      node = document.createTextNode(text);
    }
    terminal.appendChild(node);
    while (terminal.textContent.length > MAX_CHARS && terminal.firstChild) {
      terminal.removeChild(terminal.firstChild);
    }
    if (atBottom) terminal.scrollTop = terminal.scrollHeight;
  }

  // state: 'idle' | 'connecting' | 'connected'
  function setState(state, call) {
    var busy = state !== 'idle';
    connectBtn.textContent = busy ? 'Disconnect' : 'Connect';
    connectBtn.className = busy ? 'danger' : 'primary';
    titleCall.textContent = busy && call ? ' - ' + call : '';
    document.title = 'Handy-Talky Commander BBS' + titleCall.textContent;
    var connected = state === 'connected';
    lineInput.disabled = !connected;
    sendBtn.disabled = !connected;
    if (connected) lineInput.focus();
  }

  function validateCall() {
    var ok = isValidCallsign(callInput.value);
    callInput.classList.toggle('invalid', callInput.value.trim() !== '' && !ok);
    return ok;
  }

  function openLogin() {
    var saved = load('bbsCallsign');
    if (!callInput.value && saved && isValidCallsign(saved)) callInput.value = saved;
    callInput.classList.remove('invalid');
    loginErr.textContent = '';
    if (loginDlg.showModal) loginDlg.showModal(); else loginDlg.setAttribute('open', '');
    callInput.focus();
    callInput.select();
  }

  function closeLogin() {
    if (loginDlg.close) loginDlg.close(); else loginDlg.removeAttribute('open');
  }

  function connect() {
    if (socket) return;
    if (!validateCall()) {
      loginErr.textContent = 'Enter a valid callsign, for example W1AW or VE2ABC-7';
      callInput.focus();
      return;
    }
    var call = callInput.value.trim().toUpperCase();
    callInput.value = call;
    store('bbsCallsign', call);
    closeLogin();
    var url = (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host +
      '/bbs?callsign=' + encodeURIComponent(call);
    var ws;
    try { ws = new WebSocket(url); } catch (e) {
      setStatus('Unable to connect', 'error');
      return;
    }
    socket = ws;
    setState('connecting', call);
    setStatus('Connecting...');
    var opened = false;
    ws.onopen = function () {
      opened = true;
      setStatus('');
      append('*** Connected as ' + call + ' ***\n', 'info');
      setState('connected', call);
    };
    ws.onmessage = function (ev) {
      if (typeof ev.data !== 'string') return;
      if (ev.data.charAt(0) === '\u0001') {
        onControl(ev.data.substring(1));
        return;
      }
      append(ev.data.replace(/\r\n?/g, '\n'));
    };
    ws.onclose = function (ev) {
      if (socket !== ws) return;
      socket = null;
      fileToken = null;
      uploadBtn.hidden = true;
      var reason = ev.reason || (opened ? 'Disconnected' : 'Unable to connect');
      append('*** ' + reason + ' ***\n', 'info');
      setStatus(reason, ev.code === 1000 || ev.code === 1001 ? '' : 'error');
      setState('idle');
    };
  }

  function disconnect() {
    if (!socket) return;
    try { socket.close(1000, 'Disconnected'); } catch (e) {}
  }

  function onControl(text) {
    var msg;
    try { msg = JSON.parse(text); } catch (e) { return; }
    if (!msg || typeof msg !== 'object') return;
    if (msg.t === 'session') {
      fileToken = typeof msg.token === 'string' ? msg.token : null;
      maxUpload = Number(msg.maxUpload) || 0;
      uploadBtn.hidden = !(msg.upload && fileToken);
    } else if (msg.t === 'download' && typeof msg.url === 'string' &&
        msg.url.indexOf('/files/') === 0) {
      var a = document.createElement('a');
      a.href = msg.url;
      a.download = typeof msg.name === 'string' ? msg.name : '';
      a.rel = 'noopener';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
    }
  }

  function kb(bytes) {
    return bytes < 1024 ? bytes + ' bytes' : (bytes / 1024).toFixed(1) + ' KB';
  }

  function upload(file) {
    if (!file || !fileToken) return;
    if (file.size > maxUpload) {
      append('*** ' + file.name + ' is too large (' + kb(file.size) + ', max ' +
        kb(maxUpload) + ') ***\n', 'info');
      return;
    }
    append('*** Uploading ' + file.name + ' (' + kb(file.size) + ')... ***\n', 'info');
    uploadBtn.disabled = true;
    fetch('/upload?token=' + encodeURIComponent(fileToken) +
        '&name=' + encodeURIComponent(file.name), {
      method: 'POST',
      body: file,
      headers: { 'Content-Type': 'application/octet-stream' }
    }).then(function (res) {
      return res.json().catch(function () {
        return { ok: false, message: 'Upload failed (' + res.status + ')' };
      });
    }).then(function (result) {
      // The BBS already reported the outcome in the terminal when notified.
      if (!result.notified) append('*** ' + result.message + ' ***\n', 'info');
    }, function () {
      append('*** Upload failed ***\n', 'info');
    }).then(function () { uploadBtn.disabled = false; });
  }

  uploadBtn.addEventListener('click', function () { uploadFile.click(); });
  uploadFile.addEventListener('change', function () {
    var file = uploadFile.files && uploadFile.files[0];
    uploadFile.value = '';
    upload(file);
  });
  loginForm.addEventListener('submit', function (ev) { ev.preventDefault(); connect(); });
  callInput.addEventListener('input', function () {
    validateCall();
    loginErr.textContent = '';
  });
  loginCancel.addEventListener('click', closeLogin);
  connectBtn.addEventListener('click', function () {
    if (socket) disconnect(); else openLogin();
  });
  $('clearbtn').addEventListener('click', function () {
    if (!window.confirm('Clear all text in the terminal?')) return;
    terminal.textContent = '';
    if (!lineInput.disabled) lineInput.focus();
  });
  inputBar.addEventListener('submit', function (ev) {
    ev.preventDefault();
    if (!socket || socket.readyState !== WebSocket.OPEN) return;
    var text = lineInput.value;
    lineInput.value = '';
    if (text.trim() !== '') {
      history.push(text);
      if (history.length > 50) history.shift();
    }
    historyPos = history.length;
    append(text + '\n', 'sent');
    socket.send(text + '\r');
  });
  lineInput.addEventListener('keydown', function (ev) {
    if (ev.key === 'ArrowUp' && historyPos > 0) {
      historyPos--;
      lineInput.value = history[historyPos];
      ev.preventDefault();
    } else if (ev.key === 'ArrowDown' && historyPos < history.length) {
      historyPos++;
      lineInput.value = historyPos < history.length ? history[historyPos] : '';
      ev.preventDefault();
    }
  });
  sizeBtn.addEventListener('click', function (ev) {
    ev.stopPropagation();
    openSizeMenu(sizeMenu.hidden);
  });
  for (var i = 0; i < sizeItems.length; i++) {
    sizeItems[i].addEventListener('click', function (ev) {
      ev.stopPropagation();
      setSize(this.getAttribute('data-size'));
      openSizeMenu(false);
      sizeBtn.focus();
    });
  }
  sizeMenu.addEventListener('keydown', function (ev) {
    var items = Array.prototype.slice.call(sizeItems);
    var idx = items.indexOf(document.activeElement);
    if (ev.key === 'ArrowDown') {
      items[(idx + 1) % items.length].focus();
    } else if (ev.key === 'ArrowUp') {
      items[(idx - 1 + items.length) % items.length].focus();
    } else if (ev.key === 'Enter' || ev.key === ' ') {
      if (idx >= 0) setSize(items[idx].getAttribute('data-size'));
      openSizeMenu(false);
      sizeBtn.focus();
    } else if (ev.key === 'Escape' || ev.key === 'Tab') {
      openSizeMenu(false);
      if (ev.key === 'Escape') sizeBtn.focus();
      return;
    } else {
      return;
    }
    ev.preventDefault();
  });
  document.addEventListener('click', function (ev) {
    if (!sizeMenu.hidden && !sizeMenu.contains(ev.target)) openSizeMenu(false);
  });
  themeBtn.addEventListener('click', function () {
    var theme = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    setTheme(theme);
    store('bbsTheme', theme);
  });

  setTheme(document.documentElement.getAttribute('data-theme'));
  setSize(load('bbsFontSize') || 'medium');
  setState('idle');
  connectBtn.focus();
})();
</script>
</body>
</html>
''';
