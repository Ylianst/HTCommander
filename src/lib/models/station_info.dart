/// Station / contact data model ported from the C# `StationInfoClass`.
///
/// Stations are persisted on DataBroker device 0 under the `Stations` key as a
/// `List<Map<String, dynamic>>` so they survive across sessions and can be read
/// by the APRS handler for authentication lookups.
library;

/// Station type. The integer index matches the C# `StationInfoClass.StationTypes`
/// enum so serialized values stay compatible.
enum StationType {
  generic, // 0
  aprs, // 1
  terminal, // 2
  bbs, // 3
  winlink, // 4
  torrent, // 5
  agwpe, // 6
}

/// Terminal protocol. The integer index matches the C#
/// `StationInfoClass.TerminalProtocols` enum.
enum TerminalProtocol {
  rawX25, // 0
  aprs, // 1
  rawX25Compress, // 2
  x25Session, // 3
}

/// A configured station / contact.
class StationInfo {
  String callsign;
  String name;
  String description;
  StationType stationType;
  String aprsRoute;
  TerminalProtocol terminalProtocol;
  String channel;
  String ax25Destination;
  bool waitForConnection;
  String? authPassword;

  /// Modem to use for Terminal / Winlink sessions with this contact.
  ///
  /// `'Hardware'` (the default) uses the radio's built-in AFSK 1200 TNC. The
  /// other values (`'AFSK1200'`, `'PSK2400'`, `'PSK4800'`, `'G3RUH9600'`) select
  /// one of the software modem modes, which is only available on platforms that
  /// support the audio channel (not web or iOS).
  String modem;

  StationInfo({
    this.callsign = '',
    this.name = '',
    this.description = '',
    this.stationType = StationType.generic,
    this.aprsRoute = '',
    this.terminalProtocol = TerminalProtocol.x25Session,
    this.channel = '',
    this.ax25Destination = '',
    this.waitForConnection = false,
    this.authPassword,
    this.modem = 'Hardware',
  });

  /// Callsign with a trailing `-0` SSID removed (matches C# `CallsignNoZero`).
  String get callsignNoZero {
    if (callsign.endsWith('-0')) {
      return callsign.substring(0, callsign.length - 2);
    }
    return callsign;
  }

  StationInfo copyWith({
    String? callsign,
    String? name,
    String? description,
    StationType? stationType,
    String? aprsRoute,
    TerminalProtocol? terminalProtocol,
    String? channel,
    String? ax25Destination,
    bool? waitForConnection,
    String? authPassword,
    String? modem,
  }) {
    return StationInfo(
      callsign: callsign ?? this.callsign,
      name: name ?? this.name,
      description: description ?? this.description,
      stationType: stationType ?? this.stationType,
      aprsRoute: aprsRoute ?? this.aprsRoute,
      terminalProtocol: terminalProtocol ?? this.terminalProtocol,
      channel: channel ?? this.channel,
      ax25Destination: ax25Destination ?? this.ax25Destination,
      waitForConnection: waitForConnection ?? this.waitForConnection,
      authPassword: authPassword ?? this.authPassword,
      modem: modem ?? this.modem,
    );
  }

  /// Serializes to a DataBroker JSON map. Keys match the C# property names so
  /// the value is readable by [AprsStationInfo] and the export format.
  Map<String, dynamic> toJson() {
    return {
      'Callsign': callsign,
      'Name': name,
      'Description': description,
      'StationType': stationType.index,
      'APRSRoute': aprsRoute,
      'TerminalProtocol': terminalProtocol.index,
      'Channel': channel,
      'AX25Destination': ax25Destination,
      'WaitForConnection': waitForConnection,
      'AuthPassword': authPassword,
      'Modem': modem,
    };
  }

  /// Builds a station from a DataBroker JSON map. Accepts a few key spellings
  /// for resilience.
  static StationInfo fromJson(Map<String, dynamic> json) {
    StationType parseType(Object? raw) {
      if (raw is int) {
        if (raw >= 0 && raw < StationType.values.length) {
          return StationType.values[raw];
        }
        return StationType.generic;
      }
      final s = raw?.toString().toLowerCase() ?? '';
      final asInt = int.tryParse(s);
      if (asInt != null && asInt >= 0 && asInt < StationType.values.length) {
        return StationType.values[asInt];
      }
      for (final t in StationType.values) {
        if (t.name == s) return t;
      }
      return StationType.generic;
    }

    TerminalProtocol parseProtocol(Object? raw) {
      if (raw is int) {
        if (raw >= 0 && raw < TerminalProtocol.values.length) {
          return TerminalProtocol.values[raw];
        }
        return TerminalProtocol.x25Session;
      }
      final asInt = int.tryParse(raw?.toString() ?? '');
      if (asInt != null &&
          asInt >= 0 &&
          asInt < TerminalProtocol.values.length) {
        return TerminalProtocol.values[asInt];
      }
      return TerminalProtocol.x25Session;
    }

    final pwd =
        (json['AuthPassword'] ?? json['authPassword'] ?? json['password'])
            ?.toString();

    return StationInfo(
      callsign: (json['Callsign'] ?? json['callsign'] ?? json['CallSign'] ?? '')
          .toString(),
      name: (json['Name'] ?? json['name'] ?? '').toString(),
      description: (json['Description'] ?? json['description'] ?? '')
          .toString(),
      stationType: parseType(json['StationType'] ?? json['stationType']),
      aprsRoute: (json['APRSRoute'] ?? json['aprsRoute'] ?? '').toString(),
      terminalProtocol: parseProtocol(
        json['TerminalProtocol'] ?? json['terminalProtocol'],
      ),
      channel: (json['Channel'] ?? json['channel'] ?? '').toString(),
      ax25Destination:
          (json['AX25Destination'] ?? json['ax25Destination'] ?? '').toString(),
      waitForConnection:
          (json['WaitForConnection'] ?? json['waitForConnection']) == true,
      authPassword: (pwd != null && pwd.isNotEmpty && pwd != 'null')
          ? pwd
          : null,
      modem: _parseModem(json['Modem'] ?? json['modem']),
    );
  }

  /// Normalizes a stored modem value, defaulting to `'Hardware'`.
  static String _parseModem(Object? raw) {
    final s = raw?.toString() ?? '';
    switch (s.toUpperCase()) {
      case 'AFSK1200':
        return 'AFSK1200';
      case 'PSK2400':
        return 'PSK2400';
      case 'PSK4800':
        return 'PSK4800';
      case 'G3RUH9600':
        return 'G3RUH9600';
      default:
        return 'Hardware';
    }
  }

  /// Serializes a list of stations to the plain-text address-book format used
  /// by the C# import/export (`Serialize`).
  static String serializeList(List<StationInfo> stations) {
    final sb = StringBuffer();
    for (final station in stations) {
      sb.writeln('Station:');
      sb.writeln('Callsign=${station.callsign}');
      sb.writeln('Name=${station.name}');
      sb.writeln('Description=${station.description}');
      sb.writeln('StationType=${station.stationType.index}');
      sb.writeln('APRSRoute=${station.aprsRoute}');
      sb.writeln('TerminalProtocol=${station.terminalProtocol.index}');
      sb.writeln('Channel=${station.channel}');
      sb.writeln('AX25Destination=${station.ax25Destination}');
      sb.writeln('AuthPassword=${station.authPassword ?? ''}');
      sb.writeln('Modem=${station.modem}');
      sb.writeln();
    }
    return sb.toString();
  }

  /// Parses the plain-text address-book format into a list of stations.
  static List<StationInfo> deserializeList(String data) {
    final stations = <StationInfo>[];
    StationInfo? current;

    final lines = data.split(RegExp(r'[\r\n]+'));
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line == 'Station:') {
        if (current != null) stations.add(current);
        current = StationInfo();
      } else if (current != null) {
        final idx = line.indexOf('=');
        if (idx <= 0) continue;
        final key = line.substring(0, idx).trim();
        final value = line.substring(idx + 1).trim();
        switch (key) {
          case 'Callsign':
            current.callsign = value;
            break;
          case 'Name':
            current.name = value;
            break;
          case 'Description':
            current.description = value;
            break;
          case 'StationType':
            final i = int.tryParse(value) ?? 0;
            current.stationType = (i >= 0 && i < StationType.values.length)
                ? StationType.values[i]
                : StationType.generic;
            break;
          case 'APRSRoute':
            current.aprsRoute = value;
            break;
          case 'TerminalProtocol':
            final i = int.tryParse(value) ?? 3;
            current.terminalProtocol =
                (i >= 0 && i < TerminalProtocol.values.length)
                ? TerminalProtocol.values[i]
                : TerminalProtocol.x25Session;
            break;
          case 'Channel':
            current.channel = value;
            break;
          case 'AX25Destination':
            current.ax25Destination = value;
            break;
          case 'AuthPassword':
            current.authPassword = value.isEmpty ? null : value;
            break;
          case 'Modem':
            current.modem = _parseModem(value);
            break;
        }
      }
    }
    if (current != null) stations.add(current);
    return stations;
  }
}
