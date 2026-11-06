import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/radio_info_dialog.dart';
import 'package:htcommander/l10n/app_localizations.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

void main() {
  for (final hasRanges in [false, true]) {
    testWidgets('Copy All includes displayed frequency ranges=$hasRanges', (
      tester,
    ) async {
      final broker = DataBrokerClient();
      String? copiedText;
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        broker.dispose();
        DataBroker.clearDevice(1);
        DataBroker.clearDevice(9301);
      });
      broker.dispatch(
        deviceId: 1,
        name: 'ConnectedRadios',
        data: [
          {'DeviceId': 9301, 'FriendlyName': 'Test radio'},
        ],
      );
      if (hasRanges) {
        broker.dispatch(
          deviceId: 9301,
          name: 'FreqRanges',
          data: [
            {'lowHz': 108000000, 'highHz': 137000000, 'mod': 1},
            {'lowHz': 136000000, 'highHz': 174000000, 'mod': 2},
            {'lowHz': 300000000, 'highHz': 550000000, 'mod': 0},
          ],
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRadioInfoDialog(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy All'));
      await tester.pumpAndSettle();

      expect(copiedText, isNotNull);
      expect(copiedText, contains('Device Information'));
      if (hasRanges) {
        expect(
          copiedText,
          contains(
            'Frequency Ranges\n'
            '  Range 1: 108.000 - 137.000 MHz (AM RX)\n'
            '  Range 2: 136.000 - 174.000 MHz (FM RX/TX)\n'
            '  Range 3: 300.000 - 550.000 MHz (FM RX)',
          ),
        );
      } else {
        expect(copiedText, isNot(contains('Frequency Ranges')));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
