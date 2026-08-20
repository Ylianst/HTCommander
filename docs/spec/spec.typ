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
#let version = "0.1.44"
#let tagline = "Multi-platform control software for Amateur Radio handheld transceivers"
#let website = "https://ylianst.github.io/HTCommanderSite/"
#let repo = "https://github.com/Ylianst/HTCommander"
#let doc-date = datetime.today().display("[month repr:long] [day], [year]")

// ---- Theme ------------------------------------------------------------------
#let brand = rgb("#1565c0")
#let brand-dark = rgb("#0d47a1")
#let accent = rgb("#ef6c00")
#let ink = rgb("#212121")
#let muted = rgb("#616161")
#let hairline = rgb("#e0e0e0")
#let panel = rgb("#f5f7fa")

// ---- Page setup -------------------------------------------------------------
#set document(title: product + " Specification", author: "HTCommander Project")
#set text(font: ("Segoe UI", "Helvetica Neue", "Arial"), size: 10pt, fill: ink)
#set par(justify: true, leading: 0.62em)

#set page(
  paper: "a4",
  margin: (x: 1.8cm, top: 2.2cm, bottom: 1.8cm),
  header: context {
    if counter(page).get().first() > 1 [
      #set text(8.5pt, fill: muted)
      #grid(
        columns: (1fr, auto),
        align: (left + horizon, right + horizon),
        [#strong[#short-name] · Specification Sheet],
        [v#version],
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
  v(6pt)
  block(
    width: 100%,
    inset: (y: 5pt),
    stroke: (bottom: 1.5pt + brand),
    text(13pt, weight: "bold", fill: brand-dark, upper(title)),
  )
  v(2pt)
}

#let feature(name, desc) = {
  grid(
    columns: (auto, 1fr),
    column-gutter: 8pt,
    row-gutter: 0pt,
    align: (left + top, left + top),
    text(fill: accent, weight: "bold")[▪],
    [#strong[#name.] #text(fill: muted)[#desc]],
  )
  v(3pt)
}

// Yes / no / partial cell for the support matrix
#let yes = align(center, text(fill: rgb("#2e7d32"), weight: "bold")[●])
#let no = align(center, text(fill: hairline)[○])
#let part = align(center, text(fill: accent, weight: "bold")[◐])

// =============================================================================
// COVER
// =============================================================================
#block(
  width: 100%,
  fill: brand-dark,
  inset: 20pt,
  radius: 6pt,
)[
  #set text(fill: white)
  #grid(
    columns: (auto, 1fr),
    column-gutter: 18pt,
    align: (left + horizon, left + horizon),
    // App icon (falls back gracefully if the file is moved)
    box(
      radius: 12pt,
      clip: true,
      image("/src/assets/images/AppIcon.png", width: 84pt),
    ),
    [
      #text(26pt, weight: "bold")[#product]
      #v(-6pt)
      #text(12pt, fill: rgb("#bbdefb"))[#tagline]
      #v(4pt)
      #text(9.5pt, fill: rgb("#e3f2fd"))[Version #version · #doc-date]
    ],
  )
]

#v(10pt)

#grid(
  columns: (1.35fr, 1fr),
  column-gutter: 16pt,
  [
    #short-name is a free, open-source application that turns your computer or
    phone into a full control console for a range of Bluetooth-capable Amateur
    Radio handheld transceivers. It provides channel programming, digital
    messaging (APRS, Winlink, BBS), mapping, packet capture, file transfer and
    audio features across desktop and mobile platforms.

    #text(fill: muted, size: 9pt)[An Amateur Radio license is required to transmit
    using this software.]
  ],
  block(
    fill: panel,
    inset: 10pt,
    radius: 6pt,
    width: 100%,
    [
      #set text(9pt)
      #strong[At a glance]
      #v(4pt)
      #grid(
        columns: (auto, 1fr),
        row-gutter: 3pt,
        column-gutter: 8pt,
        [License:], [Open Source],
        [Platforms:], [Windows, macOS, Linux, Android, iOS, Web],
        [Connection:], [Bluetooth LE + Audio],
        [Cost:], [Free],
      )
    ],
  ),
)

// =============================================================================
// SUPPORTED HARDWARE
// =============================================================================
#section("Supported Radios")

#short-name supports EchoLink and the following Bluetooth-capable transceivers:

#v(2pt)
#grid(
  columns: (1fr, 1fr, 1fr),
  column-gutter: 10pt,
  row-gutter: 4pt,
  [• BTech UV-Pro], [• Radioddity GA-5WB], [• Vero VR-N75 / VR-N76],
  [• BTech UV-50Pro], [• Radioddity DB50-B Mini], [• Vero VR-N7500 / VR-N7600],
  [• Radtel RT-660], [• EchoLink (network)], [],
)

// =============================================================================
// FEATURES
// =============================================================================
#section("Core Features (all platforms)")

#feature("Channel Programming", "Configure, import, export and drag-and-drop channels to build the ideal configuration for your usage.")
#feature("APRS", "Send and receive APRS messages, set routes, send SMS to phones, request weather reports, and use authenticated messaging.")
#feature("BSS Protocol", "Support for the proprietary short binary message protocol from Baofeng / BTech.")
#feature("APRS Map", "OpenStreetMap-based map showing all nearby APRS stations at a glance.")
#feature("Winlink Mail", "Send and receive email over the Winlink network, including attachments.")
#feature("Address Book", "Store APRS, Winlink and Terminal contacts for quick access.")
#feature("Terminal", "Communicate in packet mode with other stations, users or BBS systems.")
#feature("BBS", "Built-in basic BBS that also acts as a Winlink gateway.")
#feature("Packet Capture", "Capture and decode packets with the built-in capture tool.")
#feature("GPS", "Use the radio's built-in GPS on supported firmware.")
#feature("Torrent File Exchange", "Many-to-many file exchange over 1200 baud FM-AFSK.")

#section("Extended Features")

#grid(
  columns: (1fr, 1fr),
  column-gutter: 16pt,
  [
    #text(10.5pt, weight: "bold", fill: brand-dark)[Desktop + Android]
    #v(3pt)
    #feature("Bluetooth Audio", "Listen and transmit through computer speakers, microphone or headset.")
    #feature("SSTV", "Send and receive images; reception is auto-detected, drag-and-drop to send.")
  ],
  [
    #text(10.5pt, weight: "bold", fill: brand-dark)[Desktop only]
    #v(3pt)
    #feature("Speech-to-Text / Text-to-Speech", "Convert incoming audio to text and typed text to speech.")
    #feature("AGWPE Protocol", "Route other applications' traffic over the radio using AGWPE.")
  ],
)

// =============================================================================
// PLATFORM SUPPORT MATRIX
// =============================================================================
#section("Platform Support Matrix")

#set text(9pt)
#table(
  columns: (2.2fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
  align: (left + horizon, center + horizon, center + horizon, center + horizon, center + horizon, center + horizon, center + horizon),
  stroke: 0.5pt + hairline,
  inset: (x: 6pt, y: 5pt),
  fill: (_, row) => if row == 0 { brand } else if calc.odd(row) { panel } else { white },
  table.header(
    [#text(fill: white, weight: "bold")[Feature]],
    [#text(fill: white, weight: "bold")[Win]],
    [#text(fill: white, weight: "bold")[macOS]],
    [#text(fill: white, weight: "bold")[Linux]],
    [#text(fill: white, weight: "bold")[Android]],
    [#text(fill: white, weight: "bold")[iOS]],
    [#text(fill: white, weight: "bold")[Web]],
  ),
  [Channel Programming], yes, yes, yes, yes, yes, yes,
  [APRS / BSS / Map], yes, yes, yes, yes, yes, yes,
  [Winlink Mail], yes, yes, yes, yes, yes, yes,
  [Terminal / BBS], yes, yes, yes, yes, yes, yes,
  [Packet Capture], yes, yes, yes, yes, yes, yes,
  [Torrent File Exchange], yes, yes, yes, yes, yes, yes,
  [Bluetooth Audio], yes, yes, yes, yes, no, no,
  [SSTV], yes, yes, yes, yes, no, no,
  [Speech-to-Text / TTS], yes, yes, yes, no, no, no,
  [AGWPE Protocol], yes, yes, yes, no, no, no,
)
#v(3pt)
#text(8.5pt, fill: muted)[● Supported #h(10pt) ◐ Partial #h(10pt) ○ Not available]
#set text(10pt)

// =============================================================================
// SYSTEM REQUIREMENTS
// =============================================================================
#section("System Requirements")

#grid(
  columns: (1fr, 1fr, 1fr),
  column-gutter: 12pt,
  row-gutter: 8pt,
  block(fill: panel, inset: 9pt, radius: 6pt, width: 100%, [
    #strong[Windows] \
    #text(9pt)[64-bit Windows 10 / 11 \ Bluetooth LE adapter]
  ]),
  block(fill: panel, inset: 9pt, radius: 6pt, width: 100%, [
    #strong[macOS] \
    #text(9pt)[Universal binary \ Bluetooth LE support]
  ]),
  block(fill: panel, inset: 9pt, radius: 6pt, width: 100%, [
    #strong[Linux] \
    #text(9pt)[x64 / ARM64 \ BlueZ Bluetooth stack]
  ]),
  block(fill: panel, inset: 9pt, radius: 6pt, width: 100%, [
    #strong[Android] \
    #text(9pt)[Android 5.0 or higher \ Bluetooth LE]
  ]),
  block(fill: panel, inset: 9pt, radius: 6pt, width: 100%, [
    #strong[iOS] \
    #text(9pt)[Bluetooth LE support]
  ]),
  block(fill: panel, inset: 9pt, radius: 6pt, width: 100%, [
    #strong[Web] \
    #text(9pt)[Chrome / Edge with \ Web Bluetooth support]
  ]),
)

// =============================================================================
// DISTRIBUTION
// =============================================================================
#section("Availability & Distribution")

#grid(
  columns: (1fr, 1fr),
  column-gutter: 16pt,
  [
    #strong[Desktop packages]
    #v(2pt)
    #set text(9pt)
    - Windows: `.msi` installer (x64)
    - macOS: `.dmg` universal binary
    - Linux x64/ARM64: `.tar.gz`, `.deb`, `.rpm`, `.AppImage`
  ],
  [
    #strong[Mobile & Web]
    #v(2pt)
    #set text(9pt)
    - Android: Google Play or `.apk`
    - Web: browser version (Chrome / Edge)
    - Source & releases on GitHub
  ],
)

#v(8pt)
#block(
  fill: panel,
  inset: 10pt,
  radius: 6pt,
  width: 100%,
  [
    #set text(9pt)
    #grid(
      columns: (auto, 1fr),
      row-gutter: 3pt,
      column-gutter: 8pt,
      [#strong[Website:]], [#website],
      [#strong[Source:]], [#repo],
      [#strong[License:]], [Open Source — see repository LICENSE file],
    )
  ],
)

#v(6pt)
#text(8pt, fill: muted)[
  #short-name is based on the Bluetooth command decoding work by Kyle Husmann
  (KC3SLD) in the BenLink project, the APRS-Parser by Lee (K0QED), and map data
  from OpenStreetMap. Specifications subject to change. This document is
  generated from #repo.
]
