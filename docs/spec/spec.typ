// =============================================================================
// HTCommander — Product Specification Sheet
// -----------------------------------------------------------------------------
// Edit this file, then rebuild the PDF with:
//     typst compile --root ..\.. spec.typ HTCommander-Spec.pdf
// See README.md in this folder for install/build instructions.
// =============================================================================

// ---- Editable metadata ------------------------------------------------------
#let product = "Handi-Talky Commander"
#let short-name = "HTCommander"
#let tagline = "The complete multi-platform command console for modern Amateur Radio handhelds"
#let website = "https://ylianst.github.io/HTCommanderSite/"
#let repo = "https://github.com/Ylianst/HTCommander"
#let doc-date = datetime.today().display("[month repr:long] [year]")

// ---- Theme ------------------------------------------------------------------
#let brand = rgb("#1565c0")
#let brand-dark = rgb("#0d47a1")
#let accent = rgb("#ef6c00")
#let good = rgb("#2e7d32")
#let ink = rgb("#212121")
#let muted = rgb("#5f6b76")
#let hairline = rgb("#e0e0e0")
#let panel = rgb("#f5f7fa")
#let panel2 = rgb("#eef3fb")

// ---- Page setup -------------------------------------------------------------
#set document(title: product + " Specification", author: "HTCommander Project")
#set text(font: ("Segoe UI", "Arial"), size: 9.7pt, fill: ink)
#set par(justify: true, leading: 0.6em)

#set page(
  paper: "a4",
  margin: (x: 1.7cm, top: 2.1cm, bottom: 1.7cm),
  header: context {
    if counter(page).get().first() > 1 [
      #set text(8.5pt, fill: muted)
      #grid(
        columns: (1fr, auto),
        align: (left + horizon, right + horizon),
        [#strong[#short-name] · Product Specification],
        [#product],
      )
      #line(length: 100%, stroke: 0.5pt + hairline)
    ]
  },
  footer: context {
    if counter(page).get().first() > 1 [
      #set text(8.5pt, fill: muted)
      #line(length: 100%, stroke: 0.5pt + hairline)
      #v(2pt)
      #grid(
        columns: (1fr, auto),
        align: (left + horizon, right + horizon),
        [#website],
        [Page #counter(page).display() of #context counter(page).final().first()],
      )
    ]
  },
)

// ---- Reusable components ----------------------------------------------------
#let section(title) = {
  v(5pt)
  block(
    width: 100%,
    inset: (y: 5pt),
    stroke: (bottom: 1.5pt + brand),
    text(13pt, weight: "bold", fill: brand-dark, upper(title)),
  )
  v(2pt)
}

#let sub(title) = {
  v(3pt)
  text(10.5pt, weight: "bold", fill: brand-dark)[#title]
  v(2pt)
}

// A feature block: bold name, what it does, and a "Benefit" line.
#let feat(name, what, benefit) = {
  block(
    width: 100%,
    breakable: false,
    inset: (left: 2pt),
    [
      #grid(
        columns: (auto, 1fr),
        column-gutter: 7pt,
        text(fill: accent, weight: "bold")[▪],
        [
          #strong[#name.] #what \
          #text(fill: good, size: 8.7pt, weight: "bold")[▸ Benefit: ] #text(fill: muted, size: 8.7pt)[#benefit]
        ],
      )
    ],
  )
  v(3.5pt)
}

// Small highlight card used on the cover page.
#let card(title, body) = block(
  fill: panel,
  inset: 9pt,
  radius: 6pt,
  width: 100%,
  breakable: false,
  [
    #text(9.5pt, weight: "bold", fill: brand-dark)[#title]
    #v(2pt)
    #text(8.7pt, fill: muted)[#body]
  ],
)

// Support-matrix cells
#let yes = align(center, text(fill: good, weight: "bold")[●])
#let no = align(center, text(fill: hairline)[○])
#let part = align(center, text(fill: accent, weight: "bold")[◐])

// =============================================================================
// COVER
// =============================================================================
#let pill(label) = box(
  inset: (x: 7pt, y: 2.5pt),
  radius: 20pt,
  fill: white.transparentize(82%),
  stroke: 0.5pt + white.transparentize(55%),
  text(7.5pt, fill: white, weight: "medium", label),
)

#block(
  width: 100%,
  fill: gradient.linear(brand-dark, brand, rgb("#1e88e5"), angle: 20deg),
  inset: 22pt,
  radius: 10pt,
  clip: true,
)[
  #set text(fill: white)
  // Decorative concentric "signal rings" in the top-right corner.
  #place(top + right, dx: 46pt, dy: -66pt, circle(radius: 86pt, stroke: 8pt + white.transparentize(88%)))
  #place(top + right, dx: 32pt, dy: -44pt, circle(radius: 58pt, stroke: 7pt + white.transparentize(84%)))
  #place(top + right, dx: 18pt, dy: -22pt, circle(radius: 32pt, stroke: 6pt + white.transparentize(80%)))

  #grid(
    columns: (auto, 1fr),
    column-gutter: 20pt,
    align: (left + horizon, left + horizon),
    // App icon on a soft rounded plate for contrast against the gradient.
    box(
      radius: 16pt,
      inset: 5pt,
      fill: white.transparentize(86%),
      box(
        radius: 12pt,
        clip: true,
        image("/src/assets/images/AppIcon.png", width: 82pt),
      ),
    ),
    [
      #text(28pt, weight: "bold")[#product]
      #v(3pt)
      #box(width: 46pt, height: 3pt, radius: 2pt, fill: accent)
      #v(5pt)
      #text(11.5pt, fill: rgb("#dcefff"))[#tagline]
      #v(9pt)
      #pill("Windows") #h(4pt) #pill("macOS") #h(4pt) #pill("Linux") #h(4pt) #pill("Android") #h(4pt) #pill("iOS") #h(4pt) #pill("Web")
      #v(7pt)
      #text(8.5pt, fill: rgb("#bcdcf5"))[Free · Open Source · #doc-date]
    ],
  )
]

#v(9pt)

#grid(
  columns: (1.4fr, 1fr),
  column-gutter: 15pt,
  [
    #short-name turns your computer, tablet or phone into a full control console
    for a range of Bluetooth-capable Amateur Radio handheld transceivers. One
    application replaces a stack of single-purpose tools: channel programming,
    APRS, Winlink email, a packet terminal, a private BBS, mapping, packet
    capture, image (SSTV) and voice transmission, plus experimental
    high-speed data modems — all with a modern, consistent interface across
    six platforms.

    Built for real field conditions, #short-name is #strong[offline-first] and
    #strong[privacy-first]: maps, callsign lookups and speech recognition all
    run locally, and the app sends #strong[no telemetry] to any server.

    #text(fill: muted, size: 8.7pt)[An Amateur Radio license is required to
    transmit using this software.]
  ],
  block(
    fill: panel2,
    inset: 11pt,
    radius: 6pt,
    width: 100%,
    [
      #set text(9pt)
      #text(weight: "bold", fill: brand-dark)[At a glance]
      #v(4pt)
      #grid(
        columns: (auto, 1fr),
        row-gutter: 3.5pt,
        column-gutter: 8pt,
        [License:], [Free & Open Source],
        [Platforms:], [Windows, macOS, Linux, Android, iOS, Web],
        [Link:], [Bluetooth LE control + audio],
        [Messaging:], [APRS, Winlink, BSS, Terminal, BBS],
        [Data:], [AX.25, AGWPE, SSTV, file transfer],
        [Privacy:], [No telemetry · offline-capable],
      )
    ],
  ),
)

#v(8pt)

// ---- Why choose highlights --------------------------------------------------
#block(
  width: 100%,
  inset: (y: 4pt),
  stroke: (bottom: 1.5pt + brand),
  text(12pt, weight: "bold", fill: brand-dark, [WHY CHOOSE HTCOMMANDER]),
)
#v(4pt)

#grid(
  columns: (1fr, 1fr, 1fr),
  column-gutter: 10pt,
  row-gutter: 8pt,
  card("All-in-one console", [Programming, messaging, email, mapping, capture and audio in a single app — no juggling separate utilities.]),
  card("Works six ways", [The same features on Windows, macOS, Linux, Android, iOS and the Web browser.]),
  card("Offline & private", [Local maps, local callsign database and on-device voice recognition. Zero telemetry.]),
  card("Dual-modem reliability", [Hardware and software AFSK modems decode in parallel; the first clean copy wins, no duplicates.]),
  card("Next-gen speed", [The adaptive DART modem targets 1–6 kbps over ordinary FM audio, 3–6× faster than AFSK1200.]),
  card("Secure messaging", [Replay-resistant HMAC-SHA256 authentication for APRS — trust without breaking HAM rules.]),
)

// =============================================================================
// PAGE 2 — MESSAGING & CONNECTIVITY
// =============================================================================
#pagebreak()
#section("Messaging & Digital Communications")

#sub("APRS — Automatic Packet Reporting System")
#feat(
  "APRS Messaging & Telemetry",
  [Send and receive text and position messages with automatic channel monitoring, multi-route digipeater selection and live map integration.],
  [Stay on top of the APRS network while operating on other channels — the app switches frequencies for you.],
)
#feat(
  "APRS-to-SMS Gateway",
  [Relay text messages from your radio to ordinary mobile phones through the APRS network (opt-in registration).],
  [Reach non-licensed family or responders when cellular service is down.],
)
#feat(
  "APRS Weather Reports",
  [Request current conditions for any location on demand, delivered as APRS packets via the WxBot service.],
  [Get field weather with no Internet connection — ideal for events and emergencies.],
)
#feat(
  "APRS Message Authentication",
  [Append a 6-digit HMAC-SHA256 token so recipients can verify sender identity and detect replays; verified messages show in green.],
  [Protect command and emergency traffic from spoofing — authentication only, fully HAM-compliant.],
)

#sub("Email, Terminal & BBS")
#feat(
  "Winlink Email",
  [A full email client for the global Winlink network: compose, send, receive and manage attachments, with automatic gateway frequency switching.],
  [Send and receive real email over radio when the Internet is unreachable.],
)
#feat(
  "Packet Terminal",
  [Direct station-to-station packet sessions over raw AX.25 or APRS frames, with saved connection profiles and per-session channel locking.],
  [Chat operator-to-operator or connect to remote BBS systems — while still monitoring APRS on another frequency.],
)
#feat(
  "Built-in BBS & Winlink Gateway",
  [Host your own private bulletin board with AX.25/APRS/compressed packet support, a text-adventure game and an integrated Winlink relay.],
  [Provide community packet and email services with no external infrastructure.],
)

#sub("Interoperability")
#feat(
  "BSS Protocol (Baofeng / BTech)",
  [Reverse-engineered support for the manufacturer's binary text, location and call-request messages carried in AFSK frames.],
  [Interoperate natively with stock Baofeng radio messaging features.],
)
#feat(
  "AGWPE Protocol Server",
  [A standard AGWPE endpoint (default port 8000) that lets third-party packet applications transmit and receive through your radio.],
  [Reuse the large ecosystem of existing AGWPE-compatible software.],
)
#feat(
  "Channel Programming",
  [Import and export channels in CHIRP CSV format with drag-and-drop reordering in both the app and the radio.],
  [Bulk-manage and share configurations without tedious manual radio programming.],
)

// =============================================================================
// PAGE 3 — MODEM & PROTOCOL TECHNOLOGY
// =============================================================================
#pagebreak()
#section("Modem & Protocol Technology")

#short-name is more than a control app — it includes a full digital signal
processing stack that runs over ordinary FM radio audio, with redundant modems
and an adaptive next-generation waveform.

#sub("Dual & Software Modems")
#feat(
  "Software AFSK 1200 Modem",
  [A pure-software 1200-baud AFSK modem with forward error correction runs alongside the radio's hardware modem, both decoding the same audio stream.],
  [More packets recovered on weak signals; automatic fallback and per-packet diagnostics showing which modem decoded and how many bits were corrected.],
)
#feat(
  "DART Adaptive High-Speed Modem",
  [A DFT-spread OFDM (SC-FDMA) waveform with LDPC coding that adapts its constellation and code rate to channel quality, targeting 1–6 kbps over FM audio.],
  [3–6× the throughput of AFSK1200 on good links, with graceful, automatic degradation — and a constant-envelope fallback mode that survives clipping and amplitude distortion.],
)

#sub("DART Adaptive Mode Table")
#set text(8.6pt)
#table(
  columns: (auto, 1.4fr, 1fr, 1fr, 1.6fr),
  align: (center + horizon, left + horizon, center + horizon, center + horizon, left + horizon),
  stroke: 0.5pt + hairline,
  inset: (x: 6pt, y: 4pt),
  fill: (_, row) => if row == 0 { brand } else if calc.odd(row) { panel } else { white },
  table.header(
    text(fill: white, weight: "bold")[Mode],
    text(fill: white, weight: "bold")[Constellation],
    text(fill: white, weight: "bold")[Code rate],
    text(fill: white, weight: "bold")[Net rate],
    text(fill: white, weight: "bold")[Use],
  ),
  [0], [BPSK], [1/2], [~1 kbps], [Most robust],
  [1], [QPSK], [1/2], [~2 kbps], [Robust],
  [2], [QPSK], [2/3], [~3 kbps], [Reliable OTA ceiling],
  [3], [8PSK], [2/3], [~4 kbps], [Good channels],
  [4], [16QAM], [3/4], [~5 kbps], [Strong signal],
  [5], [16QAM], [5/6], [~6 kbps], [Best case],
  [F], [4-CPFSK], [1/2], [fallback], [Amplitude-immune],
)
#set text(9.7pt)
#v(4pt)

#sub("Signal Processing Highlights")
#grid(
  columns: (1fr, 1fr),
  column-gutter: 14pt,
  row-gutter: 2pt,
  [
    - #strong[Waveform:] DFT-spread OFDM, 128-pt FFT, 250 Hz spacing
    - #strong[Band:] 400–2600 Hz FM audio passband
    - #strong[FEC:] LDPC (rates 1/2–5/6, 802.11n block size)
    - #strong[Sync:] Zadoff-Chu constant-envelope preamble
  ],
  [
    - #strong[Estimation:] decision-directed channel refinement
    - #strong[Tracking:] pilot-aided common-phase-error tracking
    - #strong[Link layer:] selective-repeat ARQ, adaptive rate
    - #strong[Integrity:] CRC-32 payload, CRC-16 header
  ],
)

#v(4pt)
#sub("Supported Protocols & Waveforms")
#set text(8.8pt)
#table(
  columns: (1fr, 1fr),
  align: (left + horizon, left + horizon),
  stroke: 0.5pt + hairline,
  inset: (x: 7pt, y: 4pt),
  fill: (_, row) => if calc.odd(row) { panel } else { white },
  [#strong[Modulation]], [AFSK 1200, PSK 2400, SC-FDMA OFDM (DART), 4-CPFSK],
  [#strong[Packet formats]], [AX.25, APRS, BSS (binary), KISS, AGWPE],
  [#strong[Error correction]], [LDPC (802.11n rates), ECC (AFSK softmodem)],
  [#strong[Constellations]], [BPSK, QPSK, 8PSK, 16QAM, continuous-phase FSK],
  [#strong[Audio codecs]], [PCM reference, Bluetooth SBC (32 kHz / 16-bit mono)],
  [#strong[Security]], [HMAC-SHA256 message authentication (replay-resistant)],
)
#set text(9.7pt)

// =============================================================================
// PAGE 4 — AUDIO, VISUAL, MAPPING, DATA
// =============================================================================
#pagebreak()
#section("Audio, Voice & Visual")

#sub("Voice & Audio")
#feat(
  "Speech-to-Text (Whisper AI)",
  [On-device transcription of received audio using OpenAI Whisper models (tiny to medium), with selectable language hints.],
  [Hands-free logging and net monitoring, fully offline — nothing is sent to a cloud service.],
)
#feat(
  "Text-to-Speech",
  [Type a message and transmit it as synthesized speech directly over the air.],
  [Send clear voice traffic without a microphone; an accessibility aid for all operators.],
)
#feat(
  "Voice Clips",
  [Record, name and level-adjust short audio clips for playback or on-air transmission at any time.],
  [Pre-record callsign IDs, net preambles and standard responses for consistent, effortless repeats.],
)
#feat(
  "Bluetooth Audio & Recording",
  [Two-way audio through your computer or a Bluetooth headset, with live visualization and WAV recording of received traffic.],
  [Hands-free operation plus an archive of important nets for later review.],
)

#sub("Visual Communication")
#feat(
  "SSTV — Slow-Scan Television",
  [Send images (PNG/JPEG/BMP) with drag-and-drop and automatically detect and display incoming pictures; Robot36 and many formats supported.],
  [Exchange photos of conditions, damage or events over VHF/UHF — great for field documentation.],
)

#section("Mapping, Location & Data Tools")

#sub("Mapping & GPS")
#feat(
  "OpenStreetMap with Offline Cache",
  [Plot APRS stations on street/topographic maps; select and cache regions to disk for use without Internet.],
  [Full situational awareness in the field, even with no connectivity — and no location data leaves your device.],
)
#feat(
  "GPS Integration",
  [Show the radio's GPS lock, coordinates and position pin, with one-tap center-on-me (firmware 0.8.5+).],
  [Automatic position beaconing and instant map orientation.],
)

#sub("Analysis & File Transfer")
#feat(
  "Packet Capture & Decode",
  [Capture live TX/RX packets, auto-decode raw → AX.25 → APRS, inspect bits, and export ranges to CSV.],
  [Debug your station, learn protocols from real traffic, and analyze data in external tools.],
)
#feat(
  "Torrent File Exchange (experimental)",
  [Decentralized, many-to-many file distribution over a shared frequency using multicast and peer block trading.],
  [Push large files to multiple stations at once — a novel rapid-response data capability.],
)
#feat(
  "Address Book",
  [Central store of contacts, callsigns, terminal profiles and authentication secrets.],
  [One-click access to frequent contacts and reusable, pre-configured connection profiles.],
)
#feat(
  "Offline Callsign / DXCC Database",
  [Built-in AD1C country-file lookup covering 340+ entities and 7,000+ prefixes, loaded fully in memory.],
  [Instant, Internet-free country identification for DX, logging and network analysis.],
)

// =============================================================================
// PAGE 5 — PLATFORMS, REQUIREMENTS, DISTRIBUTION
// =============================================================================
#pagebreak()
#section("Platform Support Matrix")

#set text(9pt)
#table(
  columns: (2.2fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
  align: (left + horizon, center + horizon, center + horizon, center + horizon, center + horizon, center + horizon, center + horizon),
  stroke: 0.5pt + hairline,
  inset: (x: 6pt, y: 5pt),
  fill: (_, row) => if row == 0 { brand } else if calc.odd(row) { panel } else { white },
  table.header(
    text(fill: white, weight: "bold")[Feature],
    text(fill: white, weight: "bold")[Win],
    text(fill: white, weight: "bold")[macOS],
    text(fill: white, weight: "bold")[Linux],
    text(fill: white, weight: "bold")[Android],
    text(fill: white, weight: "bold")[iOS],
    text(fill: white, weight: "bold")[Web],
  ),
  [Channel Programming], yes, yes, yes, yes, yes, yes,
  [APRS / BSS / Map], yes, yes, yes, yes, yes, yes,
  [Winlink Email], yes, yes, yes, yes, yes, yes,
  [Terminal / BBS], yes, yes, yes, yes, yes, yes,
  [Packet Capture], yes, yes, yes, yes, yes, yes,
  [Torrent File Exchange], yes, yes, yes, yes, yes, yes,
  [Bluetooth Audio & Recording], yes, yes, yes, yes, no, no,
  [SSTV], yes, yes, yes, yes, no, no,
  [Speech-to-Text / TTS], yes, yes, yes, no, no, no,
  [AGWPE Protocol Server], yes, yes, yes, no, no, no,
)
#v(3pt)
#text(8.5pt, fill: muted)[● Supported #h(10pt) ◐ Partial #h(10pt) ○ Not available]
#set text(9.7pt)

#section("Supported Radios")
#grid(
  columns: (1fr, 1fr, 1fr),
  column-gutter: 10pt,
  row-gutter: 4pt,
  [• BTech UV-Pro], [• Radioddity GA-5WB], [• Vero VR-N75 / VR-N76],
  [• BTech UV-50Pro], [• Radioddity DB50-B Mini], [• Vero VR-N7500 / VR-N7600],
  [• Radtel RT-660], [• EchoLink (network)], [],
)
#v(3pt)
#text(8.7pt, fill: muted)[Each radio pairs as two Bluetooth devices — an audio
interface and a control interface — both required for full functionality. Audio
is 32 kHz, 16-bit mono PCM over the SBC codec.]

#section("System Requirements")
#grid(
  columns: (1fr, 1fr, 1fr),
  column-gutter: 12pt,
  row-gutter: 8pt,
  block(fill: panel, inset: 9pt, radius: 6pt, width: 100%, [
    #strong[Windows] \ #text(8.7pt)[64-bit Windows 10 / 11 · Bluetooth LE adapter]
  ]),
  block(fill: panel, inset: 9pt, radius: 6pt, width: 100%, [
    #strong[macOS] \ #text(8.7pt)[Universal binary · Bluetooth LE support]
  ]),
  block(fill: panel, inset: 9pt, radius: 6pt, width: 100%, [
    #strong[Linux] \ #text(8.7pt)[x64 / ARM64 · BlueZ Bluetooth stack]
  ]),
  block(fill: panel, inset: 9pt, radius: 6pt, width: 100%, [
    #strong[Android] \ #text(8.7pt)[Android 5.0 or higher · Bluetooth LE]
  ]),
  block(fill: panel, inset: 9pt, radius: 6pt, width: 100%, [
    #strong[iOS] \ #text(8.7pt)[Bluetooth LE support]
  ]),
  block(fill: panel, inset: 9pt, radius: 6pt, width: 100%, [
    #strong[Web] \ #text(8.7pt)[Chrome / Edge with Web Bluetooth]
  ]),
)
#v(3pt)
#text(8.7pt, fill: muted)[On-device speech recognition benefits from an
AVX-capable CPU. Voice models range from ~78 MB (tiny) to ~1.5 GB (medium).]

#section("Availability & Distribution")
#grid(
  columns: (1fr, 1fr),
  column-gutter: 16pt,
  [
    #strong[Desktop packages] #v(2pt) #set text(8.8pt)
    - Windows: `.msi` installer (x64)
    - macOS: `.dmg` universal binary
    - Linux x64/ARM64: `.tar.gz`, `.deb`, `.rpm`, `.AppImage`
  ],
  [
    #strong[Mobile & Web] #v(2pt) #set text(8.8pt)
    - Android: Google Play or `.apk`
    - Web: in-browser version (Chrome / Edge)
    - Source & releases on GitHub
  ],
)

#v(8pt)
#block(
  fill: panel2,
  inset: 10pt,
  radius: 6pt,
  width: 100%,
  [
    #set text(8.8pt)
    #grid(
      columns: (auto, 1fr),
      row-gutter: 3pt,
      column-gutter: 8pt,
      [#strong[Website:]], [#website],
      [#strong[Source:]], [#repo],
      [#strong[License:]], [Free & Open Source — see repository LICENSE file],
    )
  ],
)

#v(6pt)
#text(8pt, fill: muted)[
  #short-name is based on the Bluetooth command decoding work by Kyle Husmann
  (KC3SLD) in the BenLink project, the APRS-Parser by Lee (K0QED), and map data
  from OpenStreetMap. Country data derived from the AD1C Amateur Radio Country
  Files. Some features are experimental and evolve between releases;
  specifications are subject to change. This document is generated from #repo.
]
