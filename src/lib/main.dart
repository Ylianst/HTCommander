import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'dialogs/about_dialog.dart';
import 'dialogs/gps_serial_info_dialog.dart';
import 'dialogs/import_channels_dialog.dart';
import 'dialogs/radio_connection_dialog.dart';
import 'dialogs/radio_info_dialog.dart';
import 'dialogs/settings_dialog.dart';
import 'handlers/frame_deduplicator.dart';
import 'handlers/packet_store.dart';
import 'handlers/aprs_handler.dart';
import 'handlers/airplane_handler.dart';
import 'handlers/comms_handler.dart';
import 'handlers/bbs_handler.dart';
import 'handlers/agwpe_handler.dart';
import 'handlers/web_server_handler.dart';
import 'handlers/debug_log_handler.dart';
import 'gps/gps_serial_handler.dart';
import 'torrent/torrent_handler.dart';
import 'torrent/torrent_store.dart';
import 'radio/radio_transport.dart';
// The soft-modem relies on an audio channel, which the web build does not have.
// Use a no-op stub on web so the hamlib DSP code is never compiled for web.
import 'radio/software_modem_stub.dart'
    if (dart.library.io) 'radio/software_modem.dart';
import 'services/bluetooth_service.dart';
import 'services/data_broker.dart';
import 'services/data_broker_client.dart';
import 'services/history_limiter.dart';
import 'services/window_service.dart';
import 'utils/channel_export.dart';
import 'utils/channel_import.dart';
import 'radio/radio_models.dart' show RadioChannelInfo;
import 'services/update_service.dart';
import 'winlink/mail_store.dart';
import 'winlink/winlink_client.dart';
import 'widgets/radio_panel.dart';
import 'widgets/radio_status_bar.dart';
import 'widgets/comms_tab.dart';
import 'widgets/audio_tab.dart';
import 'widgets/aprs_tab.dart';
import 'widgets/map_tab.dart';
import 'widgets/mail_tab.dart';
import 'widgets/terminal_tab.dart';
import 'widgets/contacts_tab.dart';
import 'widgets/bbs_tab.dart';
import 'widgets/torrent_tab.dart';
import 'widgets/packets_tab.dart';
import 'dialogs/update_dialog.dart';
import 'widgets/debug_tab.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Some widgets (e.g. dropdowns showing long serial port names) can
  // legitimately overflow their available width. In those cases it's acceptable
  // to clip rather than treat it as a fatal error, so suppress RenderFlex
  // overflow errors while forwarding all other errors to the default handler.
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception.toString().contains('A RenderFlex overflowed')) {
      return;
    }
    originalOnError?.call(details);
  };

  // Initialize the DataBroker for cross-component communication
  await DataBroker.initialize();

  // Ensure the built-in protected APRS routes ("Standard" and "None") always
  // exist before any component reads the APRS route configuration.
  AppSettings.ensureDefaultRoutes();

  // Register the frame deduplicator so that duplicate DataFrame events received
  // by multiple radios are collapsed into single UniqueDataFrame events.
  DataBroker.addDataHandler('FrameDeduplicator', FrameDeduplicator());

  // Register the packet store so that captured packets are persisted to disk
  // and replayed on the next launch. Must be initialized before registration so
  // that PacketStoreReady is announced once loading is complete.
  final packetStore = PacketStore();
  await packetStore.init();
  DataBroker.addDataHandler('PacketStore', packetStore);

  // Register the APRS handler so that packets on the "APRS" channel are
  // decoded, authenticated, stored and made available to the APRS tab.
  final aprsHandler = AprsHandler();
  aprsHandler.init();
  DataBroker.addDataHandler('AprsHandler', aprsHandler);

  // Register the airplane handler so that, when a Dump1090 server is configured
  // and airplane display is enabled, aircraft are polled and dispatched on the
  // "Airplanes" event for the map tab.
  final airplaneHandler = AirplaneHandler();
  airplaneHandler.init();
  DataBroker.addDataHandler('AirplaneHandler', airplaneHandler);

  // Register the software modem handler so that incoming radio audio is decoded
  // into TNC data frames using AFSK 1200, PSK 2400/4800 or G3RUH 9600
  // modulation via the hamlib library, and outgoing packets are encoded to PCM.
  final softwareModem = SoftwareModem();
  softwareModem.init();
  DataBroker.addDataHandler('SoftwareModem', softwareModem);

  // Register the comms handler so that audio from radios can be turned into a
  // decoded text history and the comms tab can drive speech-to-text state.
  final commsHandler = CommsHandler();
  commsHandler.init();
  DataBroker.addDataHandler('CommsHandler', commsHandler);

  // Register the GPS serial handler so that an external GPS receiver connected
  // to a serial port is read, its NMEA sentences parsed, and a GpsData object
  // dispatched on device 1 for the radio panel and map tab.
  final gpsSerialHandler = GpsSerialHandler();
  gpsSerialHandler.init();
  DataBroker.addDataHandler('GpsSerialHandler', gpsSerialHandler);

  // Register the BBS handler so that the BBS tab can activate a bulletin-board /
  // Winlink server on a radio. It creates per-radio BBS instances on CreateBbs,
  // locks the radio for "BBS" usage, and aggregates station statistics.
  final bbsHandler = BbsHandler();
  bbsHandler.init();
  DataBroker.addDataHandler('BbsHandler', bbsHandler);

  // Register the debug log handler so that LogInfo/LogError messages are
  // captured into DebugLogEntries from application startup, regardless of
  // whether the Debug tab has been opened.
  final debugLogHandler = DebugLogHandler();
  debugLogHandler.init();
  DataBroker.addDataHandler('DebugLogHandler', debugLogHandler);

  // Register the torrent handler so that the Torrent tab can share, request and
  // transfer files over a radio locked to the "Torrent" usage. Its store is
  // initialized first so that previously shared files are restored on launch.
  final torrentStore = TorrentStore();
  await torrentStore.init();
  final torrentHandler = TorrentHandler(store: torrentStore);
  torrentHandler.init();
  DataBroker.addDataHandler('TorrentHandler', torrentHandler);

  // Register the mail store so that Winlink mail is persisted to disk and made
  // available to the mail tab and the Winlink client. Must be initialized
  // before the Winlink client so that mail can be read/written during a sync.
  final mailStore = MailStore();
  await mailStore.initialize();

  // Start the Winlink client so that it listens for WinlinkSync requests from
  // the mail tab (Connect -> Internet / Radio) and runs the B2F protocol.
  final winlinkClient = WinlinkClient();
  DataBroker.addDataHandler('WinlinkClient', winlinkClient);

  // Register the AGWPE server handler (desktop only) so that, when enabled in
  // settings, an AGW Packet Engine (AGWPE) TCP server is exposed for external
  // packet applications. It bridges monitoring, UNPROTO and connected-mode
  // sessions to the radio. Not available on web/iOS/Android.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    final agwpeHandler = AgwpeHandler();
    agwpeHandler.init();
    DataBroker.addDataHandler('AgwpeHandler', agwpeHandler);
  }

  // Register the web server handler (desktop only) so that, when enabled in
  // settings, the bundled static web UI is served over HTTP. Not available on
  // web/iOS/Android.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    final webServerHandler = WebServerHandler();
    webServerHandler.init();
    DataBroker.addDataHandler('WebServerHandler', webServerHandler);
  }

  // Initialize the history limiter so that persisted data is pruned at startup,
  // when limits change, and periodically (every 30 min) if new data arrives.
  HistoryLimiter.instance.init();

  // Initialize the desktop self-update service (desktop only) so that users
  // can check for and install application updates from the Help menu.
  await UpdateService.instance.init();

  // Check if this is a sub-window on desktop platforms
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    try {
      final controller = await WindowController.fromCurrentEngine();
      if (controller.arguments.isNotEmpty) {
        final argument =
            jsonDecode(controller.arguments) as Map<String, dynamic>;
        // Mark this as a child window so tabs don't show "Detach..." option
        windowService.isChildWindow = true;
        runApp(SubWindowApp(windowController: controller, argument: argument));
        return;
      }
    } catch (e) {
      // Not a sub-window, continue to main app
    }
  }
  runApp(const HTCommanderApp());
}

bool get _serialGpsSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

const double _narrowDialogBreakpoint = 700;

EdgeInsets _responsiveDialogInsetPadding(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  final isNarrow = screenWidth < _narrowDialogBreakpoint;
  return EdgeInsets.symmetric(
    horizontal: isNarrow ? 8 : 40,
    vertical: isNarrow ? 12 : 24,
  );
}

Widget _wrapWithResponsiveDialogTheme(BuildContext context, Widget? child) {
  final themed = Theme.of(context).copyWith(
    dialogTheme: Theme.of(context).dialogTheme.copyWith(
      insetPadding: _responsiveDialogInsetPadding(context),
    ),
  );
  return Theme(data: themed, child: child ?? const SizedBox.shrink());
}

/// Sub-window application for detached tabs
class SubWindowApp extends StatefulWidget {
  final WindowController windowController;
  final Map<String, dynamic> argument;

  const SubWindowApp({
    super.key,
    required this.windowController,
    required this.argument,
  });

  @override
  State<SubWindowApp> createState() => _SubWindowAppState();
}

class _SubWindowAppState extends State<SubWindowApp> {
  late final String tabTitle;
  late final Widget tabContent;

  @override
  void initState() {
    super.initState();
    final windowType = widget.argument['window'] as String? ?? '';

    switch (windowType) {
      case 'comms':
        tabTitle = 'Communications';
        tabContent = const CommsTab();
      case 'audio':
        tabTitle = 'Audio';
        tabContent = const AudioTab();
      case 'aprs':
        tabTitle = 'APRS';
        tabContent = const AprsTab();
      case 'map':
        tabTitle = 'Map';
        tabContent = const MapTab();
      case 'mail':
        tabTitle = 'Mail';
        tabContent = const MailTab();
      case 'terminal':
        tabTitle = 'Terminal';
        tabContent = const TerminalTab();
      case 'contacts':
        tabTitle = 'Contacts';
        tabContent = const ContactsTab();
      case 'bbs':
        tabTitle = 'BBS';
        tabContent = const BbsTab();
      case 'torrent':
        tabTitle = 'Torrent';
        tabContent = const TorrentTab();
      case 'packets':
        tabTitle = 'Packets';
        tabContent = const PacketsTab();
      case 'debug':
        tabTitle = 'Debug';
        tabContent = const DebugTab();
      default:
        tabTitle = 'Unknown';
        tabContent = Center(child: Text('Unknown window type: $windowType'));
    }

    // Set the window title
    _setWindowTitle();
  }

  Future<void> _setWindowTitle() async {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('Handi-Talkie Commander - $tabTitle');
    await windowManager.setMinimumSize(const Size(550, 600));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Handi-Talkie Commander - $tabTitle',
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          _wrapWithResponsiveDialogTheme(context, child),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(body: tabContent),
    );
  }
}

class HTCommanderApp extends StatelessWidget {
  const HTCommanderApp({super.key});

  /// Shared observer that clears focus whenever a route is pushed, preventing
  /// the keyboard from re-appearing when a dialog is dismissed.
  static final NavigatorObserver _unfocusOnPushObserver =
      _UnfocusOnPushObserver();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Handi-Talkie Commander',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [_unfocusOnPushObserver],
      builder: (context, child) =>
          _wrapWithResponsiveDialogTheme(context, child),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MainForm(),
    );
  }
}

/// Clears the keyboard focus whenever a new route (such as a dialog) is pushed.
///
/// Flutter's default behavior restores focus to the previously focused widget
/// when a modal route is popped. Combined with the keep-alive tabs, that caused
/// the soft keyboard to reappear on the main form's text inputs every time a
/// dialog was closed — even when a tab with no text input was showing. By
/// dropping focus at push time there is no remembered node to restore, so the
/// three message inputs only receive focus when explicitly requested. A dialog
/// that sets `autofocus` on its own fields is unaffected, because that focus is
/// requested after the route is pushed.
class _UnfocusOnPushObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    FocusManager.instance.primaryFocus?.unfocus();
    super.didPush(route, previousRoute);
  }
}

// ============================================================================
// Unified Menu Definition
// ============================================================================

/// Represents a menu item that can be rendered as both native macOS menu
/// and Flutter in-app menu.
sealed class AppMenuItem {
  const AppMenuItem();
}

class AppMenuAction extends AppMenuItem {
  final String label;
  final VoidCallback? onPressed;
  final MenuSerializableShortcut? shortcut;
  final bool checked;
  final bool hideOnMacOS;

  const AppMenuAction({
    required this.label,
    this.onPressed,
    this.shortcut,
    this.checked = false,
    this.hideOnMacOS = false,
  });
}

class AppMenuDivider extends AppMenuItem {
  final bool hideOnMacOS;
  const AppMenuDivider({this.hideOnMacOS = false});
}

class AppSubmenu extends AppMenuItem {
  final String label;
  final String? macOSLabel;
  final List<AppMenuItem> children;

  const AppSubmenu({
    required this.label,
    this.macOSLabel,
    required this.children,
  });
}

// ============================================================================
// Main Form
// ============================================================================

class MainForm extends StatefulWidget {
  const MainForm({super.key});

  @override
  State<MainForm> createState() => _MainFormState();
}

class _MainFormState extends State<MainForm>
    with TickerProviderStateMixin, WindowListener {
  late TabController _tabController;
  final ScrollController _tabListScrollController = ScrollController();
  late List<_TabInfo> _currentTabs;
  bool _radioVisible = true;
  bool _showTabNames = true;
  // Whether the vertical tab list on the right is shown. Only togglable while
  // in compact mode; always shown when not in compact mode.
  bool _tabsVisible = true;
  bool _showAllChannels = false;
  // Tabs the user has chosen to hide via the context menu.
  Set<String> _hiddenTabs = {};
  // When true, all tabs are shown regardless of _hiddenTabs.
  bool _showAllTabs = false;
  bool _isCompactMode = false;
  // A saved tab label that wasn't available at startup (e.g. "Radio", which
  // only exists in compact mode). Selected once the tab set is rebuilt.
  String? _pendingRestoreTab;
  String _statusText = '';
  int _batteryPercentage =
      -1; // Battery percentage of the currently displayed radio (-1 = unknown)
  bool _dualWatchEnabled =
      false; // Dual-watch state of the currently displayed radio
  bool _scanEnabled = false; // Scan state of the currently displayed radio
  bool _audioEnabled =
      false; // Audio path state of the currently displayed radio
  bool _gpsEnabled =
      false; // GPS enabled state of the currently displayed radio
  String _softwareModemMode = 'none'; // Current software modem mode
  bool _softwareModemFec = true; // FX.25 FEC on transmit (software modem)
  String _dartTxLevel = '0'; // DART transmit level ('0'..'5' or 'F')
  String _aprsModemMode = 'none'; // APRS modem mode ('none' or 'afsk1200')
  bool _aprsModemFec = true; // FX.25 FEC on transmit (APRS modem)
  int _regionCount =
      0; // Number of regions offered by the currently displayed radio
  int _currRegion = 0; // Current region index of the currently displayed radio

  // DataBroker client for subscriptions
  final DataBrokerClient _broker = DataBrokerClient();

  // Starting device ID for radios (each connected radio gets 100, 101, 102, etc.)
  // ignore: unused_field
  static const int startingDeviceId = 100;

  // Connected radios tracking (list of device IDs)
  List<int> _connectedRadioIds = [];

  // Current radio panel device ID (the radio being displayed/controlled)
  int _currentRadioDeviceId = -1;

  // Menu state from DataBroker
  String _callSign = '';
  int _stationId = 0;
  bool _allowTransmit =
      false; // Tab visibility (Winlink/Mail, Terminal, BBS, Torrent)
  bool _winlinkPasswordSet =
      false; // Winlink/Mail tab visibility (requires a password)

  // Width threshold for compact mode (Radio becomes a tab instead of side panel)
  static const double compactWidthThreshold = 600;
  static const double hideStatusBarHeightThreshold = 400;

  // Set to true to force built-in menus even on macOS (for debugging)
  bool _forceBuiltInMenus = false;

  // Computed property: should we show built-in menus?
  bool get _showBuiltInMenus {
    if (_forceBuiltInMenus) return true;
    // On macOS, use native menus (don't show built-in)
    // On web, Platform is unavailable so always show built-in menus
    if (!kIsWeb && Platform.isMacOS) return false;
    return true;
  }

  // Tab definitions matching C# MainForm
  static const List<_TabInfo> _baseTabs = [
    _TabInfo('Comms', 'assets/images/tabs/voice.png', Icons.mic),
    _TabInfo('Audio', 'assets/images/tabs/audio.png', Icons.volume_up),
    _TabInfo('APRS', 'assets/images/tabs/aprs.png', Icons.people),
    _TabInfo('Map', 'assets/images/tabs/map.png', Icons.public),
    _TabInfo('Mail', 'assets/images/tabs/email.png', Icons.mail),
    _TabInfo('Terminal', 'assets/images/tabs/terminal.png', Icons.terminal),
    _TabInfo('Contacts', 'assets/images/tabs/contacts.png', Icons.contacts),
    _TabInfo('BBS', 'assets/images/tabs/bbs.png', Icons.forum),
    _TabInfo('Torrent', 'assets/images/tabs/torrent.png', Icons.swap_horiz),
    _TabInfo('Packets', 'assets/images/tabs/packets.png', Icons.search),
    _TabInfo('Debug', 'assets/images/tabs/debug.png', Icons.info),
  ];

  // Radio tab shown only in compact mode
  static const _TabInfo _radioTab = _TabInfo(
    'Radio',
    'assets/images/Radio.png',
    Icons.radio,
  );

  // Tabs that are only useful when the application is allowed to transmit.
  // These are hidden entirely when the "AllowTransmit" setting is disabled.
  static const Set<String> _transmitOnlyTabs = {
    'Mail', // Winlink
    'Terminal',
    'BBS',
    'Torrent',
  };

  // Get tabs for a given mode
  static List<_TabInfo> _getTabsForMode(
    bool isCompact,
    bool allowTransmit,
    bool winlinkPasswordSet,
  ) {
    // The web build talks to the radio over the BLE control channel only; there
    // is no audio channel. The Audio tab is still shown (restricted to the
    // Radio volume/squelch controls), but the "BBS" and "Torrent" tabs are
    // hidden on the web. The "Comms" tab is kept but restricted to "Chat" mode
    // (control-channel data only).
    const hiddenOnWeb = {'BBS', 'Torrent'};
    final base = _baseTabs.where((t) {
      if (kIsWeb && hiddenOnWeb.contains(t.label)) return false;
      // Hide transmit-only tabs (Winlink/Mail, Terminal, BBS, Torrent) when
      // transmitting is not allowed.
      if (!allowTransmit && _transmitOnlyTabs.contains(t.label)) return false;
      // The Winlink (Mail) tab additionally requires a Winlink password.
      if (!winlinkPasswordSet && t.label == 'Mail') return false;
      return true;
    }).toList();
    return isCompact ? [_radioTab, ...base] : base;
  }

  /// Returns the tabs for the current mode, filtering out user-hidden tabs
  /// unless [_showAllTabs] is enabled.
  List<_TabInfo> _getVisibleTabs() {
    final all = _getTabsForMode(
      _isCompactMode,
      _allowTransmit,
      _winlinkPasswordSet,
    );
    if (_showAllTabs || _hiddenTabs.isEmpty) return all;
    final visible = all.where((t) => !_hiddenTabs.contains(t.label)).toList();
    // Always show at least one tab.
    return visible.isEmpty ? all : visible;
  }

  @override
  void initState() {
    super.initState();

    // Load settings from DataBroker
    _loadSettingsFromBroker();

    // Subscribe to settings changes
    _broker.subscribeMultiple(
      deviceId: 0,
      names: [
        'CallSign',
        'StationId',
        'AllowTransmit',
        'WinlinkPassword',
        'CheckForUpdates',
        'ShowAllChannels',
      ],
      callback: _onSettingsChanged,
    );

    // Subscribe to connected radios list from device 1
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );

    // Subscribe to RadioConnect request (from RadioPanelControl)
    _broker.subscribe(
      deviceId: 1,
      name: 'RadioConnect',
      callback: _onRadioConnectRequested,
    );

    // Subscribe to BatteryAsPercentage from all radio devices
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'BatteryAsPercentage',
      callback: _onBatteryPercentageChanged,
    );

    // Subscribe to Settings changes from all radio devices (for dual-watch/scan state)
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Settings',
      callback: _onRadioSettingsChanged,
    );

    // Subscribe to AudioState changes from all radio devices (audio path on/off)
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'AudioState',
      callback: _onAudioStateChanged,
    );

    // Subscribe to GpsEnabled changes from all radio devices (GPS on/off)
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'GpsEnabled',
      callback: _onGpsEnabledChanged,
    );

    // Subscribe to Info changes from all radio devices (region count)
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Info',
      callback: _onRadioInfoChanged,
    );

    // Subscribe to HtStatus changes from all radio devices (current region)
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'HtStatus',
      callback: _onHtStatusChanged,
    );

    // Subscribe to software modem mode changes
    _broker.subscribe(
      deviceId: 0,
      name: 'SoftwareModemMode',
      callback: _onSoftwareModemModeChanged,
    );
    // Load initial value
    _softwareModemMode =
        (_broker.getValue<String>(0, 'SoftwareModemMode', 'none') ?? 'none')
            .toLowerCase();

    // Subscribe to software modem FX.25 FEC changes
    _broker.subscribe(
      deviceId: 0,
      name: 'SoftwareModemFec',
      callback: _onSoftwareModemFecChanged,
    );
    // Load initial value
    _softwareModemFec =
        _broker.getValue<bool>(0, 'SoftwareModemFec', true) ?? true;

    // Subscribe to DART transmit-level changes
    _broker.subscribe(
      deviceId: 0,
      name: 'DartTxMode',
      callback: _onDartTxModeChanged,
    );
    // Load initial value
    _dartTxLevel =
        (_broker.getValue<String>(0, 'DartTxMode', '0') ?? '0').toUpperCase();

    // Subscribe to the independent APRS modem mode / FEC changes
    _broker.subscribe(
      deviceId: 0,
      name: 'AprsSoftwareModemMode',
      callback: _onAprsModemModeChanged,
    );
    _aprsModemMode =
        (_broker.getValue<String>(0, 'AprsSoftwareModemMode', 'none') ?? 'none')
            .toLowerCase();
    _broker.subscribe(
      deviceId: 0,
      name: 'AprsSoftwareModemFec',
      callback: _onAprsModemFecChanged,
    );
    _aprsModemFec =
        _broker.getValue<bool>(0, 'AprsSoftwareModemFec', true) ?? true;

    // Initialize tabs with saved index
    _currentTabs = _getVisibleTabs();
    final savedTabName =
        DataBroker.getValue<String>(0, 'SelectedTabName', '') ?? '';
    int initialIndex = 0;
    if (savedTabName.isNotEmpty) {
      final idx = _currentTabs.indexWhere((t) => t.label == savedTabName);
      if (idx >= 0) {
        initialIndex = idx;
      } else {
        // The saved tab isn't available yet (e.g. "Radio" only exists in
        // compact mode, which isn't determined until first layout). Remember
        // it so it can be selected once the tab set is rebuilt.
        _pendingRestoreTab = savedTabName;
      }
    } else {
      // Backward compatibility: fall back to the legacy saved index.
      final savedTabIndex =
          DataBroker.getValue<int>(0, 'SelectedTabIndex', 0) ?? 0;
      initialIndex = savedTabIndex.clamp(0, _currentTabs.length - 1);
    }
    _tabController = TabController(
      length: _currentTabs.length,
      vsync: this,
      initialIndex: initialIndex,
    );

    // Listen for tab changes to save
    _tabController.addListener(_onTabChanged);

    _initWindowManager();
    _updateWindowTitle();
  }

  /// Load settings from DataBroker (device 0).
  void _loadSettingsFromBroker() {
    _callSign = DataBroker.getValue<String>(0, 'CallSign', '') ?? '';
    _stationId = DataBroker.getValue<int>(0, 'StationId', 0) ?? 0;
    _allowTransmit =
        (DataBroker.getValue<int>(0, 'AllowTransmit', 0) ?? 0) == 1;
    _winlinkPasswordSet =
        (DataBroker.getValue<String>(0, 'WinlinkPassword', '') ?? '')
            .isNotEmpty;
    _showTabNames = (DataBroker.getValue<int>(0, 'ShowTabNames', 1) ?? 1) == 1;
    _showAllChannels =
        (DataBroker.getValue<int>(0, 'ShowAllChannels', 0) ?? 0) == 1;
    _showAllTabs = (DataBroker.getValue<int>(0, 'ShowAllTabs', 0) ?? 0) == 1;
    final hiddenTabsStr =
        DataBroker.getValue<String>(0, 'HiddenTabs', '') ?? '';
    _hiddenTabs = hiddenTabsStr.isEmpty ? {} : hiddenTabsStr.split(',').toSet();
  }

  /// Handle settings changes from DataBroker.
  void _onSettingsChanged(int deviceId, String name, Object? data) {
    setState(() {
      switch (name) {
        case 'CallSign':
          _callSign = data as String? ?? '';
          _updateWindowTitle();
          break;
        case 'StationId':
          _stationId = data as int? ?? 0;
          _updateWindowTitle();
          break;
        case 'AllowTransmit':
          _allowTransmit = (data as int?) == 1;
          _rebuildTabsForTransmit();
          break;
        case 'WinlinkPassword':
          _winlinkPasswordSet = (data as String? ?? '').isNotEmpty;
          _rebuildTabsForTransmit();
          break;
        case 'ShowAllChannels':
          _showAllChannels = (data as int?) == 1;
          break;
      }
    });
  }

  /// Handle connected radios list changes.
  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    if (data == null) {
      setState(() {
        _connectedRadioIds = [];
      });
      return;
    }

    // Extract device IDs from the connected radios list (de-duplicated - the
    // broker list can contain repeated entries for the same radio).
    if (data is List) {
      final ids = <int>[];
      for (final radio in data) {
        if (radio is Map && radio['DeviceId'] != null) {
          final id = radio['DeviceId'] as int;
          if (!ids.contains(id)) ids.add(id);
        }
      }
      setState(() {
        _connectedRadioIds = ids;
        // If we have no current radio selected and radios are connected, select the first
        if (_currentRadioDeviceId < 0 && ids.isNotEmpty) {
          _currentRadioDeviceId = ids.first;
          // Load battery percentage for the newly selected radio
          _loadBatteryForCurrentRadio();
          _loadSettingsForCurrentRadio();
        }
        // If current radio disconnected, switch to another or reset
        if (_currentRadioDeviceId >= 0 &&
            !ids.contains(_currentRadioDeviceId)) {
          _currentRadioDeviceId = ids.isNotEmpty ? ids.first : -1;
          // Load battery percentage for the newly selected radio (or reset)
          _loadBatteryForCurrentRadio();
          _loadSettingsForCurrentRadio();
        }
      });
    }
  }

  /// Handle radio connect request from RadioPanelControl.
  void _onRadioConnectRequested(int deviceId, String name, Object? data) {
    _onConnect();
  }

  /// Handle battery percentage changes from any radio device.
  void _onBatteryPercentageChanged(int deviceId, String name, Object? data) {
    // Only update if this is for the currently displayed radio
    if (deviceId == _currentRadioDeviceId && data is int) {
      setState(() {
        _batteryPercentage = data;
      });
    }
  }

  /// Load battery percentage for the currently selected radio from DataBroker.
  void _loadBatteryForCurrentRadio() {
    if (_currentRadioDeviceId > 0) {
      final battery = DataBroker.getValue<int>(
        _currentRadioDeviceId,
        'BatteryAsPercentage',
      );
      _batteryPercentage = battery ?? -1;
    } else {
      _batteryPercentage = -1;
    }
  }

  /// Handle Settings changes from any radio device (dual-watch / scan state).
  void _onRadioSettingsChanged(int deviceId, String name, Object? data) {
    // Only update if this is for the currently displayed radio
    if (deviceId == _currentRadioDeviceId && data is Map) {
      setState(() {
        _dualWatchEnabled =
            (data['doubleChannel'] as int? ??
                data['double_channel'] as int? ??
                0) ==
            1;
        _scanEnabled = data['scan'] as bool? ?? false;
      });
    }
  }

  /// Handle AudioState changes from any radio device (audio path enabled/disabled).
  void _onAudioStateChanged(int deviceId, String name, Object? data) {
    // Only update if this is for the currently displayed radio
    if (deviceId == _currentRadioDeviceId && data is bool) {
      setState(() {
        _audioEnabled = data;
      });
    }
  }

  /// Handle SoftwareModemMode changes from the DataBroker.
  void _onSoftwareModemModeChanged(int deviceId, String name, Object? data) {
    if (data is String) {
      setState(() {
        _softwareModemMode = data.toLowerCase();
      });
    }
  }

  /// Handle SoftwareModemFec changes from the DataBroker.
  void _onSoftwareModemFecChanged(int deviceId, String name, Object? data) {
    if (data is bool) {
      setState(() {
        _softwareModemFec = data;
      });
    }
  }

  /// Handle DART transmit-level changes from the DataBroker.
  void _onDartTxModeChanged(int deviceId, String name, Object? data) {
    if (data is String) {
      setState(() {
        _dartTxLevel = data.toUpperCase();
      });
    }
  }

  /// Handle APRS modem mode changes from the DataBroker.
  void _onAprsModemModeChanged(int deviceId, String name, Object? data) {
    if (data is String) {
      setState(() {
        _aprsModemMode = data.toLowerCase();
      });
    }
  }

  /// Handle APRS modem FX.25 FEC changes from the DataBroker.
  void _onAprsModemFecChanged(int deviceId, String name, Object? data) {
    if (data is bool) {
      setState(() {
        _aprsModemFec = data;
      });
    }
  }

  /// Handle GpsEnabled changes from any radio device (GPS enabled/disabled).
  void _onGpsEnabledChanged(int deviceId, String name, Object? data) {
    // Only update if this is for the currently displayed radio
    if (deviceId == _currentRadioDeviceId && data is bool) {
      setState(() {
        _gpsEnabled = data;
      });
    }
  }

  /// Handle Info changes from any radio device (region count).
  void _onRadioInfoChanged(int deviceId, String name, Object? data) {
    if (deviceId == _currentRadioDeviceId && data is Map) {
      final newRegionCount = data['regionCount'] as int? ?? 0;
      // Only rebuild when the value the menu actually depends on changes.
      // Info messages can arrive frequently; rebuilding on every one would
      // recreate the (Platform)MenuBar and dismiss any open menu.
      if (newRegionCount != _regionCount) {
        setState(() {
          _regionCount = newRegionCount;
        });
      }
    }
  }

  /// Handle HtStatus changes from any radio device (current region).
  void _onHtStatusChanged(int deviceId, String name, Object? data) {
    if (deviceId == _currentRadioDeviceId && data is Map) {
      final newCurrRegion = data['currRegion'] as int? ?? 0;
      // HtStatus updates arrive continuously (they carry RSSI and other live
      // values). Only rebuild when the current region actually changes so an
      // RSSI update doesn't recreate the menu bar and close an open menu.
      if (newCurrRegion != _currRegion) {
        setState(() {
          _currRegion = newCurrRegion;
        });
      }
    }
  }

  /// Select a region on the currently selected radio (mirrors the C#
  /// regionToolStripMenuItem region item click). Dispatches a Region event
  /// which the radio handles by switching to the requested region.
  void _onSelectRegion(int regionIndex) {
    final deviceId = _currentRadioDeviceId;
    if (deviceId <= 0) return;
    _broker.dispatch(
      deviceId: deviceId,
      name: 'Region',
      data: regionIndex,
      store: false,
    );
  }

  /// Toggle GPS on the currently selected radio (mirrors the C#
  /// gPSEnabledToolStripMenuItem_Click). Dispatches a SetGPS event which the
  /// radio handles by enabling/disabling GPS notifications.
  void _onToggleGps() {
    final deviceId = _currentRadioDeviceId;
    if (deviceId <= 0) return;
    // Persist the user's GPS-enabled preference (device 0) so GPS is
    // automatically enabled when a radio connects. Radios without GPS
    // support silently ignore the enable command.
    _broker.dispatch(
      deviceId: 0,
      name: 'GpsEnabled',
      data: !_gpsEnabled,
      store: true,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: 'SetGPS',
      data: !_gpsEnabled,
      store: false,
    );
  }

  /// Toggle the audio path on the currently selected radio.
  void _onToggleAudio() {
    final deviceId = _currentRadioDeviceId;
    if (deviceId <= 0) return;
    // Toggle audio state - read the current state from the broker and dispatch
    // the opposite (mirrors the C# audioEnabledToolStripMenuItem_Click).
    final currentlyEnabled =
        DataBroker.getValue<bool>(deviceId, 'AudioState', false) ?? false;
    // Persist the user's audio-enabled preference (device 0) so the audio
    // channel is automatically enabled when a radio connects.
    _broker.dispatch(
      deviceId: 0,
      name: 'AudioEnabled',
      data: !currentlyEnabled,
      store: true,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: 'SetAudio',
      data: !currentlyEnabled,
      store: false,
    );
  }

  /// Set the software modem mode via the DataBroker.
  void _setSoftwareModemMode(String mode) {
    _broker.dispatch(
      deviceId: 0,
      name: 'SetSoftwareModemMode',
      data: mode,
      store: false,
    );
  }

  /// Toggle FX.25 FEC on the software modem via the DataBroker. When disabled,
  /// packets are sent as plain AX.25 (no FEC).
  void _toggleSoftwareModemFec() {
    _broker.dispatch(
      deviceId: 0,
      name: 'SetSoftwareModemFec',
      data: !_softwareModemFec,
      store: false,
    );
  }

  /// Set the DART transmit level ('0'..'5' or 'F') via the DataBroker.
  void _setDartTxLevel(String level) {
    _broker.dispatch(
      deviceId: 0,
      name: 'SetDartTxMode',
      data: level,
      store: false,
    );
  }

  /// Set the independent APRS modem mode ('None' or 'AFSK1200') via the
  /// DataBroker.
  void _setAprsModemMode(String mode) {
    _broker.dispatch(
      deviceId: 0,
      name: 'SetAprsSoftwareModemMode',
      data: mode,
      store: false,
    );
  }

  /// Toggle FX.25 FEC on the APRS modem via the DataBroker (independent of the
  /// general software modem's FEC setting).
  void _toggleAprsModemFec() {
    _broker.dispatch(
      deviceId: 0,
      name: 'SetAprsSoftwareModemFec',
      data: !_aprsModemFec,
      store: false,
    );
  }

  /// Load dual-watch and scan state for the currently selected radio from DataBroker.
  void _loadSettingsForCurrentRadio() {
    _audioEnabled = _currentRadioDeviceId > 0
        ? (DataBroker.getValue<bool>(
                _currentRadioDeviceId,
                'AudioState',
                false,
              ) ??
              false)
        : false;
    _gpsEnabled = _currentRadioDeviceId > 0
        ? (DataBroker.getValue<bool>(
                _currentRadioDeviceId,
                'GpsEnabled',
                false,
              ) ??
              false)
        : false;
    if (_currentRadioDeviceId > 0) {
      final info = DataBroker.getValueDynamic(_currentRadioDeviceId, 'Info');
      _regionCount = (info is Map ? info['regionCount'] as int? : null) ?? 0;
      final htStatus = DataBroker.getValueDynamic(
        _currentRadioDeviceId,
        'HtStatus',
      );
      _currRegion =
          (htStatus is Map ? htStatus['currRegion'] as int? : null) ?? 0;
    } else {
      _regionCount = 0;
      _currRegion = 0;
    }
    if (_currentRadioDeviceId > 0) {
      final settings = DataBroker.getValue<Map<String, dynamic>>(
        _currentRadioDeviceId,
        'Settings',
      );
      if (settings != null) {
        _dualWatchEnabled =
            (settings['doubleChannel'] as int? ??
                settings['double_channel'] as int? ??
                0) ==
            1;
        _scanEnabled = settings['scan'] as bool? ?? false;
        return;
      }
    }
    _dualWatchEnabled = false;
    _scanEnabled = false;
  }

  /// Toggle dual-watch on the currently selected radio.
  void _onToggleDualWatch() {
    if (_currentRadioDeviceId <= 0) return;
    _broker.dispatch(
      deviceId: _currentRadioDeviceId,
      name: 'DualWatch',
      data: !_dualWatchEnabled,
      store: false,
    );
  }

  /// Toggle scan on the currently selected radio.
  void _onToggleScan() {
    if (_currentRadioDeviceId <= 0) return;
    _broker.dispatch(
      deviceId: _currentRadioDeviceId,
      name: 'Scan',
      data: !_scanEnabled,
      store: false,
    );
  }

  /// Export the channels of the currently selected radio to a CSV file.
  ///
  /// Mirrors `exportChannelsToolStripMenuItem_Click` in the C# MainForm: the
  /// user picks a format (native HTCommander CSV or CHIRP CSV) and a
  /// destination file, then all configured channels are written out.
  Future<void> _onExportChannels() async {
    // Read the channels for the radio currently shown in the radio panel.
    final raw = _broker.getValueDynamic(_currentRadioDeviceId, 'Channels');
    final channels = (raw is List)
        ? raw.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
        : <Map<String, dynamic>>[];

    // Only keep channels that have valid TX/RX frequencies (same filter the
    // export routines apply per row).
    final hasExportable = channels.any(
      (c) =>
          ((c['txFreq'] ?? c['tx_freq'] ?? 0) as int) != 0 &&
          ((c['rxFreq'] ?? c['rx_freq'] ?? 0) as int) != 0,
    );

    if (channels.isEmpty || !hasExportable) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Channels'),
          content: const Text('No channels available to export.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Ask the user which format to export.
    final format = await showDialog<ChannelExportFormat>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Export Channels'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(ChannelExportFormat.native),
            child: const Text('Native Channel File (CSV)'),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(ChannelExportFormat.chirp),
            child: const Text('CHIRP Channel File (CSV)'),
          ),
        ],
      ),
    );
    if (format == null) return; // Cancelled.

    final content = format == ChannelExportFormat.native
        ? ChannelExport.exportToNativeFormat(channels)
        : ChannelExport.exportToChirpFormat(channels);

    final defaultFileName = format == ChannelExportFormat.native
        ? 'channels.csv'
        : 'channels_chirp.csv';

    // Web and mobile require the bytes up front (the picker writes the file
    // itself); desktop returns a path that we write to ourselves.
    final needsBytes = kIsWeb || Platform.isAndroid || Platform.isIOS;

    // Show the save dialog and write the file.
    try {
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Export Channels',
        fileName: defaultFileName,
        type: needsBytes ? FileType.any : FileType.custom,
        allowedExtensions: needsBytes ? null : const ['csv'],
        bytes: needsBytes ? Uint8List.fromList(utf8.encode(content)) : null,
      );
      if (outputPath == null) return; // Cancelled.

      // On desktop the picker only returns a path, so we still write the file.
      // On web/mobile the bytes were already written by the picker.
      if (!needsBytes) {
        await File(outputPath).writeAsString(content);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Channels exported to $defaultFileName')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error exporting channels: $e')));
    }
  }

  /// Import channels from a CSV file (CHIRP, native HTCommander, or Repeater
  /// Book format) and open the import dialog so the user can assign them to the
  /// radio's channel slots.
  ///
  /// Mirrors `importChannelsToolStripMenuItem_Click` in the C# MainForm.
  Future<void> _onImportChannels() async {
    final messenger = mounted ? ScaffoldMessenger.of(context) : null;

    // Read the radio's existing channels (the right column of the dialog).
    final raw = _broker.getValueDynamic(_currentRadioDeviceId, 'Channels');
    final radioChannels = (raw is List)
        ? raw
              .whereType<Map>()
              .map((m) => RadioChannelInfo.fromJson(m.cast<String, dynamic>()))
              .toList()
        : <RadioChannelInfo>[];

    // Pick a CSV file. Request the bytes directly so it works on web and
    // mobile, where a filesystem path may not be available.
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        dialogTitle: 'Import Channels',
        type: FileType.any,
        withData: true,
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Error opening file dialog: $e')),
      );
      return;
    }

    if (result == null || result.files.isEmpty) return; // Cancelled.

    final file = result.files.single;
    String? content;
    try {
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (!kIsWeb && file.path != null) {
        content = await File(file.path!).readAsString();
      }
    } catch (_) {
      content = null;
    }

    if (content == null) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not read the selected file')),
      );
      return;
    }

    final importedChannels = ChannelImport.parseChannelsFromCsv(content);
    if (importedChannels.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('No channels found in the selected file')),
      );
      return;
    }

    if (!mounted) return;
    final radioName = _broker.getValue<String>(
      _currentRadioDeviceId,
      'FriendlyName',
      '',
    );
    await showImportChannelsDialog(
      context,
      deviceId: _currentRadioDeviceId,
      radioName: radioName,
      importedChannels: importedChannels,
      radioChannels: radioChannels,
    );
  }

  /// Called when the connect button is pressed in RadioPanelControl.
  void _onRadioConnect() {
    _onConnect();
  }

  /// Called when tab selection changes.
  void _onTabChanged() {
    // Drop keyboard focus when moving between tabs so a text input on one tab
    // can't keep (or regain) focus while a different tab is showing. Without
    // this, the soft keyboard could reappear on tabs that have no text input.
    FocusManager.instance.primaryFocus?.unfocus();

    if (!_tabController.indexIsChanging) {
      // Save the selected tab by label (not index) so the same tab is restored
      // regardless of which tabs are present at startup (e.g. the Radio tab in
      // compact mode or hidden transmit-only tabs shift the indices).
      final idx = _tabController.index;
      final label = (idx >= 0 && idx < _currentTabs.length)
          ? _currentTabs[idx].label
          : '';
      _broker.dispatch(deviceId: 0, name: 'SelectedTabName', data: label);
    }
  }

  /// Update the window title based on call sign and station ID.
  Future<void> _updateWindowTitle() async {
    if (!isDesktop) return;

    String title = 'HTCommander';
    if (_callSign.isNotEmpty) {
      if (_stationId == 0) {
        title = 'HTCommander - $_callSign';
      } else {
        title = 'HTCommander - $_callSign-$_stationId';
      }
    }

    await windowManager.setTitle(title);
  }

  Future<void> _initWindowManager() async {
    if (isDesktop) {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      // Match the macOS native minimum window size (set in MainMenu.xib).
      await windowManager.setMinimumSize(const Size(550, 600));
      // Intercept close to clean up child windows
      await windowManager.setPreventClose(true);
    }
  }

  @override
  void onWindowClose() async {
    // Close all child windows before closing main window
    await windowService.closeAllChildren();
    await windowManager.destroy();
  }

  /// Exits the application (File -> Exit). On desktop this closes child windows
  /// and destroys the main window; elsewhere it falls back to popping the route.
  void _onExit() async {
    if (isDesktop) {
      await windowService.closeAllChildren();
      await windowManager.destroy();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _broker.dispose();
    if (isDesktop) {
      windowManager.removeListener(this);
    }
    _tabController.dispose();
    _tabListScrollController.dispose();
    super.dispose();
  }

  void _toggleTabsVisible() {
    setState(() {
      _tabsVisible = !_tabsVisible;
    });
  }

  void _updateCompactMode(bool isCompact) {
    if (_isCompactMode == isCompact) return;
    final oldIndex = _tabController.index;
    // Temporarily set _isCompactMode so _getVisibleTabs uses the new mode.
    _isCompactMode = isCompact;
    final newTabs = _getVisibleTabs();

    // Calculate new index
    int newIndex;
    if (isCompact) {
      // Entering compact mode: shift index by 1 (Radio tab added at start)
      newIndex = (oldIndex + 1).clamp(0, newTabs.length - 1);
    } else {
      // Leaving compact mode: shift index back (Radio tab removed)
      // If on Radio tab (index 0), go to first content tab
      newIndex = (oldIndex > 0 ? oldIndex - 1 : 0).clamp(0, newTabs.length - 1);
    }

    // If a saved tab couldn't be restored at startup (it only exists in the
    // new mode, e.g. "Radio" in compact mode), select it now.
    if (_pendingRestoreTab != null) {
      final idx = newTabs.indexWhere((t) => t.label == _pendingRestoreTab);
      if (idx >= 0) newIndex = idx;
      _pendingRestoreTab = null;
    }

    _tabController.dispose();

    setState(() {
      _isCompactMode = isCompact;
      _currentTabs = newTabs;
      _tabController = TabController(
        length: _currentTabs.length,
        vsync: this,
        initialIndex: newIndex,
      );
    });
    _tabController.addListener(_onTabChanged);
  }

  /// Rebuilds the tab list and controller when the "AllowTransmit" or
  /// "WinlinkPassword" setting changes, adding or removing the transmit-only
  /// tabs (Winlink/Mail, Terminal, BBS, Torrent) and the Winlink/Mail tab
  /// (which also requires a password). Called from within `_onSettingsChanged`'s
  /// `setState`, so it mutates state directly without its own `setState`.
  void _rebuildTabsForTransmit() {
    final newTabs = _getVisibleTabs();
    if (newTabs.length == _currentTabs.length) return;

    // Preserve the current selection by label where possible.
    final int oldIndex = _tabController.index;
    final String? oldLabel = (oldIndex >= 0 && oldIndex < _currentTabs.length)
        ? _currentTabs[oldIndex].label
        : null;
    int newIndex = 0;
    if (oldLabel != null) {
      final idx = newTabs.indexWhere((t) => t.label == oldLabel);
      if (idx >= 0) newIndex = idx;
    }
    newIndex = newIndex.clamp(0, newTabs.length - 1);

    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();

    _currentTabs = newTabs;
    _tabController = TabController(
      length: _currentTabs.length,
      vsync: this,
      initialIndex: newIndex,
    );
    _tabController.addListener(_onTabChanged);
  }

  // ============================================================================
  // Unified Menu Definition - Single source of truth for all menus
  // ============================================================================

  /// Whether we have at least one connected radio.
  bool get _hasConnectedRadio => _connectedRadioIds.isNotEmpty;

  /// Whether GPS serial port is configured.
  bool get _hasGpsConfigured {
    if (!_serialGpsSupported) return false;
    final gpsPort =
        DataBroker.getValue<String>(0, 'GpsSerialPort', 'None') ?? 'None';
    return gpsPort.isNotEmpty && gpsPort != 'None';
  }

  /// Resolves a display label for a radio [deviceId] from the `ConnectedRadios`
  /// list (device 1), preferring the friendly name (e.g. "UV-PRO") and falling
  /// back to "Radio $deviceId" when none is available.
  String _radioMenuLabel(int deviceId) {
    final radios = DataBroker.getValueDynamic(1, 'ConnectedRadios', null);
    if (radios is List) {
      for (final radio in radios) {
        if (radio is Map && radio['DeviceId'] == deviceId) {
          final name = radio['FriendlyName'];
          if (name is String && name.isNotEmpty) return name;
        }
      }
    }
    return 'Radio $deviceId';
  }

  /// Builds the items for the Radio > Regions submenu (mirrors the C#
  /// regionToolStripMenuItem_DropDownOpening logic). One checkable item per
  /// region the radio reports; the currently active region shows a checkmark.
  List<AppMenuItem> _buildRegionMenuItems() {
    if (!_hasConnectedRadio || _regionCount <= 0) {
      return const [AppMenuAction(label: 'No Regions', onPressed: null)];
    }
    return List<AppMenuItem>.generate(
      _regionCount,
      (i) => AppMenuAction(
        label: 'Region ${i + 1}',
        checked: i == _currRegion,
        onPressed: () => _onSelectRegion(i),
      ),
    );
  }

  List<AppSubmenu> _buildMenuDefinition() {
    return [
      // Radio menu (Connect/Disconnect on top, radio settings below)
      AppSubmenu(
        label: 'File',
        macOSLabel: 'Radio',
        children: [
          AppMenuAction(
            label: 'Connect...',
            onPressed: _onConnect,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyO,
              meta: true,
            ),
          ),
          AppMenuAction(
            label: 'Disconnect',
            onPressed: _hasConnectedRadio ? _onDisconnect : null,
          ),
          const AppMenuDivider(),
          AppMenuAction(
            label: 'Dual-Watch',
            onPressed: _hasConnectedRadio ? _onToggleDualWatch : null,
            checked: _dualWatchEnabled,
          ),
          AppMenuAction(
            label: 'Scan',
            onPressed: _hasConnectedRadio ? _onToggleScan : null,
            checked: _scanEnabled,
          ),
          AppMenuAction(
            label: 'GPS',
            onPressed: _hasConnectedRadio ? _onToggleGps : null,
            checked: _gpsEnabled,
          ),
          AppSubmenu(label: 'Regions', children: _buildRegionMenuItems()),
          const AppMenuDivider(),
          AppMenuAction(
            label: 'Export Channels...',
            onPressed: _hasConnectedRadio ? _onExportChannels : null,
          ),
          AppMenuAction(
            label: 'Import Channels...',
            onPressed: _hasConnectedRadio ? _onImportChannels : null,
          ),
          const AppMenuDivider(hideOnMacOS: true),
          AppMenuAction(
            label: 'Settings...',
            onPressed: _onSettings,
            shortcut: const SingleActivator(
              LogicalKeyboardKey.comma,
              meta: true,
            ),
            hideOnMacOS: true,
          ),
          // The web build runs in the browser and cannot quit itself, and iOS
          // and Android apps are not expected to quit themselves, so the "Exit"
          // item (and its divider) are omitted there.
          if (!kIsWeb && !Platform.isIOS && !Platform.isAndroid) ...[
            const AppMenuDivider(hideOnMacOS: true),
            AppMenuAction(
              label: 'Exit',
              onPressed: () => _onExit(),
              hideOnMacOS: true,
            ),
          ],
        ],
      ),
      // Audio menu (hidden on web and iOS: no audio channel over BLE
      // control-only transport).
      if (!kIsWeb && !Platform.isIOS)
        AppSubmenu(
          label: 'Audio',
          children: [
            AppMenuAction(
              label: 'Audio Enabled',
              onPressed: _hasConnectedRadio ? _onToggleAudio : null,
              checked: _audioEnabled,
            ),
            const AppMenuDivider(),
            AppSubmenu(
              label: 'Software Modem',
              children: [
                AppMenuAction(
                  label: 'Disabled',
                  onPressed: () => _setSoftwareModemMode('None'),
                  checked: _softwareModemMode == 'none',
                ),
                AppMenuAction(
                  label: 'AFSK 1200',
                  onPressed: () => _setSoftwareModemMode('AFSK1200'),
                  checked: _softwareModemMode == 'afsk1200',
                ),
                AppMenuAction(
                  label: 'PSK 2400',
                  onPressed: () => _setSoftwareModemMode('PSK2400'),
                  checked: _softwareModemMode == 'psk2400',
                ),
                AppMenuAction(
                  label: 'DART',
                  onPressed: () => _setSoftwareModemMode('DART'),
                  checked: _softwareModemMode == 'dart',
                ),
                const AppMenuDivider(),
                AppMenuAction(
                  label: 'FX.25 FEC',
                  onPressed: _toggleSoftwareModemFec,
                  checked: _softwareModemFec,
                ),
              ],
            ),
            AppSubmenu(
              label: 'DART Transmit Level',
              children: [
                AppMenuAction(
                  label: 'Level 0 (BPSK, LDPC 1/2)',
                  onPressed: () => _setDartTxLevel('0'),
                  checked: _dartTxLevel == '0',
                ),
                AppMenuAction(
                  label: 'Level 1 (QPSK, LDPC 1/2)',
                  onPressed: () => _setDartTxLevel('1'),
                  checked: _dartTxLevel == '1',
                ),
                AppMenuAction(
                  label: 'Level 2 (QPSK, LDPC 2/3)',
                  onPressed: () => _setDartTxLevel('2'),
                  checked: _dartTxLevel == '2',
                ),
                AppMenuAction(
                  label: 'Level 3 (8PSK, LDPC 2/3)',
                  onPressed: () => _setDartTxLevel('3'),
                  checked: _dartTxLevel == '3',
                ),
                AppMenuAction(
                  label: 'Level 4 (16QAM, LDPC 3/4)',
                  onPressed: () => _setDartTxLevel('4'),
                  checked: _dartTxLevel == '4',
                ),
                AppMenuAction(
                  label: 'Level 5 (16QAM, LDPC 5/6)',
                  onPressed: () => _setDartTxLevel('5'),
                  checked: _dartTxLevel == '5',
                ),
                AppMenuAction(
                  label: 'Level F (4-FSK, LDPC 1/2)',
                  onPressed: () => _setDartTxLevel('F'),
                  checked: _dartTxLevel == 'F',
                ),
              ],
            ),
            AppSubmenu(
              label: 'APRS Modem',
              children: [
                AppMenuAction(
                  label: 'Disabled',
                  onPressed: () => _setAprsModemMode('None'),
                  checked: _aprsModemMode == 'none',
                ),
                AppMenuAction(
                  label: 'AFSK 1200',
                  onPressed: () => _setAprsModemMode('AFSK1200'),
                  checked: _aprsModemMode == 'afsk1200',
                ),
                const AppMenuDivider(),
                AppMenuAction(
                  label: 'FX.25 FEC',
                  onPressed: _toggleAprsModemFec,
                  checked: _aprsModemFec,
                ),
              ],
            ),
          ],
        ),
      // View menu (renamed on macOS to avoid automatic system items like "Show Tab Bar")
      AppSubmenu(
        label: 'View',
        macOSLabel: 'Display',
        children: [
          // Only show Radio toggle when not in compact mode
          if (!_isCompactMode)
            AppMenuAction(
              label: 'Radio',
              onPressed: () {
                setState(() {
                  _radioVisible = !_radioVisible;
                });
              },
              checked: _radioVisible,
            ),
          // Only show Tabs toggle when in compact mode
          if (_isCompactMode)
            AppMenuAction(
              label: 'Tabs',
              onPressed: _toggleTabsVisible,
              checked: _tabsVisible,
            ),
          AppMenuAction(
            label: 'Tab Names',
            onPressed: () {
              setState(() {
                _showTabNames = !_showTabNames;
              });
              _broker.dispatch(
                deviceId: 0,
                name: 'ShowTabNames',
                data: _showTabNames ? 1 : 0,
              );
            },
            checked: _showTabNames,
          ),
          AppMenuAction(
            label: 'Show All Tabs',
            onPressed: () {
              setState(() {
                _showAllTabs = !_showAllTabs;
                _rebuildTabList();
              });
              _broker.dispatch(
                deviceId: 0,
                name: 'ShowAllTabs',
                data: _showAllTabs ? 1 : 0,
              );
            },
            checked: _showAllTabs,
          ),
          AppMenuAction(
            label: 'All Channels',
            onPressed: () {
              final newValue = !_showAllChannels;
              setState(() {
                _showAllChannels = newValue;
              });
              _broker.dispatch(
                deviceId: 0,
                name: 'ShowAllChannels',
                data: newValue ? 1 : 0,
              );
            },
            checked: _showAllChannels,
          ),
          // Dynamic radio selection when multiple radios are connected
          if (_connectedRadioIds.length >= 2) ...[
            const AppMenuDivider(),
            ..._connectedRadioIds.map(
              (radioId) => AppMenuAction(
                label: _radioMenuLabel(radioId),
                onPressed: () {
                  setState(() {
                    _currentRadioDeviceId = radioId;
                    _loadBatteryForCurrentRadio();
                    _loadSettingsForCurrentRadio();
                  });
                  // Dispatch the selected radio device ID
                  _broker.dispatch(
                    deviceId: 1,
                    name: 'SelectedRadioDeviceId',
                    data: radioId,
                  );
                },
                checked: radioId == _currentRadioDeviceId,
              ),
            ),
          ],
        ],
      ),
      // Help/About menu
      AppSubmenu(
        label: 'Help',
        children: [
          AppMenuAction(
            label: 'Radio Information...',
            onPressed: _hasConnectedRadio
                ? () => showRadioInfoDialog(
                    context,
                    initialDeviceId: _currentRadioDeviceId,
                  )
                : null,
          ),
          if (_hasGpsConfigured)
            AppMenuAction(
              label: 'GPS Information...',
              onPressed: () => showGpsSerialInfoDialog(context),
            ),
          const AppMenuDivider(),
          if (UpdateService.instance.isSupported)
            AppMenuAction(
              label: 'Check for Updates...',
              onPressed: _onCheckForUpdates,
            ),
          AppMenuAction(
            label: 'About...',
            onPressed: _onAbout,
            hideOnMacOS: true,
          ),
        ],
      ),
    ];
  }

  // ============================================================================
  // Build Methods
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Check if we should be in compact mode based on width
        final shouldBeCompact = constraints.maxWidth < compactWidthThreshold;
        // Schedule mode update for after build if needed
        if (shouldBeCompact != _isCompactMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _updateCompactMode(shouldBeCompact);
          });
        }

        final content = Scaffold(
          body: SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                // Menu bar (only show built-in if not using native macOS menus)
                if (_showBuiltInMenus) _buildBuiltInMenuBar(),
                // Compact-mode radio status bar (below menu, above tabs). Only
                // shown when the Radio tab is not the currently selected tab.
                if (_isCompactMode)
                  AnimatedBuilder(
                    animation: _tabController,
                    builder: (context, _) {
                      if (_isRadioTabSelected) return const SizedBox.shrink();
                      return _buildRadioStatusBar();
                    },
                  ),
                // Main content
                Expanded(
                  child: Row(
                    children: [
                      // Left: Radio panel (hidden in compact mode - Radio becomes a tab)
                      if (_radioVisible && !_isCompactMode) _buildRadioPanel(),
                      // Right: Tab control
                      Expanded(child: _buildTabPanel()),
                    ],
                  ),
                ),
                // Status bar (hidden when height is too small or keyboard is shown)
                if (constraints.maxHeight >= hideStatusBarHeightThreshold &&
                    MediaQuery.of(context).viewInsets.bottom == 0)
                  _buildStatusBar(),
              ],
            ),
          ),
        );

        // Wrap with PlatformMenuBar for native macOS menus
        // Always show native menus on macOS (even when debugging with built-in menus)
        // Skip on web where Platform is unavailable
        if (!kIsWeb && Platform.isMacOS) {
          return PlatformMenuBar(menus: _buildPlatformMenus(), child: content);
        }

        return content;
      },
    );
  }

  // ============================================================================
  // Native macOS Platform Menus
  // ============================================================================

  List<PlatformMenuItem> _buildPlatformMenus() {
    final menuDef = _buildMenuDefinition();
    return [
      // Standard macOS app menu
      PlatformMenu(
        label: 'Handi-Talky Commander',
        menus: [
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'About Handi-Talky Commander',
                onSelected: _onAbout,
              ),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Settings...',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.comma,
                  meta: true,
                ),
                onSelected: _onSettings,
              ),
            ],
          ),
          const PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Hide Handi-Talky Commander',
                shortcut: SingleActivator(LogicalKeyboardKey.keyH, meta: true),
              ),
              PlatformMenuItem(
                label: 'Hide Others',
                shortcut: SingleActivator(
                  LogicalKeyboardKey.keyH,
                  meta: true,
                  alt: true,
                ),
              ),
              PlatformMenuItem(label: 'Show All'),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Quit Handi-Talky Commander',
                shortcut: const SingleActivator(
                  LogicalKeyboardKey.keyQ,
                  meta: true,
                ),
                onSelected: () => SystemNavigator.pop(),
              ),
            ],
          ),
        ],
      ),
      // Convert our menu definitions to platform menus
      ...menuDef.map(_convertToPlatformMenu),
    ];
  }

  PlatformMenu _convertToPlatformMenu(AppSubmenu submenu) {
    return PlatformMenu(
      label: submenu.macOSLabel ?? submenu.label,
      menus: _convertMenuItems(submenu.children),
    );
  }

  List<PlatformMenuItem> _convertMenuItems(List<AppMenuItem> items) {
    final result = <PlatformMenuItem>[];
    final List<PlatformMenuItem> currentGroup = [];

    for (final item in items) {
      if (item is AppMenuDivider) {
        // Skip dividers marked as hidden on macOS
        if (item.hideOnMacOS) continue;
        if (currentGroup.isNotEmpty) {
          result.add(PlatformMenuItemGroup(members: List.from(currentGroup)));
          currentGroup.clear();
        }
      } else if (item is AppMenuAction) {
        // Skip items marked as hidden on macOS
        if (item.hideOnMacOS) continue;
        currentGroup.add(
          PlatformMenuItem(
            label: item.checked ? '✓ ${item.label}' : item.label,
            shortcut: item.shortcut,
            onSelected: item.onPressed,
          ),
        );
      } else if (item is AppSubmenu) {
        // Flush current group first
        if (currentGroup.isNotEmpty) {
          result.add(PlatformMenuItemGroup(members: List.from(currentGroup)));
          currentGroup.clear();
        }
        result.add(
          PlatformMenu(
            label: item.label,
            menus: _convertMenuItems(item.children),
          ),
        );
      }
    }

    // Flush remaining items
    if (currentGroup.isNotEmpty) {
      result.add(PlatformMenuItemGroup(members: currentGroup));
    }

    return result;
  }

  // ============================================================================
  // Built-in Flutter MenuBar
  // ============================================================================

  Widget _buildBuiltInMenuBar() {
    final menuDef = _buildMenuDefinition();

    // Compact menu style for menu bar items
    final menuStyle = MenuStyle(
      padding: WidgetStatePropertyAll(EdgeInsets.zero),
      minimumSize: WidgetStatePropertyAll(Size.zero),
    );

    // Compact style for dropdown menu items
    final menuItemStyle = ButtonStyle(
      padding: WidgetStatePropertyAll(
        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      minimumSize: WidgetStatePropertyAll(const Size(0, 32)),
    );

    // Compact style for top-level menu buttons
    final submenuStyle = ButtonStyle(
      padding: WidgetStatePropertyAll(
        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      minimumSize: WidgetStatePropertyAll(const Size(0, 28)),
    );

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surface,
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: MenuBar(
                  style: menuStyle,
                  children: menuDef.map((submenu) {
                    return SubmenuButton(
                      style: submenuStyle,
                      menuStyle: menuStyle,
                      menuChildren: _buildBuiltInMenuItems(
                        submenu.children,
                        menuItemStyle,
                        menuStyle,
                      ),
                      child: Text(submenu.label),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          // Toggle the right-side tab list (only meaningful in compact mode).
          // Overlaid on top of the menu bar so the menu keeps its normal layout.
          if (_isCompactMode)
            Positioned(
              top: 0,
              bottom: 0,
              right: 4,
              child: Center(
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _tabsVisible ? 'Hide tabs' : 'Show tabs',
                  icon: Icon(
                    _tabsVisible ? Icons.tab : Icons.tab_unselected,
                    size: 20,
                  ),
                  onPressed: _toggleTabsVisible,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildBuiltInMenuItems(
    List<AppMenuItem> items,
    ButtonStyle menuItemStyle,
    MenuStyle menuStyle,
  ) {
    return items.map((item) {
      if (item is AppMenuDivider) {
        return const Divider(height: 1);
      } else if (item is AppMenuAction) {
        return MenuItemButton(
          style: menuItemStyle,
          onPressed: item.onPressed,
          // Android devices typically have no physical keyboard, so suppress
          // the shortcut hint (e.g. for Connect/Settings) shown in menus.
          shortcut: (!kIsWeb && Platform.isAndroid) ? null : item.shortcut,
          leadingIcon: item.checked
              ? const Icon(Icons.check, size: 16)
              : (items.any((i) => i is AppMenuAction && i.checked)
                    ? const SizedBox(width: 16)
                    : null),
          child: Text(item.label),
        );
      } else if (item is AppSubmenu) {
        return SubmenuButton(
          style: menuItemStyle,
          menuStyle: menuStyle,
          // Align the label with sibling actions when any of them shows a
          // leading checkmark (e.g. Dual-Watch/Scan/GPS in the File menu).
          leadingIcon: items.any((i) => i is AppMenuAction && i.checked)
              ? const SizedBox(width: 16)
              : null,
          menuChildren: _buildBuiltInMenuItems(
            item.children,
            menuItemStyle,
            menuStyle,
          ),
          child: Text(item.label),
        );
      }
      return const SizedBox.shrink();
    }).toList();
  }

  // ============================================================================
  // Other UI Components
  // ============================================================================

  Widget _buildRadioPanel() {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      child: RadioPanelControl(
        deviceId: _currentRadioDeviceId,
        onConnectPressed: _onRadioConnect,
      ),
    );
  }

  // True when the currently selected tab is the (compact-only) Radio tab.
  bool get _isRadioTabSelected {
    final index = _tabController.index;
    if (index < 0 || index >= _currentTabs.length) return false;
    return _currentTabs[index].label == 'Radio';
  }

  Widget _buildRadioStatusBar() {
    return RadioStatusBar(
      deviceId: _currentRadioDeviceId,
      onConnectPressed: _onRadioConnect,
    );
  }

  Widget _buildTabPanel() {
    // Use a key based on compact mode to force clean rebuild when mode changes
    return Column(
      key: ValueKey('tab_panel_${_isCompactMode}_${_currentTabs.length}'),
      children: [
        // Tabs on the right side (vertical)
        Expanded(
          child: Row(
            children: [
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: _currentTabs
                      .map((tab) => _buildTabContent(tab))
                      .toList(),
                ),
              ),
              // Hide the tab list only in compact mode when the user toggles it off
              if (!_isCompactMode || _tabsVisible) _buildVerticalTabList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalTabList() {
    final colorScheme = Theme.of(context).colorScheme;
    final tabWidth = _showTabNames ? 92.0 : 56.0;

    return SizedBox(
      width: tabWidth,
      child: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          return Scrollbar(
            controller: _tabListScrollController,
            thumbVisibility: true,
            child: ListView.builder(
              controller: _tabListScrollController,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              itemCount: _currentTabs.length,
              itemBuilder: (context, index) {
                final tab = _currentTabs[index];
                final isSelected = _tabController.index == index;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: Colors.transparent,
                    child: GestureDetector(
                      onSecondaryTapUp: (details) {
                        _showTabContextMenu(
                          context,
                          details.globalPosition,
                          tab,
                        );
                      },
                      onLongPressStart: (details) {
                        _showTabContextMenu(
                          context,
                          details.globalPosition,
                          tab,
                        );
                      },
                      child: InkWell(
                        onTap: () => _tabController.animateTo(index),
                        child: Stack(
                          children: [
                            // Selection marker on the leading edge, matching the
                            // previous TabBar indicator.
                            Positioned(
                              top: 0,
                              bottom: 0,
                              left: 0,
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 3,
                                  height: isSelected ? 36 : 0,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 6,
                              ),
                              child: SizedBox(
                                width: double.infinity,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.asset(
                                      tab.assetPath,
                                      width: 32,
                                      height: 32,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Icon(
                                              tab.fallbackIcon,
                                              size: 32,
                                              color: isSelected
                                                  ? colorScheme.primary
                                                  : Colors.grey,
                                            );
                                          },
                                    ),
                                    if (_showTabNames) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        tab.label,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isSelected
                                              ? colorScheme.primary
                                              : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Shows a context menu for a tab with an option to hide it.
  void _showTabContextMenu(
    BuildContext context,
    Offset position,
    _TabInfo tab,
  ) {
    final isHidden = _hiddenTabs.contains(tab.label);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        CheckedPopupMenuItem<String>(
          value: 'toggle',
          checked: !isHidden,
          child: const Text('Show Tab'),
        ),
      ],
    ).then((value) {
      if (value == 'toggle') {
        _toggleTabHidden(tab.label);
      }
    });
  }

  /// Toggles a tab's hidden state and rebuilds the tab list.
  void _toggleTabHidden(String label) {
    setState(() {
      if (_hiddenTabs.contains(label)) {
        _hiddenTabs.remove(label);
      } else {
        _hiddenTabs.add(label);
      }
      _persistHiddenTabs();
      _rebuildTabList();
    });
  }

  /// Persists the hidden tabs set to DataBroker.
  void _persistHiddenTabs() {
    _broker.dispatch(
      deviceId: 0,
      name: 'HiddenTabs',
      data: _hiddenTabs.join(','),
    );
  }

  /// Rebuilds the tab list and controller after hidden tabs change.
  void _rebuildTabList() {
    final newTabs = _getVisibleTabs();
    if (newTabs.length == _currentTabs.length &&
        newTabs.every((t) => _currentTabs.any((c) => c.label == t.label))) {
      return;
    }

    // Preserve the current selection by label where possible.
    final int oldIndex = _tabController.index;
    final String? oldLabel = (oldIndex >= 0 && oldIndex < _currentTabs.length)
        ? _currentTabs[oldIndex].label
        : null;
    int newIndex = 0;
    if (oldLabel != null) {
      final idx = newTabs.indexWhere((t) => t.label == oldLabel);
      if (idx >= 0) newIndex = idx;
    }
    newIndex = newIndex.clamp(0, newTabs.length - 1);

    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();

    _currentTabs = newTabs;
    _tabController = TabController(
      length: _currentTabs.length,
      vsync: this,
      initialIndex: newIndex,
    );
    _tabController.addListener(_onTabChanged);
  }

  Widget _buildTabContent(_TabInfo tab) {
    // Return the appropriate widget based on tab label
    switch (tab.label) {
      case 'Radio':
        return RadioPanelControl(
          deviceId: _currentRadioDeviceId,
          onConnectPressed: _onRadioConnect,
        );
      case 'Comms':
        return const CommsTab();
      case 'Audio':
        return const AudioTab();
      case 'APRS':
        return const AprsTab();
      case 'Map':
        return const MapTab();
      case 'Mail':
        return const MailTab();
      case 'Terminal':
        return const TerminalTab();
      case 'Contacts':
        return const ContactsTab();
      case 'BBS':
        return const BbsTab();
      case 'Torrent':
        return const TorrentTab();
      case 'Packets':
        return const PacketsTab();
      case 'Debug':
        return DebugTab(
          showBuiltInMenus: _forceBuiltInMenus,
          onShowBuiltInMenusChanged: (value) {
            setState(() => _forceBuiltInMenus = value);
          },
        );
      default:
        return Center(child: Text('Unknown tab: ${tab.label}'));
    }
  }

  Widget _buildStatusBar() {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _statusText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          // Battery percentage on the right (only show when connected and battery info available)
          if (_currentRadioDeviceId > 0 && _batteryPercentage >= 0)
            Text(
              'Battery: $_batteryPercentage%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  // ============================================================================
  // Menu Actions
  // ============================================================================

  void _onConnect() async {
    _broker.logInfo('Connect requested - checking Bluetooth...');

    setState(() {
      _statusText = 'Checking Bluetooth...';
    });

    // Check if Bluetooth is available
    final bluetoothAvailable = await BluetoothService.checkBluetooth();
    if (!bluetoothAvailable) {
      if (!mounted) return;
      _broker.logError('Bluetooth not available');
      setState(() {
        _statusText = 'Bluetooth not available';
      });
      _showBluetoothWarning();
      return;
    }

    _broker.logInfo('Scanning for compatible radios...');
    setState(() {
      _statusText = 'Scanning for radios...';
    });

    // Find compatible devices
    final bluetoothService = BluetoothService();
    List<DiscoveredDevice> allDevices;

    try {
      allDevices = await bluetoothService.findCompatibleDevices(
        timeout: const Duration(seconds: 5),
      );
    } catch (e) {
      if (!mounted) return;
      _broker.logError('Error scanning for radios: $e');
      setState(() {
        _statusText = 'Error scanning for radios';
      });
      _showErrorDialog('Error', 'Failed to scan for Bluetooth devices: $e');
      return;
    }

    if (!mounted) return;

    // No compatible devices found
    if (allDevices.isEmpty) {
      _broker.logInfo('No compatible radios found');
      setState(() {
        _statusText = 'No compatible radios found';
      });
      _showInfoDialog(
        'No Radios Found',
        'No compatible radio devices were found.\n\n'
            'Make sure your radio is powered on and Bluetooth is enabled.',
      );
      return;
    }

    _broker.logInfo('Found ${allDevices.length} compatible device(s)');
    for (final device in allDevices) {
      _broker.logInfo('  ${device.name} (${device.id})');
    }

    // Apply stored friendly names
    final compatibleDevices = _applyStoredFriendlyNames(allDevices);

    // Filter out already connected radios
    final connectedMacs = <String>{};
    for (final radioId in _connectedRadioIds) {
      final mac = DataBroker.getValue<String>(radioId, 'MacAddress', '');
      if (mac != null && mac.isNotEmpty) {
        connectedMacs.add(mac.toUpperCase());
      }
    }

    final availableDevices = compatibleDevices.where((device) {
      return !connectedMacs.contains(device.mac.toUpperCase());
    }).toList();

    if (availableDevices.isEmpty) {
      _broker.logInfo('All radios already connected');
      setState(() {
        _statusText = 'All radios already connected';
      });
      _showInfoDialog(
        'All Connected',
        'All detected radio devices are already connected.',
      );
      return;
    }

    // If only 1 available radio and it's the only one found, connect directly
    if (availableDevices.length == 1 && allDevices.length == 1) {
      final device = availableDevices.first;
      _broker.logInfo('Connecting to ${device.name}...');
      setState(() {
        _statusText = 'Connecting to ${device.name}...';
      });

      final deviceId = await bluetoothService.connectToRadio(
        device.mac,
        device.name,
      );

      if (!mounted) return;

      if (deviceId != null) {
        _broker.logInfo('Connected to ${device.name} (deviceId: $deviceId)');
        setState(() {
          _statusText = 'Connected to ${device.name}';
        });
      } else {
        _broker.logError('Failed to connect to ${device.name}');
        setState(() {
          _statusText = 'Failed to connect to ${device.name}';
        });
      }
      return;
    }

    // Show the radio connection dialog for multiple radios
    _broker.logInfo('Showing radio selection dialog...');
    setState(() {
      _statusText = '';
    });

    await RadioConnectionDialog.show(context, compatibleDevices);
  }

  /// Apply stored friendly names to discovered devices
  List<CompatibleDevice> _applyStoredFriendlyNames(
    List<DiscoveredDevice> devices,
  ) {
    final result = <CompatibleDevice>[];

    // Get stored custom names dictionary
    final customNames = DataBroker.getValue<Map<String, dynamic>>(
      0,
      'DeviceFriendlyName',
    );

    for (final device in devices) {
      // Look up stored custom name by MAC address (uppercase with dashes removed)
      final macKey = device.id
          .toUpperCase()
          .replaceAll(':', '-')
          .replaceAll('-', '');
      final macKeyColons = device.id.toUpperCase();

      String customName = '';
      if (customNames != null) {
        // Try both formats for the key
        customName =
            customNames[macKey] as String? ??
            customNames[macKeyColons] as String? ??
            customNames[device.id.toUpperCase()] as String? ??
            '';
      }

      result.add(
        CompatibleDevice(
          name: customName.isNotEmpty ? customName : device.name,
          mac: device.id,
          bluetoothName: device.name,
        ),
      );
    }

    return result;
  }

  void _showBluetoothWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bluetooth Not Available'),
        content: const Text(
          'Bluetooth is not available or is turned off.\n\n'
          'Please enable Bluetooth in your device settings and try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        icon: const Icon(Icons.error_outline, color: Colors.red),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onDisconnect() async {
    if (_connectedRadioIds.isEmpty) return;

    final bluetoothService = BluetoothService();

    // If only one radio, disconnect it directly
    if (_connectedRadioIds.length == 1) {
      final deviceId = _connectedRadioIds.first;
      _broker.logInfo('Disconnecting radio (deviceId: $deviceId)...');
      setState(() {
        _statusText = 'Disconnecting...';
      });

      await bluetoothService.disconnectRadio(deviceId);

      if (!mounted) return;
      _broker.logInfo('Disconnected');
      setState(() {
        _statusText = 'Disconnected';
      });
    } else {
      // Show radio selection dialog for disconnect
      // For now, disconnect the current selected radio
      if (_currentRadioDeviceId >= 0) {
        _broker.logInfo(
          'Disconnecting radio (deviceId: $_currentRadioDeviceId)...',
        );
        setState(() {
          _statusText = 'Disconnecting...';
        });

        await bluetoothService.disconnectRadio(_currentRadioDeviceId);

        if (!mounted) return;
        _broker.logInfo('Disconnected');
        setState(() {
          _statusText = 'Disconnected';
        });
      }
    }
  }

  bool _settingsDialogOpen = false;

  void _onSettings() async {
    if (_settingsDialogOpen) return;
    _settingsDialogOpen = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const SettingsDialog(),
    );
    _settingsDialogOpen = false;
    if (result == true) {
      // Settings were saved to DataBroker
      // Reload settings to update UI
      _loadSettingsFromBroker();
      setState(() {});
    }
  }

  void _onCheckForUpdates() {
    _broker.logInfo('Opening Check for Updates dialog');
    showDialog(context: context, builder: (context) => const UpdateDialog());
  }

  void _onAbout() {
    _broker.logInfo('Opening About dialog');
    showDialog(context: context, builder: (context) => const HTAboutDialog());
  }
}

// ============================================================================
// Tab Info
// ============================================================================

class _TabInfo {
  final String label;
  final String assetPath;
  final IconData fallbackIcon;

  const _TabInfo(this.label, this.assetPath, this.fallbackIcon);
}
