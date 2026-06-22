import 'dart:convert';
import 'dart:io' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'dialogs/about_dialog.dart';
import 'dialogs/radio_connection_dialog.dart';
import 'dialogs/radio_info_dialog.dart';
import 'dialogs/settings_dialog.dart';
import 'handlers/frame_deduplicator.dart';
import 'handlers/packet_store.dart';
import 'handlers/aprs_handler.dart';
import 'handlers/airplane_handler.dart';
import 'handlers/voice_handler.dart';
import 'handlers/bbs_handler.dart';
import 'handlers/debug_log_handler.dart';
import 'gps/gps_serial_handler.dart';
import 'radio/radio_transport.dart';
import 'services/bluetooth_service.dart';
import 'services/data_broker.dart';
import 'services/data_broker_client.dart';
import 'services/window_service.dart';
import 'winlink/mail_store.dart';
import 'winlink/winlink_client.dart';
import 'widgets/radio_panel.dart';
import 'widgets/voice_tab.dart';
import 'widgets/audio_tab.dart';
import 'widgets/aprs_tab.dart';
import 'widgets/map_tab.dart';
import 'widgets/mail_tab.dart';
import 'widgets/terminal_tab.dart';
import 'widgets/contacts_tab.dart';
import 'widgets/bbs_tab.dart';
import 'widgets/torrent_tab.dart';
import 'widgets/packets_tab.dart';
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

  // Register the voice handler so that audio from radios can be turned into a
  // decoded text history and the voice tab can drive speech-to-text state.
  final voiceHandler = VoiceHandler();
  voiceHandler.init();
  DataBroker.addDataHandler('VoiceHandler', voiceHandler);

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

  // Register the mail store so that Winlink mail is persisted to disk and made
  // available to the mail tab and the Winlink client. Must be initialized
  // before the Winlink client so that mail can be read/written during a sync.
  final mailStore = MailStore();
  await mailStore.initialize();

  // Start the Winlink client so that it listens for WinlinkSync requests from
  // the mail tab (Connect -> Internet / Radio) and runs the B2F protocol.
  final winlinkClient = WinlinkClient();
  DataBroker.addDataHandler('WinlinkClient', winlinkClient);

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
      case 'voice':
        tabTitle = 'Voice';
        tabContent = const VoiceTab();
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Handi-Talkie Commander',
      debugShowCheckedModeBanner: false,
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
  late List<_TabInfo> _currentTabs;
  bool _radioVisible = true;
  bool _showTabNames = true;
  bool _showAllChannels = false;
  bool _isCompactMode = false;
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
  // ignore: unused_field
  bool _allowTransmit =
      false; // Used for tab visibility (BBS, Terminal, Torrent)

  // Width threshold for compact mode (Radio becomes a tab instead of side panel)
  static const double compactWidthThreshold = 600;

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
    _TabInfo('Voice', 'assets/images/Voice.png', Icons.mic),
    _TabInfo('Audio', 'assets/images/Speaker-48-Blue.png', Icons.volume_up),
    _TabInfo('APRS', 'assets/images/Signal.png', Icons.people),
    _TabInfo('Map', 'assets/images/MapPoint1.png', Icons.public),
    _TabInfo('Mail', 'assets/images/Mail.png', Icons.mail),
    _TabInfo('Terminal', 'assets/images/Terminal.png', Icons.terminal),
    _TabInfo('Contacts', 'assets/images/Person.png', Icons.contacts),
    _TabInfo('BBS', 'assets/images/BBS.png', Icons.forum),
    _TabInfo('Torrent', 'assets/images/Graph-48.png', Icons.swap_horiz),
    _TabInfo('Packets', 'assets/images/Messaging.png', Icons.search),
    _TabInfo('Debug', 'assets/images/About.png', Icons.info),
  ];

  // Radio tab shown only in compact mode
  static const _TabInfo _radioTab = _TabInfo(
    'Radio',
    'assets/images/Radio.png',
    Icons.radio,
  );

  // Get tabs for a given mode
  static List<_TabInfo> _getTabsForMode(bool isCompact) {
    return isCompact ? [_radioTab, ..._baseTabs] : _baseTabs;
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

    // Initialize tabs with saved index
    _currentTabs = _getTabsForMode(_isCompactMode);
    final savedTabIndex =
        DataBroker.getValue<int>(0, 'SelectedTabIndex', 0) ?? 0;
    final initialIndex = savedTabIndex.clamp(0, _currentTabs.length - 1);
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
    _showTabNames = (DataBroker.getValue<int>(0, 'ShowTabNames', 1) ?? 1) == 1;
    _showAllChannels =
        (DataBroker.getValue<int>(0, 'ShowAllChannels', 0) ?? 0) == 1;
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

  /// Handle GpsEnabled changes from any radio device (GPS enabled/disabled).
  void _onGpsEnabledChanged(int deviceId, String name, Object? data) {
    // Only update if this is for the currently displayed radio
    if (deviceId == _currentRadioDeviceId && data is bool) {
      setState(() {
        _gpsEnabled = data;
      });
    }
  }

  /// Toggle GPS on the currently selected radio (mirrors the C#
  /// gPSEnabledToolStripMenuItem_Click). Dispatches a SetGPS event which the
  /// radio handles by enabling/disabling GPS notifications.
  void _onToggleGps() {
    final deviceId = _currentRadioDeviceId;
    if (deviceId <= 0) return;
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

  /// Called when the connect button is pressed in RadioPanelControl.
  void _onRadioConnect() {
    _onConnect();
  }

  /// Called when tab selection changes.
  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      // Save the selected tab index to DataBroker
      _broker.dispatch(
        deviceId: 0,
        name: 'SelectedTabIndex',
        data: _tabController.index,
      );
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

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _broker.dispose();
    if (isDesktop) {
      windowManager.removeListener(this);
    }
    _tabController.dispose();
    super.dispose();
  }

  void _updateCompactMode(bool isCompact) {
    if (_isCompactMode == isCompact) return;

    final oldIndex = _tabController.index;
    final newTabs = _getTabsForMode(isCompact);

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
  }

  // ============================================================================
  // Unified Menu Definition - Single source of truth for all menus
  // ============================================================================

  /// Whether we have at least one connected radio.
  bool get _hasConnectedRadio => _connectedRadioIds.isNotEmpty;

  /// Whether GPS serial port is configured.
  bool get _hasGpsConfigured {
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
            label: 'Regions',
            onPressed: _hasConnectedRadio ? () {} : null,
          ),
          AppMenuAction(
            label: 'GPS Enabled',
            onPressed: _hasConnectedRadio ? _onToggleGps : null,
            checked: _gpsEnabled,
          ),
          const AppMenuDivider(),
          AppMenuAction(
            label: 'Export Channels...',
            onPressed: _hasConnectedRadio ? () {} : null,
          ),
          AppMenuAction(label: 'Import Channels...', onPressed: () {}),
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
          const AppMenuDivider(hideOnMacOS: true),
          AppMenuAction(
            label: 'Exit',
            onPressed: () => Navigator.of(context).maybePop(),
            hideOnMacOS: true,
          ),
        ],
      ),
      // Audio menu
      AppSubmenu(
        label: 'Audio',
        children: [
          AppMenuAction(
            label: 'Audio Enabled',
            onPressed: _hasConnectedRadio ? _onToggleAudio : null,
            checked: _audioEnabled,
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
            AppMenuAction(label: 'GPS Information...', onPressed: () {}),
          const AppMenuDivider(),
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
          body: Column(
            children: [
              // Menu bar (only show built-in if not using native macOS menus)
              if (_showBuiltInMenus) _buildBuiltInMenuBar(),
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
              // Status bar
              _buildStatusBar(),
            ],
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
      child: Row(
        children: [
          MenuBar(
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
          const Spacer(),
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
          shortcut: item.shortcut,
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
              // Vertical tab bar on the right
              RotatedBox(
                quarterTurns: 1,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor: Colors.grey,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  tabs: _currentTabs.map((tab) {
                    return RotatedBox(
                      quarterTurns: -1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 6,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              tab.assetPath,
                              width: 32,
                              height: 32,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(tab.fallbackIcon, size: 32);
                              },
                            ),
                            if (_showTabNames) ...[
                              const SizedBox(height: 2),
                              Text(
                                tab.label,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabContent(_TabInfo tab) {
    // Return the appropriate widget based on tab label
    switch (tab.label) {
      case 'Radio':
        return RadioPanelControl(
          deviceId: _currentRadioDeviceId,
          onConnectPressed: _onRadioConnect,
        );
      case 'Voice':
        return const VoiceTab();
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
