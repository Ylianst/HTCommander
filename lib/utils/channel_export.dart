/// Utilities for exporting radio channels to CSV files.
///
/// Ported from the C# `ImportUtils` export methods in
/// `reference/HTCommander/src/Utils/ImportUtils.cs`.
///
/// Channels are provided as the JSON maps stored in the DataBroker under the
/// `Channels` key (see `RadioChannelInfo.toJson` in `radio/radio_models.dart`).
library;

/// Supported export file formats.
enum ChannelExportFormat { native, chirp }

class ChannelExport {
  /// Helpers to read fields from a channel JSON map, tolerant of the legacy
  /// snake_case keys used by the native CSV format.
  static int _txFreq(Map m) => (m['txFreq'] ?? m['tx_freq'] ?? 0) as int;
  static int _rxFreq(Map m) => (m['rxFreq'] ?? m['rx_freq'] ?? 0) as int;
  static int _txSubAudio(Map m) =>
      (m['txSubAudio'] ?? m['tx_sub_audio'] ?? 0) as int;
  static int _rxSubAudio(Map m) =>
      (m['rxSubAudio'] ?? m['rx_sub_audio'] ?? 0) as int;
  static bool _txAtMaxPower(Map m) => (m['txAtMaxPower'] ?? false) as bool;
  static bool _txAtMedPower(Map m) => (m['txAtMedPower'] ?? false) as bool;
  static bool _scan(Map m) => (m['scan'] ?? false) as bool;
  static bool _talkAround(Map m) => (m['talkAround'] ?? false) as bool;
  static bool _preDeEmphBypass(Map m) =>
      (m['preDeEmphBypass'] ?? false) as bool;
  static bool _sign(Map m) => (m['sign'] ?? false) as bool;
  static bool _txDisable(Map m) =>
      (m['txDisable'] ?? m['tx_disable'] ?? false) as bool;
  static bool _mute(Map m) => (m['mute'] ?? false) as bool;
  static String _name(Map m) => (m['name'] ?? m['name_str'] ?? '') as String;

  /// 1 = wide, 0 = narrow.
  static bool _isWide(Map m) => (m['bandwidth'] ?? 0) == 1;
  static int _rxMod(Map m) => (m['rxMod'] ?? 0) as int;
  static int _txMod(Map m) => (m['txMod'] ?? 0) as int;

  /// Exports channels to native HTCommander CSV format.
  static String exportToNativeFormat(List<Map<String, dynamic>> channels) {
    final sb = StringBuffer();
    sb.writeln(
      'title,tx_freq,rx_freq,tx_sub_audio(CTCSS=freq/DCS=number),'
      'rx_sub_audio(CTCSS=freq/DCS=number),tx_power(H/M/L),'
      'bandwidth(12500/25000),scan(0=OFF/1=ON),talk around(0=OFF/1=ON),'
      'pre_de_emph_bypass(0=OFF/1=ON),sign(0=OFF/1=ON),tx_dis(0=OFF/1=ON),'
      'mute(0=OFF/1=ON),rx_modulation(0=FM/1=AM),tx_modulation(0=FM/1=AM)',
    );
    for (final c in channels) {
      final txFreq = _txFreq(c);
      final rxFreq = _rxFreq(c);
      if (txFreq == 0 || rxFreq == 0) continue;

      String power = 'L';
      if (_txAtMaxPower(c)) {
        power = 'H';
      }
      if (_txAtMedPower(c)) {
        power = 'M';
      }

      final values = <String>[
        _name(c),
        txFreq.toString(),
        rxFreq.toString(),
        _txSubAudio(c).toString(),
        _rxSubAudio(c).toString(),
        power,
        _isWide(c) ? '25000' : '12500',
        _scan(c) ? '1' : '0',
        _talkAround(c) ? '1' : '0',
        _preDeEmphBypass(c) ? '1' : '0',
        _sign(c) ? '1' : '0',
        _txDisable(c) ? '1' : '0',
        _mute(c) ? '1' : '0',
        _rxMod(c).toString(),
        _txMod(c).toString(),
      ];
      sb.writeln(values.join(','));
    }
    return sb.toString();
  }

  /// Exports channels to CHIRP CSV format.
  static String exportToChirpFormat(List<Map<String, dynamic>> channels) {
    final sb = StringBuffer();
    sb.writeln(
      'Location,Name,Frequency,Duplex,Offset,Tone,rToneFreq,cToneFreq,'
      'DtcsCode,DtcsPolarity,Mode,TStep,Skip,Power',
    );
    for (int i = 0; i < channels.length; i++) {
      final c = channels[i];
      final txFreq = _txFreq(c);
      final rxFreq = _rxFreq(c);
      if (txFreq == 0 || rxFreq == 0) continue;

      String duplex = '';
      if (txFreq < rxFreq) {
        duplex = '-';
      }
      if (txFreq > rxFreq) {
        duplex = '+';
      }

      final offset = (txFreq - rxFreq).abs() / 1000000;

      final txSub = _txSubAudio(c);
      final rxSub = _rxSubAudio(c);

      // (None),Tone,TSQL,DTCS,DTCS-R,TSQL-R,Cross
      String tone = '';
      String rToneFreq = '';
      String cToneFreq = '';
      String dtcsCode = '';
      String dtcsPolarity = '';
      if (txSub >= 1000 && rxSub >= 1000) {
        tone = 'TONE';
        rToneFreq = (rxSub / 100).toString();
        cToneFreq = (txSub / 100).toString();
      } else if (txSub > 0 &&
          rxSub > 0 &&
          txSub < 1000 &&
          rxSub < 1000 &&
          rxSub == txSub) {
        tone = 'DTCS';
        dtcsCode = rxSub.toString();
        dtcsPolarity = 'NN';
      }

      // rxMod: 0 = FM, 1 = AM, 2 = DMR
      String mode = _rxMod(c) == 1 ? 'AM' : 'FM';
      if (_rxMod(c) == 0) {
        mode = _isWide(c) ? 'FM' : 'NFM';
      }

      String power;
      if (_txAtMaxPower(c)) {
        power = '5.0W';
      } else if (_txAtMedPower(c)) {
        power = '3.0W';
      } else {
        power = '1.0W';
      }

      final values = <String>[
        i.toString(),
        _name(c),
        (rxFreq / 1000000).toStringAsFixed(6),
        duplex,
        offset.toStringAsFixed(6),
        tone,
        rToneFreq,
        cToneFreq,
        dtcsCode,
        dtcsPolarity,
        mode,
        '',
        '',
        power,
      ];
      sb.writeln(values.join(','));
    }
    return sb.toString();
  }
}
