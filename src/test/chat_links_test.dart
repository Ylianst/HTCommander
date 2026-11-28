import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/widgets/chat_widget.dart';

void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launchedUrls = <String>[];

  setUp(() {
    launchedUrls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'launch') {
            throw StateError('Unexpected URL launcher method: ${call.method}');
          }
          launchedUrls.add((call.arguments as Map)['url'] as String);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<List<TextSpan>> render(WidgetTester tester, String text) async {
    final message = ChatMessage(
      id: '1',
      route: 'APRS',
      senderCallsign: 'OTA',
      message: text,
      time: DateTime(2026),
      isSender: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatWidget(messages: [message])),
      ),
    );
    await tester.pumpAndSettle();
    return message.bodySpans!.whereType<TextSpan>().toList();
  }

  testWidgets('First PING address opens HTTPS without changing message text', (
    tester,
  ) async {
    const text = 'You earned First PING! aprsota.org/KK7VZT';
    final spans = await render(tester, text);
    expect(spans.map((span) => span.text).join(), text);
    final link = spans.singleWhere((span) => span.recognizer != null);
    expect(link.text, 'aprsota.org/KK7VZT');
    expect(link.style!.decoration, TextDecoration.underline);
    (link.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();
    expect(launchedUrls, ['https://aprsota.org/KK7VZT']);
  });

  testWidgets('chasing reply opens the complete operation path using HTTPS', (
    tester,
  ) async {
    const text = 'Now chasing VK2JKB-7 QF44oo. aprsota.org/VK2JKB/ops/51';
    final spans = await render(tester, text);
    expect(spans.map((span) => span.text).join(), text);
    final link = spans.singleWhere((span) => span.recognizer != null);
    expect(link.text, 'aprsota.org/VK2JKB/ops/51');
    (link.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();
    expect(launchedUrls, ['https://aprsota.org/VK2JKB/ops/51']);
  });

  testWidgets('OTA links trim punctuation and retain existing URL schemes', (
    tester,
  ) async {
    final spans = await render(
      tester,
      '(APRSOTA.ORG/KK7VZT). http://aprsota.org/KK7VZT '
      'https://example.com/path www.example.com',
    );
    final links = spans.where((span) => span.recognizer != null).toList();
    expect(links.map((span) => span.text), [
      'APRSOTA.ORG/KK7VZT',
      'http://aprsota.org/KK7VZT',
      'https://example.com/path',
      'www.example.com',
    ]);
    for (final link in links) {
      (link.recognizer! as TapGestureRecognizer).onTap!();
    }
    await tester.pumpAndSettle();
    expect(launchedUrls, [
      'https://aprsota.org/KK7VZT',
      'http://aprsota.org/KK7VZT',
      'https://example.com/path',
      'http://www.example.com',
    ]);
  });

  testWidgets('other bare domains and embedded OTA addresses stay plain', (
    tester,
  ) async {
    const text =
        'example.org/KK7VZT notaprsota.org/KK7VZT '
        'sub.aprsota.org/KK7VZT user@aprsota.org/KK7VZT '
        'aprsota.org.evil/KK7VZT';
    final spans = await render(tester, text);
    expect(spans.map((span) => span.text).join(), text);
    expect(spans.every((span) => span.recognizer == null), isTrue);
  });
}
