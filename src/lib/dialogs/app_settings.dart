import '../services/data_broker.dart';
import '../services/locale_controller.dart';
import '../services/theme_controller.dart';

/// Settings data model
class AppSettings {
  // License tab
  String callSign;
  int stationId;
  bool allowTransmit;

  /// Name of a chosen built-in avatar logo (see `contact_avatar.dart`), or null
  /// to fall back to the callsign initials for the operator's own avatar.
  String? avatarIcon;

  /// Base64-encoded 64x64 PNG of a custom operator avatar image, or null when
  /// none. When set it takes precedence over [avatarIcon] and the initials.
  String? avatarImage;

  // Application language tag: 'system' (follow the OS), 'en', 'fr'.
  String language;

  // Application theme mode: 'system' (follow the OS), 'light', 'dark'.
  String themeMode;

  // APRS tab
  List<AprsRoute> aprsRoutes;

  // APRS-IS (internet gateway) - APRS tab
  bool aprsIsEnabled;
  String aprsIsServer;
  int aprsIsPort;
  int aprsIsRangeKm;
  bool aprsIsGateToRf;
  String aprsIsPasscode;

  // APRS cloud notifications (HTCloudServer push) - APRS tab. When enabled the
  // app registers with aprs.meshcentral.com and receives pushed APRS messages
  // addressed to its station. Requires APRS-IS to be configured (valid
  // passcode). Android-only at runtime.
  bool aprsCloudNotifications;

  // APRS.fi API key used to backfill missed APRS messages - APRS tab
  String aprsFiApiKey;

  // Voice tab
  String voiceLanguage;
  String voiceModel;
  String voice;
  double voiceSpeechRate;
  double voicePitch;

  // Winlink tab
  String winlinkPassword;
  bool winlinkUseStationId;

  // EchoLink tab
  String echoLinkPassword;
  String echoLinkLocation;

  // Web Server tab
  bool webServerEnabled;
  int webServerPort;
  bool agwpeServerEnabled;
  int agwpeServerPort;

  // Home Assistant (Servers tab)
  bool homeAssistantEnabled;
  String homeAssistantMqttUrl;
  String homeAssistantUsername;
  String homeAssistantPassword;

  // Map/GPS tab
  String gpsSerialPort;
  int gpsBaudRate;
  bool shareSerialGpsLocation;
  String airplaneServerUrl;

  // Location source (License tab). When [manualLocationEnabled] is true the
  // current location comes from [manualLatitude]/[manualLongitude] instead of
  // the radio or serial GPS. Used for the radio position beacon, APRS-IS and
  // satellite tracking.
  bool manualLocationEnabled;
  double manualLatitude;
  double manualLongitude;

  // Application tab
  bool satelliteSupport;
  bool messageNotifications;

  // Limits tab (0 = unlimited)
  int maxAprsMessages;
  int maxPackets;
  int maxSstvImages;
  int maxCommEvents;

  /// APRS routes that always exist and cannot be edited or removed. Stored in
  /// definition order (preserved by the map) so they always appear first.
  static const Map<String, String> protectedRoutes = {
    'Standard': 'APN000,WIDE1-1,WIDE2-2',
    'None': 'APN000',
  };

  /// Whether a route with the given name is a built-in protected route.
  static bool isProtectedRouteName(String name) =>
      protectedRoutes.containsKey(name);

  /// Returns a list that always begins with the protected routes (with their
  /// canonical paths), followed by the user-defined routes. Any user routes
  /// whose names collide with a protected route are dropped in favour of the
  /// built-in definition.
  static List<AprsRoute> _withProtectedRoutes(List<AprsRoute> routes) {
    final result = <AprsRoute>[];
    protectedRoutes.forEach((name, path) {
      result.add(AprsRoute(name: name, path: path));
    });
    for (final r in routes) {
      if (!protectedRoutes.containsKey(r.name)) result.add(r);
    }
    return result;
  }

  /// Ensure the protected APRS routes exist in the DataBroker at application
  /// startup, persisting them if they are missing or have changed.
  static void ensureDefaultRoutes() {
    final routesStr = DataBroker.getValue<String>(0, 'AprsRoutes', '') ?? '';
    final routes = _withProtectedRoutes(_parseAprsRoutes(routesStr));
    final serialized = routes.map((r) => '${r.name}|${r.path}').join('|');
    if (serialized != routesStr) {
      DataBroker.dispatch(deviceId: 0, name: 'AprsRoutes', data: serialized);
    }
  }

  AppSettings({
    this.callSign = '',
    this.stationId = 0,
    this.allowTransmit = false,
    this.avatarIcon,
    this.avatarImage,
    this.language = LocaleController.systemTag,
    this.themeMode = ThemeController.systemTag,
    List<AprsRoute>? aprsRoutes,
    this.aprsIsEnabled = false,
    this.aprsIsServer = 'rotate.aprs2.net',
    this.aprsIsPort = 14580,
    this.aprsIsRangeKm = 0,
    this.aprsIsGateToRf = false,
    this.aprsIsPasscode = '',
    this.aprsCloudNotifications = false,
    this.aprsFiApiKey = '',
    this.voiceLanguage = 'auto',
    this.voiceModel = 'sense-voice',
    this.voice = '',
    this.voiceSpeechRate = 0.5,
    this.voicePitch = 1.0,
    this.winlinkPassword = '',
    this.winlinkUseStationId = false,
    this.echoLinkPassword = '',
    this.echoLinkLocation = '',
    this.webServerEnabled = false,
    this.webServerPort = 8080,
    this.agwpeServerEnabled = false,
    this.agwpeServerPort = 8000,
    this.homeAssistantEnabled = false,
    this.homeAssistantMqttUrl = '',
    this.homeAssistantUsername = '',
    this.homeAssistantPassword = '',
    this.gpsSerialPort = 'None',
    this.gpsBaudRate = 4800,
    this.shareSerialGpsLocation = false,
    this.airplaneServerUrl = '',
    this.manualLocationEnabled = false,
    this.manualLatitude = 0.0,
    this.manualLongitude = 0.0,
    this.satelliteSupport = false,
    this.messageNotifications = true,
    this.maxAprsMessages = 0,
    this.maxPackets = 0,
    this.maxSstvImages = 0,
    this.maxCommEvents = 0,
  }) : aprsRoutes = _withProtectedRoutes(aprsRoutes ?? const []);

  AppSettings copyWith({
    String? callSign,
    int? stationId,
    bool? allowTransmit,
    String? language,
    String? themeMode,
    List<AprsRoute>? aprsRoutes,
    bool? aprsIsEnabled,
    String? aprsIsServer,
    int? aprsIsPort,
    int? aprsIsRangeKm,
    bool? aprsIsGateToRf,
    String? aprsIsPasscode,
    bool? aprsCloudNotifications,
    String? aprsFiApiKey,
    String? voiceLanguage,
    String? voiceModel,
    String? voice,
    double? voiceSpeechRate,
    double? voicePitch,
    String? winlinkPassword,
    bool? winlinkUseStationId,
    String? echoLinkPassword,
    String? echoLinkLocation,
    bool? webServerEnabled,
    int? webServerPort,
    bool? agwpeServerEnabled,
    int? agwpeServerPort,
    bool? homeAssistantEnabled,
    String? homeAssistantMqttUrl,
    String? homeAssistantUsername,
    String? homeAssistantPassword,
    String? gpsSerialPort,
    int? gpsBaudRate,
    bool? shareSerialGpsLocation,
    String? airplaneServerUrl,
    bool? manualLocationEnabled,
    double? manualLatitude,
    double? manualLongitude,
    bool? satelliteSupport,
    bool? messageNotifications,
    int? maxAprsMessages,
    int? maxPackets,
    int? maxSstvImages,
    int? maxCommEvents,
  }) {
    return AppSettings(
      callSign: callSign ?? this.callSign,
      stationId: stationId ?? this.stationId,
      allowTransmit: allowTransmit ?? this.allowTransmit,
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
      aprsRoutes: aprsRoutes ?? List.from(this.aprsRoutes),
      aprsIsEnabled: aprsIsEnabled ?? this.aprsIsEnabled,
      aprsIsServer: aprsIsServer ?? this.aprsIsServer,
      aprsIsPort: aprsIsPort ?? this.aprsIsPort,
      aprsIsRangeKm: aprsIsRangeKm ?? this.aprsIsRangeKm,
      aprsIsGateToRf: aprsIsGateToRf ?? this.aprsIsGateToRf,
      aprsIsPasscode: aprsIsPasscode ?? this.aprsIsPasscode,
      aprsCloudNotifications:
          aprsCloudNotifications ?? this.aprsCloudNotifications,
      aprsFiApiKey: aprsFiApiKey ?? this.aprsFiApiKey,
      voiceLanguage: voiceLanguage ?? this.voiceLanguage,
      voiceModel: voiceModel ?? this.voiceModel,
      voice: voice ?? this.voice,
      voiceSpeechRate: voiceSpeechRate ?? this.voiceSpeechRate,
      voicePitch: voicePitch ?? this.voicePitch,
      winlinkPassword: winlinkPassword ?? this.winlinkPassword,
      winlinkUseStationId: winlinkUseStationId ?? this.winlinkUseStationId,
      echoLinkPassword: echoLinkPassword ?? this.echoLinkPassword,
      echoLinkLocation: echoLinkLocation ?? this.echoLinkLocation,
      webServerEnabled: webServerEnabled ?? this.webServerEnabled,
      webServerPort: webServerPort ?? this.webServerPort,
      agwpeServerEnabled: agwpeServerEnabled ?? this.agwpeServerEnabled,
      agwpeServerPort: agwpeServerPort ?? this.agwpeServerPort,
      homeAssistantEnabled: homeAssistantEnabled ?? this.homeAssistantEnabled,
      homeAssistantMqttUrl: homeAssistantMqttUrl ?? this.homeAssistantMqttUrl,
      homeAssistantUsername: homeAssistantUsername ?? this.homeAssistantUsername,
      homeAssistantPassword: homeAssistantPassword ?? this.homeAssistantPassword,
      gpsSerialPort: gpsSerialPort ?? this.gpsSerialPort,
      gpsBaudRate: gpsBaudRate ?? this.gpsBaudRate,
      shareSerialGpsLocation:
          shareSerialGpsLocation ?? this.shareSerialGpsLocation,
      airplaneServerUrl: airplaneServerUrl ?? this.airplaneServerUrl,
      manualLocationEnabled:
          manualLocationEnabled ?? this.manualLocationEnabled,
      manualLatitude: manualLatitude ?? this.manualLatitude,
      manualLongitude: manualLongitude ?? this.manualLongitude,
      satelliteSupport: satelliteSupport ?? this.satelliteSupport,
      messageNotifications:
          messageNotifications ?? this.messageNotifications,
      maxAprsMessages: maxAprsMessages ?? this.maxAprsMessages,
      maxPackets: maxPackets ?? this.maxPackets,
      maxSstvImages: maxSstvImages ?? this.maxSstvImages,
      maxCommEvents: maxCommEvents ?? this.maxCommEvents,
    );
  }

  /// Load settings from DataBroker (device 0).
  static AppSettings loadFromDataBroker() {
    final aprsRoutesStr = DataBroker.getValue<String>(0, 'AprsRoutes', '');
    final aprsRoutes = _parseAprsRoutes(aprsRoutesStr ?? '');

    return AppSettings(
      callSign: DataBroker.getValue<String>(0, 'CallSign', '') ?? '',
      stationId: DataBroker.getValue<int>(0, 'StationId', 0) ?? 0,
      allowTransmit:
          (DataBroker.getValue<int>(0, 'AllowTransmit', 0) ?? 0) == 1,
      avatarIcon: _nonEmptyOrNull(
          DataBroker.getValue<String>(0, 'AvatarIcon', '') ?? ''),
      avatarImage: _nonEmptyOrNull(
          DataBroker.getValue<String>(0, 'AvatarImage', '') ?? ''),
      language:
          DataBroker.getValue<String>(0, LocaleController.storageKey,
                  LocaleController.systemTag) ??
              LocaleController.systemTag,
      themeMode:
          DataBroker.getValue<String>(0, ThemeController.storageKey,
                  ThemeController.systemTag) ??
              ThemeController.systemTag,
      aprsRoutes: aprsRoutes,
      aprsIsEnabled:
          (DataBroker.getValue<int>(0, 'AprsIsEnabled', 0) ?? 0) == 1,
      aprsIsServer:
          DataBroker.getValue<String>(0, 'AprsIsServer', 'rotate.aprs2.net') ??
              'rotate.aprs2.net',
      aprsIsPort: DataBroker.getValue<int>(0, 'AprsIsPort', 14580) ?? 14580,
      aprsIsRangeKm:
          DataBroker.getValue<int>(0, 'AprsIsRangeKm', 0) ?? 0,
      aprsIsGateToRf:
          (DataBroker.getValue<int>(0, 'AprsIsGateToRf', 0) ?? 0) == 1,
      aprsIsPasscode:
          DataBroker.getValue<String>(0, 'AprsIsPasscode', '') ?? '',
      aprsCloudNotifications:
          (DataBroker.getValue<int>(0, 'AprsCloudNotifications', 0) ?? 0) == 1,
      aprsFiApiKey:
          DataBroker.getValue<String>(0, 'AprsFiApiKey', '') ?? '',
      voiceLanguage:
          DataBroker.getValue<String>(0, 'VoiceLanguage', 'auto') ?? 'auto',
      voiceModel:
          DataBroker.getValue<String>(0, 'VoiceModel', 'sense-voice') ??
          'sense-voice',
      voice: DataBroker.getValue<String>(0, 'Voice', '') ?? '',
      voiceSpeechRate:
          DataBroker.getValue<double>(0, 'VoiceSpeechRate', 0.5) ?? 0.5,
      voicePitch: DataBroker.getValue<double>(0, 'VoicePitch', 1.0) ?? 1.0,
      winlinkPassword:
          DataBroker.getValue<String>(0, 'WinlinkPassword', '') ?? '',
      winlinkUseStationId:
          (DataBroker.getValue<int>(0, 'WinlinkUseStationId', 0) ?? 0) == 1,
      echoLinkPassword:
          DataBroker.getValue<String>(0, 'EchoLinkPassword', '') ?? '',
      echoLinkLocation:
          DataBroker.getValue<String>(0, 'EchoLinkLocation', '') ?? '',
      webServerEnabled:
          (DataBroker.getValue<int>(0, 'webServerEnabled', 0) ?? 0) == 1,
      webServerPort: DataBroker.getValue<int>(0, 'webServerPort', 8080) ?? 8080,
      agwpeServerEnabled:
          (DataBroker.getValue<int>(0, 'agwpeServerEnabled', 0) ?? 0) == 1,
      agwpeServerPort:
          DataBroker.getValue<int>(0, 'agwpeServerPort', 8000) ?? 8000,
      homeAssistantEnabled:
          (DataBroker.getValue<int>(0, 'homeAssistantEnabled', 0) ?? 0) == 1,
      homeAssistantMqttUrl:
          DataBroker.getValue<String>(0, 'homeAssistantMqttUrl', '') ?? '',
      homeAssistantUsername:
          DataBroker.getValue<String>(0, 'homeAssistantUsername', '') ?? '',
      homeAssistantPassword:
          DataBroker.getValue<String>(0, 'homeAssistantPassword', '') ?? '',
      gpsSerialPort:
          DataBroker.getValue<String>(0, 'GpsSerialPort', 'None') ?? 'None',
      gpsBaudRate: DataBroker.getValue<int>(0, 'GpsBaudRate', 4800) ?? 4800,
      shareSerialGpsLocation:
          (DataBroker.getValue<int>(0, 'ShareSerialGpsLocation', 0) ?? 0) == 1,
      airplaneServerUrl:
          DataBroker.getValue<String>(0, 'AirplaneServer', '') ?? '',
      manualLocationEnabled:
          (DataBroker.getValue<int>(0, 'ManualLocationEnabled', 0) ?? 0) == 1,
      manualLatitude:
          DataBroker.getValue<double>(0, 'ManualLatitude', 0.0) ?? 0.0,
      manualLongitude:
          DataBroker.getValue<double>(0, 'ManualLongitude', 0.0) ?? 0.0,
      satelliteSupport:
          (DataBroker.getValue<int>(0, 'SatelliteSupport', 0) ?? 0) == 1,
      messageNotifications:
          (DataBroker.getValue<int>(0, 'MessageNotifications', 1) ?? 1) == 1,
      maxAprsMessages:
          DataBroker.getValue<int>(0, 'MaxAprsMessages', 0) ?? 0,
      maxPackets: DataBroker.getValue<int>(0, 'MaxPackets', 0) ?? 0,
      maxSstvImages: DataBroker.getValue<int>(0, 'MaxSstvImages', 0) ?? 0,
      maxCommEvents: DataBroker.getValue<int>(0, 'MaxCommEvents', 0) ?? 0,
    );
  }

  /// Save settings to DataBroker (device 0).
  void saveToDataBroker() {
    DataBroker.dispatch(deviceId: 0, name: 'CallSign', data: callSign);
    DataBroker.dispatch(deviceId: 0, name: 'StationId', data: stationId);
    DataBroker.dispatch(
      deviceId: 0,
      name: 'AllowTransmit',
      data: allowTransmit ? 1 : 0,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'AvatarIcon',
      data: avatarIcon ?? '',
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'AvatarImage',
      data: avatarImage ?? '',
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'AprsRoutes',
      data: _serializeAprsRoutes(),
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'AprsIsEnabled',
      data: aprsIsEnabled ? 1 : 0,
    );
    DataBroker.dispatch(deviceId: 0, name: 'AprsIsServer', data: aprsIsServer);
    DataBroker.dispatch(deviceId: 0, name: 'AprsIsPort', data: aprsIsPort);
    DataBroker.dispatch(
      deviceId: 0,
      name: 'AprsIsRangeKm',
      data: aprsIsRangeKm,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'AprsIsGateToRf',
      data: aprsIsGateToRf ? 1 : 0,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'AprsIsPasscode',
      data: aprsIsPasscode,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'AprsCloudNotifications',
      data: aprsCloudNotifications ? 1 : 0,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'AprsFiApiKey',
      data: aprsFiApiKey,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'VoiceLanguage',
      data: voiceLanguage,
    );
    DataBroker.dispatch(deviceId: 0, name: 'VoiceModel', data: voiceModel);
    DataBroker.dispatch(deviceId: 0, name: 'Voice', data: voice);
    DataBroker.dispatch(
      deviceId: 0,
      name: 'VoiceSpeechRate',
      data: voiceSpeechRate,
    );
    DataBroker.dispatch(deviceId: 0, name: 'VoicePitch', data: voicePitch);
    DataBroker.dispatch(
      deviceId: 0,
      name: 'WinlinkPassword',
      data: winlinkPassword,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'WinlinkUseStationId',
      data: winlinkUseStationId ? 1 : 0,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'EchoLinkPassword',
      data: echoLinkPassword,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'EchoLinkLocation',
      data: echoLinkLocation,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'webServerEnabled',
      data: webServerEnabled ? 1 : 0,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'webServerPort',
      data: webServerPort,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'agwpeServerEnabled',
      data: agwpeServerEnabled ? 1 : 0,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'agwpeServerPort',
      data: agwpeServerPort,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'homeAssistantEnabled',
      data: homeAssistantEnabled ? 1 : 0,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'homeAssistantMqttUrl',
      data: homeAssistantMqttUrl,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'homeAssistantUsername',
      data: homeAssistantUsername,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'homeAssistantPassword',
      data: homeAssistantPassword,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'GpsSerialPort',
      data: gpsSerialPort,
    );
    DataBroker.dispatch(deviceId: 0, name: 'GpsBaudRate', data: gpsBaudRate);
    DataBroker.dispatch(
      deviceId: 0,
      name: 'ShareSerialGpsLocation',
      data: shareSerialGpsLocation ? 1 : 0,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'AirplaneServer',
      data: airplaneServerUrl,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'ManualLocationEnabled',
      data: manualLocationEnabled ? 1 : 0,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'ManualLatitude',
      data: manualLatitude,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'ManualLongitude',
      data: manualLongitude,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'SatelliteSupport',
      data: satelliteSupport ? 1 : 0,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'MessageNotifications',
      data: messageNotifications ? 1 : 0,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'MaxAprsMessages',
      data: maxAprsMessages,
    );
    DataBroker.dispatch(deviceId: 0, name: 'MaxPackets', data: maxPackets);
    DataBroker.dispatch(
      deviceId: 0,
      name: 'MaxSstvImages',
      data: maxSstvImages,
    );
    DataBroker.dispatch(
      deviceId: 0,
      name: 'MaxCommEvents',
      data: maxCommEvents,
    );
  }

  /// Returns [value] trimmed, or null when it is empty. Used so stored empty
  /// avatar strings load back as a null (meaning "no custom avatar").
  static String? _nonEmptyOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Serialize APRS routes to pipe-separated string format: "Name|Path|Name|Path..."
  String _serializeAprsRoutes() {
    return aprsRoutes.map((r) => '${r.name}|${r.path}').join('|');
  }

  /// Parse APRS routes from pipe-separated string format.
  static List<AprsRoute> _parseAprsRoutes(String routesStr) {
    if (routesStr.isEmpty) return [];

    final parts = routesStr.split('|');
    final routes = <AprsRoute>[];

    // Routes are stored as "Name|Path|Name|Path..."
    for (var i = 0; i + 1 < parts.length; i += 2) {
      routes.add(AprsRoute(name: parts[i], path: parts[i + 1]));
    }

    return routes;
  }
}

/// APRS Route model
class AprsRoute {
  String name;
  String path;

  AprsRoute({required this.name, required this.path});
}
