/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// iax2_constants.dart - IAX2 (Inter-Asterisk eXchange v2) protocol constants.
//
// Values are taken from RFC 5456 and the Asterisk chan_iax2 implementation used
// by AllStarLink (app_rpt). Only the subset needed to place an outbound client
// call to an AllStarLink node is defined here.
//

/// Default UDP port for IAX2 signaling and media (RFC 5456 well-known port).
const int iax2DefaultPort = 4569;

/// Protocol version carried in the VERSION information element of a NEW frame.
const int iax2ProtocolVersion = 2;

/// Frame types (Full Frame "frametype" field, RFC 5456 section 8.2).
class Iax2FrameType {
  static const int dtmf = 0x01;
  static const int voice = 0x02;
  static const int video = 0x03;
  static const int control = 0x04;
  static const int nullFrame = 0x05;
  static const int iax = 0x06;
  static const int text = 0x07;
  static const int image = 0x08;
  static const int html = 0x09;
  static const int comfortNoise = 0x0a;
}

/// IAX control subclasses (frametype 0x06, RFC 5456 section 8.4).
class Iax2Subclass {
  static const int newCall = 0x01;
  static const int ping = 0x02;
  static const int pong = 0x03;
  static const int ack = 0x04;
  static const int hangup = 0x05;
  static const int reject = 0x06;
  static const int accept = 0x07;
  static const int authReq = 0x08;
  static const int authRep = 0x09;
  static const int inval = 0x0a;
  static const int lagRq = 0x0b;
  static const int lagRp = 0x0c;
  static const int regReq = 0x0d;
  static const int regAuth = 0x0e;
  static const int regAck = 0x0f;
  static const int regRej = 0x10;
  static const int regRel = 0x11;
  static const int vnak = 0x12;
  static const int dpReq = 0x13;
  static const int dpRep = 0x14;
  static const int dial = 0x15;
  static const int txReq = 0x16;
  static const int txCnt = 0x17;
  static const int txAcc = 0x18;
  static const int txReady = 0x19;
  static const int txRel = 0x1a;
  static const int txRej = 0x1b;
  static const int quelch = 0x1c;
  static const int unquelch = 0x1d;
  static const int poke = 0x1e;
  static const int mwi = 0x20;
  static const int unsupport = 0x21;
  static const int transfer = 0x22;

  static String name(int subclass) {
    switch (subclass) {
      case newCall:
        return 'NEW';
      case ping:
        return 'PING';
      case pong:
        return 'PONG';
      case ack:
        return 'ACK';
      case hangup:
        return 'HANGUP';
      case reject:
        return 'REJECT';
      case accept:
        return 'ACCEPT';
      case authReq:
        return 'AUTHREQ';
      case authRep:
        return 'AUTHREP';
      case inval:
        return 'INVAL';
      case lagRq:
        return 'LAGRQ';
      case lagRp:
        return 'LAGRP';
      case regReq:
        return 'REGREQ';
      case regAuth:
        return 'REGAUTH';
      case regAck:
        return 'REGACK';
      case regRej:
        return 'REGREJ';
      case regRel:
        return 'REGREL';
      case vnak:
        return 'VNAK';
      case poke:
        return 'POKE';
      case unsupport:
        return 'UNSUPPORT';
      default:
        return 'IAX(0x${subclass.toRadixString(16)})';
    }
  }
}

/// Control frame subclasses (frametype 0x04, RFC 5456 section 8.3). The Key /
/// Unkey Radio values are the app_rpt PTT indications used by AllStarLink.
class Iax2Control {
  static const int hangup = 0x01;
  static const int ringing = 0x03;
  static const int answer = 0x04;
  static const int busy = 0x05;
  static const int congestion = 0x08;
  static const int flashHook = 0x09;
  static const int option = 0x0b;
  static const int keyRadio = 0x0c;
  static const int unkeyRadio = 0x0d;
  static const int callProgress = 0x0e;
  static const int callProceeding = 0x0f;
  static const int hold = 0x10;
  static const int unhold = 0x11;
  static const int stopSounds = 0xff;
}

/// Information Element identifiers (RFC 5456 section 8.6, Table 1).
class Iax2Ie {
  static const int calledNumber = 0x01;
  static const int callingNumber = 0x02;
  static const int callingAni = 0x03;
  static const int callingName = 0x04;
  static const int calledContext = 0x05;
  static const int username = 0x06;
  static const int password = 0x07;
  static const int capability = 0x08;
  static const int format = 0x09;
  static const int language = 0x0a;
  static const int version = 0x0b;
  static const int adsicpe = 0x0c;
  static const int dnid = 0x0d;
  static const int authMethods = 0x0e;
  static const int challenge = 0x0f;
  static const int md5Result = 0x10;
  static const int rsaResult = 0x11;
  static const int apparentAddr = 0x12;
  static const int refresh = 0x13;
  static const int dpStatus = 0x14;
  static const int callNo = 0x15;
  static const int cause = 0x16;
  static const int iaxUnknown = 0x17;
  static const int msgCount = 0x18;
  static const int autoAnswer = 0x19;
  static const int musicOnHold = 0x1a;
  static const int transferId = 0x1b;
  static const int rdnis = 0x1c;
  static const int dateTime = 0x1f;
  static const int callingPres = 0x26;
  static const int callingTon = 0x27;
  static const int callingTns = 0x28;
  static const int samplingRate = 0x29;
  static const int causeCode = 0x2a;
  static const int encryption = 0x2b;
  static const int encKey = 0x2c;
  static const int codecPrefs = 0x2d;
}

/// Authentication method bitmask values (AUTHMETHODS IE, RFC 5456 8.6.13).
class Iax2AuthMethod {
  static const int plaintext = 0x0001; // Reserved / deprecated.
  static const int md5 = 0x0002;
  static const int rsa = 0x0004;
}

/// Media format bitmask values (RFC 5456 section 8.7). Only the formats this
/// client can encode/decode are listed.
class Iax2Format {
  static const int gsm = 0x00000002;
  static const int ulaw = 0x00000004; // G.711 mu-law.
  static const int alaw = 0x00000008; // G.711 a-law (not implemented).
  static const int slin = 0x00000040; // 16-bit signed linear little-endian.

  static String name(int format) {
    switch (format) {
      case gsm:
        return 'GSM';
      case ulaw:
        return 'ulaw';
      case alaw:
        return 'alaw';
      case slin:
        return 'slin';
      default:
        return '0x${format.toRadixString(16)}';
    }
  }
}

/// Q.931 hangup cause codes used in CAUSECODE IE (RFC 5456 8.6.33). Only the
/// common ones are named.
class Iax2Cause {
  static const int normalClearing = 16;
  static const int userBusy = 17;
  static const int noAnswer = 19;
  static const int callRejected = 21;
}
