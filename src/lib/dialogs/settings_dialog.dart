import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pasteboard/pasteboard.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dialog_utils.dart';
import '../l10n/app_localizations.dart';
import '../aprs/aprs_util.dart';
import '../aprs/weather_data.dart';
import '../allstar/allstar_node.dart';
import '../allstar/allstar_portal_service.dart';
import '../allstar/iax2_constants.dart' show iax2DefaultPort;
import '../aprsis/aprsfi_client.dart';
import '../echolink/echolink_credential_test.dart';
import '../services/serial/serial_port.dart';
import '../services/data_broker_client.dart';
import '../services/history_limiter.dart';
import '../services/locale_controller.dart';
import '../services/mqtt/mqtt_client_facade.dart';
import '../services/theme_controller.dart';
import '../services/tts_service.dart';
import '../services/sherpa_model_manager.dart';
import '../widgets/contact_avatar.dart';
import 'app_settings.dart';
import 'aprs_route_dialog.dart';
import 'contact_logo_picker_dialog.dart';
import 'echolink_create_account_dialog.dart';
import 'image_crop_dialog.dart';
import 'location_picker_dialog.dart';

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

  // Operator's own avatar for the License tab. Mirrors [_settings] and is
  // written back on save. A custom [_avatarImage] takes precedence over a
  // chosen [_avatarIcon], which in turn takes precedence over the callsign
  // initials.
  String? _avatarIcon;
  String? _avatarImage;

  // Data Broker client for reading/writing the AllStarLink account credentials.
  final DataBrokerClient _broker = DataBrokerClient();

  // Controllers
  late TextEditingController _callSignController;
  late TextEditingController _winlinkPasswordController;
  late TextEditingController _echoLinkPasswordController;
  late TextEditingController _echoLinkLocationController;
  late TextEditingController _allStarPasswordController;
  late TextEditingController _allStarNodeNumberController;
  late TextEditingController _allStarNodePasswordController;
  late TextEditingController _allStarBindPortController;
  AllStarRegMethod _allStarRegMethod = AllStarRegMethod.iax;
  bool _allStarAllowWt = false;
  late TextEditingController _aprsIsServerController;
  late TextEditingController _aprsIsPortController;
  late TextEditingController _aprsIsPasscodeController;
  late TextEditingController _aprsFiApiKeyController;
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

  // APRS.fi API key "Test" state.
  bool _aprsFiTesting = false;
  String _aprsFiTestResult = '';
  bool _aprsFiTestOk = false;

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
    _avatarIcon = _settings.avatarIcon;
    _avatarImage = _settings.avatarImage;

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
    _allStarNodeNumberController = TextEditingController(
      text: _broker.getValue<String>(0, allStarNodeNumberKey, '') ?? '',
    );
    _allStarNodePasswordController = TextEditingController(
      text: _broker.getValue<String>(0, allStarNodePasswordKey, '') ?? '',
    );
    _allStarBindPortController = TextEditingController(
      text: (_broker.getValue<int>(0, allStarBindPortKey, iax2DefaultPort) ??
              iax2DefaultPort)
          .toString(),
    );
    _allStarRegMethod = allStarRegMethodFromString(
        _broker.getValue<String>(0, allStarRegMethodKey, 'iax'));
    _allStarAllowWt = _broker.getValue<bool>(0, allStarAllowWtKey, false) ?? false;
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
    _aprsFiApiKeyController = TextEditingController(
      text: _settings.aprsFiApiKey,
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
    _allStarNodeNumberController.dispose();
    _allStarNodePasswordController.dispose();
    _allStarBindPortController.dispose();
    _aprsIsServerController.dispose();
    _aprsIsPortController.dispose();
    _aprsIsPasscodeController.dispose();
    _aprsFiApiKeyController.dispose();
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
    final EchoLinkAccountResult? result =
        await showDialog<EchoLinkAccountResult>(
      context: context,
      builder: (_) => EchoLinkCreateAccountDialog(
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

  /// Our own callsign with SSID (e.g. `KK7VZT-7`), used as the aprs.fi `dst`.
  String _selfCallsignWithId() {
    final callsign = _settings.callSign.trim().toUpperCase();
    if (callsign.isEmpty) return '';
    return _settings.stationId > 0
        ? '$callsign-${_settings.stationId}'
        : callsign;
  }

  /// Tests the entered aprs.fi API key by requesting the most recent messages
  /// addressed to our own callsign and reporting how many were found.
  Future<void> _testAprsFiApiKey() async {
    final l10n = AppLocalizations.of(context);
    final apiKey = _aprsFiApiKeyController.text.trim();
    final dst = _selfCallsignWithId();
    if (apiKey.isEmpty) {
      setState(() {
        _aprsFiTestOk = false;
        _aprsFiTestResult = l10n.settingsAprsFiTestNoKey;
      });
      return;
    }
    if (dst.isEmpty) {
      setState(() {
        _aprsFiTestOk = false;
        _aprsFiTestResult = l10n.settingsAprsFiTestNoCallSign;
      });
      return;
    }

    setState(() {
      _aprsFiTesting = true;
      _aprsFiTestResult = l10n.settingsTestTesting;
    });

    final version = _broker.getValue<String>(0, 'AppVersion', '') ?? '';
    final result = await AprsFiClient.fetchMessages(
      apiKey: apiKey,
      dstCallsign: dst,
      userAgent: version.isEmpty ? 'HTCommander' : 'HTCommander/$version',
      timeout: const Duration(seconds: 15),
    );

    if (!mounted) return;
    setState(() {
      _aprsFiTesting = false;
      _aprsFiTestOk = result.ok;
      _aprsFiTestResult = result.ok
          ? l10n.settingsAprsFiTestSuccess(result.messages.length)
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
    _settings.aprsFiApiKey = _aprsFiApiKeyController.text.trim();
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
    _settings.avatarIcon = _avatarIcon;
    _settings.avatarImage = _avatarImage;
    _settings.saveToDataBroker();

    // Persist AllStarLink node-hosting configuration (device 0).
    _broker.dispatch(
        deviceId: 0,
        name: allStarNodeNumberKey,
        data: _allStarNodeNumberController.text.trim(),
        store: true);
    _broker.dispatch(
        deviceId: 0,
        name: allStarNodePasswordKey,
        data: _allStarNodePasswordController.text,
        store: true);
    _broker.dispatch(
        deviceId: 0,
        name: allStarBindPortKey,
        data: int.tryParse(_allStarBindPortController.text) ?? iax2DefaultPort,
        store: true);
    _broker.dispatch(
        deviceId: 0,
        name: allStarRegMethodKey,
        data: allStarRegMethodToString(_allStarRegMethod),
        store: true);
    _broker.dispatch(
        deviceId: 0,
        name: allStarAllowWtKey,
        data: _allStarAllowWt,
        store: true);

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
    return DialogStyles.inputDecoration(
      context,
      hintText: hintText,
      labelText: labelText,
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
                    DropdownMenuItem(
                      value: 'it',
                      child: Text(l10n.languageItalian),
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
                Row(
                  children: [
                    Checkbox(
                      value: _settings.messageNotifications,
                      onChanged: (value) {
                        setState(
                          () => _settings.messageNotifications = value ?? false,
                        );
                      },
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(
                          () => _settings.messageNotifications =
                              !_settings.messageNotifications,
                        ),
                        child: const Text('Message Notifications'),
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

  /// Round operator avatar shown at the License tab's top-right. Tapping it
  /// opens the avatar customization menu.
  Widget _buildAvatarButton() {
    return Tooltip(
      message: AppLocalizations.of(context).contactAvatarCustomize,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTapDown: (details) => _showAvatarMenu(details.globalPosition),
        child: ContactAvatar(
          callsign: _settings.callSign,
          avatarIcon: _avatarIcon,
          avatarImage: _avatarImage,
          radius: 28,
        ),
      ),
    );
  }

  Future<void> _showAvatarMenu(Offset globalPosition) async {
    final l10n = AppLocalizations.of(context);
    // A snapshot of any clipboard image, read up front so a "Paste" item can be
    // offered only when one is available.
    Uint8List? clipboardImage;
    try {
      clipboardImage = await Pasteboard.image;
    } catch (_) {
      clipboardImage = null;
    }
    if (!mounted) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final hasCustom = _avatarIcon != null || _avatarImage != null;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'logo',
          child: Text(l10n.contactAvatarChooseLogo),
        ),
        PopupMenuItem<String>(
          value: 'image',
          child: Text(l10n.contactAvatarChooseImage),
        ),
        if (clipboardImage != null)
          PopupMenuItem<String>(
            value: 'paste',
            child: Text(l10n.contactAvatarPaste),
          ),
        if (hasCustom)
          PopupMenuItem<String>(
            value: 'reset',
            child: Text(l10n.contactAvatarReset),
          ),
      ],
    );
    if (selected == null || !mounted) return;
    switch (selected) {
      case 'logo':
        await _chooseAvatarLogo();
        break;
      case 'image':
        await _chooseAvatarImage();
        break;
      case 'paste':
        if (clipboardImage != null) await _cropAndSetAvatar(clipboardImage);
        break;
      case 'reset':
        setState(() {
          _avatarIcon = null;
          _avatarImage = null;
        });
        break;
    }
  }

  Future<void> _chooseAvatarLogo() async {
    final name = await showContactLogoPicker(context);
    if (name == null || !mounted) return;
    setState(() {
      _avatarIcon = name;
      _avatarImage = null; // a logo replaces any custom image
    });
  }

  Future<void> _chooseAvatarImage() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
      );
    } catch (_) {
      return;
    }
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;
    var bytes = file.bytes;
    if (bytes == null && !kIsWeb && file.path != null) {
      try {
        bytes = await File(file.path!).readAsBytes();
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes == null || !mounted) return;
    await _cropAndSetAvatar(bytes);
  }

  /// Runs [bytes] through the crop dialog and stores the resulting avatar image.
  Future<void> _cropAndSetAvatar(Uint8List bytes) async {
    final b64 = await showImageCropDialog(context, bytes);
    if (b64 == null || !mounted) return;
    setState(() {
      _avatarImage = b64;
      _avatarIcon = null; // a custom image replaces any chosen logo
    });
  }

  Widget _buildLicenseTab() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info text with the operator's own avatar on the upper right.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsLicenseInfo,
                      style: DialogStyles.bodyStyle,
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () =>
                          _launchUrl('https://www.arrl.org/getting-licensed'),
                      child: const Text(
                        'www.arrl.org/getting-licensed',
                        style: DialogStyles.linkStyle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _buildAvatarButton(),
            ],
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
          const SizedBox(height: 16),
          _buildLocationSection(),
        ],
      ),
    );
  }

  /// Location source section on the License tab: choose between the live GPS
  /// (radio or serial GPS) and a manually picked location. The manual location
  /// is sent to the radio and used for APRS-IS and satellite tracking.
  Widget _buildLocationSection() {
    final l10n = AppLocalizations.of(context);
    final manual = _settings.manualLocationEnabled;
    final hasCoords =
        _settings.manualLatitude != 0 || _settings.manualLongitude != 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsLocation, style: _sectionTitleStyle()),
          const SizedBox(height: 8),
          Text(l10n.settingsLocationInfo, style: _secondaryStyle()),
          const SizedBox(height: 8),
          RadioGroup<bool>(
            groupValue: manual,
            onChanged: (value) => setState(
              () => _settings.manualLocationEnabled = value ?? false,
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RadioListTile<bool>(
                    value: false,
                    title: Text(l10n.settingsLocationSourceGps),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  RadioListTile<bool>(
                    value: true,
                    title: Text(l10n.settingsLocationSourceManual),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ],
              ),
            ),
          ),
          if (manual) ...[
            const SizedBox(height: 8),
            if (hasCoords)
              Row(
                children: [
                  Expanded(
                    child: _coordDisplay(
                      l10n.settingsLocationLatitude,
                      _settings.manualLatitude.toStringAsFixed(5),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _coordDisplay(
                      l10n.settingsLocationLongitude,
                      _settings.manualLongitude.toStringAsFixed(5),
                    ),
                  ),
                ],
              )
            else
              Text(l10n.settingsLocationNotSet, style: _hintStyle()),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _pickManualLocation,
              icon: const Icon(Icons.map, size: 18),
              label: Text(l10n.settingsLocationSelectOnMap),
            ),
          ],
        ],
      ),
    );
  }

  /// Small labelled read-only coordinate display used by the Location section.
  Widget _coordDisplay(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: DialogStyles.labelStyle),
        const SizedBox(height: 4),
        Text(value, style: DialogStyles.bodyStyle),
      ],
    );
  }

  /// Opens the map picker and stores the chosen coordinates in the settings.
  Future<void> _pickManualLocation() async {
    final result = await showLocationPickerDialog(
      context,
      latitude: _settings.manualLatitude,
      longitude: _settings.manualLongitude,
    );
    if (result == null || !mounted) return;
    setState(() {
      _settings.manualLatitude = result.latitude;
      _settings.manualLongitude = result.longitude;
    });
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
          const SizedBox(height: 16),
          // Cloud push notifications via aprs.meshcentral.com. FCM-backed and
          // only implemented on Android, so the toggle is hidden elsewhere.
          // Available once APRS-IS is enabled with a valid passcode (used to
          // authenticate with the server); otherwise disabled and forced off.
          Builder(
            builder: (context) {
              if (kIsWeb || !Platform.isAndroid) {
                return const SizedBox.shrink();
              }
              final cloudAvailable = _settings.aprsIsEnabled && passcodeValid;
              if (!cloudAvailable && _settings.aprsCloudNotifications) {
                // Keep the stored value consistent when the prerequisite is lost.
                _settings.aprsCloudNotifications = false;
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _settings.aprsCloudNotifications,
                        onChanged: cloudAvailable
                            ? (value) => setState(
                                  () => _settings.aprsCloudNotifications =
                                      value ?? false,
                                )
                            : null,
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: cloudAvailable
                              ? () => setState(
                                    () => _settings.aprsCloudNotifications =
                                        !_settings.aprsCloudNotifications,
                                  )
                              : null,
                          child: Text(l10n.settingsAprsCloudNotifications),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.settingsAprsCloudNotificationsHelp,
                      style: _secondaryStyle()),
                ],
              );
            },
          ),
          const Divider(height: 32),
          Text(l10n.settingsAprsFiTitle, style: _sectionTitleStyle()),
          const SizedBox(height: 8),
          Text(l10n.settingsAprsFiIntro, style: DialogStyles.bodyStyle),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _launchUrl('https://aprs.fi/account/'),
            child: const Text('aprs.fi/account/', style: DialogStyles.linkStyle),
          ),
          const SizedBox(height: 16),
          Text(l10n.settingsAprsFiApiKey, style: DialogStyles.labelStyle),
          const SizedBox(height: 4),
          TextField(
            controller: _aprsFiApiKeyController,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: _inputDecoration(
              hintText: l10n.settingsAprsFiApiKeyHint,
            ),
            onChanged: (_) {
              // Rebuild so the Test button's enabled state tracks the field and
              // any prior result is cleared.
              setState(() => _aprsFiTestResult = '');
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton(
                onPressed: (_aprsFiApiKeyController.text.trim().isNotEmpty &&
                        !_aprsFiTesting)
                    ? _testAprsFiApiKey
                    : null,
                child: Text(l10n.settingsTest),
              ),
              if (_aprsFiTestResult.isNotEmpty) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _aprsFiTestResult,
                    style: TextStyle(
                      color: _aprsFiTesting
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : (_aprsFiTestOk
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
    // Android transcribes via the OS on-device recognizer, which downloads no
    // model into the app, so the sherpa model picker/status is not shown.
    if (defaultTargetPlatform == TargetPlatform.android) {
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
          ],
        ),
      );
    }
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
                  (m) {
                    final size = m.downloadLabel.replaceAll(' download', '');
                    // Merge the size into a trailing "(...)" in the name so a
                    // model like "Zipformer (real-time)" shows one parenthesis.
                    final label = m.name.endsWith(')')
                        ? '${m.name.substring(0, m.name.length - 1)}, $size)'
                        : '${m.name}  ($size)';
                    return DropdownMenuItem(
                      value: m.id,
                      child: Text(label),
                    );
                  },
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
          // Speech Recognition. Desktop uses sherpa-onnx (model download);
          // Android uses the OS on-device recognizer (no model). The section
          // renders a platform-appropriate body for each.
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
          const SizedBox(height: 16),
          _buildAllStarHostCard(l10n),
        ],
      ),
    );
  }

  Widget _buildAllStarHostCard(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsAllStarHostTitle, style: _sectionTitleStyle()),
          const SizedBox(height: 8),
          Text(l10n.settingsAllStarHostIntro, style: _secondaryStyle()),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.settingsAllStarNodeNumber,
                        style: DialogStyles.labelStyle),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _allStarNodeNumberController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.settingsAllStarHostPort,
                        style: DialogStyles.labelStyle),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _allStarBindPortController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l10n.settingsAllStarHostPassword, style: DialogStyles.labelStyle),
          const SizedBox(height: 4),
          TextField(
            controller: _allStarNodePasswordController,
            obscureText: true,
            decoration: _inputDecoration(),
          ),
          const SizedBox(height: 12),
          Text(l10n.settingsAllStarHostRegistration,
              style: DialogStyles.labelStyle),
          const SizedBox(height: 4),
          DropdownButtonFormField<AllStarRegMethod>(
            initialValue: _allStarRegMethod,
            decoration: _inputDecoration(),
            items: [
              DropdownMenuItem(
                value: AllStarRegMethod.iax,
                child: Text(l10n.settingsAllStarHostRegIax),
              ),
              DropdownMenuItem(
                value: AllStarRegMethod.http,
                child: Text(l10n.settingsAllStarHostRegHttp),
              ),
              DropdownMenuItem(
                value: AllStarRegMethod.none,
                child: Text(l10n.settingsAllStarHostRegNone),
              ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _allStarRegMethod = v);
            },
          ),
          const SizedBox(height: 4),
          // Transparent Material so the SwitchListTile can paint its ink
          // splashes without being hidden by the card's decorated background.
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.settingsAllStarHostAllowWt,
                  style: DialogStyles.labelStyle),
              subtitle: Text(l10n.settingsAllStarHostAllowWtHint,
                  style: _secondaryStyle()),
              value: _allStarAllowWt,
              onChanged: (v) => setState(() => _allStarAllowWt = v),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.settingsAllStarHostNote(
                int.tryParse(_allStarBindPortController.text) ??
                    iax2DefaultPort),
            style: _secondaryStyle(),
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

