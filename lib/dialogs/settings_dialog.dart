import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dialog_utils.dart';

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
    this.voiceModel = '',
    this.voice = '',
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

/// Voice model option
class ModelOption {
  final String id;
  final String name;

  const ModelOption(this.id, this.name);
}

/// Settings dialog with tabbed interface
class SettingsDialog extends StatefulWidget {
  final AppSettings initialSettings;
  final int initialTab;

  const SettingsDialog({
    super.key,
    required this.initialSettings,
    this.initialTab = 0,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late AppSettings _settings;

  // Controllers
  late TextEditingController _callSignController;
  late TextEditingController _winlinkPasswordController;
  late TextEditingController _webPortController;
  late TextEditingController _agwpePortController;
  late TextEditingController _airplaneUrlController;

  // Language options
  static const List<LanguageOption> _languages = [
    LanguageOption('auto', 'Auto-detect'),
    LanguageOption('en', 'English'),
    LanguageOption('es', 'Spanish'),
    LanguageOption('fr', 'French'),
    LanguageOption('de', 'German'),
    LanguageOption('it', 'Italian'),
    LanguageOption('pt', 'Portuguese'),
    LanguageOption('ru', 'Russian'),
    LanguageOption('zh', 'Chinese'),
    LanguageOption('ja', 'Japanese'),
    LanguageOption('ko', 'Korean'),
    LanguageOption('ar', 'Arabic'),
    LanguageOption('hi', 'Hindi'),
    LanguageOption('nl', 'Dutch'),
    LanguageOption('pl', 'Polish'),
    LanguageOption('sv', 'Swedish'),
    LanguageOption('da', 'Danish'),
    LanguageOption('fi', 'Finnish'),
    LanguageOption('no', 'Norwegian'),
  ];

  // Voice model options
  static const List<ModelOption> _models = [
    ModelOption('', 'None'),
    ModelOption('tiny', 'Tiny, 77.7 MB'),
    ModelOption('tiny.en', 'Tiny.en, 77.7 MB, English'),
    ModelOption('base', 'Base, 148 MB'),
    ModelOption('base.en', 'Base.en, 148 MB, English (Recommended)'),
    ModelOption('small', 'Small, 488 MB'),
    ModelOption('small.en', 'Small.en, 488 MB, English'),
    ModelOption('medium', 'Medium, 1.53 GB'),
    ModelOption('medium.en', 'Medium.en, 1.53 GB, English'),
  ];

  // GPS baud rates
  static const List<int> _baudRates = [4800, 9600, 19200, 38400, 57600, 115200];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _settings = widget.initialSettings.copyWith();

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
  }

  @override
  void dispose() {
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

  void _onSave() {
    _settings.winlinkPassword = _winlinkPasswordController.text;
    _settings.webServerPort = int.tryParse(_webPortController.text) ?? 8080;
    _settings.agwpeServerPort = int.tryParse(_agwpePortController.text) ?? 8000;
    _settings.airplaneServerUrl = _airplaneUrlController.text;
    Navigator.of(context).pop(_settings);
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
          color: Colors.black.withOpacity(0.05),
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
                tabs: const [
                  Tab(text: 'License'),
                  Tab(text: 'APRS'),
                  Tab(text: 'Voice'),
                  Tab(text: 'Winlink'),
                  Tab(text: 'Servers'),
                  Tab(text: 'Map'),
                ],
              ),
              const SizedBox(height: 8),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLicenseTab(),
                    _buildAprsTab(),
                    _buildVoiceTab(),
                    _buildWinlinkTab(),
                    _buildServersTab(),
                    _buildMapTab(),
                  ],
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
                // Call Sign
                const Text('Call Sign', style: DialogStyles.labelStyle),
                const SizedBox(height: 4),
                TextField(
                  controller: _callSignController,
                  decoration: _inputDecoration(hintText: 'e.g. W1AW'),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 16),
                // Station ID
                const Text('Station ID', style: DialogStyles.labelStyle),
                const SizedBox(height: 4),
                DropdownButtonFormField<int>(
                  value: _settings.stationId,
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
                        return ListTile(
                          dense: true,
                          title: Text(route.name),
                          subtitle: Text(route.path),
                          selected: false,
                          onTap: () => _editAprsRoute(index),
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
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _settings.aprsRoutes.isNotEmpty
                          ? () => _editAprsRoute(0)
                          : null,
                      child: const Text('Edit'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _settings.aprsRoutes.length > 1
                          ? () => _deleteAprsRoute(0)
                          : null,
                      child: const Text('Delete'),
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

  Widget _buildVoiceTab() {
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
          // Speech Recognition
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _sectionDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Speech Recognition (Whisper)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Language', style: DialogStyles.labelStyle),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: _settings.voiceLanguage,
                  decoration: _inputDecoration(),
                  items: _languages
                      .map(
                        (l) => DropdownMenuItem(
                          value: l.code,
                          child: Text(l.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _settings.voiceLanguage = value ?? 'auto');
                  },
                ),
                const SizedBox(height: 16),
                const Text('Model', style: DialogStyles.labelStyle),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: _settings.voiceModel,
                  decoration: _inputDecoration(),
                  items: _models
                      .map(
                        (m) =>
                            DropdownMenuItem(value: m.id, child: Text(m.name)),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _settings.voiceModel = value ?? '');
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _settings.voiceModel.isNotEmpty ? () {} : null,
                      child: const Text('Download'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _settings.voiceModel.isNotEmpty ? () {} : null,
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
                const SizedBox(height: 16),
                const Text('Voice', style: DialogStyles.labelStyle),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: _settings.voice.isEmpty ? null : _settings.voice,
                  decoration: _inputDecoration(),
                  items: const [
                    DropdownMenuItem(
                      value: 'default',
                      child: Text('System Default'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _settings.voice = value ?? 'default');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
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

  Widget _buildMapTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configure GPS and airplane tracking data sources.',
            style: DialogStyles.bodyStyle,
          ),
          const SizedBox(height: 16),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Serial Port',
                            style: DialogStyles.labelStyle,
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            value: _settings.gpsSerialPort,
                            decoration: _inputDecoration(),
                            items: const [
                              DropdownMenuItem(
                                value: 'None',
                                child: Text('None'),
                              ),
                            ],
                            onChanged: (value) {
                              setState(
                                () => _settings.gpsSerialPort = value ?? 'None',
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Baud Rate',
                            style: DialogStyles.labelStyle,
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<int>(
                            value: _settings.gpsBaudRate,
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
                  decoration: _inputDecoration(
                    hintText: 'http://localhost:8080/data/aircraft.json',
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _airplaneUrlController.text.isNotEmpty
                      ? () {}
                      : null,
                  child: const Text('Test Connection'),
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
