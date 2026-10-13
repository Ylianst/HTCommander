#!/usr/bin/env python3
"""Generate a PowerPoint deck explaining the DART modem protocol.

Content is sourced from the DART design spec (docs/NextGenModem.md), the
implementation report (docs/DART-Implementation-Report.md), the engineering
blog series (docs/blogs/dart-*.md), and the modem source in src/lib/hamlib/.

Run:  python docs/work/build_dart_slides.py
Output: docs/DART-Protocol-Explained.pptx
"""

from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

# ---------------------------------------------------------------------------
# Theme
# ---------------------------------------------------------------------------
BG        = RGBColor(0x0E, 0x14, 0x22)  # deep navy
PANEL     = RGBColor(0x16, 0x20, 0x33)  # slightly lighter panel
ACCENT    = RGBColor(0x37, 0xC8, 0xE8)  # cyan
ACCENT2   = RGBColor(0xF5, 0xB7, 0x41)  # amber
GREEN     = RGBColor(0x5B, 0xD6, 0x8A)
RED       = RGBColor(0xE8, 0x6A, 0x6A)
TEXT      = RGBColor(0xE8, 0xEE, 0xF5)  # near-white
MUTED     = RGBColor(0x9A, 0xA8, 0xBD)  # muted gray-blue
WHITE     = RGBColor(0xFF, 0xFF, 0xFF)

FONT      = "Segoe UI"
MONO      = "Consolas"

SW, SH = Inches(13.333), Inches(7.5)  # 16:9

prs = Presentation()
prs.slide_width  = SW
prs.slide_height = SH
BLANK = prs.slide_layouts[6]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _fill(shape, color):
    shape.fill.solid()
    shape.fill.fore_color.rgb = color
    shape.line.fill.background()


def bg(slide, color=BG):
    r = slide.shapes.add_shape(1, 0, 0, SW, SH)
    _fill(r, color)
    r.shadow.inherit = False
    slide.shapes._spTree.remove(r._element)
    slide.shapes._spTree.insert(2, r._element)
    return r


def rect(slide, x, y, w, h, color, line=None, line_w=None):
    s = slide.shapes.add_shape(1, x, y, w, h)
    _fill(s, color)
    s.shadow.inherit = False
    if line is not None:
        s.line.color.rgb = line
        s.line.width = line_w or Pt(1)
    return s


def txt(slide, x, y, w, h, runs, align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP,
        space_after=6, line_spacing=1.0):
    """runs: list of paragraphs; each paragraph is list of (text, size, color,
    bold, italic, font) tuples."""
    tb = slide.shapes.add_textbox(x, y, w, h)
    tf = tb.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = anchor
    tf.margin_left = tf.margin_right = Inches(0.05)
    tf.margin_top = tf.margin_bottom = Inches(0.02)
    for i, para in enumerate(runs):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.space_after = Pt(space_after)
        p.space_before = Pt(0)
        p.line_spacing = line_spacing
        for (t, size, color, bold, italic, font) in para:
            r = p.add_run()
            r.text = t
            r.font.size = Pt(size)
            r.font.color.rgb = color
            r.font.bold = bold
            r.font.italic = italic
            r.font.name = font
    return tb


def R(t, size=18, color=TEXT, bold=False, italic=False, font=FONT):
    return (t, size, color, bold, italic, font)


def accent_bar(slide, y=Inches(1.28)):
    rect(slide, Inches(0.7), y, Inches(1.6), Pt(4), ACCENT)


def header(slide, kicker, title):
    txt(slide, Inches(0.7), Inches(0.42), Inches(12), Inches(0.4),
        [[R(kicker, 14, ACCENT, True, False, FONT)]])
    txt(slide, Inches(0.7), Inches(0.72), Inches(12), Inches(0.7),
        [[R(title, 30, TEXT, True, False, FONT)]])
    accent_bar(slide)


def page_num(slide, n):
    txt(slide, Inches(12.4), Inches(7.05), Inches(0.8), Inches(0.3),
        [[R(str(n), 11, MUTED, False, False, FONT)]], align=PP_ALIGN.RIGHT)
    txt(slide, Inches(0.7), Inches(7.05), Inches(5), Inches(0.3),
        [[R("DART — Data Adaptive Rate Transport", 11, MUTED, False, False, FONT)]])


def bullets(slide, x, y, w, h, items, size=18, gap=8, lh=1.05):
    """items: list of (level, text, color, bold) or (level, [runs])."""
    tb = slide.shapes.add_textbox(x, y, w, h)
    tf = tb.text_frame
    tf.word_wrap = True
    for i, it in enumerate(items):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.space_after = Pt(gap)
        p.space_before = Pt(0)
        p.line_spacing = lh
        level = it[0]
        p.level = level
        if isinstance(it[1], list):
            for run in it[1]:
                r = p.add_run()
                r.text, r.font.size, r.font.color.rgb = run[0], Pt(run[1]), run[2]
                r.font.bold = run[3] if len(run) > 3 else False
                r.font.name = run[4] if len(run) > 4 else FONT
        else:
            text = it[1]
            color = it[2] if len(it) > 2 else TEXT
            bold = it[3] if len(it) > 3 else False
            bullet = "▸  " if level == 0 else "–  "
            indent = "    " * level
            r = p.add_run()
            r.text = indent + bullet
            r.font.size = Pt(size)
            r.font.color.rgb = ACCENT if level == 0 else MUTED
            r.font.name = FONT
            r2 = p.add_run()
            r2.text = text
            r2.font.size = Pt(size if level == 0 else size - 2)
            r2.font.color.rgb = color
            r2.font.bold = bold
            r2.font.name = FONT
    return tb


def code_block(slide, x, y, w, h, lines, size=14, title=None):
    panel = rect(slide, x, y, w, h, PANEL)
    panel.line.color.rgb = RGBColor(0x2A, 0x38, 0x52)
    panel.line.width = Pt(1)
    ty = y + Inches(0.12)
    if title:
        txt(slide, x + Inches(0.2), ty, w - Inches(0.4), Inches(0.3),
            [[R(title, 13, ACCENT2, True, False, FONT)]])
        ty = ty + Inches(0.36)
    tb = slide.shapes.add_textbox(x + Inches(0.2), ty, w - Inches(0.4), h - (ty - y) - Inches(0.1))
    tf = tb.text_frame
    tf.word_wrap = True
    for i, ln in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.space_after = Pt(2)
        p.line_spacing = 1.0
        if isinstance(ln, tuple):
            text, color = ln
        else:
            text, color = ln, TEXT
        r = p.add_run()
        r.text = text
        r.font.size = Pt(size)
        r.font.name = MONO
        r.font.color.rgb = color
    return panel


def chip(slide, x, y, w, text, color, text_color=None, h=Inches(0.42)):
    c = rect(slide, x, y, w, h, color)
    c.line.fill.background()
    tf = c.text_frame
    tf.word_wrap = True
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    tf.margin_top = tf.margin_bottom = Inches(0.02)
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER
    r = p.add_run()
    r.text = text
    r.font.size = Pt(14)
    r.font.bold = True
    r.font.name = FONT
    r.font.color.rgb = text_color or BG
    return c


def arrow(slide, x, y, w, h, color=ACCENT):
    a = slide.shapes.add_shape(13, x, y, w, h)  # right arrow
    _fill(a, color)
    a.shadow.inherit = False
    return a


def down_arrow(slide, x, y, w, h, color=ACCENT):
    a = slide.shapes.add_shape(36, x, y, w, h)  # down arrow
    _fill(a, color)
    a.shadow.inherit = False
    return a


def table(slide, x, y, w, rows, col_w, header_fill=ACCENT, body_fill=PANEL,
          alt_fill=None, fsize=14, row_h=Inches(0.42), header_color=BG):
    """rows[0] is header. col_w: list of Inches widths summing to w."""
    n_cols = len(rows[0])
    gfx = slide.shapes.add_table(len(rows), n_cols, x, y, w, row_h * len(rows))
    t = gfx.table
    t.first_row = False
    t.horz_banding = False
    for ci, cw in enumerate(col_w):
        t.columns[ci].width = cw
    for ri, row in enumerate(rows):
        t.rows[ri].height = row_h
        for ci, val in enumerate(row):
            cell = t.cell(ri, ci)
            cell.margin_left = Inches(0.08)
            cell.margin_right = Inches(0.06)
            cell.margin_top = Inches(0.02)
            cell.margin_bottom = Inches(0.02)
            cell.vertical_anchor = MSO_ANCHOR.MIDDLE
            if ri == 0:
                cell.fill.solid(); cell.fill.fore_color.rgb = header_fill
            elif alt_fill is not None and ri % 2 == 0:
                cell.fill.solid(); cell.fill.fore_color.rgb = alt_fill
            else:
                cell.fill.solid(); cell.fill.fore_color.rgb = body_fill
            tf = cell.text_frame
            tf.word_wrap = True
            p = tf.paragraphs[0]
            p.alignment = PP_ALIGN.CENTER if ci > 0 else PP_ALIGN.LEFT
            # support colored cell values via tuple (text, color)
            if isinstance(val, tuple):
                text, vcolor = val
            else:
                text, vcolor = val, None
            r = p.add_run()
            r.text = text
            r.font.size = Pt(fsize)
            r.font.name = FONT
            if ri == 0:
                r.font.bold = True
                r.font.color.rgb = header_color
            else:
                r.font.color.rgb = vcolor or TEXT
    return gfx


SLIDE = 0
def new():
    global SLIDE
    SLIDE += 1
    s = prs.slides.add_slide(BLANK)
    bg(s)
    return s


# ===========================================================================
# 1 — TITLE
# ===========================================================================
s = new()
rect(s, 0, 0, SW, Inches(0.16), ACCENT)
txt(s, Inches(0.9), Inches(2.0), Inches(11.5), Inches(0.5),
    [[R("HTCommander  ·  Signal Processing", 16, ACCENT, True, False, FONT)]])
txt(s, Inches(0.9), Inches(2.5), Inches(11.5), Inches(1.4),
    [[R("DART", 72, TEXT, True, False, FONT)],
     [R("Data Adaptive Rate Transport", 30, ACCENT2, False, False, FONT)]])
txt(s, Inches(0.9), Inches(4.4), Inches(11.5), Inches(1.2),
    [[R("A coherent, adaptive OFDM modem for sending data through",
        18, MUTED, False, False, FONT)],
     [R("ordinary FM voice radios over a Bluetooth (SBC) audio link.",
        18, MUTED, False, False, FONT)]])
chip(s, Inches(0.9), Inches(5.7), Inches(2.4), "DFT-spread OFDM", PANEL, ACCENT)
chip(s, Inches(3.5), Inches(5.7), Inches(1.9), "LDPC FEC", PANEL, ACCENT)
chip(s, Inches(5.6), Inches(5.7), Inches(2.7), "Adaptive 1–6 kbps", PANEL, ACCENT)
chip(s, Inches(8.5), Inches(5.7), Inches(2.8), "Validated over the air", PANEL, GREEN)
txt(s, Inches(0.9), Inches(6.7), Inches(11), Inches(0.4),
    [[R("How the protocol works — encoding & decoding pipeline, end to end",
        14, MUTED, False, True, FONT)]])

# ===========================================================================
# 2 — THE PROBLEM
# ===========================================================================
s = new()
header(s, "MOTIVATION", "The problem: data over an FM voice channel")
bullets(s, Inches(0.7), Inches(1.6), Inches(6.2), Inches(5),
    [(0, "Ham handhelds give you a voice channel — not a data port.",),
     (1, "To move data you must encode it as audio the radio will pass.",),
     (0, "Legacy modes are slow.",),
     (1, "AFSK 1200 bps and PSK 2400 bps are the common options.",),
     (0, "The path is genuinely hostile to data.",),
     (1, "FM audio + AGC + limiter + companding distort amplitude & phase.",),
     (1, "On modern radios audio rides a Bluetooth SBC codec — twice.",),
     (0, "Goal: 1–6 kbps that degrades gracefully, not a cliff.",),
    ], size=18, gap=9)
code_block(s, Inches(7.2), Inches(1.6), Inches(5.4), Inches(4.4),
    [("app  ──PCM──▶  Bluetooth SBC  ──▶  radio TX", ACCENT),
     ("                                    │", MUTED),
     ("                                 FM over air", MUTED),
     ("                                    ▼", MUTED),
     ("app  ◀──PCM──  Bluetooth SBC  ◀──  radio RX", ACCENT),
     ("", TEXT),
     ("Every frame crosses the lossy SBC", TEXT),
     ("codec TWICE — once on each hop.", TEXT),
     ("", TEXT),
     ("DART must survive all of it and", ACCENT2),
     ("still verify every byte with a CRC.", ACCENT2)],
    title="The real-world signal chain", size=15)
page_num(s, SLIDE)

# ===========================================================================
# 3 — THE CHANNEL
# ===========================================================================
s = new()
header(s, "CHANNEL MODEL", "What the FM-over-SBC channel actually looks like")
table(s, Inches(0.7), Inches(1.6), Inches(7.2),
      [["Property", "Behavior"],
       ["Sample rate", "32 kHz, 16-bit, mono PCM"],
       ["Usable band", "~400–2600 Hz (flat within ~2 dB)"],
       ["Unusable", "< 300 Hz (AC-coupled), > 3000 Hz (SBC rolloff)"],
       ["Channel type", "Static band-pass — no fading, no multipath"],
       ["Amplitude", "Mildly compressed (AGC + limiter + SBC)"],
       ["Noise floor", "FM noise + SBC quantization; SNR ~20–25 dB"],
       ["Delay spread", "Negligible (< 125 µs)"]],
      col_w=[Inches(2.1), Inches(5.1)], fsize=14, row_h=Inches(0.52),
      alt_fill=RGBColor(0x11, 0x1A, 0x2B))
bullets(s, Inches(8.3), Inches(1.7), Inches(4.4), Inches(4.5),
    [(0, "The channel is STATIC.",),
     (1, "One training preamble is enough to estimate & equalize it.",),
     (1, "No continuous adaptive equalizer needed.",),
     (0, "The real enemy is time-varying phase, not the band shape.",),
     (1, "A static response is removed by the equalizer.",),
     (1, "Carrier phase noise is what limits the dense modes.",),
    ], size=16, gap=10)
page_num(s, SLIDE)

# ===========================================================================
# 4 — DESIGN IDEAS
# ===========================================================================
s = new()
header(s, "DESIGN", "Five ideas that make DART work")
cards = [
    ("DFT-spread OFDM", "Frequency-domain equalization with single-carrier-low PAPR. Puts energy only in the usable 400–2600 Hz band.", ACCENT),
    ("Adaptive rate ladder", "Seven modes (BPSK→16QAM + FSK). Each frame is self-describing, so the link trades speed for robustness on the fly.", ACCENT2),
    ("LDPC forward error correction", "Soft-decision belief-propagation decoding. Four code rates (1/2 → 5/6) matched to the modulation.", GREEN),
    ("Self-describing frames", "A robust mode-0 header lets ANY receiver decode any frame with no prior negotiation — broadcast & monitoring work.", ACCENT),
    ("Constant-envelope fallback", "Mode F (4-FSK) is immune to amplitude distortion — the guaranteed-delivery floor when nothing else survives.", ACCENT2),
]
x0, y0 = Inches(0.7), Inches(1.65)
cw, ch = Inches(3.78), Inches(2.45)
gx, gy = Inches(0.18), Inches(0.22)
for i, (t, d, col) in enumerate(cards):
    col_i = i % 3
    row_i = i // 3
    x = x0 + col_i * (cw + gx)
    y = y0 + row_i * (ch + gy)
    card = rect(s, x, y, cw, ch, PANEL)
    card.line.color.rgb = RGBColor(0x2A, 0x38, 0x52); card.line.width = Pt(1)
    rect(s, x, y, Inches(0.09), ch, col)
    txt(s, x + Inches(0.28), y + Inches(0.22), cw - Inches(0.5), Inches(0.8),
        [[R(f"{i+1}", 26, col, True, False, FONT)]])
    txt(s, x + Inches(0.28), y + Inches(0.78), cw - Inches(0.5), Inches(0.6),
        [[R(t, 17, TEXT, True, False, FONT)]])
    txt(s, x + Inches(0.28), y + Inches(1.32), cw - Inches(0.5), Inches(1.0),
        [[R(d, 13, MUTED, False, False, FONT)]], line_spacing=1.05)
page_num(s, SLIDE)

# ===========================================================================
# 5 — WAVEFORM
# ===========================================================================
s = new()
header(s, "WAVEFORM", "Why DFT-spread OFDM (SC-FDMA)")
bullets(s, Inches(0.7), Inches(1.6), Inches(6.1), Inches(5),
    [(0, "OFDM: many slow subcarriers across the band.",),
     (1, "Turns a frequency-selective channel into flat per-bin gains.",),
     (1, "Equalization is a single complex divide per subcarrier.",),
     (0, "DFT-spread = SC-FDMA precoding.",),
     (1, "Spreads each symbol across all tones before the IFFT.",),
     (1, "Restores single-carrier-like low PAPR → less limiter crush.",),
     (0, "Measured PAPR reduction: ~1.3–2.0 dB vs plain OFDM.",),
     (1, "Headroom against the FM limiter / AGC.",),
    ], size=17, gap=9)
table(s, Inches(7.1), Inches(1.7), Inches(5.5),
      [["Constellation", "Plain OFDM", "SC-FDMA"],
       ["BPSK", "10.5 dB", ("8.5 dB", GREEN)],
       ["QPSK", "10.7 dB", ("8.8 dB", GREEN)],
       ["8PSK", "10.7 dB", ("8.8 dB", GREEN)],
       ["16QAM", "10.6 dB", ("9.3 dB", GREEN)]],
      col_w=[Inches(2.1), Inches(1.7), Inches(1.7)], fsize=15, row_h=Inches(0.5))
txt(s, Inches(7.1), Inches(4.5), Inches(5.5), Inches(1.5),
    [[R("99th-percentile peak-to-average power ratio.", 13, MUTED, False, True, FONT)],
     [R("Lower PAPR = the waveform's peaks are closer to its average, so the radio's limiter clips it less.", 13, MUTED, False, False, FONT)]],
    line_spacing=1.1)
page_num(s, SLIDE)

# ===========================================================================
# 6 — OFDM PARAMETERS
# ===========================================================================
s = new()
header(s, "PARAMETERS", "OFDM physical-layer parameters")
table(s, Inches(0.7), Inches(1.7), Inches(6.0),
      [["Parameter", "Value"],
       ["Sample rate", "32 kHz, 16-bit, mono"],
       ["FFT size", "128"],
       ["Subcarrier spacing", "250 Hz (32 kHz / 128)"],
       ["Active subcarriers", "9  (bins 2–10, ≈500–2600 Hz)"],
       ["Cyclic prefix", "4 samples = 125 µs"],
       ["Guard padding", "256 samples each side (~2 SBC frames)"]],
      col_w=[Inches(2.5), Inches(3.5)], fsize=15, row_h=Inches(0.56),
      alt_fill=RGBColor(0x11, 0x1A, 0x2B))
code_block(s, Inches(7.0), Inches(1.7), Inches(5.6), Inches(4.4),
    [("freq (Hz)   0    500        2600   3000  ...  16000", MUTED),
     ("            │░░░░░│█████████│░░░░░░│                 ", TEXT),
     ("             AC-   9 active    SBC                   ", MUTED),
     ("            coup.  carriers   rolloff                ", MUTED),
     ("", TEXT),
     ("Only 9 FFT bins carry data — exactly the", ACCENT2),
     ("part of the band the radio passes cleanly.", ACCENT2),
     ("", TEXT),
     ("Short CP (125 µs) is a deliberate bet:", TEXT),
     ("FM at these ranges has ~no multipath, so", TEXT),
     ("a long CP would just waste airtime.", TEXT)],
    title="Spectrum occupancy", size=14)
page_num(s, SLIDE)

# ===========================================================================
# 7 — FRAME STRUCTURE
# ===========================================================================
s = new()
header(s, "FRAMING", "Frame structure")
y = Inches(1.7)
segs = [("Guard", Inches(1.4), MUTED, BG),
        ("Zadoff-Chu\npreamble", Inches(2.6), ACCENT, BG),
        ("Header\n(mode 0)", Inches(2.4), ACCENT2, BG),
        ("Payload\n(variable mode)", Inches(4.2), GREEN, BG),
        ("Guard", Inches(1.4), MUTED, BG)]
x = Inches(0.7)
for label, w, col, tc in segs:
    c = rect(s, x, y, w, Inches(1.0), col)
    c.line.color.rgb = BG; c.line.width = Pt(2)
    tf = c.text_frame; tf.word_wrap = True
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE
    p = tf.paragraphs[0]; p.alignment = PP_ALIGN.CENTER
    for j, ln in enumerate(label.split("\n")):
        pp = p if j == 0 else tf.add_paragraph()
        pp.alignment = PP_ALIGN.CENTER
        r = pp.add_run(); r.text = ln; r.font.size = Pt(13)
        r.font.bold = True; r.font.name = FONT; r.font.color.rgb = tc
    x = x + w
bullets(s, Inches(0.7), Inches(3.1), Inches(6.0), Inches(4),
    [(0, [("Preamble  ", 17, ACCENT, True), ("— Zadoff-Chu (root 7, len 127) + 1 channel-estimation symbol. Constant-envelope, same for every mode.", 15, TEXT)]),
     (0, [("Header  ", 17, ACCENT2, True), ("— ALWAYS mode 0 (BPSK R1/2), so any receiver can read it regardless of link quality.", 15, TEXT)]),
     (0, [("Payload  ", 17, GREEN, True), ("— modulated & coded per the mode index in the header.", 15, TEXT)]),
     (0, [("Guard  ", 17, MUTED, True), ("— 256 samples so the SBC filterbank warms up & flushes without corrupting the frame.", 15, TEXT)]),
    ], gap=11)
# header fields
table(s, Inches(7.0), Inches(3.1), Inches(5.6),
      [["Header field", "Bits"],
       ["Mode index (0–5, F)", "4"],
       ["Payload length (bytes)", "12"],
       ["Source callsign (AX.25)", "48"],
       ["Destination callsign", "48"],
       ["Sequence number (ARQ)", "8"],
       ["Flags (ACK/NACK/data/bcast)", "8"],
       ["Header CRC-16", "16"]],
      col_w=[Inches(4.1), Inches(1.5)], fsize=13, row_h=Inches(0.4),
      alt_fill=RGBColor(0x11, 0x1A, 0x2B))
page_num(s, SLIDE)

# ===========================================================================
# 8 — MODE TABLE
# ===========================================================================
s = new()
header(s, "RATE LADDER", "The adaptive mode table")
table(s, Inches(0.7), Inches(1.65), Inches(11.9),
      [["Mode", "Constellation", "LDPC rate", "Bits/sym", "Net throughput", "Role"],
       ["0", "BPSK", "1/2", "1", "~1 kbps", ("most robust", GREEN)],
       ["1", "QPSK", "1/2", "2", "~2 kbps", "robust"],
       ["2", "QPSK", "2/3", "2", "~3 kbps", ("real-link ceiling", ACCENT2)],
       ["3", "8PSK", "2/3", "3", "~4 kbps", "needs ~13 dB SNR"],
       ["4", "16QAM", "3/4", "4", "~5 kbps", "needs ~16 dB SNR"],
       ["5", "16QAM", "5/6", "4", "~6 kbps", "fastest"],
       ["F", "4-CPFSK", "1/2", "~1", "~0.4 kbps", ("constant-envelope floor", RED)]],
      col_w=[Inches(1.0), Inches(2.3), Inches(1.6), Inches(1.4), Inches(2.6), Inches(3.0)],
      fsize=14, row_h=Inches(0.5), alt_fill=RGBColor(0x11, 0x1A, 0x2B))
bullets(s, Inches(0.7), Inches(5.85), Inches(11.9), Inches(1.4),
    [(0, "Modes 0–5 share ONE OFDM modulator/demodulator — only the constellation lookup and LDPC rate change.",),
     (0, "Mode F uses a separate constant-envelope FSK modulator but shares the header, LDPC, interleaver, scrambler, CRC and ARQ.",),
    ], size=15, gap=7)
page_num(s, SLIDE)

# ===========================================================================
# 9 — TX PIPELINE
# ===========================================================================
s = new()
header(s, "ENCODING", "Transmit pipeline — bytes to PCM")
steps = [
    ("Payload bytes", "the AX.25 frame to send", ACCENT),
    ("Append CRC-32", "integrity check over the payload", TEXT),
    ("LDPC encode", "systematic [data | parity], rate per mode", TEXT),
    ("Interleave", "block interleave — break SBC burst errors", TEXT),
    ("Scramble (PN15)", "whiten coded bits → flat spectrum, low PAPR", ACCENT2),
    ("Constellation map", "BPSK / QPSK / 8PSK / 16QAM (Gray-coded)", TEXT),
    ("DFT-spread + OFDM", "SC-FDMA precode → IFFT → cyclic prefix", TEXT),
    ("Assemble frame", "preamble + header + payload + guard", TEXT),
    ("32 kHz PCM out", "to the radio over Bluetooth SBC", GREEN),
]
x = Inches(0.7); y = Inches(1.7)
bw = Inches(3.75); bh = Inches(0.52); gap = Inches(0.055)
for i, (t, d, col) in enumerate(steps):
    col_i = i // 3  # columns of 3? Actually do 3 columns
# Lay out as single vertical flow in left, descriptions right — use 9 rows left col
y = Inches(1.6)
for i, (t, d, col) in enumerate(steps):
    box = rect(s, Inches(0.7), y, Inches(3.9), Inches(0.5),
               PANEL if col == TEXT else RGBColor(0x1C, 0x2A, 0x42))
    box.line.color.rgb = col if col != TEXT else RGBColor(0x2A, 0x38, 0x52)
    box.line.width = Pt(1.25 if col != TEXT else 1)
    txt(s, Inches(0.85), y + Inches(0.02), Inches(3.7), Inches(0.46),
        [[R(f"{i+1}.  ", 15, col if col != TEXT else ACCENT, True, False, FONT),
          R(t, 15, TEXT, True, False, FONT)]], anchor=MSO_ANCHOR.MIDDLE)
    txt(s, Inches(4.9), y + Inches(0.02), Inches(7.6), Inches(0.46),
        [[R(d, 14, MUTED, False, False, FONT)]], anchor=MSO_ANCHOR.MIDDLE)
    if i < len(steps) - 1:
        down_arrow(s, Inches(2.5), y + Inches(0.5), Inches(0.2), gap + Inches(0.02),
                   RGBColor(0x2A, 0x38, 0x52))
    y = y + Inches(0.5) + gap
page_num(s, SLIDE)

# ===========================================================================
# 10 — RX PIPELINE
# ===========================================================================
s = new()
header(s, "DECODING", "Receive pipeline — PCM back to bytes")
steps = [
    ("32 kHz PCM in", "rolling buffer of samples from the radio", ACCENT),
    ("Detect preamble", "Zadoff-Chu correlation → frame start + timing", TEXT),
    ("Estimate channel", "H[k] = Y/X per subcarrier from the preamble", TEXT),
    ("Decode header", "always mode 0 (BPSK R1/2) → mode, length, calls", ACCENT2),
    ("Refine channel", "re-encode header as extra pilots → kills SBC phase err", ACCENT2),
    ("Demodulate payload", "FFT → MMSE equalize → de-spread → pilots track phase", TEXT),
    ("Soft demap (LLRs)", "per-bit log-likelihood ratios", TEXT),
    ("Descramble + deinterleave", "undo PN15 (sign-flip LLRs) + reorder", TEXT),
    ("LDPC soft decode", "min-sum belief propagation, ≤ 50 iterations", TEXT),
    ("CRC-32 check", "verified payload → dispatch as a frame", GREEN),
]
y = Inches(1.55)
for i, (t, d, col) in enumerate(steps):
    box = rect(s, Inches(0.7), y, Inches(4.3), Inches(0.46),
               PANEL if col == TEXT else RGBColor(0x1C, 0x2A, 0x42))
    box.line.color.rgb = col if col != TEXT else RGBColor(0x2A, 0x38, 0x52)
    box.line.width = Pt(1.25 if col != TEXT else 1)
    txt(s, Inches(0.85), y + Inches(0.01), Inches(4.1), Inches(0.44),
        [[R(f"{i+1}.  ", 14, col if col != TEXT else ACCENT, True, False, FONT),
          R(t, 14, TEXT, True, False, FONT)]], anchor=MSO_ANCHOR.MIDDLE)
    txt(s, Inches(5.25), y + Inches(0.01), Inches(7.3), Inches(0.44),
        [[R(d, 13.5, MUTED, False, False, FONT)]], anchor=MSO_ANCHOR.MIDDLE)
    if i < len(steps) - 1:
        down_arrow(s, Inches(2.7), y + Inches(0.46), Inches(0.18), Inches(0.085),
                   RGBColor(0x2A, 0x38, 0x52))
    y = y + Inches(0.46) + Inches(0.065)
page_num(s, SLIDE)

# ===========================================================================
# 11 — LDPC
# ===========================================================================
s = new()
header(s, "FORWARD ERROR CORRECTION", "LDPC — the error-correcting core")
bullets(s, Inches(0.7), Inches(1.6), Inches(6.2), Inches(5),
    [(0, "IEEE 802.11n information-part connections, N = 648.",),
     (0, "Dual-diagonal (IRA accumulator) parity structure.",),
     (1, "O(M) systematic encoding at every rate — always succeeds.",),
     (0, "Soft-input decoder: min-sum belief propagation.",),
     (1, "Input is LLRs: positive → likely 0, negative → likely 1.",),
     (1, "Iterative check/variable-node message passing, ≤ 50 iters.",),
     (1, "0.75 scaling factor on the min-sum approximation.",),
     (0, "Code shortening on short frames (next slide) adds 5+ dB.",),
    ], size=16, gap=8)
table(s, Inches(7.2), Inches(1.8), Inches(5.4),
      [["Rate", "K (info)", "N (coded)", "Modes"],
       ["1/2", "324", "648", "0, 1, F"],
       ["2/3", "432", "648", "2, 3"],
       ["3/4", "486", "648", "4"],
       ["5/6", "540", "648", "5"]],
      col_w=[Inches(1.1), Inches(1.4), Inches(1.5), Inches(1.4)],
      fsize=15, row_h=Inches(0.55))
txt(s, Inches(7.2), Inches(4.7), Inches(5.4), Inches(1.5),
    [[R("Systematic code: the K information bits appear verbatim in the codeword, followed by N−K parity bits.", 14, MUTED, False, False, FONT)]],
    line_spacing=1.15)
page_num(s, SLIDE)

# ===========================================================================
# 12 — SCRAMBLING
# ===========================================================================
s = new()
header(s, "WHITENING", "Scrambling — why the modem randomizes its own bits")
bullets(s, Inches(0.7), Inches(1.6), Inches(6.2), Inches(5),
    [(0, "Repetitive data (a frame of zeros) is poison for QAM.",),
     (1, "Spectral lines, PAPR blows up, constellation collapses.",),
     (1, "Phase/timing recovery starve on a DC-like stream.",),
     (0, "LDPC can't fix it — it's linear.",),
     (1, "All-zero input → all-zero codeword. Interleaver just shuffles zeros.",),
     (0, "So scramble AFTER LDPC + interleave, before the mapper.",),
     (0, "Additive PN15 LFSR, reset per frame.",),
     (1, "x¹⁵ + x¹⁴ + 1, period 32,767 > largest frame's coded bits.",),
     (1, "1 channel error stays 1 error (no multiplication like G3RUH).",),
     (1, "RX descramble = conditional LLR sign-flip — lossless to FEC.",),
    ], size=15, gap=6)
code_block(s, Inches(7.2), Inches(1.7), Inches(5.4), Inches(2.0),
    [("TX:  ... interleave → [SCRAMBLE] → map ...", ACCENT),
     ("RX:  ... soft-demap → [DESCRAMBLE] →", ACCENT),
     ("                         deinterleave ...", ACCENT)],
    title="Where it slots in", size=13)
table(s, Inches(7.2), Inches(4.0), Inches(5.4),
      [["Scrambler", "Error behavior", "Soft FEC"],
       [("Multiplicative", RED), "multiplies ×(taps+1)", "corrupts LLRs"],
       [("Additive (DART)", GREEN), "1 error → 1 error", "clean sign-flip"]],
      col_w=[Inches(1.9), Inches(2.0), Inches(1.5)], fsize=13, row_h=Inches(0.55))
page_num(s, SLIDE)

# ===========================================================================
# 13 — CODE SHORTENING
# ===========================================================================
s = new()
header(s, "RECEIVER TRICK", "Code shortening — free margin on short frames")
bullets(s, Inches(0.7), Inches(1.6), Inches(6.3), Inches(5),
    [(0, "A short message fills only part of a fixed LDPC block.",),
     (1, "The rest is zero-padding — bits whose value we already know.",),
     (0, "Tell the decoder those bits are known (pin their LLRs).",),
     (1, "Known bits become CONSTRAINTS that tighten parity checks.",),
     (1, "The effective code rate collapses → recovers from noisier input.",),
     (0, "Purely a smarter receiver — nothing on air changes.",),
     (1, "Also strengthens the 144-bit header inside its 324-bit block.",),
     (0, "Self-scaling: biggest gain on the shortest frames (ACKs, beacons).",),
    ], size=16, gap=8)
table(s, Inches(7.3), Inches(1.9), Inches(5.3),
      [["16QAM R5/6, 2-byte frame", "Decodes to"],
       ["Without shortening", ("+3 dB SNR", RED)],
       ["With shortening", ("−2 dB SNR", GREEN)]],
      col_w=[Inches(3.3), Inches(2.0)], fsize=15, row_h=Inches(0.6))
txt(s, Inches(7.3), Inches(3.9), Inches(5.3), Inches(2),
    [[R("> 5 dB improvement.", 20, GREEN, True, False, FONT)],
     [R("The failure mode even changes: the LDPC code is no longer the bottleneck — the preamble detector gives out first.", 14, MUTED, False, False, FONT)]],
    line_spacing=1.15, space_after=10)
page_num(s, SLIDE)

# ===========================================================================
# 14 — SYNCHRONIZATION
# ===========================================================================
s = new()
header(s, "SYNC", "Synchronization & channel estimation")
cards = [
    ("Preamble detection", "Cross-correlate against the known Zadoff-Chu sequence. Ideal autocorrelation (zero sidelobes) → a sharp, unambiguous peak marks frame start.", ACCENT),
    ("Frequency offset", "The preamble's repeated halves rotate in phase by Δf·T. The angle between them gives the carrier frequency offset, corrected by a complex de-rotation.", ACCENT2),
    ("Channel estimation", "Divide the received preamble spectrum by the known transmitted one: H[k] = Y[k] / X[k] at every active subcarrier. One shot — the channel is static.", GREEN),
    ("Equalization", "One complex tap per subcarrier. MMSE: X̂ = H*·Y / (|H|² + σ²) — limits noise blow-up on weak subcarriers vs plain zero-forcing.", ACCENT),
]
x0, y0 = Inches(0.7), Inches(1.7)
cw, ch = Inches(5.85), Inches(2.4)
for i, (t, d, col) in enumerate(cards):
    x = x0 + (i % 2) * (cw + Inches(0.3))
    y = y0 + (i // 2) * (ch + Inches(0.25))
    card = rect(s, x, y, cw, ch, PANEL)
    card.line.color.rgb = RGBColor(0x2A, 0x38, 0x52); card.line.width = Pt(1)
    rect(s, x, y, Inches(0.09), ch, col)
    txt(s, x + Inches(0.3), y + Inches(0.22), cw - Inches(0.5), Inches(0.5),
        [[R(t, 19, TEXT, True, False, FONT)]])
    txt(s, x + Inches(0.3), y + Inches(0.78), cw - Inches(0.55), Inches(1.5),
        [[R(d, 15, MUTED, False, False, FONT)]], line_spacing=1.12)
page_num(s, SLIDE)

# ===========================================================================
# 15 — SBC CODEC PROBLEM
# ===========================================================================
s = new()
header(s, "KEY RESULT", "Surviving the Bluetooth SBC codec")
bullets(s, Inches(0.7), Inches(1.6), Inches(6.2), Inches(5),
    [(0, "The single hardest problem: the SBC codec round-trip.",),
     (1, "Left ~29° residual phase error after one channel estimate.",),
     (1, "BPSK tolerated it; QPSK and above failed CRC.",),
     (0, "Fix: decision-directed channel refinement.",),
     (1, "The header always decodes (sent at the most robust mode).",),
     (1, "Re-encode it → treat its 72 OFDM symbols as extra pilots.",),
     (1, "Average Y·conj(X) across them → far better phase estimate.",),
     (0, "Result: every higher-order mode survives the SBC codec.",),
    ], size=16, gap=9)
code_block(s, Inches(7.2), Inches(1.7), Inches(5.4), Inches(4.3),
    [("SBC probe (real UV-Pro hardware):", ACCENT2),
     ("", TEXT),
     ("  group delay ........ ~73 samples", TEXT),
     ("  preamble corr ...... ~0.89 (preserved)", GREEN),
     ("  residual phase ..... 29° → tracked out", GREEN),
     ("", TEXT),
     ("The guard interval absorbs the 73-sample", TEXT),
     ("delay; correlation stays well above the", TEXT),
     ("0.6 detection threshold.", TEXT),
     ("", TEXT),
     ("TX stream raised to bitpool 40 (from 18);", MUTED),
     ("radio→app return path fixed at 18 by", MUTED),
     ("firmware.", MUTED)],
    title="Measured", size=14)
page_num(s, SLIDE)

# ===========================================================================
# 16 — PHASE NOISE & PILOTS
# ===========================================================================
s = new()
header(s, "CHASING THE CEILING", "Phase noise & pilot-aided tracking")
bullets(s, Inches(0.7), Inches(1.6), Inches(6.2), Inches(5),
    [(0, "Over the air, dense modes failed worse than simulation predicted.",),
     (1, "The culprit: time-varying carrier phase noise.",),
     (0, "Two regimes that look identical on an EVM meter:",),
     (1, "Fast (> ~12°/sym): inter-carrier interference — irreducible.",),
     (1, "Slow (drifts across the frame): correctable with pilots.",),
     (0, "Pilots: known symbols every 8 data symbols.",),
     (1, "Give a decision-independent phase reference.",),
     (0, "Measured real link: 0.5–1.6°/symbol → slow regime.",),
     (1, "Pilots recovered QPSK R2/3: +50% throughput (~2 → ~3 kbps).",),
    ], size=15, gap=7)
table(s, Inches(7.3), Inches(1.9), Inches(5.3),
      [["Phase drift", "With pilots", "No pilots"],
       ["~12°/sym (fast)", ("fail", RED), ("fail", RED)],
       ["~5°/sym", ("14.5%", GREEN), "17.0%"],
       ["~2.6°/sym (slow)", ("9.6%", GREEN), "14.5%"]],
      col_w=[Inches(2.1), Inches(1.6), Inches(1.6)], fsize=14, row_h=Inches(0.55))
txt(s, Inches(7.3), Inches(4.3), Inches(5.3), Inches(1.8),
    [[R("16QAM EVM at fixed noise. Pilots win when phase is slow, do nothing when it's fast.", 14, MUTED, False, False, FONT)],
     [R("Remaining 8PSK/16QAM ceiling is raw SNR — a link-budget problem, not DSP.", 14, ACCENT2, False, False, FONT)]],
    line_spacing=1.15, space_after=8)
page_num(s, SLIDE)

# ===========================================================================
# 17 — ISI / CYCLIC PREFIX
# ===========================================================================
s = new()
header(s, "VERIFIED", "Inter-symbol interference & the cyclic prefix")
bullets(s, Inches(0.7), Inches(1.6), Inches(6.2), Inches(5),
    [(0, "The CP is a guard buffer against channel echoes.",),
     (1, "Echo within CP → equalizer folds it in, invisibly.",),
     (1, "Echo beyond CP → energy spills: inter-symbol interference.",),
     (0, "DART's CP is deliberately short: 4 samples = 125 µs.",),
     (0, "Measured: clean knee exactly at the CP boundary.",),
     (1, "EVM roughly doubles the moment an echo exceeds 4 samples.",),
     (0, "Real SBC/audio path adds NO dispersion past the CP.",),
     (1, "Growing the CP through SBC buys nothing — flat 0.4% EVM.",),
     (1, "RF multipath would need a ~37 km path difference to matter.",),
    ], size=15, gap=7)
table(s, Inches(7.3), Inches(1.9), Inches(5.3),
      [["Echo delay", "In time", "EVM"],
       ["4 samples (= CP)", "125 µs", ("4.2%", GREEN)],
       ["5 samples (> CP)", "156 µs", ("7.9%", RED)],
       ["8 samples", "250 µs", ("11.3%", RED)],
       ["16 samples", "500 µs", ("14.9%", RED)]],
      col_w=[Inches(2.0), Inches(1.5), Inches(1.2)], fsize=14, row_h=Inches(0.52))
txt(s, Inches(7.3), Inches(4.9), Inches(5.3), Inches(1.2),
    [[R("Verdict: the short-CP bet was safe. ISI is not a DART limiter.", 15, ACCENT2, True, False, FONT)]],
    line_spacing=1.1)
page_num(s, SLIDE)

# ===========================================================================
# 18 — MODE F
# ===========================================================================
s = new()
header(s, "FALLBACK", "Mode F — the constant-envelope floor")
bullets(s, Inches(0.7), Inches(1.6), Inches(6.2), Inches(5),
    [(0, "For amplitude-hostile radios (hard limiting, companding).",),
     (0, "4-CPFSK: one of four continuous-phase tones per symbol.",),
     (1, "Strictly constant envelope → immune to AGC/limiter/SBC amplitude damage.",),
     (1, "Non-coherent detection — no channel estimate or phase tracking.",),
     (0, "Whole frame (header + payload) is FSK → amplitude-immune end to end.",),
     (0, "Shares LDPC, interleaver, scrambler, CRC and ARQ with the OFDM modes.",),
     (0, "Cost: ~3× longer on air — the bottom rung of the ladder.",),
    ], size=16, gap=9)
table(s, Inches(7.3), Inches(1.9), Inches(5.3),
      [["Parameter", "Value"],
       ["Modulation", "4-CPFSK, 2 bits/sym"],
       ["Symbol rate", "400 symbols/s"],
       ["Tones", "600/1000/1400/1800 Hz"],
       ["FEC", "LDPC rate 1/2"]],
      col_w=[Inches(1.9), Inches(3.4)], fsize=15, row_h=Inches(0.55),
      alt_fill=RGBColor(0x11, 0x1A, 0x2B))
code_block(s, Inches(7.3), Inches(4.6), Inches(5.3), Inches(1.6),
    [("8% hard-clip + SBC + 14 dB SNR:", ACCENT2),
     ("  16QAM modes ...... 0/5  decoded", RED),
     ("  Mode F (4-FSK) ... 5/5  decoded", GREEN)],
    title="When nothing else works", size=14)
page_num(s, SLIDE)

# ===========================================================================
# 19 — LINK LAYER
# ===========================================================================
s = new()
header(s, "LINK LAYER", "Delivery: datagrams, ARQ & rate adaptation")
cards = [
    ("Connectionless datagrams", "Fire-and-forget with the broadcast flag. No ACK. The right model for APRS beacons, group chat, and CQ calls — the packet goes to everyone.", ACCENT),
    ("Connected ARQ", "Sliding send window (default 4 in flight). In-order delivery, ACK per good frame, NACK + selective retransmit of only the lost frame. Keeps the pipe full.", ACCENT2),
    ("Rate adaptation", "Walks the ladder F→0→1→2→3→4→5: up one rung after 3 clean ACKs, down two on any NACK/timeout. Same MCS idea as Wi-Fi, LTE, VARA.", GREEN),
    ("Per-packet metadata", "Every frame records direction, mode, EVM, SNR, preamble correlation, retransmits, CRC — the rows the Flutter packet-capture tab renders.", ACCENT),
]
x0, y0 = Inches(0.7), Inches(1.7)
cw, ch = Inches(5.85), Inches(2.4)
for i, (t, d, col) in enumerate(cards):
    x = x0 + (i % 2) * (cw + Inches(0.3))
    y = y0 + (i // 2) * (ch + Inches(0.25))
    card = rect(s, x, y, cw, ch, PANEL)
    card.line.color.rgb = RGBColor(0x2A, 0x38, 0x52); card.line.width = Pt(1)
    rect(s, x, y, Inches(0.09), ch, col)
    txt(s, x + Inches(0.3), y + Inches(0.22), cw - Inches(0.5), Inches(0.5),
        [[R(t, 19, TEXT, True, False, FONT)]])
    txt(s, x + Inches(0.3), y + Inches(0.78), cw - Inches(0.55), Inches(1.5),
        [[R(d, 15, MUTED, False, False, FONT)]], line_spacing=1.12)
page_num(s, SLIDE)

# ===========================================================================
# 20 — OTA RESULTS
# ===========================================================================
s = new()
header(s, "FIELD RESULTS", "Over the air: two UV-Pro HTs, 50 ft, 2 m / 70 cm")
table(s, Inches(0.7), Inches(1.65), Inches(8.2),
      [["Level", "Mode", "EVM", "SNR", "Phase drift", "CRC"],
       ["0", "BPSK R1/2", "~45%", "~7 dB", "1.6°/sym", ("OK", GREEN)],
       ["1", "QPSK R1/2", "~42%", "~7.5 dB", "1.3°/sym", ("OK", GREEN)],
       ["2", "QPSK R2/3", "~44%", "~7 dB", "1.4°/sym", ("OK", GREEN)],
       ["3", "8PSK R2/3", "~34%", "~9.4 dB", "0.6°/sym", ("fail", RED)],
       ["4", "16QAM R3/4", "~28%", "~11 dB", "0.9°/sym", ("fail", RED)]],
      col_w=[Inches(1.0), Inches(2.1), Inches(1.3), Inches(1.3), Inches(1.6), Inches(0.9)],
      fsize=14, row_h=Inches(0.52), alt_fill=RGBColor(0x11, 0x1A, 0x2B))
bullets(s, Inches(9.2), Inches(1.75), Inches(3.5), Inches(5),
    [(0, "Reliable ceiling: Level 2, ~3 kbps.",),
     (0, "Textbook graceful degradation.",),
     (0, "Phase noise solved by pilots.",),
     (0, "8PSK/16QAM are SNR-limited — a link-budget problem.",),
     (0, "Mode F delivered through an 8% hard-clip channel.",),
    ], size=14, gap=10)
txt(s, Inches(0.7), Inches(5.7), Inches(12), Inches(1.4),
    [[R("Simulation control experiment:  ", 15, ACCENT2, True, False, FONT),
      R("16QAM through simulated SBC + 25 dB noise decoded at 2.9% EVM with zero corrections — ", 15, TEXT, False, False, FONT)],
     [R("proving the over-the-air failure is the radio's phase noise, not the codec or additive noise.", 15, TEXT, False, False, FONT)]],
    line_spacing=1.15)
page_num(s, SLIDE)

# ===========================================================================
# 21 — CODE MAP
# ===========================================================================
s = new()
header(s, "SOURCE MAP", "Where it lives in the code (src/lib/hamlib/)")
files = [
    ("dart_modem.dart", "Full TX/RX chain, frame & header, 6-mode table, channel refinement"),
    ("dart_ofdm.dart", "OFDM + DFT-spread, radix-2 FFT/IFFT, CP, equalizer"),
    ("dart_constellation.dart", "BPSK/QPSK/8PSK/16QAM map & soft-LLR demap; Complex type"),
    ("dart_ldpc.dart", "LDPC encoder + min-sum belief-propagation soft decoder"),
    ("dart_fsk.dart", "Constant-envelope 4-CPFSK modem for Mode F"),
    ("dart_preamble.dart", "Zadoff-Chu preamble: detection, sync, channel estimation"),
    ("dart_link.dart", "Link layer: datagrams, selective-repeat ARQ, rate adaptation"),
    ("dart_packet_info.dart", "Per-packet metadata & signal quality for the capture tab"),
]
y = Inches(1.65)
for i, (f, d) in enumerate(files):
    box = rect(s, Inches(0.7), y, Inches(11.95), Inches(0.56), PANEL if i % 2 else RGBColor(0x14, 0x1E, 0x30))
    box.line.fill.background()
    txt(s, Inches(0.9), y + Inches(0.02), Inches(3.6), Inches(0.52),
        [[R(f, 15, ACCENT, True, False, MONO)]], anchor=MSO_ANCHOR.MIDDLE)
    txt(s, Inches(4.6), y + Inches(0.02), Inches(7.9), Inches(0.52),
        [[R(d, 14, TEXT, False, False, FONT)]], anchor=MSO_ANCHOR.MIDDLE)
    y = y + Inches(0.62)
txt(s, Inches(0.7), y + Inches(0.05), Inches(12), Inches(0.5),
    [[R("Integrated via software_modem.dart (Audio → Software Modem → DART) — rides the same 32 kHz broker flow as AFSK 1200 and PSK 2400.",
        13, MUTED, False, True, FONT)]])
page_num(s, SLIDE)

# ===========================================================================
# 22 — SUMMARY
# ===========================================================================
s = new()
header(s, "SUMMARY", "DART in one slide")
bullets(s, Inches(0.7), Inches(1.6), Inches(6.2), Inches(5),
    [(0, "Adaptive DFT-spread OFDM + LDPC for FM voice radios.",),
     (0, "9 subcarriers in 400–2600 Hz; 32 kHz / 16-bit mono.",),
     (0, "Seven self-describing modes: BPSK → 16QAM, plus 4-FSK floor.",),
     (0, "Robust mode-0 header → any receiver decodes any frame.",),
     (0, "Decision-directed refinement + pilots beat SBC phase noise.",),
     (0, "Scrambling, code shortening, MMSE, short CP — all measured.",),
     (0, "Link layer: datagrams, selective-repeat ARQ, rate ladder.",),
    ], size=16, gap=10)
# right: headline metrics
metrics = [
    ("~3 kbps", "reliable over-the-air ceiling (QPSK R2/3)", GREEN),
    ("6 modes", "all pass encode→SBC→noise→decode in test", ACCENT),
    ("5+ dB", "margin from code shortening on short frames", ACCENT2),
    ("0.5–1.6°/sym", "real-link phase drift — tracked by pilots", ACCENT),
]
y = Inches(1.75)
for val, lbl, col in metrics:
    card = rect(s, Inches(7.2), y, Inches(5.4), Inches(1.05), PANEL)
    card.line.color.rgb = RGBColor(0x2A, 0x38, 0x52); card.line.width = Pt(1)
    rect(s, Inches(7.2), y, Inches(0.09), Inches(1.05), col)
    txt(s, Inches(7.5), y + Inches(0.12), Inches(5), Inches(0.5),
        [[R(val, 24, col, True, False, FONT)]])
    txt(s, Inches(7.5), y + Inches(0.6), Inches(5), Inches(0.4),
        [[R(lbl, 14, MUTED, False, False, FONT)]])
    y = y + Inches(1.2)
page_num(s, SLIDE)


# ---------------------------------------------------------------------------
import os
out = os.path.join(os.path.dirname(__file__), "..", "presentations", "DART-Protocol-Explained.pptx")
out = os.path.abspath(out)
os.makedirs(os.path.dirname(out), exist_ok=True)
prs.save(out)
print(f"Wrote {out} with {SLIDE} slides")
