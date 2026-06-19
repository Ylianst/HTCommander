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
  });

  bool get hasLocation => latitude != null && longitude != null;
}

/// Reusable chat widget for displaying message conversations
/// Used by APRS and Voice tabs
class ChatWidget extends StatefulWidget {
  final List<ChatMessage> messages;
  final ValueChanged<ChatMessage>? onMessageTap;
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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChatWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to bottom when new messages are added
    if (widget.messages.length > oldWidget.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
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
    final showRoute = _shouldShowRoute(index);

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
        // Route/callsign (above bubble)
        if (showRoute)
          Padding(
            padding: EdgeInsets.only(
              left: message.isSender ? 0 : 12,
              right: message.isSender ? 12 : 0,
              bottom: 2,
            ),
            child: Text(
              message.route,
              style: TextStyle(color: widget.routeTextColor, fontSize: 12),
            ),
          ),
        // Message bubble
        _buildBubble(message),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildBubble(ChatMessage message) {
    return GestureDetector(
      onTap: widget.onMessageTap != null
          ? () => widget.onMessageTap!(message)
          : null,
      onLongPress: widget.onMessageLongPress != null
          ? () => widget.onMessageLongPress!(message)
          : null,
      child: Row(
        mainAxisAlignment: message.isSender
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          // Icon on left for received messages
          if (!message.isSender && message.icon != null)
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      message.message,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  // Location indicator
                  if (message.hasLocation)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Icon on right for sent messages
          if (message.isSender && message.icon != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(message.icon, size: 16, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}
