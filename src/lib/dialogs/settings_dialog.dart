import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dialog_utils.dart';
import '../l10n/app_localizations.dart';
import '../aprs/aprs_util.dart';
import '../aprs/weather_data.dart';
import '../allstar/allstar_node.dart';
import '../allstar/allstar_portal_service.dart';
import '../echolink/echolink_credential_test.dart';
import '../services/serial/serial_port.dart';
import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/history_limiter.dart';
import '../services/locale_controller.dart';
import '../services/mqtt/mqtt_client_facade.dart';
import '../services/theme_controller.dart';
import '../services/tts_service.dart';
import '../services/sherpa_model_manager.dart';

/// Settings data model
class AppSettings {
  // License tab
  String callSign;
  int stationId;
  bool allowTransmit;

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

  // Application tab
  bool satelliteSupport;

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
    this.language = LocaleController.systemTag,
    this.themeMode = ThemeController.systemTag,
    List<AprsRoute>? aprsRoutes,
    this.aprsIsEnabled = false,
    this.aprsIsServer = 'rotate.aprs2.net',
    this.aprsIsPort = 14580,
    this.aprsIsRangeKm = 0,
    this.aprsIsGateToRf = false,
    this.aprsIsPasscode = '',
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
    this.satelliteSupport = false,
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
    bool? satelliteSupport,
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
      satelliteSupport: satelliteSupport ?? this.satelliteSupport,
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
      satelliteSupport:
          (DataBroker.getValue<int>(0, 'SatelliteSupport', 0) ?? 0) == 1,
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
      name: 'SatelliteSupport',
      data: satelliteSupport ? 1 : 0,
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

/// Settings dialog with tabbed interface
class SettingsDialog extends StatefulWidget {
  final int initialTab;

  const SettingsDialog({super.key, this.initialTab = 0});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog>
    with SingleTickerProviderStateMixin {
  static bool get _serialGpsSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  late TabController _tabController;
  late AppSettings _settings;

  // Data Broker client for reading/writing the AllStarLink account credentials.
  final DataBrokerClient _broker = DataBrokerClient();

  // Controllers
  late TextEditingController _callSignController;
  late TextEditingController _winlinkPasswordController;
  late TextEditingController _echoLinkPasswordController;
  late TextEditingController _echoLinkLocationController;
  late TextEditingController _allStarPasswordController;
  late TextEditingController _aprsIsServerController;
  late TextEditingController _aprsIsPortController;
  late TextEditingController _aprsIsPasscodeController;
  late TextEditingController _webPortController;
  late TextEditingController _agwpePortController;
  late TextEditingController _airplaneUrlController;
  late TextEditingController _homeAssistantUrlController;
  late TextEditingController _homeAssistantUsernameController;
  late TextEditingController _homeAssistantPasswordController;

  // True when the user picked "Custom" in the APRS-IS server-region dropdown,
  // revealing the raw server/port fields. Otherwise a well-known region is
  // selected and the server/port are managed automatically.
  bool _aprsIsCustomServer = false;


  // Dump1090 "Test Connection" state.
  bool _airplaneTesting = false;
  String _airplaneTestResult = '';
  // Whether the last completed test succeeded (drives the result text color).
  bool _airplaneTestOk = false;

  // Home Assistant MQTT "Test" state.
  bool _homeAssistantTesting = false;
  String _homeAssistantTestResult = '';
  bool _homeAssistantTestOk = false;

  // EchoLink credential "Test" state.
  bool _echoLinkTesting = false;
  String _echoLinkTestResult = '';
  bool _echoLinkTestOk = false;

  // AllStarLink account "Test" state.
  bool _allStarTesting = false;
  String _allStarTestResult = '';
  bool _allStarTestOk = false;

  // Serial ports available for the GPS receiver (desktop only).
  List<String> _availablePorts = const [];

  // Available text-to-speech voices, loaded asynchronously.
  List<Map<String, String>> _voices = const [];
  bool _voicesLoaded = false;

  // Whether text-to-speech synthesis is usable on this machine, and, when it is
  // not, the platform-specific instructions telling the user how to enable it.
  bool _ttsAvailable = true;
  String _ttsInstructions = '';

  // Current history item counts (loaded asynchronously for the Limits tab).
  HistoryCounts? _historyCounts;

  // GPS baud rates
  static const List<int> _baudRates = [4800, 9600, 19200, 38400, 57600, 115200];

  /// Settings tabs in display order. On the web the radio is used over the BLE
  /// control channel only, so the audio-centric "Comms" tab and the
  /// internet-service "Servers" / "Map" tabs are hidden. On Android/iOS the
  /// "Servers" tab is hidden. All tabs remain visible on desktop platforms.
  List<String> get _visibleTabs {
    const all = ['License', 'APRS', 'Comms', 'Winlink', 'EchoLink', 'AllStar', 'Servers', 'Map', 'Limits', 'Application'];
    if (kIsWeb) {
      return all
          .where((t) => t != 'Comms' && t != 'Servers' && t != 'Map' && t != 'EchoLink' && t != 'AllStar')
          .toList();
    }
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return all.where((t) => t != 'Servers').toList();
    }
    return all;
  }

  /// Localized display title for a given tab identifier (see [_visibleTabs]).
  String _tabTitle(String title) {
    final l10n = AppLocalizations.of(context);
    switch (title) {
      case 'License':
        return l10n.settingsTabLicense;
      case 'APRS':
        return l10n.settingsTabAprs;
      case 'Comms':
        return l10n.settingsTabComms;
      case 'Winlink':
        return l10n.settingsTabWinlink;
      case 'EchoLink':
        return l10n.settingsTabEchoLink;
      case 'AllStar':
        return l10n.settingsTabAllStar;
      case 'Servers':
        return l10n.settingsTabServers;
      case 'Map':
        return l10n.settingsTabMap;
      case 'Limits':
        return l10n.settingsTabLimits;
      case 'Application':
        return l10n.settingsTabApplication;
    }
    return title;
  }

  /// Builds the content widget for a given tab title (see [_visibleTabs]).
  Widget _buildTabContentFor(String title) {
    switch (title) {
      case 'License':
        return _buildLicenseTab();
      case 'APRS':
        return _buildAprsTab();
      case 'Comms':
        return _buildCommsTab();
      case 'Winlink':
        return _buildWinlinkTab();
      case 'EchoLink':
        return _buildEchoLinkTab();
      case 'AllStar':
        return _buildAllStarTab();
      case 'Servers':
        return _buildServersTab();
      case 'Map':
        return _buildMapTab();
      case 'Limits':
        return _buildLimitsTab();
      case 'Application':
        return _buildApplicationTab();
    }
    return const SizedBox.shrink();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _visibleTabs.length,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, _visibleTabs.length - 1),
    );

    // Load settings from DataBroker
    _settings = AppSettings.loadFromDataBroker();

    // Enumerate serial ports for the GPS receiver dropdown (desktop only).
    _availablePorts = _listSerialPorts();

    _callSignController = TextEditingController(text: _settings.callSign);
    _winlinkPasswordController = TextEditingController(
      text: _settings.winlinkPassword,
    );
    _echoLinkPasswordController = TextEditingController(
      text: _settings.echoLinkPassword,
    );
    _echoLinkLocationController = TextEditingController(
      text: _settings.echoLinkLocation,
    );
    _allStarPasswordController = TextEditingController(
      text: _broker.getValue<String>(0, allStarPasswordKey, '') ?? '',
    );
    _aprsIsServerController = TextEditingController(
      text: _settings.aprsIsServer,
    );
    _aprsIsPortController = TextEditingController(
      text: _settings.aprsIsPort.toString(),
    );
    // A stored server/port that doesn't match a well-known region (on the
    // default port) starts the section in "Custom" mode so the user's manual
    // configuration stays visible and editable.
    _aprsIsCustomServer = !(_settings.aprsIsPort == _aprsIsDefaultPort &&
        _aprsIsRegionHosts.contains(_settings.aprsIsServer));
    _aprsIsPasscodeController = TextEditingController(
      text: _settings.aprsIsPasscode,
    );
    _webPortController = TextEditingController(
      text: _settings.webServerPort.toString(),
    );
    _agwpePortController = TextEditingController(
      text: _settings.agwpeServerPort.toString(),
    );
    _airplaneUrlController = TextEditingController(
      text: _settings.airplaneServerUrl,
    );
    _homeAssistantUrlController = TextEditingController(
      text: _settings.homeAssistantMqttUrl,
    );
    _homeAssistantUsernameController = TextEditingController(
      text: _settings.homeAssistantUsername,
    );
    _homeAssistantPasswordController = TextEditingController(
      text: _settings.homeAssistantPassword,
    );

    _callSignController.addListener(_onCallSignChanged);
    _echoLinkPasswordController.addListener(_onEchoLinkPasswordChanged);
    _allStarPasswordController.addListener(_onAllStarPasswordChanged);
    _aprsIsPasscodeController.addListener(_onAprsIsPasscodeChanged);

    // Load the available TTS voices for the Voice tab.
    _loadVoices();

    // Load current history counts for the Limits tab.
    _loadHistoryCounts();

    // Sync the speech-to-text model status shown in the Voice tab.
    // Speech-to-text is not available on Android.
    if (defaultTargetPlatform != TargetPlatform.android) {
      SherpaModelManager.refreshStatus(
        SherpaModelManager.modelById(_settings.voiceModel).id,
      );
    }
  }

  /// Loads the available text-to-speech voices for the Voice settings tab.
  Future<void> _loadVoices() async {
    final available = await TtsService.instance.isAvailable();
    final instructions =
        available ? '' : TtsService.instance.setupInstructions;
    final voices = List<Map<String, String>>.from(
      await TtsService.instance.getVoices(),
    );
    voices.sort((a, b) {
      final byLocale = (a['locale'] ?? '').compareTo(b['locale'] ?? '');
      if (byLocale != 0) return byLocale;
      return (a['name'] ?? '').compareTo(b['name'] ?? '');
    });
    if (!mounted) return;
    setState(() {
      _voices = voices;
      _voicesLoaded = true;
      _ttsAvailable = available;
      _ttsInstructions = instructions;
    });
  }

  /// Loads current history item counts for display in the Limits tab.
  Future<void> _loadHistoryCounts() async {
    final counts = await HistoryLimiter.getCounts();
    if (!mounted) return;
    setState(() => _historyCounts = counts);
  }

  @override
  void dispose() {
    TtsService.instance.stopPreview();
    _tabController.dispose();
    _callSignController.dispose();
    _winlinkPasswordController.dispose();
    _echoLinkPasswordController.dispose();
    _echoLinkLocationController.dispose();
    _allStarPasswordController.dispose();
    _aprsIsServerController.dispose();
    _aprsIsPortController.dispose();
    _aprsIsPasscodeController.dispose();
    _webPortController.dispose();
    _agwpePortController.dispose();
    _airplaneUrlController.dispose();
    _homeAssistantUrlController.dispose();
    _homeAssistantUsernameController.dispose();
    _homeAssistantPasswordController.dispose();
    super.dispose();
  }

  void _onCallSignChanged() {
    setState(() {
      _settings.callSign = _callSignController.text.toUpperCase();
      if (_settings.callSign.length < 3) {
        _settings.allowTransmit = false;
      }
      // The passcode is tied to the call sign; a changed call sign can
      // invalidate a previously correct passcode, which must disable APRS-IS.
      if (!_aprsIsPasscodeValid) _settings.aprsIsEnabled = false;
    });
  }

  /// Rebuilds so the EchoLink "Test" button enables once a password is entered.
  void _onEchoLinkPasswordChanged() {
    if (mounted) setState(() {});
  }

  /// Rebuilds so the AllStarLink "Test" button enables once a password is
  /// entered.
  void _onAllStarPasswordChanged() {
    if (mounted) setState(() {});
  }

  /// The APRS-IS passcode derived from the current call sign. Empty when no
  /// call sign is set.
  String get _expectedAprsIsPasscode => _settings.callSign.isEmpty
      ? ''
      : AprsUtil.aprsValidationCode(_settings.callSign);

  /// True when the passcode the user typed matches the one expected for their
  /// call sign. APRS-IS can only be enabled while this is true.
  bool get _aprsIsPasscodeValid =>
      _settings.callSign.isNotEmpty &&
      _aprsIsPasscodeController.text.trim() == _expectedAprsIsPasscode;

  /// Keeps the stored passcode in sync with the field and disables APRS-IS if
  /// the passcode is no longer correct.
  void _onAprsIsPasscodeChanged() {
    if (!mounted) return;
    setState(() {
      _settings.aprsIsPasscode = _aprsIsPasscodeController.text.trim();
      if (!_aprsIsPasscodeValid) _settings.aprsIsEnabled = false;
    });
  }

  /// Validates the EchoLink call sign + password against the directory server.
  Future<void> _testEchoLinkConnection() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _echoLinkTesting = true;
      _echoLinkTestResult = l10n.settingsTestTesting;
    });

    final EchoLinkCredentialResult result = await testEchoLinkCredentials(
      callsign: _settings.callSign,
      password: _echoLinkPasswordController.text,
      location: _echoLinkLocationController.text,
    );

    if (!mounted) return;
    setState(() {
      _echoLinkTesting = false;
      _echoLinkTestOk = result.ok;
      switch (result.status) {
        case EchoLinkCredentialStatus.valid:
          _echoLinkTestResult = l10n.settingsEchoLinkTestSuccess;
          break;
        case EchoLinkCredentialStatus.incorrectPassword:
          _echoLinkTestResult = l10n.settingsEchoLinkTestBadPassword;
          break;
        case EchoLinkCredentialStatus.validationPending:
          _echoLinkTestResult = l10n.settingsEchoLinkTestValidation;
          break;
        case EchoLinkCredentialStatus.unreachable:
          _echoLinkTestResult = l10n.settingsEchoLinkTestUnreachable;
          break;
        case EchoLinkCredentialStatus.unknown:
          _echoLinkTestResult = l10n.settingsEchoLinkTestInconclusive;
          break;
      }
    });
  }

  /// Authenticates the AllStarLink portal account (call sign + password) and, on
  /// success, stores the account password and the Web Transceiver token so the
  /// AllStarLink radio can go online.
  Future<void> _testAllStarConnection() async {
    final l10n = AppLocalizations.of(context);
    final String callSign = _settings.callSign.trim();
    if (callSign.isEmpty) {
      setState(() {
        _allStarTestOk = false;
        _allStarTestResult = l10n.settingsAllStarNoCallsign;
      });
      return;
    }
    setState(() {
      _allStarTesting = true;
      _allStarTestResult = l10n.settingsTestTesting;
    });

    final AllStarPortalService service = AllStarPortalService();
    AllStarWtAuthResult result;
    try {
      result = await service.fetchToken(
        username: callSign,
        password: _allStarPasswordController.text,
      );
    } finally {
      service.dispose();
    }
    if (!mounted) return;

    if (result.success) {
      _broker.dispatch(
          deviceId: 0,
          name: allStarPasswordKey,
          data: _allStarPasswordController.text,
          store: true);
      _broker.dispatch(
          deviceId: 0,
          name: allStarWtTokenKey,
          data: result.token,
          store: true);
    }
    setState(() {
      _allStarTesting = false;
      _allStarTestOk = result.success;
      _allStarTestResult = result.success
          ? l10n.settingsAllStarAuthSuccess
          : l10n.settingsAllStarAuthFailed(result.message);
    });
  }

  /// Registers a new EchoLink account for the call sign entered on the License
  /// tab. Prompts for an email address and a new password, performs the
  /// directory-server login that creates the (pending) account, saves the
  /// password, and offers to open the EchoLink validation page so the user can
  /// provide proof of license (required before the call sign can connect).
  Future<void> _createEchoLinkAccount() async {
    final l10n = AppLocalizations.of(context);
    final _EchoLinkAccountResult? result =
        await showDialog<_EchoLinkAccountResult>(
      context: context,
      builder: (_) => _EchoLinkCreateAccountDialog(
        callsign: _settings.callSign,
        location: _echoLinkLocationController.text,
      ),
    );
    if (result == null || !mounted) return;

    // Persist the chosen password: the Save handler reads this controller, and
    // updating it also re-enables the Test button.
    setState(() {
      _echoLinkPasswordController.text = result.password;
      _echoLinkTestOk = true;
      _echoLinkTestResult = result.alreadyValidated
          ? l10n.settingsEchoLinkAccountAlreadyValid
          : l10n.settingsEchoLinkAccountCreated;
    });

    // A newly created call sign still needs to be validated on the web before
    // it can be used. Offer to open the validation page with the call sign and
    // email pre-filled.
    if (!result.alreadyValidated) {
      final bool open = await DialogHelper.showConfirmDialog(
        context,
        title: l10n.settingsEchoLinkCreateAccountTitle,
        message: l10n.settingsEchoLinkValidatePrompt,
        okText: l10n.settingsEchoLinkValidateNow,
        cancelText: l10n.commonClose,
      );
      if (open) {
        _launchUrl(
          'https://www.echolink.org/validation/'
          '?callsign=${Uri.encodeComponent(_settings.callSign)}'
          '&email=${Uri.encodeComponent(result.email)}',
        );
      }
    }
  }

  /// Resolves a user-entered dump1090 server value into a full aircraft.json
  /// URL, mirroring the C# `AirplaneHandler.ResolveUrl`. Bare host[:port]
  /// values are expanded to `http://<server>/data/aircraft.json`.
  String? _resolveDump1090Url(String server) {
    final trimmed = server.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }
    return 'http://$trimmed/data/aircraft.json';
  }

  /// Fetches the dump1090 aircraft.json endpoint and validates the response,
  /// mirroring the C# `OnTestAirplaneServer` test. Reports the aircraft count
  /// on success or a failure message otherwise.
  Future<void> _testAirplaneConnection() async {
    final l10n = AppLocalizations.of(context);
    final url = _resolveDump1090Url(_airplaneUrlController.text);
    if (url == null) {
      setState(() {
        _airplaneTestOk = false;
        _airplaneTestResult = l10n.settingsTestEmptyAddress;
      });
      return;
    }

    setState(() {
      _airplaneTesting = true;
      _airplaneTestResult = l10n.settingsTestTesting;
    });

    String result;
    bool ok = false;
    // Holds the full exception text when the test fails so it can be shown in
    // a pop-up dialog instead of overflowing the settings dialog.
    String? errorDetail;
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        result = l10n.settingsTestFailedHttp(response.statusCode);
      } else {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final aircraft = decoded['aircraft'];
          final count = aircraft is List ? aircraft.length : 0;
          result = l10n.settingsTestSuccess(count);
          ok = true;
        } else {
          result = l10n.settingsTestUnexpectedJson;
        }
      }
    } on TimeoutException {
      result = l10n.settingsTestTimedOut;
    } on FormatException {
      result = l10n.settingsTestInvalidJson;
    } catch (e) {
      // Keep the inline status short and surface the (potentially long)
      // exception text in a pop-up dialog instead.
      result = l10n.settingsTestFailed;
      errorDetail = e.toString();
    }

    if (!mounted) return;
    setState(() {
      _airplaneTesting = false;
      _airplaneTestResult = result;
      _airplaneTestOk = ok;
    });

    if (errorDetail != null) {
      _showTestErrorDialog(errorDetail);
    }
  }

  /// Shows the full exception text from a failed connection test in a scrollable
  /// pop-up dialog so long messages do not overflow the settings dialog.
  void _showTestErrorDialog(String error) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context).settingsTestConnectionFailedTitle),
        content: SingleChildScrollView(child: SelectableText(error)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).commonOk),
          ),
        ],
      ),
    );
  }

  /// Tests the Home Assistant MQTT broker connection using the URL, username,
  /// and password currently entered, updating the inline result text.
  Future<void> _testHomeAssistantConnection() async {
    final l10n = AppLocalizations.of(context);
    final url = _homeAssistantUrlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _homeAssistantTestOk = false;
        _homeAssistantTestResult = l10n.settingsTestEmptyAddress;
      });
      return;
    }

    setState(() {
      _homeAssistantTesting = true;
      _homeAssistantTestResult = l10n.settingsTestTesting;
    });

    final result = await MqttClientFacade.testConnection(
      url: url,
      username: _homeAssistantUsernameController.text,
      password: _homeAssistantPasswordController.text,
      timeout: const Duration(seconds: 10),
    );

    if (!mounted) return;
    setState(() {
      _homeAssistantTesting = false;
      _homeAssistantTestOk = result.ok;
      _homeAssistantTestResult = result.ok
          ? l10n.settingsHomeAssistantTestSuccess
          : l10n.settingsTestFailed;
    });

    if (!result.ok && result.error != null) {
      _showTestErrorDialog(result.error!);
    }
  }

  void _onSave() async {
    final l10n = AppLocalizations.of(context);
    // Update settings from text controllers
    _settings.winlinkPassword = _winlinkPasswordController.text;
    _settings.echoLinkPassword = _echoLinkPasswordController.text;
    _settings.echoLinkLocation = _echoLinkLocationController.text;
    _settings.aprsIsServer = _aprsIsServerController.text.trim();
    _settings.aprsIsPort = int.tryParse(_aprsIsPortController.text) ?? 14580;
    _settings.webServerPort = int.tryParse(_webPortController.text) ?? 8080;
    _settings.agwpeServerPort = int.tryParse(_agwpePortController.text) ?? 8000;
    _settings.airplaneServerUrl = _airplaneUrlController.text;
    _settings.homeAssistantMqttUrl = _homeAssistantUrlController.text.trim();
    _settings.homeAssistantUsername = _homeAssistantUsernameController.text;
    _settings.homeAssistantPassword = _homeAssistantPasswordController.text;

    // Check if any limit would cause items to be deleted.
    final counts = _historyCounts;
    if (counts != null) {
      final deletions = <String>[];
      if (_settings.maxAprsMessages > 0 &&
          counts.aprsMessages > _settings.maxAprsMessages) {
        deletions.add(
          l10n.settingsDeleteAprsMessages(
            counts.aprsMessages - _settings.maxAprsMessages,
          ),
        );
      }
      if (_settings.maxPackets > 0 &&
          counts.packets > _settings.maxPackets) {
        deletions.add(
          l10n.settingsDeletePackets(counts.packets - _settings.maxPackets),
        );
      }
      if (_settings.maxSstvImages > 0 &&
          counts.sstvImages > _settings.maxSstvImages) {
        deletions.add(
          l10n.settingsDeleteSstvImages(
            counts.sstvImages - _settings.maxSstvImages,
          ),
        );
      }
      if (_settings.maxCommEvents > 0 &&
          counts.commEvents > _settings.maxCommEvents) {
        deletions.add(
          l10n.settingsDeleteCommEvents(
            counts.commEvents - _settings.maxCommEvents,
          ),
        );
      }

      if (deletions.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.settingsDeleteHistoryTitle),
            content: Text(
              l10n.settingsDeleteHistoryBody(
                deletions.map((d) => '\u2022 $d').join('\n'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.commonOk),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
    }

    // Save all settings to DataBroker (persisted to SharedPreferences)
    _settings.saveToDataBroker();

    // Apply the selected application language (persists and rebuilds the app).
    LocaleController.instance.setLanguage(_settings.language);

    // Apply the selected theme mode (persists and rebuilds the app).
    ThemeController.instance.setThemeMode(_settings.themeMode);

    if (!mounted) return;
    Navigator.of(
      context,
    ).pop(true); // Return true to indicate settings were saved
  }

  // Helper for consistent input decoration
  InputDecoration _inputDecoration({String? hintText, String? labelText}) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      hintText: hintText,
      labelText: labelText,
      isDense: true,
      contentPadding: labelText != null
          ? const EdgeInsets.fromLTRB(12, 20, 12, 12)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    );
  }

  // Helper for section card styling
  BoxDecoration _sectionDecoration() {
    final theme = Theme.of(context);
    return BoxDecoration(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: theme.shadowColor.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  // Bold section title style (theme-aware for light/dark).
  TextStyle _sectionTitleStyle() {
    return TextStyle(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  // Small italic helper/hint text style (theme-aware for light/dark).
  TextStyle _hintStyle() {
    return TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    );
  }

  // Small non-italic secondary text style (theme-aware for light/dark).
  TextStyle _secondaryStyle() {
    return TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tab bar - centered
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                labelColor: scheme.primary,
                unselectedLabelColor: scheme.onSurfaceVariant,
                indicatorColor: scheme.primary,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: Colors.transparent,
                tabs: _visibleTabs
                    .map((t) => Tab(text: _tabTitle(t)))
                    .toList(),
              ),
              const SizedBox(height: 8),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: _visibleTabs.map(_buildTabContentFor).toList(),
                ),
              ),
              const SizedBox(height: 16),
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: Text(AppLocalizations.of(context).commonCancel),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _onSave,
                    style: DialogStyles.primaryButtonStyle(context),
                    child: Text(AppLocalizations.of(context).commonOk),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApplicationTab() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Application language selector
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsLanguage,
                  style: _sectionTitleStyle(),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _settings.language,
                  decoration: _inputDecoration(),
                  items: [
                    DropdownMenuItem(
                      value: LocaleController.systemTag,
                      child: Text(l10n.languageSystem),
                    ),
                    DropdownMenuItem(
                      value: 'en',
                      child: Text(l10n.languageEnglish),
                    ),
                    DropdownMenuItem(
                      value: 'fr',
                      child: Text(l10n.languageFrench),
                    ),
                    DropdownMenuItem(
                      value: 'es',
                      child: Text(l10n.languageSpanish),
                    ),
                    DropdownMenuItem(
                      value: 'zh',
                      child: Text(l10n.languageChinese),
                    ),
                    DropdownMenuItem(
                      value: 'ja',
                      child: Text(l10n.languageJapanese),
                    ),
                    DropdownMenuItem(
                      value: 'hi',
                      child: Text(l10n.languageHindi),
                    ),
                    DropdownMenuItem(
                      value: 'de',
                      child: Text(l10n.languageGerman),
                    ),
                    DropdownMenuItem(
                      value: 'pl',
                      child: Text(l10n.languagePolish),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _settings.language = value);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.settingsLanguageHint,
                  style: _hintStyle(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Application theme mode selector
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsThemeMode,
                  style: _sectionTitleStyle(),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _settings.themeMode,
                  decoration: _inputDecoration(),
                  items: [
                    DropdownMenuItem(
                      value: ThemeController.systemTag,
                      child: Text(l10n.settingsThemeModeSystem),
                    ),
                    DropdownMenuItem(
                      value: ThemeController.lightTag,
                      child: Text(l10n.settingsThemeModeLight),
                    ),
                    DropdownMenuItem(
                      value: ThemeController.darkTag,
                      child: Text(l10n.settingsThemeModeDark),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _settings.themeMode = value);
                    // Apply immediately so the change can be previewed live.
                    ThemeController.instance.setThemeMode(value);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.settingsThemeModeHint,
                  style: _hintStyle(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Optional features
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Features', style: _sectionTitleStyle()),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Checkbox(
                      value: _settings.satelliteSupport,
                      onChanged: (value) {
                        setState(
                          () => _settings.satelliteSupport = value ?? false,
                        );
                      },
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(
                          () => _settings.satelliteSupport =
                              !_settings.satelliteSupport,
                        ),
                        child: const Text('Satellite Support'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLicenseTab() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info text
          Text(
            l10n.settingsLicenseInfo,
            style: DialogStyles.bodyStyle,
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _launchUrl('https://www.arrl.org/getting-licensed'),
            child: const Text(
              'www.arrl.org/getting-licensed',
              style: DialogStyles.linkStyle,
            ),
          ),
          const SizedBox(height: 24),
          // Call Sign & Station ID group
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsCallSignStationId,
                  style: _sectionTitleStyle(),
                ),
                const SizedBox(height: 16),
                // Call Sign & Station ID on the same line
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Call Sign
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.settingsCallSign,
                            style: DialogStyles.labelStyle,
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _callSignController,
                            decoration: _inputDecoration(
                              hintText: l10n.settingsCallSignHint,
                            ),
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[A-Za-z0-9]'),
                              ),
                              TextInputFormatter.withFunction(
                                (oldValue, newValue) => newValue.copyWith(
                                  text: newValue.text.toUpperCase(),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Station ID
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.settingsStationId,
                            style: DialogStyles.labelStyle,
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<int>(
                            initialValue: _settings.stationId,
                            decoration: _inputDecoration(),
                            items: List.generate(
                              16,
                              (i) => DropdownMenuItem(
                                value: i,
                                child: Text(
                                  i == 0 ? l10n.settingsNone : i.toString(),
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              setState(() => _settings.stationId = value ?? 0);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Allow Transmit
                Row(
                  children: [
                    Checkbox(
                      value: _settings.allowTransmit,
                      onChanged: _settings.callSign.length >= 3
                          ? (value) {
                              setState(
                                () => _settings.allowTransmit = value ?? false,
                              );
                            }
                          : null,
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: _settings.callSign.length >= 3
                            ? () => setState(
                                () => _settings.allowTransmit =
                                    !_settings.allowTransmit,
                              )
                            : null,
                        child: Text(
                          l10n.settingsAllowTransmit,
                          style: TextStyle(
                            color: _settings.callSign.length >= 3
                                ? null
                                : Theme.of(context).disabledColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_settings.callSign.length < 3)
                  Text(
                    l10n.settingsCallSignHelp,
                    style: _hintStyle(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAprsTab() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsAprsIntro,
            style: DialogStyles.bodyStyle,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsAprsRoutes,
                  style: _sectionTitleStyle(),
                ),
                const SizedBox(height: 8),
                // Routes list
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListView.builder(
                      itemCount: _settings.aprsRoutes.length,
                      itemBuilder: (context, index) {
                        final route = _settings.aprsRoutes[index];
                        final isProtected = AppSettings.isProtectedRouteName(
                          route.name,
                        );
                        final canDelete = !isProtected;
                        return ListTile(
                          dense: true,
                          title: Text(route.name),
                          subtitle: Text(route.path),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                tooltip: isProtected
                                    ? l10n.settingsEditRouteProtected
                                    : l10n.settingsEditRoute,
                                onPressed: isProtected
                                    ? null
                                    : () => _editAprsRoute(index),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete,
                                  size: 20,
                                  color: canDelete ? Colors.red.shade400 : null,
                                ),
                                tooltip: canDelete
                                    ? l10n.settingsDeleteRoute
                                    : l10n.settingsDeleteRouteProtected,
                                onPressed: canDelete
                                    ? () => _deleteAprsRoute(index)
                                    : null,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _addAprsRoute,
                      child: Text(l10n.settingsAdd),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildAprsIsSection(),
        ],
      ),
    );
  }

  /// APRS-IS (internet gateway) settings section shown on the APRS tab.
  Widget _buildAprsIsSection() {
    final l10n = AppLocalizations.of(context);
    final hasCallSign = _settings.callSign.isNotEmpty;
    final account = hasCallSign ? _settings.callSign : l10n.settingsNone;
    final passcodeValid = _aprsIsPasscodeValid;
    final passcodeEntered = _aprsIsPasscodeController.text.trim().isNotEmpty;
    // Turning APRS-IS on requires a valid passcode, but it can always be
    // turned off (e.g. a previously enabled station whose passcode is blank).
    final canToggle = hasCallSign && (passcodeValid || _settings.aprsIsEnabled);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsAprsIsTitle, style: _sectionTitleStyle()),
          const SizedBox(height: 8),
          Text(l10n.settingsAprsIsIntro, style: DialogStyles.bodyStyle),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _launchUrl('https://www.aprs-is.net'),
            child: const Text('www.aprs-is.net', style: DialogStyles.linkStyle),
          ),
          const SizedBox(height: 16),
          if (!hasCallSign) ...[
            Text(l10n.settingsAprsIsNoCallSign, style: _secondaryStyle()),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Checkbox(
                value: _settings.aprsIsEnabled,
                onChanged: canToggle
                    ? (value) => setState(
                          () => _settings.aprsIsEnabled = value ?? false,
                        )
                    : null,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: canToggle
                      ? () => setState(
                            () => _settings.aprsIsEnabled =
                                !_settings.aprsIsEnabled,
                          )
                      : null,
                  child: Text(l10n.settingsAprsIsEnable),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.settingsAprsIsPasscodeFor(account),
                  style: DialogStyles.labelStyle),
              const SizedBox(height: 4),
              TextField(
                controller: _aprsIsPasscodeController,
                enabled: hasCallSign,
                // Once APRS-IS is enabled with a valid passcode, hide the
                // passcode behind dots and lock the field. The user must
                // un-check APRS-IS to reveal and change it.
                readOnly: _settings.aprsIsEnabled && passcodeValid,
                obscureText: _settings.aprsIsEnabled && passcodeValid,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(
                  hintText: l10n.settingsAprsIsPasscodeHint,
                ).copyWith(
                  // Highlight the field in light red when a passcode is
                  // entered but does not match the call sign.
                  fillColor: (passcodeEntered && !passcodeValid)
                      ? const Color(0xFFFFCDD2)
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.settingsAprsIsServerRegion,
                  style: DialogStyles.labelStyle),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _aprsIsCustomServer
                    ? ''
                    : _aprsIsServerController.text.trim(),
                decoration: _inputDecoration(),
                items: _aprsIsRegionItems(l10n),
                onChanged: hasCallSign
                    ? (value) => setState(() {
                          if (value == null || value.isEmpty) {
                            _aprsIsCustomServer = true;
                          } else {
                            _aprsIsCustomServer = false;
                            _aprsIsServerController.text = value;
                            _aprsIsPortController.text =
                                _aprsIsDefaultPort.toString();
                          }
                        })
                    : null,
              ),
              if (_aprsIsCustomServer) ...[
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.settingsAprsIsServer,
                              style: DialogStyles.labelStyle),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _aprsIsServerController,
                            enabled: hasCallSign,
                            decoration: _inputDecoration().copyWith(
                              suffixIcon: _presetMenu(
                                enabled: hasCallSign,
                                presets: _aprsIsServerPresets,
                                onSelected: (value) => setState(
                                  () => _aprsIsServerController.text = value,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.settingsPort,
                              style: DialogStyles.labelStyle),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _aprsIsPortController,
                            enabled: hasCallSign,
                            keyboardType: TextInputType.number,
                            decoration: _inputDecoration().copyWith(
                              suffixIcon: _presetMenu(
                                enabled: hasCallSign,
                                presets: _aprsIsPortPresets,
                                onSelected: (value) => setState(
                                  () => _aprsIsPortController.text = value,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.settingsAprsIsRange, style: DialogStyles.labelStyle),
              const SizedBox(height: 4),
              DropdownButtonFormField<int>(
                initialValue: _aprsIsRangeItems(l10n)
                        .any((e) => e.value == _settings.aprsIsRangeKm)
                    ? _settings.aprsIsRangeKm
                    : 0,
                decoration: _inputDecoration(),
                items: _aprsIsRangeItems(l10n),
                onChanged: hasCallSign
                    ? (value) => setState(
                          () => _settings.aprsIsRangeKm = value ?? 0,
                        )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.settingsAprsIsRangeHelp, style: _secondaryStyle()),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _settings.aprsIsGateToRf,
                onChanged: hasCallSign
                    ? (value) => setState(
                          () => _settings.aprsIsGateToRf = value ?? false,
                        )
                    : null,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: hasCallSign
                      ? () => setState(
                            () => _settings.aprsIsGateToRf =
                                !_settings.aprsIsGateToRf,
                          )
                      : null,
                  child: Text(l10n.settingsAprsIsGateToRf),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(l10n.settingsAprsIsGateToRfHelp, style: _secondaryStyle()),
        ],
      ),
    );
  }

  /// Default APRS-IS port (filtered feed) used when a well-known server region
  /// is selected from the simplified dropdown.
  static const int _aprsIsDefaultPort = 14580;

  /// Well-known APRS-IS server hostnames offered as friendly regions in the
  /// simplified server dropdown. A stored server matching one of these (on the
  /// default port) shows the region instead of the raw server/port fields.
  static const List<String> _aprsIsRegionHosts = [
    'rotate.aprs2.net',
    'noam.aprs2.net',
    'soam.aprs2.net',
    'euro.aprs2.net',
    'asia.aprs2.net',
    'aunz.aprs2.net',
  ];

  /// Region dropdown items mapping a friendly name to a well-known server
  /// hostname. The final entry (empty value) is "Custom", which reveals the
  /// raw server/port fields.
  List<DropdownMenuItem<String>> _aprsIsRegionItems(AppLocalizations l10n) {
    return [
      DropdownMenuItem(
        value: 'rotate.aprs2.net',
        child: Text(l10n.settingsAprsIsRegionWorldwide),
      ),
      DropdownMenuItem(
        value: 'noam.aprs2.net',
        child: Text(l10n.settingsAprsIsRegionNorthAmerica),
      ),
      DropdownMenuItem(
        value: 'soam.aprs2.net',
        child: Text(l10n.settingsAprsIsRegionSouthAmerica),
      ),
      DropdownMenuItem(
        value: 'euro.aprs2.net',
        child: Text(l10n.settingsAprsIsRegionEurope),
      ),
      DropdownMenuItem(
        value: 'asia.aprs2.net',
        child: Text(l10n.settingsAprsIsRegionAsia),
      ),
      DropdownMenuItem(
        value: 'aunz.aprs2.net',
        child: Text(l10n.settingsAprsIsRegionOceania),
      ),
      DropdownMenuItem(
        value: '',
        child: Text(l10n.settingsAprsIsRegionCustom),
      ),
    ];
  }

  /// Common APRS-IS servers offered in the preset dropdown. Users may still
  /// type any server they like.
  static const List<(String, String)> _aprsIsServerPresets = [
    ('rotate.aprs2.net', 'Worldwide (rotate)'),
    ('noam.aprs2.net', 'North America'),
    ('soam.aprs2.net', 'South America'),
    ('euro.aprs2.net', 'Europe'),
    ('asia.aprs2.net', 'Asia'),
    ('aunz.aprs2.net', 'Oceania'),
  ];

  /// Common APRS-IS ports offered in the preset dropdown. Users may still type
  /// any port they like.
  static const List<(String, String)> _aprsIsPortPresets = [
    ('14580', 'Filtered feed'),
    ('10152', 'Full feed'),
    ('23000', 'Full feed (UDP)'),
  ];

  /// A trailing dropdown button that fills a text field with a chosen preset.
  /// Each preset is a (value, description) pair; the value is what gets typed
  /// into the field.
  Widget _presetMenu({
    required bool enabled,
    required List<(String, String)> presets,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      enabled: enabled,
      icon: const Icon(Icons.arrow_drop_down),
      tooltip: '',
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final (value, label) in presets)
          PopupMenuItem<String>(
            value: value,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: _secondaryStyle(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// APRS-IS range dropdown items. Distances are stored in kilometres; the
  /// labels are shown in miles or km depending on the OS regional (metric)
  /// setting, reusing the same detection as the APRS weather feature.
  List<DropdownMenuItem<int>> _aprsIsRangeItems(AppLocalizations l10n) {
    final metric = WeatherData.systemUsesMetric;
    final items = <DropdownMenuItem<int>>[
      DropdownMenuItem<int>(value: 0, child: Text(l10n.settingsAprsIsRangeOff)),
    ];
    for (final n in const [10, 20, 30, 40, 50, 60]) {
      final km = metric ? n : (n * 1.60934).round();
      items.add(
        DropdownMenuItem<int>(
          value: km,
          child: Text(
            metric
                ? l10n.settingsAprsIsRangeKm(n)
                : l10n.settingsAprsIsRangeMiles(n),
          ),
        ),
      );
    }
    return items;
  }

  void _addAprsRoute() async {
    final result = await showDialog<AprsRoute>(
      context: context,
      builder: (context) => AprsRouteDialog(
        existingNames: _settings.aprsRoutes.map((r) => r.name).toList(),
      ),
    );
    if (result != null) {
      setState(() => _settings.aprsRoutes.add(result));
    }
  }

  void _editAprsRoute(int index) async {
    final result = await showDialog<AprsRoute>(
      context: context,
      builder: (context) => AprsRouteDialog(
        route: _settings.aprsRoutes[index],
        existingNames: [
          for (var i = 0; i < _settings.aprsRoutes.length; i++)
            if (i != index) _settings.aprsRoutes[i].name,
        ],
      ),
    );
    if (result != null) {
      setState(() => _settings.aprsRoutes[index] = result);
    }
  }

  void _deleteAprsRoute(int index) {
    setState(() => _settings.aprsRoutes.removeAt(index));
  }

  /// Human-readable size, e.g. "923 MB" or "1.2 GB".
  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  /// Display name for a recognition language code.
  String _sttLanguageName(String code) {
    final l10n = AppLocalizations.of(context);
    switch (code) {
      case 'auto':
        return l10n.settingsLangAutoDetect;
      case 'en':
        return l10n.languageEnglish;
      case 'zh':
        return l10n.settingsLangChinese;
      case 'ja':
        return l10n.settingsLangJapanese;
      case 'ko':
        return l10n.settingsLangKorean;
      case 'yue':
        return l10n.settingsLangCantonese;
    }
    return code;
  }

  /// Speech-to-text setup: model selection, language and on-device management.
  Widget _buildSpeechRecognitionSection() {
    final l10n = AppLocalizations.of(context);
    final model = SherpaModelManager.modelById(_settings.voiceModel);
    final langCodes = model.languages ?? const <String>[];
    final sttLang = langCodes.contains(_settings.voiceLanguage)
        ? _settings.voiceLanguage
        : (langCodes.isNotEmpty ? langCodes.first : 'auto');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsSpeechToText,
            style: _sectionTitleStyle(),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.settingsSpeechToTextInfo,
            style: DialogStyles.bodyStyle,
          ),
          const SizedBox(height: 16),
          Text(l10n.settingsModel, style: DialogStyles.labelStyle),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: model.id,
            decoration: _inputDecoration(),
            items: SherpaModelManager.models
                .map(
                  (m) => DropdownMenuItem(
                    value: m.id,
                    child: Text('${m.name}  (${m.downloadLabel})'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              final id = value ?? SherpaModelManager.defaultModelId;
              setState(() => _settings.voiceModel = id);
              SherpaModelManager.refreshStatus(id);
            },
          ),
          const SizedBox(height: 6),
          Text(
            model.description,
            style: _secondaryStyle(),
          ),
          const SizedBox(height: 16),
          if (model.multilingual) ...[
            Text(
              l10n.settingsRecognitionLanguage,
              style: DialogStyles.labelStyle,
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: sttLang,
              decoration: _inputDecoration(),
              items: langCodes
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(_sttLanguageName(c)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() => _settings.voiceLanguage = value ?? 'auto');
              },
            ),
            const SizedBox(height: 6),
            Text(
              l10n.settingsRecognitionLanguageHelp,
              style: _secondaryStyle(),
            ),
            const SizedBox(height: 16),
          ],
          Text(l10n.settingsStatus, style: DialogStyles.labelStyle),
          const SizedBox(height: 4),
          ValueListenableBuilder<SttModelStatus>(
            valueListenable: SherpaModelManager.statusOf(model.id),
            builder: (context, status, _) =>
                _buildSttModelStatus(model, status),
          ),
        ],
      ),
    );
  }

  /// Status line + actions for the selected recognition [model].
  Widget _buildSttModelStatus(SttModel model, SttModelStatus status) {
    final l10n = AppLocalizations.of(context);
    final busy =
        status.state == SttModelState.downloading ||
        status.state == SttModelState.installing;

    Widget statusLine;
    switch (status.state) {
      case SttModelState.ready:
        statusLine = Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: FutureBuilder<int>(
                future: SherpaModelManager.installedSizeBytes(model.id),
                builder: (context, snap) {
                  final size = snap.data ?? 0;
                  final suffix = size > 0 ? ' (${_formatBytes(size)})' : '';
                  return Text(
                    l10n.settingsModelInstalled(suffix),
                    style: DialogStyles.bodyStyle,
                  );
                },
              ),
            ),
          ],
        );
        break;
      case SttModelState.downloading:
        final pct = status.progress;
        final detail = status.totalBytes > 0
            ? l10n.settingsBytesOf(
                _formatBytes(status.receivedBytes),
                _formatBytes(status.totalBytes),
              )
            : _formatBytes(status.receivedBytes);
        statusLine = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pct != null
                  ? l10n.settingsDownloadingModelPct(
                      (pct * 100).toStringAsFixed(0),
                    )
                  : l10n.settingsDownloadingModel,
              style: DialogStyles.bodyStyle,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: pct),
            const SizedBox(height: 4),
            Text(
              detail,
              style: _secondaryStyle(),
            ),
          ],
        );
        break;
      case SttModelState.installing:
        final pct = status.progress;
        statusLine = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pct != null
                  ? l10n.settingsInstallingModelPct(
                      (pct * 100).toStringAsFixed(0),
                    )
                  : l10n.settingsInstallingModel,
              style: DialogStyles.bodyStyle,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: pct),
          ],
        );
        break;
      case SttModelState.error:
        statusLine = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                status.message ?? l10n.settingsModelInstallError,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
        break;
      case SttModelState.notInstalled:
        statusLine = Text(
          l10n.settingsModelNotDownloaded(model.downloadLabel),
          style: DialogStyles.bodyStyle,
        );
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        statusLine,
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: busy || status.state == SttModelState.ready
                  ? null
                  : () => SherpaModelManager.ensureModel(model.id),
              icon: const Icon(Icons.download, size: 18),
              label: Text(
                status.state == SttModelState.error
                    ? l10n.settingsRetry
                    : l10n.settingsDownload,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: busy || status.state != SttModelState.ready
                  ? null
                  : () => _confirmRemoveSttModel(model),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(l10n.settingsRemove),
            ),
          ],
        ),
      ],
    );
  }

  /// Confirms then deletes the cached files for [model] from disk.
  Future<void> _confirmRemoveSttModel(SttModel model) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsRemoveSttModelTitle),
        content: Text(l10n.settingsRemoveSttModelBody(model.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsRemove),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SherpaModelManager.deleteModel(model.id);
    }
  }

  Widget _buildCommsTab() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsCommsIntro,
            style: DialogStyles.bodyStyle,
          ),
          const SizedBox(height: 16),
          // Speech Recognition (sherpa-onnx) – not available on Android.
          if (defaultTargetPlatform != TargetPlatform.android) ...[
            _buildSpeechRecognitionSection(),
            const SizedBox(height: 16),
          ],
          // Text-to-Speech
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsTextToSpeech,
                  style: _sectionTitleStyle(),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.settingsTextToSpeechInfo,
                  style: DialogStyles.bodyStyle,
                ),
                const SizedBox(height: 16),
                if (_voicesLoaded && !_ttsAvailable) ...[
                  _buildTtsUnavailableNotice(),
                  const SizedBox(height: 16),
                ],
                Text(l10n.settingsVoice, style: DialogStyles.labelStyle),
                const SizedBox(height: 4),
                _buildVoiceDropdown(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      l10n.settingsSpeechRate,
                      style: DialogStyles.labelStyle,
                    ),
                    const Spacer(),
                    Text(
                      _settings.voiceSpeechRate.toStringAsFixed(2),
                      style: DialogStyles.bodyStyle,
                    ),
                  ],
                ),
                Slider(
                  value: _settings.voiceSpeechRate.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: _settings.voiceSpeechRate.toStringAsFixed(2),
                  onChanged: (value) {
                    setState(() => _settings.voiceSpeechRate = value);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(l10n.settingsPitch, style: DialogStyles.labelStyle),
                    const Spacer(),
                    Text(
                      _settings.voicePitch.toStringAsFixed(2),
                      style: DialogStyles.bodyStyle,
                    ),
                  ],
                ),
                Slider(
                  value: _settings.voicePitch.clamp(0.5, 2.0),
                  min: 0.5,
                  max: 2.0,
                  divisions: 30,
                  label: _settings.voicePitch.toStringAsFixed(2),
                  onChanged: (value) {
                    setState(() => _settings.voicePitch = value);
                  },
                ),
                if (TtsService.instance.isPreviewSupported) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _previewVoice,
                      icon: const Icon(Icons.volume_up, size: 18),
                      label: Text(l10n.settingsPreview),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A highlighted notice shown in the Text-to-Speech section when synthesis is
  /// unavailable on this machine, including platform-specific setup steps.
  Widget _buildTtsUnavailableNotice() {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsTtsUnavailableTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  _ttsInstructions,
                  style: DialogStyles.bodyStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Speaks a short sample using the currently selected voice, rate and pitch
  /// so the user can audition the Text-to-Speech settings before saving.
  void _previewVoice() {
    TtsService.instance.preview(
      'This is a Handi-Talky Commander voice preview.',
      voiceJson: _settings.voice.isEmpty ? null : _settings.voice,
      rate: _settings.voiceSpeechRate,
      pitch: _settings.voicePitch,
    );
  }

  /// Builds the voice selection dropdown for the Text-to-Speech section,
  /// populated from the platform's available voices.
  Widget _buildVoiceDropdown() {
    final l10n = AppLocalizations.of(context);
    if (!_voicesLoaded) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(l10n.settingsLoadingVoices, style: DialogStyles.bodyStyle),
          ],
        ),
      );
    }

    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: '', child: Text(l10n.settingsSystemDefault)),
      for (final voice in _voices)
        DropdownMenuItem(
          value: TtsService.encodeVoice(voice),
          child: Text(TtsService.voiceLabel(voice)),
        ),
    ];

    // Ensure the persisted value is selectable even if the voice list changed.
    final values = items.map((i) => i.value).toSet();
    final current = values.contains(_settings.voice) ? _settings.voice : '';

    return DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      decoration: _inputDecoration(),
      items: items,
      onChanged: (value) {
        setState(() => _settings.voice = value ?? '');
      },
    );
  }

  Widget _buildWinlinkTab() {
    final l10n = AppLocalizations.of(context);
    final winlinkLogin =
        _settings.winlinkUseStationId && _settings.stationId > 0
        ? '${_settings.callSign}-${_settings.stationId}'
        : _settings.callSign;
    final winlinkAccount = _settings.callSign.isNotEmpty
        ? '$winlinkLogin@winlink.org'
        : l10n.settingsNone;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsWinlinkIntro,
            style: DialogStyles.bodyStyle,
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _launchUrl('https://www.winlink.org'),
            child: const Text('www.winlink.org', style: DialogStyles.linkStyle),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsWinlinkAccount,
                  style: _sectionTitleStyle(),
                ),
                const SizedBox(height: 16),
                Text(l10n.settingsPasswordFor(winlinkAccount),
                    style: DialogStyles.labelStyle),
                const SizedBox(height: 4),
                TextField(
                  controller: _winlinkPasswordController,
                  enabled: _settings.callSign.isNotEmpty,
                  obscureText: true,
                  decoration: _inputDecoration(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: _settings.winlinkUseStationId,
                      onChanged: (value) {
                        setState(
                          () => _settings.winlinkUseStationId = value ?? false,
                        );
                      },
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(
                          () => _settings.winlinkUseStationId =
                              !_settings.winlinkUseStationId,
                        ),
                        child: Text(l10n.settingsUseStationIdWinlink),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEchoLinkTab() {
    final l10n = AppLocalizations.of(context);
    final hasCallSign = _settings.callSign.isNotEmpty;
    final echoLinkAccount = hasCallSign ? _settings.callSign : l10n.settingsNone;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsEchoLinkIntro,
            style: DialogStyles.bodyStyle,
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _launchUrl('https://www.echolink.org'),
            child:
                const Text('www.echolink.org', style: DialogStyles.linkStyle),
          ),
          const SizedBox(height: 16),
          if (!hasCallSign) ...[
            Text(
              l10n.settingsEchoLinkNoCallSign,
              style: _secondaryStyle(),
            ),
            const SizedBox(height: 16),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsEchoLinkAccount,
                  style: _sectionTitleStyle(),
                ),
                const SizedBox(height: 16),
                Text(l10n.settingsPasswordFor(echoLinkAccount),
                    style: DialogStyles.labelStyle),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _echoLinkPasswordController,
                        enabled: hasCallSign,
                        obscureText: true,
                        decoration: _inputDecoration(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: (hasCallSign &&
                              _echoLinkPasswordController.text.isNotEmpty &&
                              !_echoLinkTesting)
                          ? _testEchoLinkConnection
                          : null,
                      child: Text(l10n.settingsTest),
                    ),
                  ],
                ),
                if (_echoLinkTestResult.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _echoLinkTestResult,
                    style: TextStyle(
                      color: _echoLinkTesting
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : (_echoLinkTestOk
                              ? Colors.green.shade700
                              : Colors.red.shade700),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(l10n.settingsEchoLinkLocation,
                    style: DialogStyles.labelStyle),
                const SizedBox(height: 4),
                TextField(
                  controller: _echoLinkLocationController,
                  enabled: hasCallSign,
                  decoration: _inputDecoration(),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.settingsEchoLinkLocationHelp,
                  style: _secondaryStyle(),
                ),
              ],
            ),
          ),
          if (hasCallSign) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _sectionDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsEchoLinkCreateAccount,
                    style: _sectionTitleStyle(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.settingsEchoLinkCreateAccountHelp,
                    style: _secondaryStyle(),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _createEchoLinkAccount,
                      child: Text(l10n.settingsEchoLinkCreateAccountButton),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAllStarTab() {
    final l10n = AppLocalizations.of(context);
    final hasCallSign = _settings.callSign.isNotEmpty;
    final allStarAccount = hasCallSign ? _settings.callSign : l10n.settingsNone;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsAllStarIntro,
            style: DialogStyles.bodyStyle,
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _launchUrl('https://www.allstarlink.org'),
            child: const Text('www.allstarlink.org',
                style: DialogStyles.linkStyle),
          ),
          const SizedBox(height: 16),
          if (!hasCallSign) ...[
            Text(
              l10n.settingsAllStarNoCallsign,
              style: _secondaryStyle(),
            ),
            const SizedBox(height: 16),
          ],
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsAllStarAccount,
                  style: _sectionTitleStyle(),
                ),
                const SizedBox(height: 16),
                Text(l10n.settingsPasswordFor(allStarAccount),
                    style: DialogStyles.labelStyle),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _allStarPasswordController,
                        enabled: hasCallSign,
                        obscureText: true,
                        decoration: _inputDecoration(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: (hasCallSign &&
                              _allStarPasswordController.text.isNotEmpty &&
                              !_allStarTesting)
                          ? _testAllStarConnection
                          : null,
                      child: Text(l10n.settingsTest),
                    ),
                  ],
                ),
                if (_allStarTestResult.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _allStarTestResult,
                    style: TextStyle(
                      color: _allStarTesting
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : (_allStarTestOk
                              ? Colors.green.shade700
                              : Colors.red.shade700),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServersTab() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsServersIntro,
            style: DialogStyles.bodyStyle,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsLocalServers,
                  style: _sectionTitleStyle(),
                ),
                const SizedBox(height: 16),
                // Web Server
                Row(
                  children: [
                    Checkbox(
                      value: _settings.webServerEnabled,
                      onChanged: (value) {
                        setState(
                          () => _settings.webServerEnabled = value ?? false,
                        );
                      },
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(
                          () => _settings.webServerEnabled =
                              !_settings.webServerEnabled,
                        ),
                        child: Text(l10n.settingsEnableWebServer),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Row(
                    children: [
                      Text(l10n.settingsPort, style: DialogStyles.labelStyle),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _webPortController,
                          enabled: _settings.webServerEnabled,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                // AGWPE Server
                Row(
                  children: [
                    Checkbox(
                      value: _settings.agwpeServerEnabled,
                      onChanged: (value) {
                        setState(
                          () => _settings.agwpeServerEnabled = value ?? false,
                        );
                      },
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(
                          () => _settings.agwpeServerEnabled =
                              !_settings.agwpeServerEnabled,
                        ),
                        child: Text(l10n.settingsEnableAgwpeServer),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Row(
                    children: [
                      Text(l10n.settingsPort, style: DialogStyles.labelStyle),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _agwpePortController,
                          enabled: _settings.agwpeServerEnabled,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsHomeAssistant,
                  style: _sectionTitleStyle(),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.settingsHomeAssistantDescription,
                  style: DialogStyles.bodyStyle,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: _settings.homeAssistantEnabled,
                      onChanged: (value) {
                        setState(
                          () => _settings.homeAssistantEnabled = value ?? false,
                        );
                      },
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(
                          () => _settings.homeAssistantEnabled =
                              !_settings.homeAssistantEnabled,
                        ),
                        child: Text(l10n.settingsEnableHomeAssistant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.settingsHomeAssistantMqttUrl,
                  style: DialogStyles.labelStyle,
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _homeAssistantUrlController,
                  decoration: _inputDecoration().copyWith(
                    hintText: 'mqtt://homeassistant.local:1883',
                  ),
                  onChanged: (_) {
                    setState(() => _homeAssistantTestResult = '');
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.settingsHomeAssistantUsername,
                            style: DialogStyles.labelStyle,
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _homeAssistantUsernameController,
                            decoration: _inputDecoration(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.settingsHomeAssistantPassword,
                            style: DialogStyles.labelStyle,
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _homeAssistantPasswordController,
                            obscureText: true,
                            decoration: _inputDecoration(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: (_homeAssistantUrlController.text
                                  .trim()
                                  .isNotEmpty &&
                              !_homeAssistantTesting)
                          ? _testHomeAssistantConnection
                          : null,
                      child: Text(l10n.settingsTest),
                    ),
                    if (_homeAssistantTestResult.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _homeAssistantTestResult,
                          style: TextStyle(
                            color: _homeAssistantTesting
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : (_homeAssistantTestOk
                                    ? Colors.green.shade700
                                    : Colors.red.shade700),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the serial ports available on the system, or an empty list on
  /// platforms that do not support serial access (web/mobile). Wrapped in a
  /// try/catch because port enumeration can throw on unsupported platforms.
  static List<String> _listSerialPorts() {
    if (!_serialGpsSupported) return const [];
    try {
      return SerialPort.availablePorts;
    } catch (_) {
      return const [];
    }
  }

  /// Builds the dropdown items for the GPS serial port: always "None" plus any
  /// available ports, and the currently-configured value even if it is no
  /// longer present (so the saved selection stays visible).
  List<DropdownMenuItem<String>> _gpsPortItems() {
    // Use a set: libserialport can enumerate the same port twice on Windows,
    // which would otherwise create duplicate dropdown items and trip
    // DropdownButton's "exactly one matching value" assertion.
    final values = <String>{'None', ..._availablePorts};
    if (_settings.gpsSerialPort.isNotEmpty) {
      values.add(_settings.gpsSerialPort);
    }
    return values
        .map(
          (p) => DropdownMenuItem(
            value: p,
            child: Text(p, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList();
  }

  Widget _buildMapTab() {
    final l10n = AppLocalizations.of(context);
    final mapIntro = _serialGpsSupported
        ? l10n.settingsMapIntroGps
        : l10n.settingsMapIntroNoGps;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mapIntro, style: DialogStyles.bodyStyle),
          const SizedBox(height: 16),
          if (_serialGpsSupported) ...[
            // GPS Settings
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _sectionDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsGpsSerialPort,
                    style: _sectionTitleStyle(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 13,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.settingsSerialPort,
                              style: DialogStyles.labelStyle,
                            ),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              initialValue: _settings.gpsSerialPort,
                              isExpanded: true,
                              decoration: _inputDecoration(),
                              items: _gpsPortItems(),
                              onChanged: (value) {
                                setState(
                                  () =>
                                      _settings.gpsSerialPort = value ?? 'None',
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 7,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.settingsBaudRate,
                              style: DialogStyles.labelStyle,
                            ),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<int>(
                              initialValue: _settings.gpsBaudRate,
                              decoration: _inputDecoration(),
                              items: _baudRates
                                  .map(
                                    (b) => DropdownMenuItem(
                                      value: b,
                                      child: Text(b.toString()),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(
                                  () => _settings.gpsBaudRate = value ?? 4800,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _settings.shareSerialGpsLocation,
                        onChanged: (value) {
                          setState(
                            () => _settings.shareSerialGpsLocation =
                                value ?? false,
                          );
                        },
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(
                            () => _settings.shareSerialGpsLocation =
                                !_settings.shareSerialGpsLocation,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 12),
                              Text(l10n.settingsShareGpsLocation),
                              const SizedBox(height: 2),
                              Text(
                                l10n.settingsShareGpsLocationHelp,
                                style: _secondaryStyle(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Airplane Tracking
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsAirplaneTracking,
                  style: _sectionTitleStyle(),
                ),
                const SizedBox(height: 16),
                Text(l10n.settingsServerUrl, style: DialogStyles.labelStyle),
                const SizedBox(height: 4),
                TextField(
                  controller: _airplaneUrlController,
                  onChanged: (_) {
                    // Clear the previous result when the URL changes, matching
                    // the C# dump1090urlTextBox_TextChanged behavior.
                    setState(() => _airplaneTestResult = '');
                  },
                  decoration: _inputDecoration(
                    hintText: 'http://localhost:8080/data/aircraft.json',
                  ),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 360;
                    return Row(
                      children: [
                        ElevatedButton(
                          onPressed:
                              (_airplaneUrlController.text.trim().isNotEmpty &&
                                  !_airplaneTesting)
                              ? _testAirplaneConnection
                              : null,
                          child: Text(
                            narrow
                                ? l10n.settingsTest
                                : l10n.settingsTestConnection,
                          ),
                        ),
                        if (_airplaneTestResult.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _airplaneTestResult,
                              style: TextStyle(
                                color: _airplaneTesting
                                    ? Theme.of(context).colorScheme.onSurfaceVariant
                                    : (_airplaneTestOk
                                          ? Colors.green.shade700
                                          : Colors.red.shade700),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Formats a limit value for display: 0 means "Unlimited".
  String _limitLabel(int value) {
    return value == 0
        ? AppLocalizations.of(context).settingsUnlimited
        : value.toString();
  }

  /// Builds a single limit slider row.
  Widget _buildLimitSlider({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    int? currentCount,
  }) {
    final l10n = AppLocalizations.of(context);
    // Slider positions: 0=Unlimited, then log-ish steps.
    const List<int> steps = [0, 50, 100, 200, 500, 1000, 2000, 5000, 10000];
    final int idx = steps.indexOf(value);
    final int sliderIndex = idx >= 0 ? idx : 0;

    final bool willDelete =
        currentCount != null && value > 0 && currentCount > value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(label, style: DialogStyles.labelStyle),
            ),
            const SizedBox(width: 8),
            Text(
              _limitLabel(value),
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: willDelete ? Colors.red.shade700 : null,
              ),
            ),
          ],
        ),
        if (currentCount != null)
          Text(
            l10n.settingsLimitCurrent(currentCount),
            style: _secondaryStyle(),
          ),
        Slider(
          padding: const EdgeInsets.symmetric(vertical: 8),
          value: sliderIndex.toDouble(),
          min: 0,
          max: (steps.length - 1).toDouble(),
          divisions: steps.length - 1,
          label: _limitLabel(steps[sliderIndex.clamp(0, steps.length - 1)]),
          onChanged: (v) {
            onChanged(steps[v.round().clamp(0, steps.length - 1)]);
          },
        ),
        if (willDelete)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              l10n.settingsLimitItemsDeleted(currentCount - value),
              style: TextStyle(
                fontSize: 12,
                color: Colors.red.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLimitsTab() {
    final l10n = AppLocalizations.of(context);
    final counts = _historyCounts;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsLimitsIntro,
            style: DialogStyles.bodyStyle,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsHistoryLimits,
                  style: _sectionTitleStyle(),
                ),
                const SizedBox(height: 16),
                _buildLimitSlider(
                  label: l10n.settingsLimitAprsMessages,
                  value: _settings.maxAprsMessages,
                  currentCount: counts?.aprsMessages,
                  onChanged: (v) =>
                      setState(() => _settings.maxAprsMessages = v),
                ),
                const SizedBox(height: 8),
                _buildLimitSlider(
                  label: l10n.settingsLimitPackets,
                  value: _settings.maxPackets,
                  currentCount: counts?.packets,
                  onChanged: (v) => setState(() => _settings.maxPackets = v),
                ),
                const SizedBox(height: 8),
                _buildLimitSlider(
                  label: l10n.settingsLimitSstvImages,
                  value: _settings.maxSstvImages,
                  currentCount: counts?.sstvImages,
                  onChanged: (v) =>
                      setState(() => _settings.maxSstvImages = v),
                ),
                const SizedBox(height: 8),
                _buildLimitSlider(
                  label: l10n.settingsLimitCommEvents,
                  value: _settings.maxCommEvents,
                  currentCount: counts?.commEvents,
                  onChanged: (v) =>
                      setState(() => _settings.maxCommEvents = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Result of a successful EchoLink account creation.
class _EchoLinkAccountResult {
  /// The password the user chose (and which was registered with the server).
  final String password;

  /// The email address the user entered (used for web validation).
  final String email;

  /// True when the call sign was already registered and validated with this
  /// password (nothing new was created); false when a new pending account was
  /// registered and still needs web validation.
  final bool alreadyValidated;

  const _EchoLinkAccountResult({
    required this.password,
    required this.email,
    required this.alreadyValidated,
  });
}

/// Dialog that registers a new EchoLink account for a given call sign.
///
/// Collects an email address and a new password, then performs the directory
/// login that creates the (pending) account. Pops an [_EchoLinkAccountResult]
/// on success, or null if cancelled.
class _EchoLinkCreateAccountDialog extends StatefulWidget {
  final String callsign;
  final String location;

  const _EchoLinkCreateAccountDialog({
    required this.callsign,
    required this.location,
  });

  @override
  State<_EchoLinkCreateAccountDialog> createState() =>
      _EchoLinkCreateAccountDialogState();
}

class _EchoLinkCreateAccountDialogState
    extends State<_EchoLinkCreateAccountDialog> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  static final RegExp _emailRegExp =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onChanged);
    _passwordController.addListener(_onChanged);
    _confirmController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _emailValid => _emailRegExp.hasMatch(_emailController.text.trim());
  bool get _passwordsMatch =>
      _passwordController.text == _confirmController.text;

  bool get _canCreate =>
      !_busy &&
      _emailValid &&
      _passwordController.text.isNotEmpty &&
      _passwordsMatch;

  InputDecoration _decoration(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = '';
    });

    final EchoLinkCredentialResult result = await testEchoLinkCredentials(
      callsign: widget.callsign,
      password: _passwordController.text,
      location: widget.location,
    );

    if (!mounted) return;

    switch (result.status) {
      case EchoLinkCredentialStatus.validationPending:
        Navigator.of(context).pop(
          _EchoLinkAccountResult(
            password: _passwordController.text,
            email: _emailController.text.trim(),
            alreadyValidated: false,
          ),
        );
        return;
      case EchoLinkCredentialStatus.valid:
        Navigator.of(context).pop(
          _EchoLinkAccountResult(
            password: _passwordController.text,
            email: _emailController.text.trim(),
            alreadyValidated: true,
          ),
        );
        return;
      case EchoLinkCredentialStatus.incorrectPassword:
        setState(() {
          _busy = false;
          _error = l10n.settingsEchoLinkAccountExists;
        });
        return;
      case EchoLinkCredentialStatus.unreachable:
        setState(() {
          _busy = false;
          _error = l10n.settingsEchoLinkTestUnreachable;
        });
        return;
      case EchoLinkCredentialStatus.unknown:
        setState(() {
          _busy = false;
          _error = l10n.settingsEchoLinkTestInconclusive;
        });
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return HTDialog(
      title: l10n.settingsEchoLinkCreateAccountTitle,
      maxWidth: 440,
      maxHeight: 520,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.settingsEchoLinkCreateAccountIntro(widget.callsign),
              style: DialogStyles.bodyStyle,
            ),
            const SizedBox(height: 16),
            Text(l10n.settingsEchoLinkEmail, style: DialogStyles.labelStyle),
            const SizedBox(height: 4),
            TextField(
              controller: _emailController,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: _decoration(context),
            ),
            if (_emailController.text.isNotEmpty && !_emailValid) ...[
              const SizedBox(height: 4),
              Text(
                l10n.settingsEchoLinkEmailInvalid,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            Text(l10n.settingsEchoLinkNewPassword,
                style: DialogStyles.labelStyle),
            const SizedBox(height: 4),
            TextField(
              controller: _passwordController,
              enabled: !_busy,
              obscureText: true,
              decoration: _decoration(context),
            ),
            const SizedBox(height: 16),
            Text(l10n.settingsEchoLinkConfirmPassword,
                style: DialogStyles.labelStyle),
            const SizedBox(height: 4),
            TextField(
              controller: _confirmController,
              enabled: !_busy,
              obscureText: true,
              decoration: _decoration(context),
            ),
            if (_confirmController.text.isNotEmpty && !_passwordsMatch) ...[
              const SizedBox(height: 4),
              Text(
                l10n.settingsEchoLinkPasswordMismatch,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.settingsEchoLinkCreating,
                      style: DialogStyles.bodyStyle),
                ],
              ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _error,
                style: TextStyle(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          style: DialogStyles.secondaryButtonStyle(context),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _canCreate ? _submit : null,
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.settingsEchoLinkCreateAccountButton),
        ),
      ],
    );
  }
}

/// Dialog for editing APRS routes
class AprsRouteDialog extends StatefulWidget {
  final AprsRoute? route;

  /// Names of other routes that already exist. The OK button is disabled when
  /// the entered name matches one of these (case-insensitive), preventing
  /// duplicate route names.
  final List<String> existingNames;

  const AprsRouteDialog({super.key, this.route, this.existingNames = const []});

  @override
  State<AprsRouteDialog> createState() => _AprsRouteDialogState();
}

class _AprsRouteDialogState extends State<AprsRouteDialog> {
  late TextEditingController _nameController;
  late TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.route?.name ?? '');
    _pathController = TextEditingController(text: widget.route?.path ?? '');
    _nameController.addListener(_onChanged);
    _pathController.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  /// Whether the entered name duplicates an existing route name.
  bool get _isDuplicateName {
    final name = _nameController.text.trim().toLowerCase();
    if (name.isEmpty) return false;
    return widget.existingNames.any((n) => n.trim().toLowerCase() == name);
  }

  /// Whether the current input is valid and the route can be saved.
  bool get _canSave =>
      _nameController.text.trim().isNotEmpty &&
      _pathController.text.trim().isNotEmpty &&
      !_isDuplicateName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HTDialog(
      title: widget.route == null
          ? l10n.settingsAddAprsRoute
          : l10n.settingsEditAprsRoute,
      maxWidth: 400,
      maxHeight: 320,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsName, style: DialogStyles.labelStyle),
          const SizedBox(height: 4),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              hintText: l10n.settingsNameHint,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
          ),
          if (_isDuplicateName) ...[
            const SizedBox(height: 4),
            Text(
              l10n.settingsDuplicateRoute,
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          Text(l10n.settingsPath, style: DialogStyles.labelStyle),
          const SizedBox(height: 4),
          TextField(
            controller: _pathController,
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              hintText: 'e.g. APN000,WIDE1-1,WIDE2-2',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          style: DialogStyles.secondaryButtonStyle(context),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: _canSave
              ? () {
                  Navigator.of(context).pop(
                    AprsRoute(
                      name: _nameController.text.trim(),
                      path: _pathController.text.trim(),
                    ),
                  );
                }
              : null,
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.commonOk),
        ),
      ],
    );
  }
}
