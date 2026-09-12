/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// Utilities for importing radio channels from CSV files.
///
/// Ported from the C# `ImportUtils.ParseChannelsFromFile` / `ParseChannel1/2/3`
/// methods in `reference/HTCommander/src/Utils/ImportUtils.cs`.
///
/// Three CSV layouts are recognised, matching the C# implementation:
///  1. CHIRP format        (`Location`, `Name`, `Frequency`, `Mode`, ...)
///  2. Native HTCommander   (`title`, `tx_freq`, `rx_freq`, ...)
///  3. Repeater Book format (`Frequency Output`, `Frequency Input`,
///     `Description`, `PL Output Tone`, `PL Input Tone`, `Mode`)
library;

import '../radio/radio_models.dart';

class ChannelImport {
  /// Parses the textual content of a CSV file into a list of channels.
  ///
  /// Returns an empty list if the content is empty, has no recognised header,
  /// or contains no parseable channel rows. Individual rows that fail to parse,
  /// carry an unsupported mode, or have no valid frequency are skipped so a
  /// single bad row (or an unsupported digital channel such as D-STAR/Fusion)
  /// never aborts the whole import.
  static List<RadioChannelInfo> parseChannelsFromCsv(String content) {
    final rows = _parseCsvRows(content);
    if (rows.length < 2) return <RadioChannelInfo>[];

    // Build a header -> column index map from the first row.
    final headerCells = rows.first;
    final headers = <String, int>{};
    for (int i = 0; i < headerCells.length; i++) {
      headers[_removeQuotes(headerCells[i].trim())] = i;
    }

    // Decide which layout this file uses from the header once, up front.
    final isChirp =
        headers.containsKey('Location') &&
        headers.containsKey('Name') &&
        headers.containsKey('Frequency') &&
        headers.containsKey('Mode');
    final isNative =
        headers.containsKey('title') &&
        headers.containsKey('tx_freq') &&
        headers.containsKey('rx_freq');
    final isRepeaterBook =
        headers.containsKey('Frequency Output') &&
        headers.containsKey('Frequency Input') &&
        headers.containsKey('Description') &&
        headers.containsKey('PL Output Tone') &&
        headers.containsKey('PL Input Tone') &&
        headers.containsKey('Mode');

    if (!isChirp && !isNative && !isRepeaterBook) {
      return <RadioChannelInfo>[];
    }

    final result = <RadioChannelInfo>[];
    for (int i = 1; i < rows.length; i++) {
      final parts = rows[i];
      // Skip blank lines (a lone empty field or an entirely empty row).
      if (parts.every((c) => c.trim().isEmpty)) continue;
      try {
        RadioChannelInfo? c;
        if (isChirp) {
          c = _parseChannel1(parts, headers);
        } else if (isNative) {
          c = _parseChannel2(parts, headers);
        } else {
          c = _parseChannel3(parts, headers);
        }
        if (c != null) result.add(c);
      } catch (_) {
        // Skip malformed rows rather than failing the whole import.
      }
    }

    return result;
  }

  /// Splits raw CSV text into rows of fields.
  ///
  /// Unlike a naive `split(',')` this understands the parts of the CSV spec
  /// that appear in real CHIRP / spreadsheet exports and previously caused
  /// whole files (or individual channels) to fail to import:
  ///  * a leading UTF-8 byte-order mark (Excel/Notepad add one), which would
  ///    otherwise corrupt the first header cell so no format is recognised;
  ///  * quoted fields containing the delimiter or line breaks
  ///    (e.g. a `"Name, with comma"` cell), with `""` as an escaped quote;
  ///  * `,`, `;` or tab delimiters (spreadsheets re-save with `;` in some
  ///    locales);
  ///  * `\n`, `\r\n` and lone `\r` line endings.
  static List<List<String>> _parseCsvRows(String content) {
    // Strip a leading UTF-8 BOM if present.
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1);
    }

    final delimiter = _detectDelimiter(content);
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < content.length; i++) {
      final ch = content[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < content.length && content[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == delimiter) {
        row.add(field.toString());
        field.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < content.length && content[i + 1] == '\n') {
          i++;
        }
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else {
        field.write(ch);
      }
    }

    // Flush any trailing field / row not terminated by a line break.
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }

    return rows;
  }

  /// Picks the field delimiter from the header line, counting characters that
  /// appear outside quotes. Defaults to a comma (the CHIRP standard).
  static String _detectDelimiter(String content) {
    final end = content.indexOf('\n');
    final firstLine = end == -1 ? content : content.substring(0, end);
    int commas = 0, semicolons = 0, tabs = 0;
    bool inQuotes = false;
    for (int i = 0; i < firstLine.length; i++) {
      final ch = firstLine[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes) {
        if (ch == ',') {
          commas++;
        } else if (ch == ';') {
          semicolons++;
        } else if (ch == '\t') {
          tabs++;
        }
      }
    }
    if (semicolons > commas && semicolons >= tabs) return ';';
    if (tabs > commas && tabs > semicolons) return '\t';
    return ',';
  }

  // --- Format 1: CHIRP -------------------------------------------------------

  static RadioChannelInfo? _parseChannel1(
    List<String> parts,
    Map<String, int> headers,
  ) {
    final name = _getValue(parts, headers, 'Name');
    final rxFreqMHz = _tryParseDouble(_getValue(parts, headers, 'Frequency'));
    final rxFreq = rxFreqMHz != null ? (rxFreqMHz * 1000000).round() : 0;
    // An empty or unparseable frequency means the row has no usable channel.
    if (rxFreq <= 0) return null;

    // --- Power level ---
    bool txAtMaxPower = true; // Default to High
    bool txAtMedPower = false;
    final powerStr = _getValue(parts, headers, 'Power');
    if (powerStr.isNotEmpty && powerStr.toUpperCase().endsWith('W')) {
      final watts = _tryParseDouble(powerStr.substring(0, powerStr.length - 1));
      if (watts != null) {
        if (watts <= 1.0) {
          txAtMaxPower = false;
          txAtMedPower = false; // Low
        } else if (watts <= 4.0) {
          txAtMaxPower = false;
          txAtMedPower = true; // Medium
        } else {
          txAtMaxPower = true;
          txAtMedPower = false; // High
        }
      }
    }

    // --- Frequency: duplex / offset / split ---
    int txFreq;
    bool txDisable = false;
    final duplex = _getValue(parts, headers, 'Duplex');
    final offsetMHz = _tryParseDouble(_getValue(parts, headers, 'Offset'));
    final dup = duplex.toLowerCase();
    if (dup == 'split' && offsetMHz != null) {
      // 'Split' means the Offset column is the TX frequency in MHz.
      txFreq = (offsetMHz * 1000000).round();
    } else if ((duplex == '+' || duplex == '-') && offsetMHz != null) {
      final offsetHz = (offsetMHz * 1000000).round();
      txFreq = rxFreq + ((duplex == '+' ? 1 : -1) * offsetHz);
    } else if (dup == 'off') {
      // Receive-only channel: keep the RX frequency but disable transmit.
      txFreq = rxFreq;
      txDisable = true;
    } else {
      txFreq = rxFreq; // Simplex or missing duplex info.
    }

    // --- Tone / sub-audio ---
    int rxSubAudio = 0;
    int txSubAudio = 0;
    final toneMode = _getValue(parts, headers, 'Tone');
    final rToneFreq = _tryParseDouble(_getValue(parts, headers, 'rToneFreq'));
    final cToneFreq = _tryParseDouble(_getValue(parts, headers, 'cToneFreq'));
    final rToneFreqValue = rToneFreq != null ? (rToneFreq * 100).round() : 0;
    final cToneFreqValue = cToneFreq != null ? (cToneFreq * 100).round() : 0;
    final dtcsCode = _tryParseInt(_getValue(parts, headers, 'DtcsCode'));
    final rxDtcsCode = _tryParseInt(_getValue(parts, headers, 'RxDtcsCode'));
    final crossMode = _getValue(parts, headers, 'CrossMode');

    final tone = toneMode.toLowerCase();
    if (tone == 'tone') {
      txSubAudio = rToneFreqValue;
      rxSubAudio = 0;
    } else if (tone == 'tsql') {
      txSubAudio = cToneFreqValue;
      rxSubAudio = cToneFreqValue;
    } else if (tone == 'dtcs') {
      if (dtcsCode != null) {
        txSubAudio = dtcsCode;
        rxSubAudio = dtcsCode;
      }
    } else if (tone == 'cross') {
      switch (crossMode.toLowerCase()) {
        case 'tone->tone':
          txSubAudio = rToneFreqValue;
          rxSubAudio = cToneFreqValue;
          break;
        case 'tone->':
          txSubAudio = 0;
          rxSubAudio = rToneFreqValue;
          break;
        case '->tone':
          txSubAudio = cToneFreqValue;
          rxSubAudio = 0;
          break;
        case 'dtcs->dtcs':
          if (dtcsCode != null) txSubAudio = dtcsCode;
          if (rxDtcsCode != null) rxSubAudio = rxDtcsCode;
          break;
        case 'tone->dtcs':
          txSubAudio = rToneFreqValue;
          if (rxDtcsCode != null) rxSubAudio = rxDtcsCode;
          break;
        case 'dtcs->tone':
          if (dtcsCode != null) txSubAudio = dtcsCode;
          rxSubAudio = cToneFreqValue;
          break;
        case 'dtcs->':
          if (dtcsCode != null) txSubAudio = dtcsCode;
          rxSubAudio = 0;
          break;
        case '->dtcs':
          txSubAudio = 0;
          if (rxDtcsCode != null) rxSubAudio = rxDtcsCode;
          break;
      }
    }

    // --- Mode and bandwidth ---
    // Only analog modes the radio can actually store are accepted. Digital or
    // broadcast modes that a CHIRP CSV can name but this radio can't program
    // (DMR, WFM broadcast, DV/D-STAR, DN/Fusion, P25, NXDN, ...) are skipped so
    // the rest of the file still imports.
    RadioModulationType mod;
    RadioBandwidthType bandwidth;
    final mode = _getValue(parts, headers, 'Mode').toUpperCase();
    switch (mode) {
      case 'FM':
        mod = RadioModulationType.fm;
        bandwidth = RadioBandwidthType.wide;
        break;
      case 'NFM':
      case 'FMN':
        mod = RadioModulationType.fm;
        bandwidth = RadioBandwidthType.narrow;
        break;
      case 'AM':
        mod = RadioModulationType.am;
        bandwidth = RadioBandwidthType.wide;
        break;
      default:
        return null;
    }

    return RadioChannelInfo(
      channelId: 0,
      name: _clampName(name),
      rxFreq: rxFreq,
      txFreq: txFreq,
      rxMod: mod,
      txMod: mod,
      rxSubAudio: rxSubAudio,
      txSubAudio: txSubAudio,
      bandwidth: bandwidth,
      txAtMaxPower: txAtMaxPower,
      txAtMedPower: txAtMedPower,
      txDisable: txDisable,
    );
  }

  // --- Format 2: Native HTCommander -----------------------------------------

  static RadioChannelInfo? _parseChannel2(
    List<String> parts,
    Map<String, int> headers,
  ) {
    final name = _getValue(parts, headers, 'title');
    final txFreq = _tryParseInt(_getValue(parts, headers, 'tx_freq')) ?? 0;
    final rxFreq = _tryParseInt(_getValue(parts, headers, 'rx_freq')) ?? 0;
    final txSubAudio =
        _tryParseInt(
          _getValue(parts, headers, 'tx_sub_audio(CTCSS=freq/DCS=number)'),
        ) ??
        0;
    final rxSubAudio =
        _tryParseInt(
          _getValue(parts, headers, 'rx_sub_audio(CTCSS=freq/DCS=number)'),
        ) ??
        0;

    final power = _getValue(parts, headers, 'tx_power(H/M/L)');
    final txAtMaxPower = power == 'H';
    final txAtMedPower = power == 'M';

    final bandwidth =
        _getValue(parts, headers, 'bandwidth(12500/25000)') == '25000'
        ? RadioBandwidthType.wide
        : RadioBandwidthType.narrow;
    final scan = _getValue(parts, headers, 'scan(0=OFF/1=ON)') == '1';
    final talkAround =
        _getValue(parts, headers, 'talk around(0=OFF/1=ON)') == '1';
    final preDeEmphBypass =
        _getValue(parts, headers, 'pre_de_emph_bypass(0=OFF/1=ON)') == '1';
    final sign = _getValue(parts, headers, 'sign(0=OFF/1=ON)') == '1';
    final txDisable = _getValue(parts, headers, 'tx_dis(0=OFF/1=ON)') == '1';
    final mute = _getValue(parts, headers, 'mute(0=OFF/1=ON)') == '1';

    final rxMod = _parseNativeMod(
      _getValue(parts, headers, 'rx_modulation(0=FM/1=AM)'),
    );
    final txMod = _parseNativeMod(
      _getValue(parts, headers, 'tx_modulation(0=FM/1=AM)'),
    );

    return RadioChannelInfo(
      channelId: 0,
      name: _clampName(name),
      txFreq: txFreq,
      rxFreq: rxFreq,
      txSubAudio: txSubAudio,
      rxSubAudio: rxSubAudio,
      txAtMaxPower: txAtMaxPower,
      txAtMedPower: txAtMedPower,
      bandwidth: bandwidth,
      scan: scan,
      talkAround: talkAround,
      preDeEmphBypass: preDeEmphBypass,
      sign: sign,
      txDisable: txDisable,
      mute: mute,
      rxMod: rxMod,
      txMod: txMod,
    );
  }

  static RadioModulationType _parseNativeMod(String value) {
    switch (value) {
      case 'AM':
        return RadioModulationType.am;
      case 'DMR':
        return RadioModulationType.dmr;
      case 'FM':
      case 'FO':
        return RadioModulationType.fm;
    }
    // The native export writes the modulation index (0=FM/1=AM/2=DMR).
    final index = _tryParseInt(value);
    if (index != null &&
        index >= 0 &&
        index < RadioModulationType.values.length) {
      return RadioModulationType.values[index];
    }
    return RadioModulationType.fm;
  }

  // --- Format 3: Repeater Book -----------------------------------------------

  static RadioChannelInfo? _parseChannel3(
    List<String> parts,
    Map<String, int> headers,
  ) {
    for (int i = 0; i < parts.length; i++) {
      parts[i] = _removeQuotes(parts[i].trim());
    }

    final name = _clampName(_getValue(parts, headers, 'Description'));

    final rxFreqMHz = _tryParseDouble(
      _getValue(parts, headers, 'Frequency Input'),
    );
    int rxFreq = rxFreqMHz != null ? (rxFreqMHz * 1000000).round() : 0;
    final txFreqMHz = _tryParseDouble(
      _getValue(parts, headers, 'Frequency Output'),
    );
    int txFreq = txFreqMHz != null ? (txFreqMHz * 1000000).round() : 0;
    if (rxFreq == 0) rxFreq = txFreq;
    if (txFreq == 0) txFreq = rxFreq;
    if (rxFreq == 0 && txFreq == 0) return null;

    RadioModulationType mod;
    RadioBandwidthType bandwidth;
    final modeStr = _getValue(parts, headers, 'Mode');
    if (modeStr == 'AM') {
      mod = RadioModulationType.am;
      bandwidth = RadioBandwidthType.wide;
    } else if (modeStr == 'FM') {
      mod = RadioModulationType.fm;
      bandwidth = RadioBandwidthType.wide;
    } else if (modeStr == 'FMN') {
      mod = RadioModulationType.fm;
      bandwidth = RadioBandwidthType.narrow;
    } else {
      return null;
    }

    String rxSub = _getValue(parts, headers, 'PL Output Tone');
    String txSub = _getValue(parts, headers, 'PL Input Tone');
    if (txSub.isEmpty) txSub = rxSub;
    if (rxSub.isEmpty) rxSub = txSub;

    int rxSubAudio = 0;
    int txSubAudio = 0;
    if (rxSub.endsWith(' PL')) {
      final v = _tryParseDouble(rxSub.substring(0, rxSub.length - 3));
      rxSubAudio = v != null ? (v * 100).round() : 0;
    }
    if (txSub.endsWith(' PL')) {
      final v = _tryParseDouble(txSub.substring(0, txSub.length - 3));
      txSubAudio = v != null ? (v * 100).round() : 0;
    }

    return RadioChannelInfo(
      channelId: 0,
      name: name,
      rxFreq: rxFreq,
      txFreq: txFreq,
      rxMod: mod,
      txMod: mod,
      rxSubAudio: rxSubAudio,
      txSubAudio: txSubAudio,
      bandwidth: bandwidth,
      txAtMaxPower: true,
      txAtMedPower: false,
    );
  }

  // --- Helpers ---------------------------------------------------------------

  /// Returns the trimmed, de-quoted value for [key], or '' if the column is
  /// missing or out of range.
  static String _getValue(
    List<String> parts,
    Map<String, int> headers,
    String key,
  ) {
    final index = headers[key];
    if (index == null || index < 0 || index >= parts.length) return '';
    return _removeQuotes(parts[index].trim());
  }

  /// Removes a single pair of surrounding double quotes, if present.
  static String _removeQuotes(String value) {
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  static double? _tryParseDouble(String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    final d = double.tryParse(v);
    if (d != null) return d;
    // Fallback for spreadsheets re-saved in locales that use a decimal comma
    // (e.g. "443,100000"), which pairs with the ';' delimiter handled above.
    if (v.contains(',') && !v.contains('.')) {
      return double.tryParse(v.replaceAll(',', '.'));
    }
    return null;
  }

  static int? _tryParseInt(String value) {
    if (value.isEmpty) return null;
    return int.tryParse(value.trim());
  }

  /// Channel names are limited to 10 characters on the radio.
  static String _clampName(String name) {
    if (name.length > 10) return name.substring(0, 10);
    return name;
  }
}
