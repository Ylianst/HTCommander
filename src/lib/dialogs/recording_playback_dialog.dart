import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Playback dialog for an audio recording, ported from the C#
/// `RecordingPlaybackForm`. Shows a play/pause button, a draggable position
/// bar (seek), and the current/total time of the clip.
class RecordingPlaybackDialog extends StatefulWidget {
  /// Full path to the audio file to play.
  final String filePath;

  /// When true, playback starts automatically once the file is loaded.
  final bool autoPlay;

  const RecordingPlaybackDialog({
    super.key,
    required this.filePath,
    this.autoPlay = false,
  });

  @override
  State<RecordingPlaybackDialog> createState() =>
      _RecordingPlaybackDialogState();
}

class _RecordingPlaybackDialogState extends State<RecordingPlaybackDialog> {
  final AudioPlayer _player = AudioPlayer();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _loadFailed = false;

  /// Position (in milliseconds) while the user is dragging the seek bar; null
  /// when not dragging.
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _player.setReleaseMode(ReleaseMode.stop);
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted && _dragValue == null) setState(() => _position = p);
    });
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = _duration;
        });
      }
    });
    _loadSource();
  }

  Future<void> _loadSource() async {
    try {
      if (!await File(widget.filePath).exists()) {
        if (mounted) setState(() => _loadFailed = true);
        return;
      }
      await _player.setSource(DeviceFileSource(widget.filePath));
      // Duration is delivered via the onDurationChanged listener set up in
      // initState. Avoid a manual getDuration() here: on the audioplayers
      // Darwin backend, calling it right after setSource races with the
      // native "prepared" completion and triggers duplicate platform-channel
      // responses ("Message responses can be sent only once").
      if (widget.autoPlay && mounted) {
        await _player.resume();
      }
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_loadFailed) return;
    if (_isPlaying) {
      await _player.pause();
    } else {
      // Restart from the beginning if playback finished.
      if (_duration > Duration.zero && _position >= _duration) {
        await _player.seek(Duration.zero);
        if (mounted) setState(() => _position = Duration.zero);
      }
      await _player.resume();
    }
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours >= 1 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fileName = widget.filePath.split(Platform.pathSeparator).last;
    final maxMs = _duration.inMilliseconds.toDouble();
    final currentMs = (_dragValue ?? _position.inMilliseconds.toDouble()).clamp(
      0.0,
      maxMs <= 0 ? 0.0 : maxMs,
    );
    final displayPosition = _dragValue != null
        ? Duration(milliseconds: _dragValue!.round())
        : _position;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.audiotrack, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loadFailed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l10n.rpbFailedToLoad,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            Row(
              children: [
                IconButton(
                  iconSize: 40,
                  onPressed: _loadFailed ? null : _togglePlay,
                  icon: Icon(
                    _isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                  ),
                  color: Theme.of(context).colorScheme.primary,
                ),
                Expanded(
                  child: Slider(
                    value: currentMs,
                    min: 0,
                    max: maxMs <= 0 ? 1 : maxMs,
                    onChanged: (maxMs <= 0 || _loadFailed)
                        ? null
                        : (v) => setState(() => _dragValue = v),
                    onChangeEnd: (maxMs <= 0 || _loadFailed)
                        ? null
                        : (v) async {
                            await _player.seek(
                              Duration(milliseconds: v.round()),
                            );
                            if (mounted) {
                              setState(() {
                                _position = Duration(milliseconds: v.round());
                                _dragValue = null;
                              });
                            }
                          },
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(displayPosition),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonClose),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
