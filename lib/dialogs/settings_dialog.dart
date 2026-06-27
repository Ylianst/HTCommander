import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dialog_utils.dart';
import '../services/serial/serial_port.dart';
import '../services/data_broker.dart';
import '../services/tts_service.dart';
import '../services/sherpa_model_manager.dart';

/// Settings data model
class AppSettings {
  // License tab
  String callSign;
  int stationId;
  bool allowTransmit;

  // APRS tab
  List<AprsRoute> aprsRoutes;

  // Voice tab
  String voiceLanguage;
  String voiceModel;
  String voice;
  double voiceSpeechRate;
  double voicePitch;

  // Winlink tab
  String winlinkPassword;
  bool winlinkUseStationId;

  // Web Server tab
  bool webServerEnabled;
  int webServerPort;
  bool agwpeServerEnabled;
  int agwpeServerPort;

  // Map/GPS tab
  String gpsSerialPort;
  int gpsBaudRate;
  String airplaneServerUrl;

  AppSettings({
    this.callSign = '',
    this.stationId = 0,
    this.allowTransmit = false,
    List<AprsRoute>? aprsRoutes,
    this.voiceLanguage = 'auto',
    this.voiceModel = 'sense-voice',
    this.voice = '',
    this.voiceSpeechRate = 0.5,
    this.voicePitch = 1.0,
    this.winlinkPassword = '',
    this.winlinkUseStationId = false,
    this.webServerEnabled = false,
    this.webServerPort = 8080,
    this.agwpeServerEnabled = false,
    this.agwpeServerPort = 8000,
    this.gpsSerialPort = 'None',
    this.gpsBaudRate = 4800,
    this.airplaneServerUrl = '',
  }) : aprsRoutes =
           aprsRoutes ??
           [AprsRoute(name: 'Standard', path: 'APN000,WIDE1-1,WIDE2-2')];

  AppSettings copyWith({
    String? callSign,
    int? stationId,
    bool? allowTransmit,
    List<AprsRoute>? aprsRoutes,
    String? voiceLanguage,
    String? voiceModel,
    String? voice,
    double? voiceSpeechRate,
    double? voicePitch,
    String? winlinkPassword,
    bool? winlinkUseStationId,
    bool? webServerEnabled,
    int? webServerPort,
    bool? agwpeServerEnabled,
    int? agwpeServerPort,
    String? gpsSerialPort,
    int? gpsBaudRate,
    String? airplaneServerUrl,
  }) {
    return AppSettings(
      callSign: callSign ?? this.callSign,
      stationId: stationId ?? this.stationId,
      allowTransmit: allowTransmit ?? this.allowTransmit,
      aprsRoutes: aprsRoutes ?? List.from(this.aprsRoutes),
      voiceLanguage: voiceLanguage ?? this.voiceLanguage,
      voiceModel: voiceModel ?? this.voiceModel,
      voice: voice ?? this.voice,
      voiceSpeechRate: voiceSpeechRate ?? this.voiceSpeechRate,
      voicePitch: voicePitch ?? this.voicePitch,
      winlinkPassword: winlinkPassword ?? this.winlinkPassword,
      winlinkUseStationId: winlinkUseStationId ?? this.winlinkUseStationId,
      webServerEnabled: webServerEnabled ?? this.webServerEnabled,
      webServerPort: webServerPort ?? this.webServerPort,
      agwpeServerEnabled: agwpeServerEnabled ?? this.agwpeServerEnabled,
      agwpeServerPort: agwpeServerPort ?? this.agwpeServerPort,
      gpsSerialPort: gpsSerialPort ?? this.gpsSerialPort,
      gpsBaudRate: gpsBaudRate ?? this.gpsBaudRate,
      airplaneServerUrl: airplaneServerUrl ?? this.airplaneServerUrl,
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
      aprsRoutes: aprsRoutes.isNotEmpty
          ? aprsRoutes
          : [AprsRoute(name: 'Standard', path: 'APN000,WIDE1-1,WIDE2-2')],
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
      webServerEnabled:
          (DataBroker.getValue<int>(0, 'webServerEnabled', 0) ?? 0) == 1,
      webServerPort: DataBroker.getValue<int>(0, 'webServerPort', 8080) ?? 8080,
      agwpeServerEnabled:
          (DataBroker.getValue<int>(0, 'agwpeServerEnabled', 0) ?? 0) == 1,
      agwpeServerPort:
          DataBroker.getValue<int>(0, 'agwpeServerPort', 8000) ?? 8000,
      gpsSerialPort:
          DataBroker.getValue<String>(0, 'GpsSerialPort', 'None') ?? 'None',
      gpsBaudRate: DataBroker.getValue<int>(0, 'GpsBaudRate', 4800) ?? 4800,
      airplaneServerUrl:
          DataBroker.getValue<String>(0, 'AirplaneServer', '') ?? '',
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
      name: 'GpsSerialPort',
      data: gpsSerialPort,
    );
    DataBroker.dispatch(deviceId: 0, name: 'GpsBaudRate', data: gpsBaudRate);
    DataBroker.dispatch(
      deviceId: 0,
      name: 'AirplaneServer',
      data: airplaneServerUrl,
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

/// Voice language option
class LanguageOption {
  final String code;
  final String name;

  const LanguageOption(this.code, this.name);
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

  // Controllers
  late TextEditingController _callSignController;
  late TextEditingController _winlinkPasswordController;
  late TextEditingController _webPortController;
  late TextEditingController _agwpePortController;
  late TextEditingController _airplaneUrlController;

  // Dump1090 "Test Connection" state.
  bool _airplaneTesting = false;
  String _airplaneTestResult = '';

  // Serial ports available for the GPS receiver (desktop only).
  List<String> _availablePorts = const [];

  // Available text-to-speech voices, loaded asynchronously.
  List<Map<String, String>> _voices = const [];
  bool _voicesLoaded = false;

  // Language options (SenseVoice-supported recognition languages).
  static const List<LanguageOption> _languages = [
    LanguageOption('auto', 'Auto-detect'),
    LanguageOption('en', 'English'),
    LanguageOption('zh', 'Chinese'),
    LanguageOption('ja', 'Japanese'),
    LanguageOption('ko', 'Korean'),
    LanguageOption('yue', 'Cantonese'),
  ];

  // GPS baud rates
  static const List<int> _baudRates = [4800, 9600, 19200, 38400, 57600, 115200];

  /// Settings tabs in display order. On the web the radio is used over the BLE
  /// control channel only, so the audio-centric "Comms" tab and the
  /// internet-service "Servers" / "Map" tabs are hidden. On Android/iOS the
  /// "Servers" tab is hidden. All tabs remain visible on desktop platforms.
  List<String> get _visibleTabs {
    const all = ['License', 'APRS', 'Comms', 'Winlink', 'Servers', 'Map'];
    if (kIsWeb) {
      return all
          .where((t) => t != 'Comms' && t != 'Servers' && t != 'Map')
          .toList();
    }
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return all.where((t) => t != 'Servers').toList();
    }
    return all;
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
      case 'Servers':
        return _buildServersTab();
      case 'Map':
        return _buildMapTab();
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
    _webPortController = TextEditingController(
      text: _settings.webServerPort.toString(),
    );
    _agwpePortController = TextEditingController(
      text: _settings.agwpeServerPort.toString(),
    );
    _airplaneUrlController = TextEditingController(
      text: _settings.airplaneServerUrl,
    );

    _callSignController.addListener(_onCallSignChanged);

    // Load the available TTS voices for the Voice tab.
    _loadVoices();

    // Sync the speech-to-text model status shown in the Voice tab.
    SherpaModelManager.refreshStatus(
      SherpaModelManager.modelById(_settings.voiceModel).id,
    );
  }

  /// Loads the available text-to-speech voices for the Voice settings tab.
  Future<void> _loadVoices() async {
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
    });
  }

  @override
  void dispose() {
    TtsService.instance.stopPreview();
    _tabController.dispose();
    _callSignController.dispose();
    _winlinkPasswordController.dispose();
    _webPortController.dispose();
    _agwpePortController.dispose();
    _airplaneUrlController.dispose();
    super.dispose();
  }

  void _onCallSignChanged() {
    setState(() {
      _settings.callSign = _callSignController.text.toUpperCase();
      if (_settings.callSign.length < 3) {
        _settings.allowTransmit = false;
      }
    });
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
    final url = _resolveDump1090Url(_airplaneUrlController.text);
    if (url == null) {
      setState(() => _airplaneTestResult = 'Failed: empty server address');
      return;
    }

    setState(() {
      _airplaneTesting = true;
      _airplaneTestResult = 'Testing...';
    });

    String result;
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        result = 'Failed: HTTP ${response.statusCode}';
      } else {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final aircraft = decoded['aircraft'];
          final count = aircraft is List ? aircraft.length : 0;
          result = 'Success, $count aircraft found.';
        } else {
          result = 'Failed: unexpected JSON format';
        }
      }
    } on TimeoutException {
      result = 'Failed: request timed out';
    } on FormatException {
      result = 'Failed: invalid JSON response';
    } catch (e) {
      result = 'Failed: $e';
    }

    if (!mounted) return;
    setState(() {
      _airplaneTesting = false;
      _airplaneTestResult = result;
    });
  }

  void _onSave() {
    // Update settings from text controllers
    _settings.winlinkPassword = _winlinkPasswordController.text;
    _settings.webServerPort = int.tryParse(_webPortController.text) ?? 8080;
    _settings.agwpeServerPort = int.tryParse(_agwpePortController.text) ?? 8000;
    _settings.airplaneServerUrl = _airplaneUrlController.text;

    // Save all settings to DataBroker (persisted to SharedPreferences)
    _settings.saveToDataBroker();

    Navigator.of(
      context,
    ).pop(true); // Return true to indicate settings were saved
  }

  // Helper for consistent input decoration
  InputDecoration _inputDecoration({String? hintText, String? labelText}) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.grey.shade100,
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
        borderSide: const BorderSide(color: Colors.blue, width: 2),
      ),
    );
  }

  // Helper for section card styling
  BoxDecoration _sectionDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF5F5F5),
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
                labelColor: Colors.blue.shade700,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.blue,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: Colors.transparent,
                tabs: _visibleTabs.map((t) => Tab(text: t)).toList(),
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
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _onSave,
                    style: DialogStyles.primaryButtonStyle(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLicenseTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info text
          const Text(
            'In the United States, you need an amateur radio license to transmit. '
            'Visit the ARRL website for more information on getting licensed.',
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
                  'Call Sign & Station ID',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
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
                          const Text(
                            'Call Sign',
                            style: DialogStyles.labelStyle,
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _callSignController,
                            decoration: _inputDecoration(hintText: 'e.g. W1AW'),
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
                          const Text(
                            'Station ID',
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
                                child: Text(i == 0 ? 'None' : i.toString()),
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
                          'Allow this application to transmit',
                          style: TextStyle(
                            color: _settings.callSign.length >= 3
                                ? null
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_settings.callSign.length < 3)
                  Text(
                    'Enter a valid call sign (at least 3 characters) to enable transmit',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAprsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configure APRS routing paths for packet transmission.',
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
                  'APRS Routes',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                // Routes list
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListView.builder(
                      itemCount: _settings.aprsRoutes.length,
                      itemBuilder: (context, index) {
                        final route = _settings.aprsRoutes[index];
                        final canDelete = _settings.aprsRoutes.length > 1;
                        return ListTile(
                          dense: true,
                          title: Text(route.name),
                          subtitle: Text(route.path),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                tooltip: 'Edit route',
                                onPressed: () => _editAprsRoute(index),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete,
                                  size: 20,
                                  color: canDelete ? Colors.red.shade400 : null,
                                ),
                                tooltip: canDelete
                                    ? 'Delete route'
                                    : 'At least one route is required',
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
                      child: const Text('Add'),
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

  void _addAprsRoute() async {
    final result = await showDialog<AprsRoute>(
      context: context,
      builder: (context) => const AprsRouteDialog(),
    );
    if (result != null) {
      setState(() => _settings.aprsRoutes.add(result));
    }
  }

  void _editAprsRoute(int index) async {
    final result = await showDialog<AprsRoute>(
      context: context,
      builder: (context) => AprsRouteDialog(route: _settings.aprsRoutes[index]),
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
    for (final l in _languages) {
      if (l.code == code) return l.name;
    }
    return code;
  }

  /// Speech-to-text setup: model selection, language and on-device management.
  Widget _buildSpeechRecognitionSection() {
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
            'Speech-to-Text',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Transcribes received radio audio to text. Runs fully offline on '
            'this device; audio is never written to disk.',
            style: DialogStyles.bodyStyle,
          ),
          const SizedBox(height: 16),
          const Text('Model', style: DialogStyles.labelStyle),
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
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          if (model.multilingual) ...[
            const Text('Recognition Language', style: DialogStyles.labelStyle),
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
              'Language changes take effect the next time the engine starts.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
          ],
          const Text('Status', style: DialogStyles.labelStyle),
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
                    'Model installed$suffix',
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
            ? '${_formatBytes(status.receivedBytes)} of '
                  '${_formatBytes(status.totalBytes)}'
            : _formatBytes(status.receivedBytes);
        statusLine = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pct != null
                  ? 'Downloading model… ${(pct * 100).toStringAsFixed(0)}%'
                  : 'Downloading model…',
              style: DialogStyles.bodyStyle,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: pct),
            const SizedBox(height: 4),
            Text(
              detail,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                  ? 'Installing model… ${(pct * 100).toStringAsFixed(0)}%'
                  : 'Installing model…',
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
                status.message ?? 'Model could not be installed.',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
        break;
      case SttModelState.notInstalled:
        statusLine = Text(
          'Model not downloaded. ${model.downloadLabel} happens once and is '
          'cached on this device.',
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
                status.state == SttModelState.error ? 'Retry' : 'Download',
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: busy || status.state != SttModelState.ready
                  ? null
                  : () => _confirmRemoveSttModel(model),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remove'),
            ),
          ],
        ),
      ],
    );
  }

  /// Confirms then deletes the cached files for [model] from disk.
  Future<void> _confirmRemoveSttModel(SttModel model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove speech-to-text model?'),
        content: Text(
          'The downloaded "${model.name}" model will be deleted to reclaim '
          'disk space. It will be downloaded again the next time it is used.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SherpaModelManager.deleteModel(model.id);
    }
  }

  Widget _buildCommsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configure speech recognition and text-to-speech settings.',
            style: DialogStyles.bodyStyle,
          ),
          const SizedBox(height: 16),
          // Speech Recognition (sherpa-onnx)
          _buildSpeechRecognitionSection(),
          const SizedBox(height: 16),
          // Text-to-Speech
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Text-to-Speech',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Used when sending text in "Speech" mode from the Comms tab.',
                  style: DialogStyles.bodyStyle,
                ),
                const SizedBox(height: 16),
                const Text('Voice', style: DialogStyles.labelStyle),
                const SizedBox(height: 4),
                _buildVoiceDropdown(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Speech Rate', style: DialogStyles.labelStyle),
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
                    const Text('Pitch', style: DialogStyles.labelStyle),
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
                      label: const Text('Preview'),
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
    if (!_voicesLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading voices…', style: DialogStyles.bodyStyle),
          ],
        ),
      );
    }

    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: '', child: Text('System Default')),
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
    final winlinkAccount = _settings.callSign.isNotEmpty
        ? '${_settings.callSign}@winlink.org'
        : 'None';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configure Winlink email settings for radio email.',
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
                  'Winlink Account',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Account', style: DialogStyles.labelStyle),
                const SizedBox(height: 4),
                TextField(
                  enabled: false,
                  decoration: _inputDecoration(hintText: winlinkAccount),
                  controller: TextEditingController(text: winlinkAccount),
                ),
                const SizedBox(height: 4),
                Text(
                  'Based on your call sign from the License tab',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                const Text('Password', style: DialogStyles.labelStyle),
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
                        child: const Text('Use Station ID for Winlink'),
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

  Widget _buildServersTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configure local server settings.',
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
                  'Local Servers',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
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
                        child: const Text('Enable Web Server'),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Row(
                    children: [
                      const Text('Port:', style: DialogStyles.labelStyle),
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
                        child: const Text('Enable AGWPE Server'),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 48),
                  child: Row(
                    children: [
                      const Text('Port:', style: DialogStyles.labelStyle),
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
    final values = <String>['None', ..._availablePorts];
    if (_settings.gpsSerialPort.isNotEmpty &&
        !values.contains(_settings.gpsSerialPort)) {
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
    final mapIntro = _serialGpsSupported
        ? 'Configure GPS and airplane tracking data sources.'
        : 'Configure airplane tracking data sources.';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mapIntro,
            style: DialogStyles.bodyStyle,
          ),
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
                    'GPS Serial Port',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
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
                            const Text(
                              'Serial Port',
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
                            const Text(
                              'Baud Rate',
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
                  'Airplane Tracking (dump1090)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Server URL', style: DialogStyles.labelStyle),
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
                Row(
                  children: [
                    ElevatedButton(
                      onPressed:
                          (_airplaneUrlController.text.trim().isNotEmpty &&
                              !_airplaneTesting)
                          ? _testAirplaneConnection
                          : null,
                      child: const Text('Test Connection'),
                    ),
                    if (_airplaneTestResult.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _airplaneTestResult,
                          style: TextStyle(
                            color: _airplaneTestResult.startsWith('Success')
                                ? Colors.green.shade700
                                : _airplaneTestResult == 'Testing...'
                                ? Colors.grey.shade700
                                : Colors.red.shade700,
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

  void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Dialog for editing APRS routes
class AprsRouteDialog extends StatefulWidget {
  final AprsRoute? route;

  const AprsRouteDialog({super.key, this.route});

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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HTDialog(
      title: widget.route == null ? 'Add APRS Route' : 'Edit APRS Route',
      maxWidth: 400,
      maxHeight: 280,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Name', style: DialogStyles.labelStyle),
          const SizedBox(height: 4),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey.shade100,
              hintText: 'e.g. Standard',
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
                borderSide: const BorderSide(color: Colors.blue, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Path', style: DialogStyles.labelStyle),
          const SizedBox(height: 4),
          TextField(
            controller: _pathController,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey.shade100,
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
                borderSide: const BorderSide(color: Colors.blue, width: 2),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          style: DialogStyles.secondaryButtonStyle(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_nameController.text.isEmpty || _pathController.text.isEmpty) {
              return;
            }
            Navigator.of(context).pop(
              AprsRoute(name: _nameController.text, path: _pathController.text),
            );
          },
          style: DialogStyles.primaryButtonStyle(context),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
