/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/data_broker.dart';
import '../services/data_broker_client.dart';
import '../services/microphone_capture.dart';
import '../services/system_audio.dart';
import 'spectrogram/spectrogram_view.dart';

/// Which audio source the spectrograph visualizes (or none to hide it).
enum SpectrogramSource { none, radio, microphone }

/// Audio tab - radio + application + computer audio controls.
///
/// This is the Flutter port of the C# RadioAudioForm. It exposes:
///   * Radio volume (0-15) and squelch (0-9) for the connected radio.
///   * The application's audio output volume (software gain on received radio
///     audio) and mute.
///   * The computer's master output volume and mute (macOS only).
///   * An optional spectrograph of either the received radio audio or the
///     microphone, selected from the tab's sub-menu. The selection persists
///     across app restarts (stored on DataBroker device 0).
///
/// Device selection (audio input/output endpoints) from the C# form is not
/// included in this version.
class AudioTab extends StatefulWidget {
  const AudioTab({super.key});

  @override
  State<AudioTab> createState() => _AudioTabState();
}

class _AudioTabState extends State<AudioTab>
    with AutomaticKeepAliveClientMixin {
  final DataBrokerClient _broker = DataBrokerClient();

  int _currentRadioDeviceId = -1;

  // Whether the radio's audio channel is enabled. Mirrors the Comms tab's
  // Enable/Disable button and the radio's 'AudioState' broker value.
  bool _audioEnabled = false;

  // Radio controls.
  int _radioVolume = 0; // 0-15
  int _squelchLevel = 0; // 0-9

  // Application audio output (software gain on received radio audio).
  double _appVolume = 1.0; // 0.0-1.0
  bool _appMuted = false;

  // Computer master output volume (macOS only).
  double _masterVolume = 0.0; // 0.0-1.0
  bool _masterMuted = false;
  bool _masterAvailable = false;
  bool _draggingMaster = false;
  Timer? _masterPollTimer;

  // Spectrograph. Persisted on DataBroker device 0 ('SpectrogramSource').
  SpectrogramSource _spectrogramSource = SpectrogramSource.none;
  SpectrogramController? _spectrogram;

  /// Whether the spectrograph is currently shown (any source other than none).
  bool get _showSpectrogram => _spectrogramSource != SpectrogramSource.none;

  // Live microphone capture (used by the microphone source).
  MicrophoneCapture? _micCapture;
  bool _micStarting = false;
  String? _micError;

  // Microphone transmit gain (linear multiplier, 1.0 = unchanged). Persisted
  // on DataBroker device 0 ('MicrophoneGain'). Shared with the Comms tab's
  // push-to-talk path so boosting here also boosts transmitted audio.
  double _micGain = 1.0;

  @override
  bool get wantKeepAlive => true;

  /// Whether the radio's audio channel is available on this platform. Web and
  /// iOS talk to the radio over the BLE control channel only (no audio
  /// channel), so the Audio tab shows only the Radio controls (Volume and
  /// Squelch) and hides the Enable button, the spectrograph sub-menu and the
  /// application/microphone/computer audio sections.
  bool get _audioChannelSupported => !kIsWeb && !Platform.isIOS;

  @override
  void initState() {
    super.initState();

    // Track which radio is shown / connected.
    _broker.subscribe(
      deviceId: 1,
      name: 'ConnectedRadios',
      callback: _onConnectedRadiosChanged,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'SelectedRadioDeviceId',
      callback: _onSelectedRadioChanged,
    );

    // Radio + application audio state (all devices, filtered to the current one).
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'State',
      callback: _onRadioStateChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Volume',
      callback: _onVolumeChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Settings',
      callback: _onSettingsChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'OutputVolume',
      callback: _onOutputVolumeChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'Mute',
      callback: _onMuteChanged,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'AudioDataAvailable',
      callback: _onAudioDataAvailable,
    );
    _broker.subscribe(
      deviceId: DataBroker.allDevices,
      name: 'AudioState',
      callback: _onAudioStateChanged,
    );
    _broker.subscribe(
      deviceId: 0,
      name: 'MicrophoneGain',
      callback: _onMicGainChanged,
    );

    _currentRadioDeviceId = _resolveCurrentRadioId();
    _audioEnabled = _readAudioState();
    _loadForCurrentRadio();
    _initMasterVolume();

    // Restore the persisted microphone gain (device 0 = global settings).
    _micGain = (_broker.getValue<double>(0, 'MicrophoneGain', 1.0) ?? 1.0)
        .clamp(1.0, 8.0);

    // Restore the persisted spectrograph source (device 0 = global settings).
    final savedSource =
        _broker.getValue<String>(0, 'SpectrogramSource', 'none') ?? 'none';
    _spectrogramSource = _sourceFromName(savedSource);
    if (_spectrogramSource != SpectrogramSource.none) {
      _spectrogram = SpectrogramController(
        sampleRate: 32000,
        fftSize: 512,
        // Only the bottom quarter of the band (0-4000 Hz of the 16 kHz
        // Nyquist) is displayed, so the generator computes only those bins.
        maxFrequency: 4000,
        intensity: 5,
        decibel: true,
      );
      _updateMicCapture();
    }
  }

  @override
  void dispose() {
    _masterPollTimer?.cancel();
    _micCapture?.dispose();
    _spectrogram?.dispose();
    _broker.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Current radio resolution
  // ---------------------------------------------------------------------------

  /// Resolve the device ID of the radio shown in the Radio Panel. Prefers the
  /// explicitly selected radio, falling back to the first connected one.
  int _resolveCurrentRadioId() {
    final connectedIds = _radioIds(
      DataBroker.getValueDynamic(1, 'ConnectedRadios'),
    );
    final selected =
        DataBroker.getValue<int>(1, 'SelectedRadioDeviceId', -1) ?? -1;
    if (selected > 0 && connectedIds.contains(selected)) return selected;
    return connectedIds.isNotEmpty ? connectedIds.first : -1;
  }

  /// Extract all connected radio device IDs from a ConnectedRadios list.
  List<int> _radioIds(Object? data) {
    final ids = <int>[];
    if (data is List) {
      for (final radio in data) {
        if (radio is Map && radio['DeviceId'] != null) {
          ids.add(radio['DeviceId'] as int);
        }
      }
    }
    return ids;
  }

  /// Whether the radio currently shown is connected.
  bool get _isConnected {
    if (_currentRadioDeviceId <= 0) return false;
    final connected = _radioIds(
      DataBroker.getValueDynamic(1, 'ConnectedRadios'),
    );
    return connected.contains(_currentRadioDeviceId);
  }

  /// Load the current radio's stored audio state into the UI.
  void _loadForCurrentRadio() {
    final id = _currentRadioDeviceId;
    if (id <= 0) return;

    _radioVolume = (_broker.getValue<int>(id, 'Volume', 0) ?? 0).clamp(0, 15);

    final settings = _broker.getValueDynamic(id, 'Settings');
    if (settings is Map && settings['squelchLevel'] is int) {
      _squelchLevel = (settings['squelchLevel'] as int).clamp(0, 9);
    }

    _appVolume = (_broker.getValue<double>(id, 'OutputVolume', 1.0) ?? 1.0)
        .clamp(0.0, 1.0);
    _appMuted = _broker.getValue<bool>(id, 'Mute', false) ?? false;

    // Ask the radio for its current volume level.
    if (_isConnected) {
      _broker.dispatch(
        deviceId: id,
        name: 'GetVolume',
        data: null,
        store: false,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Broker event handlers
  // ---------------------------------------------------------------------------

  void _onConnectedRadiosChanged(int deviceId, String name, Object? data) {
    if (!mounted) return;
    setState(() {
      _currentRadioDeviceId = _resolveCurrentRadioId();
      _audioEnabled = _readAudioState();
      _loadForCurrentRadio();
    });
  }

  void _onSelectedRadioChanged(int deviceId, String name, Object? data) {
    if (!mounted || data is! int) return;
    setState(() {
      _currentRadioDeviceId = data;
      _audioEnabled = _readAudioState();
      _loadForCurrentRadio();
    });
  }

  /// Reads the current AudioState of the radio shown in the Radio Panel.
  bool _readAudioState() {
    if (_currentRadioDeviceId <= 0) return false;
    return _broker.getValue<bool>(_currentRadioDeviceId, 'AudioState', false) ??
        false;
  }

  void _onAudioStateChanged(int deviceId, String name, Object? data) {
    if (!mounted || deviceId != _currentRadioDeviceId) return;
    if (data is bool) setState(() => _audioEnabled = data);
  }

  /// Toggles the audio channel of the radio shown in the Radio Panel. The UI
  /// updates when the 'AudioState' broker value changes in response.
  void _onEnable() {
    final deviceId = _currentRadioDeviceId;
    if (deviceId <= 0) return;
    final desired = !_audioEnabled;
    // Persist the user's audio-enabled preference (device 0) so the audio
    // channel is automatically enabled when a radio connects.
    _broker.dispatch(
      deviceId: 0,
      name: 'AudioEnabled',
      data: desired,
      store: true,
    );
    _broker.dispatch(
      deviceId: deviceId,
      name: 'SetAudio',
      data: desired,
      store: false,
    );
  }

  void _onRadioStateChanged(int deviceId, String name, Object? data) {
    if (!mounted || deviceId != _currentRadioDeviceId) return;
    setState(() {
      if (data == 'Connected') _loadForCurrentRadio();
    });
  }

  void _onVolumeChanged(int deviceId, String name, Object? data) {
    if (!mounted || deviceId != _currentRadioDeviceId) return;
    int? volume;
    if (data is int) {
      volume = data;
    } else if (data is num) {
      volume = data.toInt();
    }
    if (volume == null) return;
    setState(() => _radioVolume = volume!.clamp(0, 15));
  }

  void _onSettingsChanged(int deviceId, String name, Object? data) {
    if (!mounted || deviceId != _currentRadioDeviceId) return;
    if (data is Map && data['squelchLevel'] is int) {
      setState(() => _squelchLevel = (data['squelchLevel'] as int).clamp(0, 9));
    }
  }

  void _onOutputVolumeChanged(int deviceId, String name, Object? data) {
    if (!mounted || deviceId != _currentRadioDeviceId) return;
    double? vol;
    if (data is double) {
      vol = data;
    } else if (data is num) {
      vol = data.toDouble();
    }
    if (vol == null) return;
    setState(() => _appVolume = vol!.clamp(0.0, 1.0));
  }

  void _onMuteChanged(int deviceId, String name, Object? data) {
    if (!mounted || deviceId != _currentRadioDeviceId) return;
    if (data is bool) setState(() => _appMuted = data);
  }

  void _onMicGainChanged(int deviceId, String name, Object? data) {
    final double? gain = data is double
        ? data
        : (data is int ? data.toDouble() : null);
    if (gain == null) return;
    final clamped = gain.clamp(1.0, 8.0);
    _micCapture?.gain = clamped;
    if (!mounted) return;
    setState(() => _micGain = clamped);
  }

  void _onAudioDataAvailable(int deviceId, String name, Object? data) {
    final controller = _spectrogram;
    // Only the radio source consumes the received audio stream. The microphone
    // source is fed from live capture instead.
    if (controller == null || _spectrogramSource != SpectrogramSource.radio) {
      return;
    }
    if (deviceId != _currentRadioDeviceId) return;
    if (data is! Map) return;

    // Visualize the received (non-transmit) radio audio.
    final transmit = data['transmit'] as bool? ?? false;
    if (transmit) return;

    // Don't draw audio received on a muted channel.
    final muted = data['muted'] as bool? ?? false;
    if (muted) return;

    final pcm = data['data'];
    final offset = data['offset'] as int? ?? 0;
    final length = data['length'] as int?;
    if (pcm is Uint8List) {
      controller.feedPcm16(pcm, offset, length);
    } else if (pcm is List<int>) {
      controller.feedPcm16(Uint8List.fromList(pcm), offset, length);
    }
  }

  // ---------------------------------------------------------------------------
  // Master (computer) volume
  // ---------------------------------------------------------------------------

  Future<void> _initMasterVolume() async {
    if (!SystemAudio.isSupported) {
      if (mounted) setState(() => _masterAvailable = false);
      return;
    }
    await _refreshMasterVolume();
    // Poll periodically so external changes (e.g. media keys) are reflected.
    _masterPollTimer = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => _refreshMasterVolume(),
    );
  }

  Future<void> _refreshMasterVolume() async {
    if (_draggingMaster) return;
    final vol = await SystemAudio.getMasterVolume();
    final mute = await SystemAudio.getMute();
    if (!mounted) return;
    setState(() {
      _masterAvailable = vol != null;
      if (vol != null) _masterVolume = vol;
      if (mute != null) _masterMuted = mute;
    });
  }

  // ---------------------------------------------------------------------------
  // Control change handlers
  // ---------------------------------------------------------------------------

  void _onRadioVolumeChanged(double value) {
    setState(() => _radioVolume = value.round().clamp(0, 15));
  }

  void _onRadioVolumeCommitted(double value) {
    if (_currentRadioDeviceId <= 0) return;
    _broker.dispatch(
      deviceId: _currentRadioDeviceId,
      name: 'SetVolumeLevel',
      data: value.round().clamp(0, 15),
      store: false,
    );
  }

  void _onSquelchChanged(double value) {
    setState(() => _squelchLevel = value.round().clamp(0, 9));
  }

  void _onSquelchCommitted(double value) {
    if (_currentRadioDeviceId <= 0) return;
    _broker.dispatch(
      deviceId: _currentRadioDeviceId,
      name: 'SetSquelchLevel',
      data: value.round().clamp(0, 9),
      store: false,
    );
  }

  void _onAppVolumeChanged(double value) {
    setState(() => _appVolume = value.clamp(0.0, 1.0));
    if (_currentRadioDeviceId <= 0) return;
    // SetOutputVolume accepts a 0-100 integer (percent) like the C# form.
    _broker.dispatch(
      deviceId: _currentRadioDeviceId,
      name: 'SetOutputVolume',
      data: (value * 100).round().clamp(0, 100),
      store: false,
    );
  }

  void _onAppMuteToggled() {
    final newValue = !_appMuted;
    setState(() => _appMuted = newValue);
    if (_currentRadioDeviceId <= 0) return;
    _broker.dispatch(
      deviceId: _currentRadioDeviceId,
      name: 'SetMute',
      data: newValue,
      store: false,
    );
  }

  void _onMasterVolumeChanged(double value) {
    setState(() => _masterVolume = value.clamp(0.0, 1.0));
    SystemAudio.setMasterVolume(value);
  }

  void _onMasterMuteToggled() {
    final newValue = !_masterMuted;
    setState(() => _masterMuted = newValue);
    SystemAudio.setMute(newValue);
  }

  void _onMicGainSliderChanged(double value) {
    final clamped = value.clamp(1.0, 8.0);
    setState(() => _micGain = clamped);
    _micCapture?.gain = clamped;
    // Persist on device 0 so the Comms tab and the next launch pick it up.
    _broker.dispatch(
      deviceId: 0,
      name: 'MicrophoneGain',
      data: clamped,
      store: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Spectrograph
  // ---------------------------------------------------------------------------

  SpectrogramSource _sourceFromName(String name) {
    switch (name) {
      case 'radio':
        return SpectrogramSource.radio;
      case 'microphone':
        return SpectrogramSource.microphone;
      default:
        return SpectrogramSource.none;
    }
  }

  void _setSpectrogramSource(SpectrogramSource source) {
    setState(() {
      _spectrogramSource = source;
      if (source != SpectrogramSource.none) {
        _spectrogram ??= SpectrogramController(
          sampleRate: 32000,
          fftSize: 512,
          // Only the bottom quarter of the band (0-4000 Hz of the 16 kHz
          // Nyquist) is displayed, so the generator computes only those bins.
          maxFrequency: 4000,
          intensity: 5,
          decibel: true,
        );
        _spectrogram!.clear();
      }
    });

    // Persist the selection on device 0 so it is restored on the next launch.
    _broker.dispatch(
      deviceId: 0,
      name: 'SpectrogramSource',
      data: source.name,
      store: true,
    );

    _updateMicCapture();
  }

  // ---------------------------------------------------------------------------
  // Live microphone capture
  // ---------------------------------------------------------------------------

  /// Whether the current spectrograph configuration needs the live microphone.
  bool get _micNeeded => _spectrogramSource == SpectrogramSource.microphone;

  /// Starts or stops microphone capture to match the current spectrogram state.
  Future<void> _updateMicCapture() async {
    if (_micNeeded) {
      await _startMic();
    } else {
      await _stopMic();
    }
  }

  Future<void> _startMic() async {
    if (!MicrophoneCapture.isSupported) {
      if (mounted) {
        setState(() => _micError = 'Microphone capture is not supported here.');
      }
      return;
    }
    final capture = _micCapture ??= MicrophoneCapture(sampleRate: 32000);
    capture.gain = _micGain;
    if (capture.isCapturing || _micStarting) return;
    _micStarting = true;
    final ok = await capture.start(_onMicPcm);
    _micStarting = false;
    if (!mounted) return;
    setState(() {
      _micError = ok
          ? null
          : 'Microphone unavailable. Grant access in System Settings > '
                'Privacy & Security > Microphone.';
    });
  }

  Future<void> _stopMic() async {
    await _micCapture?.stop();
    if (mounted && _micError != null) setState(() => _micError = null);
  }

  void _onMicPcm(Uint8List pcm16) {
    final controller = _spectrogram;
    if (controller == null ||
        _spectrogramSource != SpectrogramSource.microphone) {
      return;
    }
    controller.feedPcm16(pcm16);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionTitle('Radio'),
                _buildSliderRow(
                  label: 'Volume',
                  value: _radioVolume.toDouble(),
                  min: 0,
                  max: 15,
                  divisions: 15,
                  valueLabel: '$_radioVolume',
                  enabled: _isConnected,
                  onChanged: _onRadioVolumeChanged,
                  onChangeEnd: _onRadioVolumeCommitted,
                ),
                _buildSliderRow(
                  label: 'Squelch',
                  value: _squelchLevel.toDouble(),
                  min: 0,
                  max: 9,
                  divisions: 9,
                  valueLabel: '$_squelchLevel',
                  enabled: _isConnected,
                  onChanged: _onSquelchChanged,
                  onChangeEnd: _onSquelchCommitted,
                ),
                // Web and iOS expose only the Radio controls above: there is no
                // audio channel for application/microphone/computer audio or
                // the spectrograph, so those sections are hidden there.
                if (_audioChannelSupported) ...[
                  const SizedBox(height: 16),
                  _buildSectionTitle('Computer'),
                  _buildSliderRow(
                    label: 'Application',
                    value: _appVolume,
                    min: 0,
                    max: 1,
                    valueLabel: '${(_appVolume * 100).round()}%',
                    enabled: _currentRadioDeviceId > 0,
                    muted: _appMuted,
                    onMuteToggled: _currentRadioDeviceId > 0
                        ? _onAppMuteToggled
                        : null,
                    onChanged: _onAppVolumeChanged,
                  ),
                  if (SystemAudio.isSupported)
                    _buildSliderRow(
                      label: 'Master',
                      value: _masterVolume,
                      min: 0,
                      max: 1,
                      valueLabel: _masterAvailable
                          ? '${(_masterVolume * 100).round()}%'
                          : 'N/A',
                      enabled: _masterAvailable,
                      muted: _masterMuted,
                      onMuteToggled: _masterAvailable
                          ? _onMasterMuteToggled
                          : null,
                      onChangeStart: (_) => _draggingMaster = true,
                      onChanged: _onMasterVolumeChanged,
                      onChangeEnd: (_) => _draggingMaster = false,
                    ),
                  _buildSliderRow(
                    label: 'Mic Gain',
                    value: _micGain,
                    min: 1,
                    max: 8,
                    valueLabel: '${(_micGain * 100).round()}%',
                    enabled: MicrophoneCapture.isSupported,
                    onChanged: _onMicGainSliderChanged,
                  ),
                  if (!MicrophoneCapture.isSupported)
                    const Padding(
                      padding: EdgeInsets.only(left: 4, top: 2),
                      child: Text(
                        'Microphone capture is not available on this platform.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  if (_showSpectrogram) ...[
                    const SizedBox(height: 16),
                    _buildSectionTitle(_spectrogramTitle()),
                    ClipRect(
                      child: SizedBox(
                        height: 200,
                        child: _spectrogram == null
                            ? const ColoredBox(color: Colors.black)
                            : SpectrogramView(controller: _spectrogram!),
                      ),
                    ),
                    if (_micNeeded && _micError != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, top: 4),
                        child: Text(
                          _micError!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _spectrogramTitle() {
    switch (_spectrogramSource) {
      case SpectrogramSource.radio:
        return 'Radio Spectrograph';
      case SpectrogramSource.microphone:
        return 'Microphone Spectrograph';
      case SpectrogramSource.none:
        return 'Spectrograph';
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required String valueLabel,
    required bool enabled,
    bool? muted,
    VoidCallback? onMuteToggled,
    ValueChanged<double>? onChangeStart,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: enabled ? null : Colors.grey,
              ),
            ),
          ),
          if (onMuteToggled != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: (muted ?? false) ? 'Unmute' : 'Mute',
              icon: Icon(
                (muted ?? false) ? Icons.volume_off : Icons.volume_up,
                size: 18,
                color: enabled ? null : Colors.grey,
              ),
              onPressed: enabled ? onMuteToggled : null,
            ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChangeStart: enabled ? onChangeStart : null,
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              valueLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: enabled ? null : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(color: Color(0xFFC0C0C0)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      clipBehavior: Clip.hardEdge,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showButton = constraints.maxWidth > 180;
          return Row(
            children: [
              const Text(
                'Audio',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              if (showButton && _audioChannelSupported)
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: (_audioEnabled || _isConnected)
                        ? _onEnable
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      textStyle: const TextStyle(fontSize: 12),
                      backgroundColor: _audioEnabled
                          ? Colors.red.shade100
                          : null,
                    ),
                    child: Text(_audioEnabled ? 'Disable' : 'Enable'),
                  ),
                ),
              if (showButton && _audioChannelSupported)
                const SizedBox(width: 8),
              // The only sub-menu items are spectrograph sources, which are not
              // supported on web/iOS, so the menu button is hidden there.
              if (_audioChannelSupported)
                Builder(
                  builder: (context) => InkWell(
                    onTap: () => _showMenu(context),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.asset(
                        'assets/images/MenuIcon.png',
                        width: 24,
                        height: 24,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.menu, size: 24);
                        },
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final Offset offset = button.localToGlobal(Offset.zero);

    const menuItemPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    const menuItemHeight = 32.0;

    Widget checkRow(String text, bool checked) => Row(
      children: [
        SizedBox(
          width: 20,
          child: checked
              ? const Text('✓', style: TextStyle(fontSize: 14))
              : null,
        ),
        Text(text),
      ],
    );

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + button.size.height,
        offset.dx + button.size.width,
        offset.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'sourceNone',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: checkRow(
            'No Spectrograph',
            _spectrogramSource == SpectrogramSource.none,
          ),
        ),
        PopupMenuItem<String>(
          value: 'sourceRadio',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: checkRow(
            'Radio Spectrograph',
            _spectrogramSource == SpectrogramSource.radio,
          ),
        ),
        PopupMenuItem<String>(
          value: 'sourceMicrophone',
          height: menuItemHeight,
          padding: menuItemPadding,
          child: checkRow(
            'Microphone Spectrograph',
            _spectrogramSource == SpectrogramSource.microphone,
          ),
        ),
      ],
    ).then((value) {
      if (!mounted || value == null) return;
      switch (value) {
        case 'sourceNone':
          _setSpectrogramSource(SpectrogramSource.none);
          break;
        case 'sourceRadio':
          _setSpectrogramSource(SpectrogramSource.radio);
          break;
        case 'sourceMicrophone':
          _setSpectrogramSource(SpectrogramSource.microphone);
          break;
      }
    });
  }
}
