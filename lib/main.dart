import 'dart:convert';
import 'dart:io' show Platform;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'dialogs/about_dialog.dart';
import 'dialogs/settings_dialog.dart';
import 'services/window_service.dart';
import 'widgets/radio_panel.dart';
import 'widgets/voice_tab.dart';
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
  bool _isCompactMode = false;
  String _statusText = '';

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
    _currentTabs = _getTabsForMode(_isCompactMode);
    _tabController = TabController(length: _currentTabs.length, vsync: this);
    _initWindowManager();
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

  List<AppSubmenu> _buildMenuDefinition() {
    return [
      // File menu (renamed to Radio on macOS with only Connect/Disconnect)
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
            onPressed: null, // Disabled until connected
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
          const AppMenuDivider(hideOnMacOS: true),
          AppMenuAction(
            label: 'Exit',
            onPressed: () => Navigator.of(context).maybePop(),
            hideOnMacOS: true,
          ),
        ],
      ),
      // Settings menu
      AppSubmenu(
        label: 'Settings',
        children: [
          const AppMenuAction(label: 'Dual-Watch', onPressed: null),
          const AppMenuAction(label: 'Scan', onPressed: null),
          const AppMenuAction(label: 'Regions', onPressed: null),
          AppMenuAction(label: 'GPS Enabled', onPressed: () {}),
          const AppMenuDivider(),
          const AppMenuAction(label: 'Export Channels...', onPressed: null),
          AppMenuAction(label: 'Import Channels...', onPressed: () {}),
        ],
      ),
      // Audio menu
      AppSubmenu(
        label: 'Audio',
        children: [
          AppMenuAction(label: 'Audio Enabled', onPressed: () {}),
          AppMenuAction(label: 'Audio Controls...', onPressed: () {}),
          AppMenuAction(label: 'Audio Clips...', onPressed: () {}),
          AppMenuAction(label: 'Spectrogram...', onPressed: () {}),
          AppSubmenu(
            label: 'Software Modem',
            children: [
              AppMenuAction(label: 'Disabled', onPressed: () {}),
              AppMenuAction(label: 'AFK 1200', onPressed: () {}),
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
          AppMenuAction(
            label: 'Tab Names',
            onPressed: () {
              setState(() {
                _showTabNames = !_showTabNames;
              });
            },
            checked: _showTabNames,
          ),
          AppMenuAction(label: 'Radio Window...', onPressed: () {}),
          AppMenuAction(label: 'All Channels', onPressed: () {}),
        ],
      ),
      // Help/About menu
      AppSubmenu(
        label: 'Help',
        children: [
          const AppMenuAction(label: 'Radio Information...', onPressed: null),
          const AppMenuAction(label: 'GPS Information...', onPressed: null),
          const AppMenuDivider(),
          AppMenuAction(label: 'Check for Updates', onPressed: () {}),
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
      child: const RadioPanelControl(),
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
        return const RadioPanelControl();
      case 'Voice':
        return const VoiceTab();
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
        ],
      ),
    );
  }

  // ============================================================================
  // Menu Actions
  // ============================================================================

  void _onConnect() {
    setState(() {
      _statusText = 'Connecting...';
    });
  }

  // App settings (would normally be loaded/saved to storage)
  AppSettings _appSettings = AppSettings();
  bool _settingsDialogOpen = false;

  void _onSettings() async {
    if (_settingsDialogOpen) return;
    _settingsDialogOpen = true;
    final result = await showDialog<AppSettings>(
      context: context,
      builder: (context) => SettingsDialog(initialSettings: _appSettings),
    );
    _settingsDialogOpen = false;
    if (result != null) {
      setState(() {
        _appSettings = result;
      });
    }
  }

  void _onAbout() {
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
