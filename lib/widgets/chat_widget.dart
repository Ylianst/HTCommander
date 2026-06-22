import 'dart:io';

import 'package:flutter/material.dart';

/// Authentication state for chat messages
enum ChatAuthState { unknown, none, success, failed }

/// Chat message data
class ChatMessage {
  final String id;
  final String route;
  final String senderCallsign;
  final String message;
  final DateTime time;
  final bool isSender; // true = sent (right), false = received (left)
  final ChatAuthState authState;
  final double? latitude;
  final double? longitude;
  final IconData? icon;
  final Object? tag;

  /// Filename of an associated media file (e.g. an audio recording), if any.
  final String? filename;

  /// Absolute path to an inline image to display in the bubble (e.g. a decoded
  /// SSTV picture), if any.
  final String? imagePath;

  const ChatMessage({
    required this.id,
    required this.route,
    required this.senderCallsign,
    required this.message,
    required this.time,
    required this.isSender,
    this.authState = ChatAuthState.unknown,
    this.latitude,
    this.longitude,
    this.icon,
    this.tag,
    this.filename,
    this.imagePath,
  });

  bool get hasLocation => latitude != null && longitude != null;
}

/// Reusable chat widget for displaying message conversations
/// Used by APRS and Voice tabs
class ChatWidget extends StatefulWidget {
  final List<ChatMessage> messages;
  final ValueChanged<ChatMessage>? onMessageTap;
  final ValueChanged<ChatMessage>? onMessageDoubleTap;
  final ValueChanged<ChatMessage>? onMessageLongPress;
  final Color bubbleColor;
  final Color bubbleAuthColor;
  final Color bubbleFailedColor;
  final Color senderBubbleColor;
  final Color routeTextColor;
  final Color timeTextColor;
  final double bubbleMaxWidthFactor;

  const ChatWidget({
    super.key,
    required this.messages,
    this.onMessageTap,
    this.onMessageDoubleTap,
    this.onMessageLongPress,
    this.bubbleColor = const Color(0xFFADD8E6), // LightBlue
    this.bubbleAuthColor = const Color(0xFF90EE90), // LightGreen
    this.bubbleFailedColor = const Color(0xFFFFB6C1), // LightPink
    this.senderBubbleColor = const Color(0xFFDCF8C6), // Light green for sent
    this.routeTextColor = Colors.grey,
    this.timeTextColor = Colors.grey,
    this.bubbleMaxWidthFactor = 0.75,
  });

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> {
  final ScrollController _scrollController = ScrollController();

  /// Number of messages seen at the last build. The messages list is mutated
  /// in place by the parent, so the widget's own list reference can't be
  /// compared frame-to-frame; this state value detects newly added bubbles.
  int _lastMessageCount = 0;

  /// How close (in pixels) to the bottom the view must be for newly added
  /// messages to trigger auto-scroll.
  static const double _autoScrollThreshold = 80.0;

  @override
  void initState() {
    super.initState();
    _lastMessageCount = widget.messages.length;
    // When the conversation is initially populated, jump to the bottom so the
    // latest messages are visible right away.
    _jumpToBottom();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Jumps to the bottom of the list, re-pinning across several frames. The
  /// ListView builds its items lazily, so its reported maxScrollExtent grows
  /// as off-screen bubbles lay out; a single jump would land short of the true
  /// bottom. Re-jumping until the extent stabilizes guarantees we end up fully
  /// scrolled down.
  void _jumpToBottom([int attemptsRemaining = 6]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      if (attemptsRemaining > 0) {
        _jumpToBottom(attemptsRemaining - 1);
      }
    });
  }

  @override
  void didUpdateWidget(ChatWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newCount = widget.messages.length;
    if (newCount <= _lastMessageCount) {
      // No new bubbles (cleared, replaced, or unchanged). Just track the count.
      _lastMessageCount = newCount;
      return;
    }

    final wasEmpty = _lastMessageCount == 0;
    // Capture whether the view was at the bottom BEFORE the new bubbles lay
    // out (the scroll position here still reflects the previous content).
    var atBottom = true;
    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      atBottom = pos.pixels >= pos.maxScrollExtent - _autoScrollThreshold;
    }
    _lastMessageCount = newCount;

    if (!wasEmpty && !atBottom) return;

    if (wasEmpty) {
      // Initial fill: pin to the bottom across frames as the lazy list lays out.
      _jumpToBottom();
      return;
    }

    // Auto-scroll to bottom when new messages are added.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  bool _shouldShowTimestamp(int index) {
    if (index == 0) return true;
    final current = widget.messages[index];
    final previous = widget.messages[index - 1];
    // Show timestamp if more than 30 minutes between messages
    return current.time.difference(previous.time).inMinutes > 30;
  }

  bool _shouldShowRoute(int index) {
    if (index == 0) return true;
    final current = widget.messages[index];
    final previous = widget.messages[index - 1];
    // Show route if different from previous message
    return current.route != previous.route;
  }

  String _formatTimestamp(DateTime time) {
    final now = DateTime.now();
    if (now.day == time.day &&
        now.month == time.month &&
        now.year == time.year) {
      // Same day - show time only
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      // Different day - show date and time
      return '${time.month}/${time.day}/${time.year} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  Color _getBubbleColor(ChatMessage message) {
    if (message.isSender) {
      return widget.senderBubbleColor;
    }
    switch (message.authState) {
      case ChatAuthState.success:
        return widget.bubbleAuthColor;
      case ChatAuthState.failed:
        return widget.bubbleFailedColor;
      default:
        return widget.bubbleColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: widget.messages.length,
        itemBuilder: (context, index) {
          final message = widget.messages[index];
          return _buildMessageItem(message, index);
        },
      ),
    );
  }

  Widget _buildMessageItem(ChatMessage message, int index) {
    final showTimestamp = _shouldShowTimestamp(index);
    final hasText = message.message.trim().isNotEmpty;
    // When there is no bubble (empty text), the header is the only content, so
    // always show it. A header with an icon (e.g. a recording) is tappable.
    // Show the icon in the header when the bubble has no text, or when the
    // bubble contains an inline image (e.g. an SSTV picture) so the icon sits
    // in the title instead of beside the large image bubble.
    final iconHeader =
        message.icon != null && (!hasText || message.imagePath != null);
    final showRoute = iconHeader
        ? true
        : (hasText ? _shouldShowRoute(index) : true);

    return Column(
      crossAxisAlignment: message.isSender
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        // Timestamp (centered)
        if (showTimestamp)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                _formatTimestamp(message.time),
                style: TextStyle(color: widget.timeTextColor, fontSize: 12),
              ),
            ),
          ),
        // Route/callsign header (above bubble, or standalone when no bubble)
        if (showRoute) _buildHeader(message, withIcon: iconHeader),
        // Message bubble (only when there is text to show)
        if (hasText) _buildBubble(message),
        const SizedBox(height: 4),
      ],
    );
  }

  /// Builds the route/callsign header. When [withIcon] is true the message's
  /// icon is shown next to the header and the whole header becomes tappable
  /// (used for recordings and other media that have no text bubble).
  Widget _buildHeader(ChatMessage message, {bool withIcon = false}) {
    Widget header = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (withIcon && message.icon != null) ...[
          Icon(message.icon, size: 16, color: Colors.grey),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            message.route,
            style: TextStyle(color: widget.routeTextColor, fontSize: 12),
          ),
        ),
      ],
    );

    if (withIcon &&
        (widget.onMessageTap != null || widget.onMessageDoubleTap != null)) {
      header = InkWell(
        onTap: widget.onMessageTap != null
            ? () => widget.onMessageTap!(message)
            : null,
        onDoubleTap: widget.onMessageDoubleTap != null
            ? () => widget.onMessageDoubleTap!(message)
            : null,
        child: header,
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: message.isSender ? 0 : 12,
        right: message.isSender ? 12 : 0,
        bottom: 2,
      ),
      child: header,
    );
  }

  Widget _buildBubble(ChatMessage message) {
    return GestureDetector(
      onTap: widget.onMessageTap != null
          ? () => widget.onMessageTap!(message)
          : null,
      onDoubleTap: widget.onMessageDoubleTap != null
          ? () => widget.onMessageDoubleTap!(message)
          : null,
      onLongPress: widget.onMessageLongPress != null
          ? () => widget.onMessageLongPress!(message)
          : null,
      child: Row(
        mainAxisAlignment: message.isSender
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          // Icon on left for received messages (image bubbles show the icon
          // in the header instead).
          if (!message.isSender &&
              message.icon != null &&
              message.imagePath == null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(message.icon, size: 16, color: Colors.grey),
            ),
          // Bubble
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth:
                    MediaQuery.of(context).size.width *
                    widget.bubbleMaxWidthFactor,
              ),
              decoration: BoxDecoration(
                color: _getBubbleColor(message),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: message.isSender
                      ? const Radius.circular(12)
                      : Radius.zero,
                  bottomRight: message.isSender
                      ? Radius.zero
                      : const Radius.circular(12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    offset: const Offset(1, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Inline image (e.g. a decoded SSTV picture).
                  if (message.imagePath != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(message.imagePath!),
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          message.message,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      // Authentication indicator (lock = verified, broken =
                      // failed). Surfaces AX25 auth state on the bubble itself,
                      // complementing the bubble color coding.
                      ..._buildAuthIcon(message),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Icon on right for sent messages (image bubbles show the icon in
          // the header instead).
          if (message.isSender &&
              message.icon != null &&
              message.imagePath == null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(message.icon, size: 16, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  /// Builds the inline authentication indicator shown inside the bubble.
  /// Returns a green closed lock for verified messages, a red broken lock for
  /// messages that failed verification, and nothing otherwise.
  List<Widget> _buildAuthIcon(ChatMessage message) {
    final IconData icon;
    final Color color;
    final String tooltip;
    switch (message.authState) {
      case ChatAuthState.success:
        icon = Icons.lock;
        color = Colors.green.shade700;
        tooltip = 'Authenticated';
        break;
      case ChatAuthState.failed:
        icon = Icons.lock_open;
        color = Colors.red.shade700;
        tooltip = 'Authentication failed';
        break;
      case ChatAuthState.none:
      case ChatAuthState.unknown:
        return const [];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Tooltip(
          message: tooltip,
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    ];
  }
}
