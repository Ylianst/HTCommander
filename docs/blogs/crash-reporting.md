# It Crashed — Now What? How to Report a Crash in HTCommander

*A practical guide for anyone who hit a bug and wants to help fix it. It covers
the fastest way to capture what went wrong — from the built-in Debug tab export
to the on-disk crash log that survives an app that won't even start — on Windows,
macOS, Linux, Android, and iOS, plus exactly what to include so a report is
actionable on the first try.*

---

## Why this matters

A bug report that says *"it crashed"* and a bug report that includes a crash log
are two very different things. The first starts a guessing game; the second often
points straight at the faulting line. HTCommander talks to real radio hardware
over Bluetooth and serial, juggles audio devices, and runs background network
services — there are a lot of moving parts, and the details of *your* machine
matter. The good news: the app is built to hand you those details. This post
shows you where to find them.

There are three ways to get diagnostics out of HTCommander, in rough order of
how broken things are:

1. **The app runs** → file a report straight from the app, or export the Debug
   log.
2. **The app crashes, but launched at least once** → grab the on-disk crash log.
3. **The app won't start at all** → run it from a terminal and/or read the crash
   log the previous launch left behind.

Let's walk through each.

---

## 0. The one-click way: "Report a Crash…"

If the app is running, the fastest path is the built-in reporter. It's in two
places:

- The **About** dialog (**Help → About**) has a **Report a Crash…** button.
- The **Debug** tab menu has a **Report a Crash…** item.

Either one opens your web browser to a **pre-filled GitHub issue** — already
populated with the app version, your platform, and the most recent log lines
(including any crash stack traces). You just describe what you were doing and
click submit.

A few things worth knowing:

- **It uses your own GitHub account.** Nothing is sent by the app itself and
  there's no telemetry or tracking server — the report is only filed when *you*
  press submit on GitHub. If you don't have a GitHub account, use one of the log
  export options below and send the file another way.
- **Please attach the full crash log file.** The pre-filled text only carries the
  *tail* of the log (to keep the link a sane length). The issue text tells you
  exactly where `htcommander_crash.log` lives on your machine — drag-and-drop that
  file into the GitHub issue before submitting so we get the complete stack
  traces.

If you'd rather not use GitHub, read on — everything the button does can be done
by hand.

---

## 1. The app runs: export the Debug log

HTCommander captures its own application log from the moment it launches — you
don't need to have the Debug tab open beforehand for messages to be recorded. It
even writes a startup banner with the version and platform, e.g.
`HTCommander 0.1.31 started on windows`.

To send it to us:

1. Open the **Debug** tab.
2. Click the tab's **menu** (the menu icon at the top-right of the tab).
3. Choose **Save to File…**.
4. Save the `debug_log_YYYY-MM-DD_HHMMSS.txt` file it offers and attach it to your
   report.

Every line is timestamped, and failures are marked `[Error]`, so this is usually
the single most useful thing you can send when the app is still usable.

---

## 2. The on-disk crash log

Some failures happen before there's any UI to click — a bad audio driver, a
missing system library, a crash during startup. For those, HTCommander writes
uncaught errors to a plain-text **crash log file on disk**, independently of the
Debug tab. Even if the window never appears, this file is written as early as the
app can resolve a place to put it.

The file is called **`htcommander_crash.log`** and lives in the platform's
application-support directory:

| Platform | Where to find `htcommander_crash.log` |
|---|---|
| **Windows** | `%APPDATA%\com.example\htcommander\` — paste `%APPDATA%` into the Explorer address bar and open `com.example\htcommander` |
| **macOS** | `~/Library/Application Support/com.meshcentral.htcommander/` — in Finder, use **Go → Go to Folder…** and paste the path |
| **Linux** | `~/.local/share/htcommander/` (or `$XDG_DATA_HOME/htcommander/` if set) |
| **Android** | the app's private support directory (retrievable over `adb`, see below) |
| **iOS** | the app sandbox's Application Support directory (via a device backup or Xcode's device container tools) |

> **Tip (Windows):** the quickest way is to press **Win + R**, type
> `%APPDATA%`, press Enter, then look for the HTCommander folder. Sort by *Date
> modified* to find the most recent `htcommander_crash.log`.

The log rotates automatically once it grows past half a megabyte (the previous
contents move to `htcommander_crash.log.1`), so if a crash just happened, the
newest details are always at the **bottom** of `htcommander_crash.log`. Each
entry is timestamped and, for errors, includes the full stack trace — exactly
what we need.

On **Android**, if you have USB debugging enabled, you can pull the file from a
computer:

```bash
adb exec-out run-as <app.package.id> cat files/htcommander_crash.log > htcommander_crash.log
```

(The package id is on the app's Play/settings page; if `run-as` is blocked on a
release build, use the live-log method in the next section instead.)

---

## 3. The app won't start at all

If double-clicking does nothing, or the window flashes and vanishes, the crash is
happening at launch. Two things help here.

### Read the crash log from the failed launch

Even a launch that never draws a window usually gets far enough to write to
`htcommander_crash.log`. Check the location for your platform in the table above —
the last entries will describe what went wrong. This is the whole point of the
on-disk log: it survives a UI that never appeared.

### Run it from a terminal to capture live output

Running the executable from a terminal keeps the window from closing instantly on
a crash and captures the raw error output the OS would otherwise swallow.

**Windows** (PowerShell, from the folder containing the app's `.exe`):

```powershell
.\htcommander.exe *> htcommander_output.txt
```

The `*>` redirects both normal and error output into a file you can attach.

**macOS / Linux** (from the folder containing the binary):

```bash
./htcommander 2>&1 | tee htcommander_output.txt
```

**Android** (live device log while you reproduce the crash):

```bash
adb logcat -c            # clear the log
adb logcat > logcat.txt  # start capturing, then launch the app and reproduce
```

### Check the OS crash reporter

For a hard native crash (an access violation, a missing DLL), the operating
system often logs it separately:

- **Windows:** open **Event Viewer → Windows Logs → Application** and look for an
  *Application Error* entry naming `htcommander.exe`. Right-click it →
  **Save Selected Events…** and send the `.evtx`. This tells us the faulting
  module and exception code. A very common cause of "won't start" on Windows is a
  missing **Visual C++ Redistributable** or an incomplete extraction of the app
  folder — if you see a `VCRUNTIME140.dll not found`-style dialog, a screenshot of
  it is enough.
- **macOS:** the **Console** app under **Crash Reports** (or *Reports*) will have a
  matching entry you can copy out.

---

## What to include in a good report

You don't need all of this, but the more you include, the faster it gets fixed:

- **What you were doing** when it happened (connecting a radio? starting audio?
  opening a specific tab?), and whether it's repeatable.
- The **crash log file** (`htcommander_crash.log`) and/or the **Debug tab export**.
- The **terminal output** file if the app wouldn't start.
- Your **OS and version** (e.g. "Windows 11 23H2", "macOS 14.5", "Ubuntu 24.04"),
  and the **HTCommander version** (shown in **About**, and in the log's startup
  banner).
- Which **radio** and **connection type** (Bluetooth / USB serial) were in use, if
  relevant.
- A **screenshot** of any error dialog.

File it on the
[GitHub issues page](https://github.com/Ylianst/HTCommander/issues) — the
in-app **Report a Crash…** button (see section 0) opens a pre-filled issue for
you — attach the log(s), and we'll take it from there. Thank you — every log
makes the next release more solid.

---

**Related:** [Building HTCommander from Source](building-from-source.md) ·
[A Complete Protocol Reference](radio-command-protocol.md)
