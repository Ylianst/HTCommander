import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/winlink/winlink_utils.dart';

void main() {
  test('WinlinkSecurity', () => expect(WinlinkSecurity.test(), isTrue));
  test('WinlinkCompression', () => expect(WinlinkCompression.test(), isTrue));
  test('WinLinkChecksum', () => expect(WinLinkChecksum.test(), isTrue));
  test('WinlinkCrc16', () => expect(WinlinkCrc16.test(), isTrue));
}
