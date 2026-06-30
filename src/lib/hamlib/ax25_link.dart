// Ax25Link.dart, AX.25 Data Link State Machine
//
// Ported from Ax25Link.cs (HamLib).

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

// Limits and defaults for parameters
class Ax25LinkConstants {
  Ax25LinkConstants._();

  // Max bytes in Information part of frame
  static const int ax25N1PaclenMin = 1;
  static const int ax25N1PaclenDefault = 256; // some v2.0 implementations have 128
  static const int ax25N1PaclenMax = 2048; // AX25_MAX_INFO_LEN

  // Number of times to retry before giving up
  static const int ax25N2RetryMin = 1;
  static const int ax25N2RetryDefault = 10;
  static const int ax25N2RetryMax = 15;

  // Number of seconds to wait before retrying
  static const int ax25T1vFrackMin = 1;
  static const int ax25T1vFrackDefault = 3; // KPC-3+ has 4, TM-D710A has 3
  static const int ax25T1vFrackMax = 15;

  // Window size - number of I frames to send before waiting for ack
  static const int ax25KMaxframeBasicMin = 1;
  static const int ax25KMaxframeBasicDefault = 4;
  static const int ax25KMaxframeBasicMax = 7;

  static const int ax25KMaxframeExtendedMin = 1;
  static const int ax25KMaxframeExtendedDefault = 32;
  static const int ax25KMaxframeExtendedMax = 63; // In theory 127 but restricted

  static const double t3Default = 300.0; // 5 minutes of inactivity
  static const int generousK = 63; // For SREJ window calculations

  static const int magic1 = 0x11592201;
  static const int magic2 = 0x02221201;
  static const int magic3 = 0x03331301;
  static const int rcMagic = 0x08291951;
}

// Data link state machine states
enum DlsmState {
  disconnected, // 0
  awaitingConnection, // 1
  awaitingRelease, // 2
  connected, // 3
  timerRecovery, // 4
  awaitingV22Connection, // 5
}

// SREJ enable options
enum SrejEnable {
  none(0),
  single(1),
  multi(2),
  notSpecified(99);

  final int value;
  const SrejEnable(this.value);
}

// MDL (Management Data Link) state
enum MdlState {
  ready, // 0
  negotiating, // 1
}

// Connected data block for transmit/receive queues
class CData {
  int pid;
  late Uint8List data;
  late int len;
  late int size; // Allocated size
  CData? next;

  CData(this.pid, Uint8List? data, int len) {
    if (data != null && len > 0) {
      this.data = Uint8List(len);
      this.data.setRange(0, math.min(len, data.length), data);
      this.len = len;
      size = len;
    } else {
      this.data = Uint8List(0);
      this.len = 0;
      size = 0;
    }
  }

  CData.fromString(this.pid, String? str, int len) {
    if (str != null && str.isNotEmpty) {
      data = ascii.encode(str);
      this.len = math.min(len, data.length);
      size = data.length;
    } else {
      data = Uint8List(0);
      this.len = 0;
      size = 0;
    }
  }
}

// Registered callsign for incoming connections
class RegCallsign {
  String? callsign;
  int chan = 0;
  int client = 0;
  RegCallsign? next;
  int magic = Ax25LinkConstants.rcMagic;
}

// AX.25 Data Link State Machine
class Ax25Dlsm {
  int magic1 = Ax25LinkConstants.magic1;
  Ax25Dlsm? next;

  int streamId = 0;
  int chan = 0;
  int client = 0;

  List<String?> addrs = List<String?>.filled(10, null);
  int numAddr = 0;

  static const int ownCall = 0; // AX25_SOURCE
  static const int peerCall = 1; // AX25_DESTINATION

  double startTime = 0.0;
  DlsmState state = DlsmState.disconnected;

  int modulo = 0;
  SrejEnable srejEnable = SrejEnable.none;

  int n1Paclen = 0;
  int n2Retry = 0;
  int kMaxframe = 0;

  int rc = 0;
  int vs = 0;
  int va = 0;
  int vr = 0;

  bool layerThreeInitiated = false;

  // Exception conditions
  bool peerReceiverBusy = false;
  bool rejectException = false;
  bool ownReceiverBusy = false;
  bool acknowledgePending = false;

  // Timing
  double srt = 0.0;
  double t1v = 0.0;

  bool radioChannelBusy = false;

  // Timer T1
  double t1Exp = 0.0;
  double t1PausedAt = 0.0;
  double t1RemainingWhenLastStopped = -999.0;
  bool t1HadExpired = false;

  // Timer T3
  double t3Exp = 0.0;

  // Statistics
  List<int> countRecvFrameType = List<int>.filled(20, 0);
  int peakRcValue = 0;

  // Transmit/Receive queues
  CData? iFrameQueue;
  List<CData?> txdataByNs = List<CData?>.filled(128, null);
  int magic3 = Ax25LinkConstants.magic3;
  List<CData?> rxdataByNs = List<CData?>.filled(128, null);
  int magic2 = Ax25LinkConstants.magic2;

  // MDL state machine for XID exchange
  MdlState mdlState = MdlState.ready;
  int mdlRc = 0;
  double tm201Exp = 0.0;
  double tm201PausedAt = 0.0;

  // Segment reassembler
  CData? raBuff;
  int raFollowing = 0;
}

// Placeholder for misc config
class MiscConfig {
  double frack = 3.0;
  int paclen = 256;
  int maxframeBasic = 4;
  int maxframeExtended = 32;
  int retry = 10;
  int maxv22 = 3;
  List<String> v20Addrs = <String>[];
  int get v20Count => v20Addrs.length;
  List<String> noxidAddrs = <String>[];
  int get noxidCount => noxidAddrs.length;
}

// Main Ax25Link class
class Ax25Link {
  Ax25Link._();

  static Ax25Dlsm? _listHead;
  static RegCallsign? _regCallsignList;
  static int _nextStreamId = 0;

  // Debug switches
  static bool _sDebugProtocolErrors = false;
  static bool _sDebugClientApp = false;
  static bool _sDebugRadio = false;
  static bool _sDebugVariables = false;
  static bool _sDebugRetry = false;
  static bool _sDebugTimers = false;
  static bool _sDebugLinkHandle = false;
  static bool _sDebugStats = false;
  static bool _sDebugMisc = false;

  // Configuration
  static late MiscConfig _gMiscConfigP;

  // DCD and PTT status per channel
  static final List<bool> _dcdStatus = List<bool>.filled(16, false);
  static final List<bool> _pttStatus = List<bool>.filled(16, false);

  // Initialize the ax25_link module
  static void ax25LinkInit(MiscConfig pconfig, int debug) {
    _gMiscConfigP = pconfig;

    if (debug >= 1) {
      _sDebugProtocolErrors = true;
      _sDebugClientApp = true;
      _sDebugRadio = true;
      _sDebugVariables = true;
      _sDebugRetry = true;
      _sDebugLinkHandle = true;
      _sDebugStats = true;
      _sDebugMisc = true;
      _sDebugTimers = true;
    }
  }

  // ============================================================================
  // HELPER FUNCTIONS
  // ============================================================================

  // Modulo arithmetic helper
  static int _ax25Modulo(int n, int m, String file, String func, int line) {
    if (m != 8 && m != 128) {
      print('INTERNAL ERROR: $n modulo $m, $file, $func, $line');
      m = 8;
    }
    // Use masking so negative numbers are handled properly
    return n & (m - 1);
  }

  // Case-insensitive ordinal string comparison
  static bool _eqIgnoreCase(String? a, String? b) =>
      (a ?? '').toLowerCase() == (b ?? '').toLowerCase();

  // Test whether we can send more frames (within window size)
  static bool _withinWindowSize(Ax25Dlsm s) {
    return s.vs !=
        _ax25Modulo(
            s.va + s.kMaxframe, s.modulo, 'Ax25Link', 'withinWindowSize', 0);
  }

  // Get current time in seconds (floating point)
  static double _getTime() {
    return DateTime.now().millisecondsSinceEpoch / 1000.0;
  }

  // Set variables with debug output
  static void _setVs(Ax25Dlsm s, int n) {
    s.vs = n;
    if (_sDebugVariables) {
      print('V(S) = ${s.vs}');
    }
    assert(s.vs >= 0 && s.vs < s.modulo);
  }

  static void _setVa(Ax25Dlsm s, int n) {
    s.va = n;
    if (_sDebugVariables) {
      print('V(A) = ${s.va}');
    }
    assert(s.va >= 0 && s.va < s.modulo);

    // Clear out acknowledged frames
    int x = _ax25Modulo(n - 1, s.modulo, 'Ax25Link', 'setVa', 0);
    while (s.txdataByNs[x] != null) {
      s.txdataByNs[x] = null;
      x = _ax25Modulo(x - 1, s.modulo, 'Ax25Link', 'setVa', 0);
    }
  }

  static void _setVr(Ax25Dlsm s, int n) {
    s.vr = n;
    if (_sDebugVariables) {
      print('V(R) = ${s.vr}');
    }
    assert(s.vr >= 0 && s.vr < s.modulo);
  }

  static void _setRc(Ax25Dlsm s, int n) {
    s.rc = n;
    if (_sDebugVariables) {
      print('rc = ${s.rc}, state = ${s.state}');
    }
  }

  // Enter new state
  static void _enterNewState(
      Ax25Dlsm s, DlsmState newState, String fromFunc, int fromLine) {
    if (_sDebugVariables) {
      print(
          '\n>>> NEW STATE = $newState, previously ${s.state}, called from $fromFunc $fromLine <<<\n');
    }

    assert(newState.index >= 0 && newState.index <= 5);

    // Handle connected indicator
    if ((newState == DlsmState.connected ||
            newState == DlsmState.timerRecovery) &&
        (s.state != DlsmState.connected &&
            s.state != DlsmState.timerRecovery)) {
      // Turn on connected indicator
    } else if ((newState != DlsmState.connected &&
            newState != DlsmState.timerRecovery) &&
        (s.state == DlsmState.connected ||
            s.state == DlsmState.timerRecovery)) {
      // Turn off connected indicator
    }

    s.state = newState;
  }

  // Initialize T1V and SRT
  static void _initT1vSrt(Ax25Dlsm s) {
    s.t1v = _gMiscConfigP.frack * (2 * (s.numAddr - 2) + 1);
    s.srt = s.t1v / 2.0;
  }

  // ============================================================================
  // TIMER FUNCTIONS
  // ============================================================================

  // Start T1 timer
  static void _startT1(Ax25Dlsm s, String fromFunc, int fromLine) {
    double now = _getTime();

    if (_sDebugTimers) {
      print(
          'Start T1 for t1v = ${s.t1v.toStringAsFixed(3)} sec, rc = ${s.rc}, [now=${(now - s.startTime).toStringAsFixed(3)}] from $fromFunc $fromLine');
    }

    s.t1Exp = now + s.t1v;
    if (s.radioChannelBusy) {
      s.t1PausedAt = now;
    } else {
      s.t1PausedAt = 0;
    }
    s.t1HadExpired = false;
  }

  // Stop T1 timer
  static void _stopT1(Ax25Dlsm s, String fromFunc, int fromLine) {
    double now = _getTime();

    _resumeT1(s, fromFunc, fromLine); // Adjust expire time if paused

    if (s.t1Exp == 0.0) {
      // Was already stopped
    } else {
      s.t1RemainingWhenLastStopped = s.t1Exp - now;
      if (s.t1RemainingWhenLastStopped < 0) s.t1RemainingWhenLastStopped = 0;
    }

    if (_sDebugTimers) {
      if (s.t1Exp == 0.0) {
        print(
            'Stop T1. Wasn\'t running, [now=${(now - s.startTime).toStringAsFixed(3)}] from $fromFunc $fromLine');
      } else {
        print(
            'Stop T1, ${s.t1RemainingWhenLastStopped.toStringAsFixed(3)} remaining, [now=${(now - s.startTime).toStringAsFixed(3)}] from $fromFunc $fromLine');
      }
    }

    s.t1Exp = 0.0;
    s.t1HadExpired = false;
  }

  // Check if T1 is running
  static bool _isT1Running(Ax25Dlsm s, String fromFunc, int fromLine) {
    bool result = s.t1Exp != 0.0;

    if (_sDebugTimers) {
      print('is_t1_running? returns $result');
    }

    return result;
  }

  // Pause T1 timer
  static void _pauseT1(Ax25Dlsm s, String fromFunc, int fromLine) {
    if (s.t1Exp == 0.0) {
      // Stopped so nothing to do
    } else if (s.t1PausedAt == 0.0) {
      // Running and not paused
      double now = _getTime();
      s.t1PausedAt = now;

      if (_sDebugTimers) {
        print(
            'Paused T1 with ${(s.t1Exp - now).toStringAsFixed(3)} still remaining, [now=${(now - s.startTime).toStringAsFixed(3)}] from $fromFunc $fromLine');
      }
    } else {
      if (_sDebugTimers) {
        print('T1 error: Didn\'t expect pause when already paused.');
      }
    }
  }

  // Resume T1 timer
  static void _resumeT1(Ax25Dlsm s, String fromFunc, int fromLine) {
    if (s.t1Exp == 0.0) {
      // Stopped so nothing to do
    } else if (s.t1PausedAt == 0.0) {
      // Running but not paused
    } else {
      double now = _getTime();
      double pausedForSec = now - s.t1PausedAt;

      s.t1Exp += pausedForSec;
      s.t1PausedAt = 0.0;

      if (_sDebugTimers) {
        print(
            'Resumed T1 after pausing for ${pausedForSec.toStringAsFixed(3)} sec, ${(s.t1Exp - now).toStringAsFixed(3)} still remaining, [now=${(now - s.startTime).toStringAsFixed(3)}]');
      }
    }
  }

  // Start T3 timer
  static void _startT3(Ax25Dlsm s, String fromFunc, int fromLine) {
    double now = _getTime();

    if (_sDebugTimers) {
      print(
          'Start T3 for ${Ax25LinkConstants.t3Default.toStringAsFixed(3)} sec, [now=${(now - s.startTime).toStringAsFixed(3)}] from $fromFunc $fromLine');
    }

    s.t3Exp = now + Ax25LinkConstants.t3Default;
  }

  // Stop T3 timer
  static void _stopT3(Ax25Dlsm s, String fromFunc, int fromLine) {
    if (_sDebugTimers) {
      double now = _getTime();

      if (s.t3Exp == 0.0) {
        print('Stop T3. Wasn\'t running.');
      } else {
        print(
            'Stop T3, ${(s.t3Exp - now).toStringAsFixed(3)} remaining, [now=${(now - s.startTime).toStringAsFixed(3)}] from $fromFunc $fromLine');
      }
    }
    s.t3Exp = 0.0;
  }

  // Start TM201 timer
  static void _startTm201(Ax25Dlsm s, String fromFunc, int fromLine) {
    double now = _getTime();

    if (_sDebugTimers) {
      print(
          'Start TM201 for t1v = ${s.t1v.toStringAsFixed(3)} sec, rc = ${s.rc}, [now=${(now - s.startTime).toStringAsFixed(3)}] from $fromFunc $fromLine');
    }

    s.tm201Exp = now + s.t1v;
    if (s.radioChannelBusy) {
      s.tm201PausedAt = now;
    } else {
      s.tm201PausedAt = 0;
    }
  }

  // Stop TM201 timer
  // ignore: unused_element
  static void _stopTm201(Ax25Dlsm s, String fromFunc, int fromLine) {
    double now = _getTime();

    if (_sDebugTimers) {
      print(
          'Stop TM201. [now=${(now - s.startTime).toStringAsFixed(3)}] from $fromFunc $fromLine');
    }

    s.tm201Exp = 0.0;
  }

  // Pause TM201 timer
  static void _pauseTm201(Ax25Dlsm s, String fromFunc, int fromLine) {
    if (s.tm201Exp == 0.0) {
      // Stopped so nothing to do
    } else if (s.tm201PausedAt == 0.0) {
      // Running and not paused
      double now = _getTime();
      s.tm201PausedAt = now;

      if (_sDebugTimers) {
        print(
            'Paused TM201 with ${(s.tm201Exp - now).toStringAsFixed(3)} still remaining, [now=${(now - s.startTime).toStringAsFixed(3)}] from $fromFunc $fromLine');
      }
    } else {
      if (_sDebugTimers) {
        print('TM201 error: Didn\'t expect pause when already paused.');
      }
    }
  }

  // Resume TM201 timer
  static void _resumeTm201(Ax25Dlsm s, String fromFunc, int fromLine) {
    if (s.tm201Exp == 0.0) {
      // Stopped so nothing to do
    } else if (s.tm201PausedAt == 0.0) {
      // Running but not paused
    } else {
      double now = _getTime();
      double pausedForSec = now - s.tm201PausedAt;

      s.tm201Exp += pausedForSec;
      s.tm201PausedAt = 0.0;

      if (_sDebugTimers) {
        print(
            'Resumed TM201 after pausing for ${pausedForSec.toStringAsFixed(3)} sec, ${(s.tm201Exp - now).toStringAsFixed(3)} still remaining, [now=${(now - s.startTime).toStringAsFixed(3)}]');
      }
    }
  }

  // ============================================================================
  // TIMER EXPIRY FUNCTIONS
  // ============================================================================

  // Timer expiry check
  static void dlTimerExpiry() {
    double now = _getTime();

    // Process T1 expiry
    Ax25Dlsm? p = _listHead;
    while (p != null) {
      final pNext = p.next;
      if (p.t1Exp != 0 && p.t1PausedAt == 0 && p.t1Exp <= now) {
        p.t1Exp = 0;
        p.t1PausedAt = 0;
        p.t1HadExpired = true;
        _t1Expiry(p);
      }
      p = pNext;
    }

    // Process T3 expiry
    p = _listHead;
    while (p != null) {
      final pNext = p.next;
      if (p.t3Exp != 0 && p.t3Exp <= now) {
        p.t3Exp = 0;
        _t3Expiry(p);
      }
      p = pNext;
    }

    // Process TM201 expiry
    p = _listHead;
    while (p != null) {
      final pNext = p.next;
      if (p.tm201Exp != 0 && p.tm201PausedAt == 0 && p.tm201Exp <= now) {
        p.tm201Exp = 0;
        p.tm201PausedAt = 0;
        _tm201Expiry(p);
      }
      p = pNext;
    }
  }

  // T1 timer expiry
  static void _t1Expiry(Ax25Dlsm s) {
    if (_sDebugTimers) {
      double now = _getTime();
      print(
          't1_expiry(), [now=${(now - s.startTime).toStringAsFixed(3)}], state=${s.state}, rc=${s.rc}');
    }

    switch (s.state) {
      case DlsmState.disconnected:
        // Ignore it
        break;

      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
        // MAXV22 hack for compatibility
        if (s.state == DlsmState.awaitingV22Connection &&
            s.rc == _gMiscConfigP.maxv22) {
          _setVersion20(s);
          _enterNewState(s, DlsmState.awaitingConnection, 't1Expiry', 0);
        }

        if (s.rc == s.n2Retry) {
          _discardIQueue(s);
          print(
              'Failed to connect to ${s.addrs[Ax25Dlsm.peerCall]} after ${s.n2Retry} tries.');
          // server_link_terminated would be called here
          _enterNewState(s, DlsmState.disconnected, 't1Expiry', 0);
          _dlConnectionTerminated(s);
        } else {
          _setRc(s, s.rc + 1);
          if (s.rc > s.peakRcValue) s.peakRcValue = s.rc;

          // Would send SABME or SABM here
          _selectT1Value(s);
          _startT1(s, 't1Expiry', 0);
        }
        break;

      case DlsmState.awaitingRelease:
        if (s.rc == s.n2Retry) {
          print(
              'Stream ${s.streamId}: Disconnected from ${s.addrs[Ax25Dlsm.peerCall]}.');
          // server_link_terminated would be called here
          _enterNewState(s, DlsmState.disconnected, 't1Expiry', 0);
          _dlConnectionTerminated(s);
        } else {
          _setRc(s, s.rc + 1);
          if (s.rc > s.peakRcValue) s.peakRcValue = s.rc;

          // Would send DISC here
          _selectT1Value(s);
          _startT1(s, 't1Expiry', 0);
        }
        break;

      case DlsmState.connected:
        _setRc(s, 1);
        _transmitEnquiry(s);
        _enterNewState(s, DlsmState.timerRecovery, 't1Expiry', 0);
        break;

      case DlsmState.timerRecovery:
        if (s.rc == s.n2Retry) {
          if (s.va != s.vs) {
            if (_sDebugProtocolErrors) {
              print(
                  'Stream ${s.streamId}: AX.25 Protocol Error I: ${s.n2Retry} timeouts: unacknowledged sent data.');
            }
          } else if (s.peerReceiverBusy) {
            if (_sDebugProtocolErrors) {
              print(
                  'Stream ${s.streamId}: AX.25 Protocol Error U: ${s.n2Retry} timeouts: extended peer busy condition.');
            }
          } else {
            if (_sDebugProtocolErrors) {
              print(
                  'Stream ${s.streamId}: AX.25 Protocol Error T: ${s.n2Retry} timeouts: no response to enquiry.');
            }
          }

          print(
              'Stream ${s.streamId}: Disconnected from ${s.addrs[Ax25Dlsm.peerCall]} due to timeouts.');
          // server_link_terminated would be called here

          _discardIQueue(s);

          // Would send DM here

          _enterNewState(s, DlsmState.disconnected, 't1Expiry', 0);
          _dlConnectionTerminated(s);
        } else {
          _setRc(s, s.rc + 1);
          if (s.rc > s.peakRcValue) s.peakRcValue = s.rc;

          _transmitEnquiry(s);
        }
        break;
    }
  }

  // T3 timer expiry
  static void _t3Expiry(Ax25Dlsm s) {
    if (_sDebugTimers) {
      double now = _getTime();
      print('t3_expiry(), [now=${(now - s.startTime).toStringAsFixed(3)}]');
    }

    switch (s.state) {
      case DlsmState.disconnected:
      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
      case DlsmState.awaitingRelease:
      case DlsmState.timerRecovery:
        break;

      case DlsmState.connected:
        _setRc(s, 1);
        _transmitEnquiry(s);
        _enterNewState(s, DlsmState.timerRecovery, 't3Expiry', 0);
        break;
    }
  }

  // TM201 timer expiry
  static void _tm201Expiry(Ax25Dlsm s) {
    if (_sDebugTimers) {
      double now = _getTime();
      print(
          'tm201_expiry(), [now=${(now - s.startTime).toStringAsFixed(3)}], state=${s.state}, rc=${s.rc}');
    }

    switch (s.mdlState) {
      case MdlState.ready:
        // Timer shouldn't be running
        break;

      case MdlState.negotiating:
        s.mdlRc++;
        if (s.mdlRc > s.n2Retry) {
          print(
              'Stream ${s.streamId}: AX.25 Protocol Error MDL-C: Management retry limit exceeded.');
          s.mdlState = MdlState.ready;
        } else {
          // Would send XID command again here
          _startTm201(s, 'tm201Expiry', 0);
        }
        break;
    }
  }

  // Get next timer expiry time
  static double ax25LinkGetNextTimerExpiry() {
    double tnext = 0;

    for (Ax25Dlsm? p = _listHead; p != null; p = p.next) {
      // Consider if running and not paused
      if (p.t1Exp != 0 && p.t1PausedAt == 0) {
        if (tnext == 0 || p.t1Exp < tnext) {
          tnext = p.t1Exp;
        }
      }

      if (p.t3Exp != 0) {
        if (tnext == 0 || p.t3Exp < tnext) {
          tnext = p.t3Exp;
        }
      }

      if (p.tm201Exp != 0 && p.tm201PausedAt == 0) {
        if (tnext == 0 || p.tm201Exp < tnext) {
          tnext = p.tm201Exp;
        }
      }
    }

    return tnext;
  }

  // ============================================================================
  // LINK MANAGEMENT FUNCTIONS
  // ============================================================================

  // Get or create link handle
  static Ax25Dlsm? _getLinkHandle(
      List<String> addrs, int numAddr, int chan, int client, bool create) {
    if (_sDebugLinkHandle) {
      print(
          'get_link_handle (${addrs[0]}>${addrs[1]}, chan=$chan, client=$client, create=$create)');
    }

    // Look for existing
    if (client == -1) {
      // from the radio
      for (Ax25Dlsm? p = _listHead; p != null; p = p.next) {
        if (p.chan == chan &&
            _eqIgnoreCase(addrs[1], p.addrs[Ax25Dlsm.ownCall]) &&
            _eqIgnoreCase(addrs[0], p.addrs[Ax25Dlsm.peerCall])) {
          if (_sDebugLinkHandle) {
            print(
                'get_link_handle returns existing stream id ${p.streamId} for incoming.');
          }
          return p;
        }
      }
    } else {
      // from client app
      for (Ax25Dlsm? p = _listHead; p != null; p = p.next) {
        if (p.chan == chan &&
            p.client == client &&
            _eqIgnoreCase(addrs[0], p.addrs[Ax25Dlsm.ownCall]) &&
            _eqIgnoreCase(addrs[1], p.addrs[Ax25Dlsm.peerCall])) {
          if (_sDebugLinkHandle) {
            print(
                'get_link_handle returns existing stream id ${p.streamId} for outgoing.');
          }
          return p;
        }
      }
    }

    // Could not find existing
    if (!create) {
      if (_sDebugLinkHandle) {
        print('get_link_handle: Search failed. Do not create new.');
      }
      return null;
    }

    // Check registered callsigns if from radio
    int incomingForClient = -1;
    if (client == -1) {
      RegCallsign? found;
      for (RegCallsign? r = _regCallsignList;
          r != null && found == null;
          r = r.next) {
        if (_eqIgnoreCase(addrs[1], r.callsign) && chan == r.chan) {
          found = r;
          incomingForClient = r.client;
        }
      }

      if (found == null) {
        if (_sDebugLinkHandle) {
          print('get_link_handle: not for me. Ignore it.');
        }
        return null;
      }
    }

    // Create new data link state machine
    final newS = Ax25Dlsm()
      ..magic1 = Ax25LinkConstants.magic1
      ..startTime = _getTime()
      ..streamId = _nextStreamId++
      ..modulo = 8
      ..chan = chan
      ..numAddr = numAddr
      ..state = DlsmState.disconnected
      ..t1RemainingWhenLastStopped = -999
      ..magic2 = Ax25LinkConstants.magic2
      ..magic3 = Ax25LinkConstants.magic3;

    // Set addresses
    if (incomingForClient >= 0) {
      // Swap source/destination and reverse digi path for incoming
      newS.addrs[0] = addrs[1];
      newS.addrs[1] = addrs[0];

      int j = 2;
      int k = numAddr - 1;
      while (k >= 2) {
        newS.addrs[j] = addrs[k];
        j++;
        k--;
      }

      newS.client = incomingForClient;
    } else {
      newS.addrs.setRange(0, numAddr, addrs);
      newS.client = client;
    }

    // Add to linked list
    newS.next = _listHead;
    _listHead = newS;

    if (_sDebugLinkHandle) {
      print('get_link_handle returns NEW stream id ${newS.streamId}');
    }

    return newS;
  }

  // Connection cleanup
  static void _dlConnectionCleanup(Ax25Dlsm s) {
    if (_sDebugStats) {
      print('${s.countRecvFrameType[0]} I frames received');
      print('${s.peakRcValue} peak retry count');
    }

    if (_sDebugClientApp) {
      print('dl_connection_cleanup: remove ${s.addrs[0]}>${s.addrs[1]}');
    }

    _discardIQueue(s);

    for (int n = 0; n < 128; n++) {
      if (s.txdataByNs[n] != null) {
        s.txdataByNs[n] = null;
      }
    }

    for (int n = 0; n < 128; n++) {
      if (s.rxdataByNs[n] != null) {
        s.rxdataByNs[n] = null;
      }
    }

    if (s.raBuff != null) {
      s.raBuff = null;
    }

    _enterNewState(s, DlsmState.disconnected, 'dlConnectionCleanup', 0);

    s.magic1 = 0;
    s.magic2 = 0;
    s.magic3 = 0;
  }

  // Connection terminated
  static void _dlConnectionTerminated(Ax25Dlsm s) {
    assert(s.magic1 == Ax25LinkConstants.magic1);
    assert(s.magic2 == Ax25LinkConstants.magic2);
    assert(s.magic3 == Ax25LinkConstants.magic3);

    // Remove from list
    Ax25Dlsm? dlprev;
    Ax25Dlsm? dlentry = _listHead;
    while (dlentry != s) {
      dlprev = dlentry;
      dlentry = dlentry!.next;
    }

    if (dlprev == null) {
      _listHead = s.next;
    } else {
      dlprev.next = s.next;
    }

    _dlConnectionCleanup(s);
  }

  // ============================================================================
  // UTILITY FUNCTIONS
  // ============================================================================

  // Discard I frame queue
  static void _discardIQueue(Ax25Dlsm s) {
    while (s.iFrameQueue != null) {
      s.iFrameQueue = s.iFrameQueue!.next;
    }
  }

  // Clear exception conditions
  static void _clearExceptionConditions(Ax25Dlsm s) {
    s.peerReceiverBusy = false;
    s.rejectException = false;
    s.ownReceiverBusy = false;
    s.acknowledgePending = false;

    // Clear out of sequence incoming I frames
    for (int n = 0; n < 128; n++) {
      if (s.rxdataByNs[n] != null) {
        s.rxdataByNs[n] = null;
      }
    }
  }

  // Establish data link
  static void _establishDataLink(Ax25Dlsm s) {
    _clearExceptionConditions(s);
    _setRc(s, 1);

    // Would send SABME or SABM here

    _stopT3(s, 'establishDataLink', 0);
    _startT1(s, 'establishDataLink', 0);
  }

  // Set version 2.0
  static void _setVersion20(Ax25Dlsm s) {
    s.srejEnable = SrejEnable.none;
    s.modulo = 8;
    s.n1Paclen = _gMiscConfigP.paclen;
    s.kMaxframe = _gMiscConfigP.maxframeBasic;
    s.n2Retry = _gMiscConfigP.retry;
  }

  // Set version 2.2
  static void _setVersion22(Ax25Dlsm s) {
    s.srejEnable = SrejEnable.single;
    s.modulo = 128;
    s.n1Paclen = _gMiscConfigP.paclen;
    s.kMaxframe = _gMiscConfigP.maxframeExtended;
    s.n2Retry = _gMiscConfigP.retry;
  }

  // Transmit enquiry
  static void _transmitEnquiry(Ax25Dlsm s) {
    if (_sDebugRetry) {
      print(
          '\n****** TRANSMIT ENQUIRY RR/RNR cmd P=1 ****** state=${s.state}, rc=${s.rc}\n');
    }

    // Would send RR or RNR command with P=1 here

    s.acknowledgePending = false;
    _startT1(s, 'transmitEnquiry', 0);
  }

  // Select T1 value
  static void _selectT1Value(Ax25Dlsm s) {
    double oldSrt = s.srt;

    if (s.rc == 0) {
      if (s.t1RemainingWhenLastStopped >= 0) {
        s.srt = 7.0 / 8.0 * s.srt +
            1.0 / 8.0 * (s.t1v - s.t1RemainingWhenLastStopped);
      }

      if (s.srt < 1) {
        s.srt = 1;
        if (s.numAddr > 2) {
          s.srt += 2 * (s.numAddr - 2);
        }
      }

      s.t1v = s.srt * 2;
    } else {
      if (s.t1HadExpired) {
        s.t1v = s.rc * 0.25 + s.srt * 2;
      }
    }

    if (_sDebugTimers) {
      print(
          'Stream ${s.streamId}: select_t1_value, rc = ${s.rc}, t1 remaining = ${s.t1RemainingWhenLastStopped.toStringAsFixed(3)}, old srt = ${oldSrt.toStringAsFixed(3)}, new srt = ${s.srt.toStringAsFixed(3)}, new t1v = ${s.t1v.toStringAsFixed(3)}');
    }

    // Guardrails
    double maxT1v = 2 * (_gMiscConfigP.frack * (2 * (s.numAddr - 2) + 1));
    if (s.t1v < 0.25 || s.t1v > maxT1v) {
      _initT1vSrt(s);
    }
  }

  // Is good N(R)?
  // ignore: unused_element
  static bool _isGoodNr(Ax25Dlsm s, int nr) {
    int adjustedVa =
        _ax25Modulo(s.va - s.va, s.modulo, 'Ax25Link', 'isGoodNr', 0);
    int adjustedNr =
        _ax25Modulo(nr - s.va, s.modulo, 'Ax25Link', 'isGoodNr', 0);
    int adjustedVs =
        _ax25Modulo(s.vs - s.va, s.modulo, 'Ax25Link', 'isGoodNr', 0);

    bool result = adjustedVa <= adjustedNr && adjustedNr <= adjustedVs;

    if (_sDebugMisc) {
      print(
          'is_good_nr, V(a) ${s.va} <= nr $nr <= V(s) ${s.vs}, returns $result');
    }

    return result;
  }

  // Check if we can send I frames (pop from queue)
  static void _iFramePopOffQueue(Ax25Dlsm s) {
    if (s.iFrameQueue == null) {
      return;
    }

    switch (s.state) {
      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
        if (s.layerThreeInitiated) {
          final txdata = s.iFrameQueue!;
          s.iFrameQueue = txdata.next;
          // Discard it
        }
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        while (!s.peerReceiverBusy &&
            s.iFrameQueue != null &&
            _withinWindowSize(s)) {
          final txdata = s.iFrameQueue!;
          s.iFrameQueue = txdata.next;
          txdata.next = null;

          // Would construct and send I frame here
          // For now, store in sent array
          int ns = s.vs;
          if (s.txdataByNs[ns] != null) {
            s.txdataByNs[ns] = null;
          }
          s.txdataByNs[ns] = txdata;

          _setVs(
              s, _ax25Modulo(s.vs + 1, s.modulo, 'Ax25Link', 'iFramePopOffQueue', 0));
          s.acknowledgePending = false;

          _stopT3(s, 'iFramePopOffQueue', 0);
          _startT1(s, 'iFramePopOffQueue', 0);
        }
        break;

      case DlsmState.disconnected:
      case DlsmState.awaitingRelease:
        break;
    }
  }

  // Public API functions that would be called from the data link queue

  static void dlConnectRequest(
      List<String> addrs, int numAddr, int chan, int client) {
    final s = _getLinkHandle(addrs, numAddr, chan, client, true)!;

    switch (s.state) {
      case DlsmState.disconnected:
        _initT1vSrt(s);

        // Check if this is a v2.0 only station
        bool oldVersion = false;
        for (int n = 0; n < _gMiscConfigP.v20Count && !oldVersion; n++) {
          if (_eqIgnoreCase(addrs[1], _gMiscConfigP.v20Addrs[n])) {
            oldVersion = true;
          }
        }

        if (oldVersion || _gMiscConfigP.maxv22 == 0) {
          _setVersion20(s);
          _establishDataLink(s);
          s.layerThreeInitiated = true;
          _enterNewState(s, DlsmState.awaitingConnection, 'dlConnectRequest', 0);
        } else {
          _setVersion22(s);
          _establishDataLink(s);
          s.layerThreeInitiated = true;
          _enterNewState(
              s, DlsmState.awaitingV22Connection, 'dlConnectRequest', 0);
        }
        break;

      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
        _discardIQueue(s);
        s.layerThreeInitiated = true;
        break;

      case DlsmState.awaitingRelease:
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        _discardIQueue(s);
        _establishDataLink(s);
        s.layerThreeInitiated = true;
        _enterNewState(
            s,
            s.modulo == 128
                ? DlsmState.awaitingV22Connection
                : DlsmState.awaitingConnection,
            'dlConnectRequest',
            0);
        break;
    }
  }

  static void dlDisconnectRequest(
      List<String> addrs, int numAddr, int chan, int client) {
    final s = _getLinkHandle(addrs, numAddr, chan, client, true)!;

    switch (s.state) {
      case DlsmState.disconnected:
        print(
            'Stream ${s.streamId}: Disconnected from ${s.addrs[Ax25Dlsm.peerCall]}.');
        _enterNewState(s, DlsmState.disconnected, 'dlDisconnectRequest', 0);
        _dlConnectionTerminated(s);
        break;

      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
        print(
            'Stream ${s.streamId}: In progress connection attempt to ${s.addrs[Ax25Dlsm.peerCall]} terminated by user.');
        _discardIQueue(s);
        _setRc(s, 0);
        // Would send DISC here
        _stopT1(s, 'dlDisconnectRequest', 0);
        _stopT3(s, 'dlDisconnectRequest', 0);
        _enterNewState(s, DlsmState.disconnected, 'dlDisconnectRequest', 0);
        _dlConnectionTerminated(s);
        break;

      case DlsmState.awaitingRelease:
        // Would send DM expedited here
        print(
            'Stream ${s.streamId}: Disconnected from ${s.addrs[Ax25Dlsm.peerCall]}.');
        _stopT1(s, 'dlDisconnectRequest', 0);
        _enterNewState(s, DlsmState.disconnected, 'dlDisconnectRequest', 0);
        _dlConnectionTerminated(s);
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        _discardIQueue(s);
        _setRc(s, 0);
        // Would send DISC here
        _stopT3(s, 'dlDisconnectRequest', 0);
        _startT1(s, 'dlDisconnectRequest', 0);
        _enterNewState(s, DlsmState.awaitingRelease, 'dlDisconnectRequest', 0);
        break;
    }
  }

  static void dlDataRequest(
      List<String> addrs, int numAddr, int chan, int client, CData txdata) {
    final s = _getLinkHandle(addrs, numAddr, chan, client, true)!;

    // Handle segmentation if data is too large
    if (txdata.len > s.n1Paclen) {
      // Segmentation logic would go here
      // For now, split into max-size chunks
      int offset = 0;
      int remaining = txdata.len;

      while (remaining > 0) {
        int thisLen = math.min(remaining, s.n1Paclen);

        // Create a slice of the data array
        Uint8List dataSlice = Uint8List(thisLen);
        dataSlice.setRange(0, thisLen, txdata.data, offset);

        final newTxdata = CData(txdata.pid, dataSlice, thisLen);
        _dataRequestGoodSize(s, newTxdata);
        offset += thisLen;
        remaining -= thisLen;
      }
      return;
    }

    _dataRequestGoodSize(s, txdata);
  }

  static void _dataRequestGoodSize(Ax25Dlsm s, CData txdata) {
    switch (s.state) {
      case DlsmState.disconnected:
      case DlsmState.awaitingRelease:
        // Discard it
        break;

      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
        if (!s.layerThreeInitiated) {
          _appendIFrameToQueue(s, txdata);
        }
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        _appendIFrameToQueue(s, txdata);
        break;
    }

    // Kick off transmission if conditions are right
    if ((s.state == DlsmState.connected || s.state == DlsmState.timerRecovery) &&
        !s.peerReceiverBusy &&
        _withinWindowSize(s)) {
      s.acknowledgePending = true;
      // Would call lm_seize_request here
    }
  }

  // Append a txdata to the I frame queue
  static void _appendIFrameToQueue(Ax25Dlsm s, CData txdata) {
    if (s.iFrameQueue == null) {
      txdata.next = null;
      s.iFrameQueue = txdata;
    } else {
      var plast = s.iFrameQueue!;
      while (plast.next != null) {
        plast = plast.next!;
      }
      txdata.next = null;
      plast.next = txdata;
    }
  }

  static void dlRegisterCallsign(String callsign, int chan, int client) {
    if (_sDebugClientApp) {
      print('dl_register_callsign ($callsign, chan=$chan, client=$client)');
    }

    final r = RegCallsign()
      ..callsign = callsign
      ..chan = chan
      ..client = client
      ..next = _regCallsignList
      ..magic = Ax25LinkConstants.rcMagic;

    _regCallsignList = r;
  }

  static void dlUnregisterCallsign(String callsign, int chan, int client) {
    if (_sDebugClientApp) {
      print('dl_unregister_callsign ($callsign, chan=$chan, client=$client)');
    }

    RegCallsign? prev;
    RegCallsign? r = _regCallsignList;

    while (r != null) {
      assert(r.magic == Ax25LinkConstants.rcMagic);

      if (_eqIgnoreCase(r.callsign, callsign) &&
          r.chan == chan &&
          r.client == client) {
        if (r == _regCallsignList) {
          _regCallsignList = r.next;
          r = _regCallsignList;
        } else {
          prev!.next = r.next;
          r = prev.next;
        }
      } else {
        prev = r;
        r = r.next;
      }
    }
  }

  static void dlClientCleanup(int client) {
    if (_sDebugClientApp) {
      print('dl_client_cleanup ($client)');
    }

    // Clean up state machines for this client
    Ax25Dlsm? dlprev;
    Ax25Dlsm? s = _listHead;

    while (s != null) {
      assert(s.magic1 == Ax25LinkConstants.magic1);
      assert(s.magic2 == Ax25LinkConstants.magic2);
      assert(s.magic3 == Ax25LinkConstants.magic3);

      if (s.client == client) {
        if (s == _listHead) {
          _listHead = s.next;
          _dlConnectionCleanup(s);
          s = _listHead;
        } else {
          dlprev!.next = s.next;
          _dlConnectionCleanup(s);
          s = dlprev.next;
        }
      } else {
        dlprev = s;
        s = s.next;
      }
    }

    // Clean up registered callsigns for this client
    RegCallsign? rcprev;
    RegCallsign? r = _regCallsignList;

    while (r != null) {
      assert(r.magic == Ax25LinkConstants.rcMagic);

      if (r.client == client) {
        if (r == _regCallsignList) {
          _regCallsignList = r.next;
          r = _regCallsignList;
        } else {
          rcprev!.next = r.next;
          r = rcprev.next;
        }
      } else {
        rcprev = r;
        r = r.next;
      }
    }
  }

  // ============================================================================
  // ADDITIONAL HELPER FUNCTIONS
  // ============================================================================

  // Check I frame acknowledged
  // ignore: unused_element
  static void _checkIFrameAckd(Ax25Dlsm s, int nr) {
    if (s.peerReceiverBusy) {
      _setVa(s, nr);
      _startT3(s, 'checkIFrameAckd', 0);
      if (!_isT1Running(s, 'checkIFrameAckd', 0)) {
        _startT1(s, 'checkIFrameAckd', 0);
      }
    } else if (nr == s.vs) {
      _setVa(s, nr);
      _stopT1(s, 'checkIFrameAckd', 0);
      _startT3(s, 'checkIFrameAckd', 0);
      _selectT1Value(s);
    } else if (nr != s.va) {
      if (_sDebugMisc) {
        print(
            'check_i_frame_ackd n(r)=$nr, v(a)=${s.va}, Set v(a) to new value $nr');
      }

      _setVa(s, nr);
      _startT1(s, 'checkIFrameAckd', 0);
    }
  }

  // N(R) error recovery
  // ignore: unused_element
  static void _nrErrorRecovery(Ax25Dlsm s) {
    if (_sDebugProtocolErrors) {
      print(
          'Stream ${s.streamId}: AX.25 Protocol Error J: N(r) sequence error.');
    }
    _establishDataLink(s);
    s.layerThreeInitiated = false;
  }

  // Enquiry response
  static void _enquiryResponse(Ax25Dlsm s, int frameType, int f) {
    if (_sDebugRetry) {
      print('\n****** ENQUIRY RESPONSE F=$f ******\n');
    }

    // This is simplified - full implementation would check frame type
    // and handle SREJ enabled cases more completely

    // Would send RR or RNR response with F bit here
    s.acknowledgePending = false;
  }

  // Check need for response
  // ignore: unused_element
  static void _checkNeedForResponse(
      Ax25Dlsm s, int frameType, bool isCommand, int pf) {
    if (isCommand && pf == 1) {
      int f = 1;
      _enquiryResponse(s, frameType, f);
    } else if (!isCommand && pf == 1) {
      if (_sDebugProtocolErrors) {
        print(
            'Stream ${s.streamId}: AX.25 Protocol Error A: F=1 received but P=1 not outstanding.');
      }
    }
  }

  // Invoke retransmission
  // ignore: unused_element
  static void _invokeRetransmission(Ax25Dlsm s, int nrInput) {
    int localVs;
    int sentCount = 0;

    if (_sDebugMisc) {
      print(
          'invoke_retransmission(): starting with $nrInput, state=${s.state}, rc=${s.rc}');
    }

    if (s.txdataByNs[nrInput] == null) {
      print(
          'Internal Error, Can\'t resend starting with N(S) = $nrInput. It is not available.');
      return;
    }

    localVs = nrInput;
    do {
      if (s.txdataByNs[localVs] != null) {
        if (_sDebugMisc) {
          print('invoke_retransmission(): Resending N(S) = $localVs');
        }

        // Would construct and send I frame here with:
        // N(S) = localVs
        // N(R) = s.Vr
        // P = 0

        sentCount++;
      } else {
        print(
            'Internal Error, state=${s.state}, need to retransmit N(S) = $localVs for REJ but it is not available.');
      }
      localVs =
          _ax25Modulo(localVs + 1, s.modulo, 'Ax25Link', 'invokeRetransmission', 0);
    } while (localVs != s.vs);

    if (sentCount == 0) {
      print('Internal Error, Nothing to retransmit. N(R)=$nrInput');
    }
  }

  // Is N(S) in expected window?
  // ignore: unused_element
  static bool _isNsInWindow(Ax25Dlsm s, int ns) {
    int adjustedVr =
        _ax25Modulo(s.vr - s.vr, s.modulo, 'Ax25Link', 'isNsInWindow', 0);
    int adjustedNs =
        _ax25Modulo(ns - s.vr, s.modulo, 'Ax25Link', 'isNsInWindow', 0);
    int adjustedVrpk = _ax25Modulo(s.vr + Ax25LinkConstants.generousK - s.vr,
        s.modulo, 'Ax25Link', 'isNsInWindow', 0);

    bool result = adjustedVr < adjustedNs && adjustedNs < adjustedVrpk;

    if (_sDebugRetry) {
      print(
          'is_ns_in_window, V(R) ${s.vr} < N(S) $ns < V(R)+k ${s.vr + Ax25LinkConstants.generousK}, returns $result');
    }

    return result;
  }

  // Data indication to client
  // ignore: unused_element
  static void _dlDataIndication(Ax25Dlsm s, int pid, Uint8List data, int len) {
    // Segment reassembly would be handled here
    // For now, just pass through

    if (_sDebugClientApp) {
      print('call dl_data_indication() N(S)=${s.vr}, data length=$len');
    }

    // Would call server_rec_conn_data here to deliver to client application
  }

  // ============================================================================
  // CHANNEL BUSY MANAGEMENT
  // ============================================================================

  static void lmChannelBusy(int chan, bool isDcd, bool status) {
    assert(chan >= 0 && chan < 16);

    if (isDcd) {
      if (_sDebugRadio) {
        print('lm_channel_busy: DCD chan $chan = $status');
      }
      _dcdStatus[chan] = status;
    } else {
      if (_sDebugRadio) {
        print('lm_channel_busy: PTT chan $chan = $status');
      }
      _pttStatus[chan] = status;
    }

    bool busy = _dcdStatus[chan] || _pttStatus[chan];

    // Apply to all state machines for this channel
    for (Ax25Dlsm? s = _listHead; s != null; s = s.next) {
      if (chan == s.chan) {
        if (busy && !s.radioChannelBusy) {
          s.radioChannelBusy = true;
          _pauseT1(s, 'lmChannelBusy', 0);
          _pauseTm201(s, 'lmChannelBusy', 0);
        } else if (!busy && s.radioChannelBusy) {
          s.radioChannelBusy = false;
          _resumeT1(s, 'lmChannelBusy', 0);
          _resumeTm201(s, 'lmChannelBusy', 0);
        }
      }
    }
  }

  // ============================================================================
  // SEIZE CONFIRM (Channel Clear for Transmission)
  // ============================================================================

  static void lmSeizeConfirm(int chan) {
    assert(chan >= 0 && chan < 16);

    for (Ax25Dlsm? s = _listHead; s != null; s = s.next) {
      if (chan == s.chan) {
        switch (s.state) {
          case DlsmState.disconnected:
          case DlsmState.awaitingConnection:
          case DlsmState.awaitingRelease:
          case DlsmState.awaitingV22Connection:
            break;

          case DlsmState.connected:
          case DlsmState.timerRecovery:
            // Transmit I frames from queue if conditions allow
            _iFramePopOffQueue(s);

            // Send RR if needed
            if (s.acknowledgePending) {
              s.acknowledgePending = false;
              _enquiryResponse(s, 0, 0); // frame_not_AX25 case
            }
            break;
        }
      }
    }
  }

  // ============================================================================
  // FRAME RECEPTION STUBS
  // ============================================================================

  // These are simplified versions showing the state machine logic
  // Full implementation would integrate with Ax25Pad for frame parsing

  static void processSabmFrame(Ax25Dlsm s, bool extended, int p) {
    switch (s.state) {
      case DlsmState.disconnected:
        if (extended) {
          _setVersion22(s);
        } else {
          _setVersion20(s);
        }

        // Would send UA response here

        _clearExceptionConditions(s);
        _setVs(s, 0);
        _setVa(s, 0);
        _setVr(s, 0);

        print(
            'Stream ${s.streamId}: Connected to ${s.addrs[Ax25Dlsm.peerCall]}. (${extended ? "v2.2" : "v2.0"})');

        // Would call server_link_established here

        _initT1vSrt(s);
        _startT3(s, 'processSabmFrame', 0);
        _setRc(s, 0);
        _enterNewState(s, DlsmState.connected, 'processSabmFrame', 0);
        break;

      case DlsmState.awaitingConnection:
        if (extended) {
          // Would send DM response here
          _enterNewState(
              s, DlsmState.awaitingV22Connection, 'processSabmFrame', 0);
        } else {
          // Would send UA response here
          // Stay in state 1
        }
        break;

      case DlsmState.awaitingV22Connection:
        if (extended) {
          // Would send UA response here
          // Stay in state 5
        } else {
          // Would send UA response here
          _enterNewState(s, DlsmState.awaitingConnection, 'processSabmFrame', 0);
        }
        break;

      case DlsmState.awaitingRelease:
        // Would send DM response here
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        // Would send UA response here

        if (s.state == DlsmState.timerRecovery) {
          if (extended) {
            _setVersion22(s);
          } else {
            _setVersion20(s);
          }
        }

        _clearExceptionConditions(s);
        if (_sDebugProtocolErrors) {
          print(
              'Stream ${s.streamId}: AX.25 Protocol Error F: Data Link reset; i.e. SABM(e) received in state ${s.state}.');
        }

        if (s.vs != s.va) {
          _discardIQueue(s);
          // Would call server_link_established here
        }

        _stopT1(s, 'processSabmFrame', 0);
        _startT3(s, 'processSabmFrame', 0);
        _setVs(s, 0);
        _setVa(s, 0);
        _setVr(s, 0);
        _setRc(s, 0);
        _enterNewState(s, DlsmState.connected, 'processSabmFrame', 0);
        break;
    }
  }

  static void processDiscFrame(Ax25Dlsm s, int p) {
    switch (s.state) {
      case DlsmState.disconnected:
      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
        // Would send DM response here
        break;

      case DlsmState.awaitingRelease:
        // Would send UA response (expedited) here
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        _discardIQueue(s);

        // Would send UA response here

        print(
            'Stream ${s.streamId}: Disconnected from ${s.addrs[Ax25Dlsm.peerCall]}.');
        // Would call server_link_terminated here

        _stopT1(s, 'processDiscFrame', 0);
        _stopT3(s, 'processDiscFrame', 0);
        _enterNewState(s, DlsmState.disconnected, 'processDiscFrame', 0);
        _dlConnectionTerminated(s);
        break;
    }
  }

  static void processUaFrame(Ax25Dlsm s, int f) {
    switch (s.state) {
      case DlsmState.disconnected:
        if (_sDebugProtocolErrors) {
          print(
              'Stream ${s.streamId}: AX.25 Protocol Error C: Unexpected UA in state ${s.state}.');
        }
        break;

      case DlsmState.awaitingConnection:
      case DlsmState.awaitingV22Connection:
        if (f == 1) {
          if (s.layerThreeInitiated) {
            print(
                'Stream ${s.streamId}: Connected to ${s.addrs[Ax25Dlsm.peerCall]}. (${s.state == DlsmState.awaitingV22Connection ? "v2.2" : "v2.0"})');
            // Would call server_link_established here (outgoing=true)
          } else if (s.vs != s.va) {
            _initT1vSrt(s);
            _startT3(s, 'processUaFrame', 0);

            print(
                'Stream ${s.streamId}: Connected to ${s.addrs[Ax25Dlsm.peerCall]}. (${s.state == DlsmState.awaitingV22Connection ? "v2.2" : "v2.0"})');
            // Would call server_link_established here
          }

          _stopT1(s, 'processUaFrame', 0);
          _startT3(s, 'processUaFrame', 0);
          _setVs(s, 0);
          _setVa(s, 0);
          _setVr(s, 0);
          _selectT1Value(s);

          // Would call mdl_negotiate_request here for v2.2

          _setRc(s, 0);
          _enterNewState(s, DlsmState.connected, 'processUaFrame', 0);
        } else {
          if (_sDebugProtocolErrors) {
            print(
                'Stream ${s.streamId}: AX.25 Protocol Error D: UA received without F=1 when SABM or DISC was sent P=1.');
          }
        }
        break;

      case DlsmState.awaitingRelease:
        if (f == 1) {
          print(
              'Stream ${s.streamId}: Disconnected from ${s.addrs[Ax25Dlsm.peerCall]}.');
          // Would call server_link_terminated here
          _stopT1(s, 'processUaFrame', 0);
          _enterNewState(s, DlsmState.disconnected, 'processUaFrame', 0);
          _dlConnectionTerminated(s);
        } else {
          if (_sDebugProtocolErrors) {
            print(
                'Stream ${s.streamId}: AX.25 Protocol Error D: UA received without F=1 when SABM or DISC was sent P=1.');
          }
        }
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        if (_sDebugProtocolErrors) {
          print(
              'Stream ${s.streamId}: AX.25 Protocol Error C: Unexpected UA in state ${s.state}.');
        }
        _establishDataLink(s);
        s.layerThreeInitiated = false;
        _enterNewState(
            s,
            s.modulo == 128
                ? DlsmState.awaitingV22Connection
                : DlsmState.awaitingConnection,
            'processUaFrame',
            0);
        break;
    }
  }

  static void processDmFrame(Ax25Dlsm s, int f) {
    switch (s.state) {
      case DlsmState.disconnected:
        break;

      case DlsmState.awaitingConnection:
        if (f == 1) {
          _discardIQueue(s);
          print(
              'Stream ${s.streamId}: Disconnected from ${s.addrs[Ax25Dlsm.peerCall]}.');
          // Would call server_link_terminated here
          _stopT1(s, 'processDmFrame', 0);
          _enterNewState(s, DlsmState.disconnected, 'processDmFrame', 0);
          _dlConnectionTerminated(s);
        }
        break;

      case DlsmState.awaitingRelease:
        if (f == 1) {
          print(
              'Stream ${s.streamId}: Disconnected from ${s.addrs[Ax25Dlsm.peerCall]}.');
          // Would call server_link_terminated here
          _stopT1(s, 'processDmFrame', 0);
          _enterNewState(s, DlsmState.disconnected, 'processDmFrame', 0);
          _dlConnectionTerminated(s);
        }
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        if (_sDebugProtocolErrors) {
          print(
              'Stream ${s.streamId}: AX.25 Protocol Error E: DM received in state ${s.state}.');
        }
        print(
            'Stream ${s.streamId}: Disconnected from ${s.addrs[Ax25Dlsm.peerCall]}.');
        // Would call server_link_terminated here
        _discardIQueue(s);
        _stopT1(s, 'processDmFrame', 0);
        _stopT3(s, 'processDmFrame', 0);
        _enterNewState(s, DlsmState.disconnected, 'processDmFrame', 0);
        _dlConnectionTerminated(s);
        break;

      case DlsmState.awaitingV22Connection:
        // Compatibility hack for non-compliant stations
        if (f == 1) {
          print(
              '${s.addrs[Ax25Dlsm.peerCall]} doesn\'t understand AX.25 v2.2. Trying v2.0 ...');
          print('You can avoid this failed attempt and speed up the');
          print(
              'process by putting "V20 ${s.addrs[Ax25Dlsm.peerCall]}" in the configuration file.');

          _initT1vSrt(s);
          _setVersion20(s);
          _establishDataLink(s);
          s.layerThreeInitiated = true;
          _enterNewState(s, DlsmState.awaitingConnection, 'processDmFrame', 0);
        }
        break;
    }
  }

  static void processFrmrFrame(Ax25Dlsm s) {
    switch (s.state) {
      case DlsmState.disconnected:
      case DlsmState.awaitingConnection:
      case DlsmState.awaitingRelease:
        // Ignore it
        break;

      case DlsmState.connected:
      case DlsmState.timerRecovery:
        if (_sDebugProtocolErrors) {
          print(
              'Stream ${s.streamId}: AX.25 Protocol Error K: FRMR not expected in state ${s.state}.');
        }
        _setVersion20(s);
        _establishDataLink(s);
        s.layerThreeInitiated = false;
        _enterNewState(s, DlsmState.awaitingConnection, 'processFrmrFrame', 0);
        break;

      case DlsmState.awaitingV22Connection:
        print(
            '${s.addrs[Ax25Dlsm.peerCall]} doesn\'t understand AX.25 v2.2. Trying v2.0 ...');
        print('You can avoid this failed attempt and speed up the');
        print(
            'process by putting "V20 ${s.addrs[Ax25Dlsm.peerCall]}" in the configuration file.');

        _initT1vSrt(s);
        _setVersion20(s);
        _establishDataLink(s);
        s.layerThreeInitiated = true;
        _enterNewState(s, DlsmState.awaitingConnection, 'processFrmrFrame', 0);
        break;
    }
  }
}
