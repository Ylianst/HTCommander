/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dialog_utils.dart';
import '../services/data_broker_client.dart';
import '../radio/radio_models.dart';

/// Opens the channel editor for the given [channelId] on the connected radio
/// identified by [deviceId]. On OK the edited channel is pushed to the radio
/// through the DataBroker (`WriteChannel`).
Future<void> showRadioChannelDialog(
  BuildContext context, {
  required int deviceId,
  required int channelId,
  String? radioName,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => RadioChannelDialog(
      deviceId: deviceId,
      channelId: channelId,
      radioName: radioName,
    ),
  );
}

/// Channel editor dialog. Mirrors the C# `RadioChannelForm`: a simple "basic"
/// view (single frequency, mode, power) that automatically expands to an
/// "advanced" view exposing separate RX/TX frequencies, CTCSS/DCS tones,
/// bandwidth, scan, talk-around and de-emphasis when needed.
class RadioChannelDialog extends StatefulWidget {
  final int deviceId;
  final int channelId;
  final String? radioName;

  const RadioChannelDialog({
    super.key,
    required this.deviceId,
    required this.channelId,
    this.radioName,
  });

  @override
  State<RadioChannelDialog> createState() => _RadioChannelDialogState();
}

class _RadioChannelDialogState extends State<RadioChannelDialog> {
  final DataBrokerClient _broker = DataBrokerClient();

  // The channel as last read from the radio (used to preserve fields we do not
  // edit, like fixed-frequency flags).
  RadioChannelInfo? _original;

  late TextEditingController _nameController;
  late TextEditingController _rxFreqController;
  late TextEditingController _txFreqController;

  bool _advancedMode = false;

  // Editable state.
  int _powerIndex = 0; // 0=High, 1=Medium, 2=Low
  int _modeIndex = 0; // 0=FM, 1=AM
  int _bandwidthIndex = 0; // 0=Wide, 1=Narrow
  bool _txDisable = false;
  bool _mute = false;
  bool _scan = false;
  bool _talkAround = false;
  bool _deemphasis = false;
  int _rxToneValue = 0;
  int _txToneValue = 0;

  static const List<String> _powerOptions = ['High', 'Medium', 'Low'];
  static const List<String> _modeOptions = ['FM', 'AM'];
  static const List<String> _bandwidthOptions = [
    '25 KHz Wide',
    '12.5 KHz Narrow',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _rxFreqController = TextEditingController();
    _txFreqController = TextEditingController();
    _rxFreqController.addListener(_onFreqChanged);
    _txFreqController.addListener(_onFreqChanged);

    _loadChannel();

    // Refresh if the radio reports updated channels while the dialog is open.
    _broker.subscribe(
      deviceId: widget.deviceId,
      name: 'Channels',
      callback: _onChannelsChanged,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    _nameController.dispose();
    _rxFreqController.dispose();
    _txFreqController.dispose();
    super.dispose();
  }

  void _onChannelsChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    // Only populate from the broker until the channel is first loaded, so a
    // later channel refresh does not clobber the user's in-progress edits.
    if (_original == null) _loadChannel();
  }

  RadioChannelInfo? _readChannel() {
    final channels = _broker.getJsonListValue<RadioChannelInfo>(
      widget.deviceId,
      'Channels',
      (json) => RadioChannelInfo.fromJson(json),
    );
    if (channels == null) return null;
    for (final c in channels) {
      if (c.channelId == widget.channelId) return c;
    }
    return null;
  }

  void _loadChannel() {
    final c = _readChannel();
    if (c == null) return;

    int rxFreq = c.rxFreq;
    int txFreq = c.txFreq;
    if (txFreq == 0) txFreq = rxFreq;
    if (rxFreq == 0) rxFreq = txFreq;

    _original = c;

    // Switch to advanced automatically when the channel uses features the basic
    // view cannot represent. This must be decided BEFORE populating the
    // frequency fields: setting the controllers fires _onFreqChanged, which in
    // basic mode forces TX to track RX and would otherwise clobber a distinct
    // TX frequency during load.
    if (rxFreq != txFreq ||
        c.rxSubAudio != 0 ||
        c.txSubAudio != 0 ||
        c.talkAround ||
        c.scan ||
        c.bandwidth == RadioBandwidthType.narrow) {
      _advancedMode = true;
    }

    _nameController.text = c.name;
    _rxFreqController.text = _formatFreq(rxFreq);
    _txFreqController.text = _formatFreq(txFreq);

    _modeIndex =
        (c.txMod == RadioModulationType.am || c.rxMod == RadioModulationType.am)
        ? 1
        : 0;
    _bandwidthIndex = c.bandwidth == RadioBandwidthType.wide ? 0 : 1;
    _powerIndex = c.txAtMaxPower ? 0 : (c.txAtMedPower ? 1 : 2);
    _txDisable = c.txDisable;
    _mute = c.mute;
    _scan = c.scan;
    _talkAround = c.talkAround;
    _deemphasis = !c.preDeEmphBypass;
    _rxToneValue = c.rxSubAudio;
    _txToneValue = c.txSubAudio;

    if (mounted) setState(() {});
  }

  String _formatFreq(int hz) {
    if (hz == 0) return '';
    return (hz / 1000000).toString();
  }

  void _onFreqChanged() {
    if (!_advancedMode) {
      // In basic mode RX and TX track the single frequency field.
      if (_txFreqController.text != _rxFreqController.text) {
        _txFreqController.text = _rxFreqController.text;
      }
    }
    if (mounted) setState(() {});
  }

  // --- Frequency validation (mirrors C# CheckFreqRange) ---------------------

  bool _checkFreqRange(String text) {
    final freq = double.tryParse(text);
    if (freq == null) return false;
    if (_modeIndex == 0) {
      // FM: 136-174 MHz or 300-550 MHz
      if (freq < 136) return false;
      if (freq > 550) return false;
      if (freq > 174 && freq < 300) return false;
    } else {
      // AM: 108-136 MHz
      if (freq < 108) return false;
      if (freq > 136) return false;
    }
    return true;
  }

  String get _freqHelp => _modeIndex == 0
      ? '136 MHz - 174 MHz, 300 MHz - 550 MHz'
      : '108 MHz - 136 MHz';

  bool get _rxFreqValid => _checkFreqRange(_rxFreqController.text);
  bool get _txFreqValid => _checkFreqRange(_txFreqController.text);

  bool get _canSave {
    if (widget.deviceId <= 0) return false;
    if (_advancedMode) {
      return _rxFreqValid && _txFreqValid;
    }
    return _rxFreqValid;
  }

  // --- Save ------------------------------------------------------------------

  void _onSave() {
    final original = _original;
    if (original == null || widget.deviceId <= 0) return;

    final rxMHz = double.tryParse(_rxFreqController.text);
    if (rxMHz == null) return;
    final rxFreq = (rxMHz * 1000000).round();

    int txFreq;
    int rxSubAudio = 0;
    int txSubAudio = 0;
    bool scan = false;
    bool talkAround = false;
    bool deemphasis = original.preDeEmphBypass ? false : true;
    RadioBandwidthType bandwidth = RadioBandwidthType.wide;

    if (_advancedMode) {
      final txMHz = double.tryParse(_txFreqController.text);
      if (txMHz == null) return;
      txFreq = (txMHz * 1000000).round();
      rxSubAudio = _rxToneValue;
      txSubAudio = _txToneValue;
      scan = _scan;
      talkAround = _talkAround;
      deemphasis = _deemphasis;
      bandwidth = _bandwidthIndex == 0
          ? RadioBandwidthType.wide
          : RadioBandwidthType.narrow;
    } else {
      txFreq = rxFreq;
    }

    final mod = _modeIndex == 1
        ? RadioModulationType.am
        : RadioModulationType.fm;

    final updated = original.copyWith(
      name: _nameController.text,
      rxFreq: rxFreq,
      txFreq: txFreq,
      rxMod: mod,
      txMod: mod,
      rxSubAudio: rxSubAudio,
      txSubAudio: txSubAudio,
      scan: scan,
      talkAround: talkAround,
      bandwidth: bandwidth,
      preDeEmphBypass: !deemphasis,
      txDisable: _txDisable,
      mute: _mute,
      txAtMaxPower: _powerIndex == 0,
      txAtMedPower: _powerIndex == 1,
    );

    // Push the edited channel to the radio through the DataBroker.
    _broker.dispatch(
      deviceId: widget.deviceId,
      name: 'WriteChannel',
      data: updated,
      store: false,
    );

    Navigator.of(context).pop();
  }

  // --- UI --------------------------------------------------------------------

  String get _title {
    final base = 'Channel ${widget.channelId + 1}';
    final radio = widget.radioName;
    if (radio != null && radio.isNotEmpty) return '$radio $base';
    return base;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFF5F5F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text(_title, style: DialogStyles.titleStyle)),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: _advancedMode
                      ? _buildAdvancedContent()
                      : _buildBasicContent(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (!_advancedMode)
                    TextButton.icon(
                      onPressed: () => setState(() => _advancedMode = true),
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('More settings'),
                      style: DialogStyles.secondaryButtonStyle(context),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: DialogStyles.secondaryButtonStyle(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _canSave ? _onSave : null,
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

  Widget _buildBasicContent() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Name'),
          const SizedBox(height: 4),
          TextField(
            controller: _nameController,
            maxLength: 10,
            decoration: _inputDecoration(
              hintText: 'Channel name',
            ).copyWith(counterText: ''),
          ),
          const SizedBox(height: 16),
          _label('Frequency (MHz)'),
          const SizedBox(height: 4),
          _freqField(_rxFreqController, _rxFreqValid),
          const SizedBox(height: 4),
          Text(
            _freqHelp,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Mode'),
                    const SizedBox(height: 4),
                    _dropdown(
                      _modeOptions,
                      _modeIndex,
                      (v) => setState(() => _modeIndex = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Power'),
                    const SizedBox(height: 4),
                    _dropdown(
                      _powerOptions,
                      _powerIndex,
                      (v) => setState(() => _powerIndex = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _checkbox(
            'Disable transmit',
            _txDisable,
            (v) => setState(() => _txDisable = v),
          ),
          _checkbox('Mute', _mute, (v) => setState(() => _mute = v)),
        ],
      ),
    );
  }

  Widget _buildAdvancedContent() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _sectionDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Name'),
          const SizedBox(height: 4),
          TextField(
            controller: _nameController,
            maxLength: 10,
            decoration: _inputDecoration(
              hintText: 'Channel name',
            ).copyWith(counterText: ''),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Receive (MHz)'),
                    const SizedBox(height: 4),
                    _freqField(_rxFreqController, _rxFreqValid),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Transmit (MHz)'),
                    const SizedBox(height: 4),
                    _freqField(_txFreqController, _txFreqValid),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _freqHelp,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Mode'),
                    const SizedBox(height: 4),
                    _dropdown(
                      _modeOptions,
                      _modeIndex,
                      (v) => setState(() => _modeIndex = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Bandwidth'),
                    const SizedBox(height: 4),
                    _dropdown(
                      _bandwidthOptions,
                      _bandwidthIndex,
                      (v) => setState(() => _bandwidthIndex = v),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _label('Power'),
          const SizedBox(height: 4),
          _dropdown(
            _powerOptions,
            _powerIndex,
            (v) => setState(() => _powerIndex = v),
          ),
          const SizedBox(height: 16),
          _label('Receive tone (CTCSS / DCS)'),
          const SizedBox(height: 4),
          _toneDropdown(_rxToneValue, (v) => setState(() => _rxToneValue = v)),
          const SizedBox(height: 16),
          _label('Transmit tone (CTCSS / DCS)'),
          const SizedBox(height: 4),
          _toneDropdown(_txToneValue, (v) => setState(() => _txToneValue = v)),
          const SizedBox(height: 8),
          _checkbox(
            'Disable transmit',
            _txDisable,
            (v) => setState(() => _txDisable = v),
          ),
          _checkbox('Mute', _mute, (v) => setState(() => _mute = v)),
          _checkbox('Scan', _scan, (v) => setState(() => _scan = v)),
          _checkbox(
            'Talk around',
            _talkAround,
            (v) => setState(() => _talkAround = v),
          ),
          _checkbox(
            'De-emphasis',
            _deemphasis,
            (v) => setState(() => _deemphasis = v),
          ),
        ],
      ),
    );
  }

  // --- Reusable widgets ------------------------------------------------------

  Widget _label(String text) => Text(text, style: DialogStyles.labelStyle);

  Widget _freqField(TextEditingController controller, bool valid) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: _inputDecoration(hintText: 'e.g. 146.520').copyWith(
        fillColor: valid || controller.text.isEmpty
            ? Colors.grey.shade100
            : const Color(0xFFFFD0C0),
      ),
    );
  }

  Widget _dropdown(
    List<String> options,
    int value,
    ValueChanged<int> onChanged,
  ) {
    return DropdownButtonFormField<int>(
      initialValue: value.clamp(0, options.length - 1),
      isExpanded: true,
      decoration: _inputDecoration(),
      items: [
        for (int i = 0; i < options.length; i++)
          DropdownMenuItem(
            value: i,
            child: Text(options[i], overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => onChanged(v ?? 0),
    );
  }

  Widget _toneDropdown(int value, ValueChanged<int> onChanged) {
    return DropdownButtonFormField<int>(
      initialValue: _toneValues.contains(value) ? value : 0,
      isExpanded: true,
      decoration: _inputDecoration(),
      items: [
        for (int i = 0; i < _toneOptions.length; i++)
          DropdownMenuItem(value: _toneValues[i], child: Text(_toneOptions[i])),
      ],
      onChanged: (v) => onChanged(v ?? 0),
    );
  }

  Widget _checkbox(String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }

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

  InputDecoration _inputDecoration({String? hintText}) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.grey.shade100,
      hintText: hintText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
}

// --- CTCSS / DCS tone tables --------------------------------------------------
//
// Sub-audio values follow the radio encoding used in the C# RadioChannelForm:
//   0                -> None
//   CTCSS frequency  -> round(frequency_Hz * 100)  (e.g. 67.0 Hz -> 6700)
//   DCS code         -> the numeric "N" code        (e.g. DCS-023N -> 23)
// CTCSS values are always >= 1000, DCS codes are always < 1000, so the two
// ranges never collide.

const List<String> _ctcssHzLabels = [
  '67.0 Hz',
  '69.3 Hz',
  '71.9 Hz',
  '74.4 Hz',
  '77.0 Hz',
  '79.7 Hz',
  '82.5 Hz',
  '85.4 Hz',
  '88.5 Hz',
  '91.5 Hz',
  '94.8 Hz',
  '97.4 Hz',
  '100.0 Hz',
  '103.5 Hz',
  '107.2 Hz',
  '110.9 Hz',
  '114.8 Hz',
  '118.8 Hz',
  '123.0 Hz',
  '127.3 Hz',
  '131.8 Hz',
  '136.5 Hz',
  '141.3 Hz',
  '146.2 Hz',
  '151.4 Hz',
  '156.7 Hz',
  '159.8 Hz',
  '162.2 Hz',
  '165.5 Hz',
  '167.9 Hz',
  '173.8 Hz',
  '177.3 Hz',
  '179.9 Hz',
  '186.2 Hz',
  '189.9 Hz',
  '192.8 Hz',
  '196.6 Hz',
  '199.5 Hz',
  '203.5 Hz',
  '206.5 Hz',
  '210.7 Hz',
  '213.8 Hz',
  '218.1 Hz',
  '221.3 Hz',
  '225.7 Hz',
  '229.1 Hz',
  '233.6 Hz',
  '237.1 Hz',
  '241.8 Hz',
  '245.5 Hz',
  '250.3 Hz',
  '254.1 Hz',
];

const List<String> _dcsLabels = [
  'DCS-023N/047I',
  'DCS-025N/244I',
  'DCS-026N/464I',
  'DCS-031N/627I',
  'DCS-032N/051I',
  'DCS-036N/172I',
  'DCS-043N/445I',
  'DCS-047N/023I',
  'DCS-051N/032I',
  'DCS-053N/452I',
  'DCS-054N/413I',
  'DCS-065N/271I',
  'DCS-071N/306I',
  'DCS-072N/245I',
  'DCS-073N/506I',
  'DCS-074N/174I',
  'DCS-114N/712I',
  'DCS-115N/152I',
  'DCS-116N/754I',
  'DCS-122N/225I',
  'DCS-125N/365I',
  'DCS-131N/364I',
  'DCS-132N/546I',
  'DCS-134N/223I',
  'DCS-143N/412I',
  'DCS-145N/274I',
  'DCS-152N/115I',
  'DCS-155N/731I',
  'DCS-156N/265I',
  'DCS-162N/503I',
  'DCS-165N/251I',
  'DCS-172N/036I',
  'DCS-174N/074I',
  'DCS-205N/263I',
  'DCS-212N/356I',
  'DCS-223N/134I',
  'DCS-225N/122I',
  'DCS-226N/411I',
  'DCS-243N/351I',
  'DCS-244N/025I',
  'DCS-245N/072I',
  'DCS-246N/523I',
  'DCS-251N/165I',
  'DCS-252N/462I',
  'DCS-255N/446I',
  'DCS-261N/732I',
  'DCS-263N/205I',
  'DCS-265N/156I',
  'DCS-266N/454I',
  'DCS-271N/065I',
  'DCS-274N/145I',
  'DCS-306N/071I',
  'DCS-311N/664I',
  'DCS-315N/423I',
  'DCS-325N/526I',
  'DCS-331N/465I',
  'DCS-332N/455I',
  'DCS-343N/532I',
  'DCS-346N/612I',
  'DCS-351N/243I',
  'DCS-356N/212I',
  'DCS-364N/131I',
  'DCS-365N/125I',
  'DCS-371N/734I',
  'DCS-411N/226I',
  'DCS-412N/143I',
  'DCS-413N/054I',
  'DCS-423N/315I',
  'DCS-431N/723I',
  'DCS-432N/516I',
  'DCS-445N/043I',
  'DCS-446N/255I',
  'DCS-452N/053I',
  'DCS-454N/266I',
  'DCS-455N/332I',
  'DCS-462N/252I',
  'DCS-464N/026I',
  'DCS-465N/331I',
  'DCS-466N/662I',
  'DCS-503N/162I',
  'DCS-506N/073I',
  'DCS-516N/432I',
  'DCS-523N/246I',
  'DCS-526N/325I',
  'DCS-532N/343I',
  'DCS-546N/132I',
  'DCS-565N/703I',
  'DCS-606N/631I',
  'DCS-612N/346I',
  'DCS-624N/632I',
  'DCS-627N/031I',
  'DCS-631N/606I',
  'DCS-632N/624I',
  'DCS-654N/743I',
  'DCS-662N/466I',
  'DCS-664N/311I',
  'DCS-703N/565I',
  'DCS-712N/114I',
  'DCS-723N/431I',
  'DCS-731N/155I',
  'DCS-732N/261I',
  'DCS-734N/371I',
  'DCS-743N/654I',
  'DCS-754N/116I',
];

/// Display labels for the tone dropdown ("None" + CTCSS + DCS).
final List<String> _toneOptions = ['None', ..._ctcssHzLabels, ..._dcsLabels];

/// Sub-audio encoded values matching [_toneOptions] index for index.
final List<int> _toneValues = [
  0,
  for (final label in _ctcssHzLabels)
    (double.parse(label.split(' ').first) * 100).round(),
  for (final label in _dcsLabels) int.parse(label.substring(4, 7)),
];
