import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;

import 'pacsat.dart';

enum FileTransferState {
  queued, offering, receiving, sending, verifying, completed,
  rejected, canceled, noResponse, paused, expired, failed,
}

class FileTransferLink {
  final int deviceId;
  final String radioMac;
  final int regionId;
  final int channelId;
  final String channel;
  final String encoding;
  final int rxFrequency;
  final int txFrequency;
  const FileTransferLink({
    required this.deviceId, required this.radioMac, required this.regionId,
    required this.channelId, required this.channel, required this.encoding,
    required this.rxFrequency, required this.txFrequency,
  });
  String get key => '$radioMac:$regionId:$channelId:$rxFrequency:$txFrequency';
  Map<String, Object?> toJson() => {
    'deviceId':deviceId, 'radioMac':radioMac, 'regionId':regionId,
    'channelId':channelId, 'channel':channel, 'encoding':encoding,
    'rxFrequency':rxFrequency, 'txFrequency':txFrequency,
  };
  factory FileTransferLink.fromJson(Map<String,dynamic> json) => FileTransferLink(
    deviceId:json['deviceId'] as int, radioMac:json['radioMac'] as String,
    regionId:json['regionId'] as int, channelId:json['channelId'] as int,
    channel:json['channel'] as String, encoding:json['encoding'] as String,
    rxFrequency:json['rxFrequency'] as int, txFrequency:json['txFrequency'] as int,
  );
}

class FileTransfer {
  final String id;
  final FileTransferLink link;
  final String source;
  final bool outgoing;
  final PacsatFile file;
  final DateTime created;
  FileTransferState state;
  PacsatBuffer? buffer;
  int transferred = 0;
  String? error;
  String? savedPath;
  DateTime lastHeard;
  DateTime lastOffer;
  DateTime nextAction;
  bool accepted = false;
  List<FileHole> pending = [];
  List<FileHole> replies = [];
  DateTime? replyAt;
  int bursts = 0;
  int piecesInBurst = 0;
  int checkRetries = 0;
  int missedCheckIns = 0;
  bool waiting = false;
  int reminders = 0;
  int completionReports = 0;
  int offers = 0;
  double rate = 80;
  DateTime? previousPiece;
  bool measured = false;
  bool durable = true;
  bool headerReply = false;
  List<Uint8List> requestFrames = [];
  DateTime? autoResumeUntil;
  DateTime? rateStarted;
  int airBytes = 0;

  FileTransfer({
    required this.id, required this.link, required this.source,
    required this.outgoing, required this.file, required this.created,
    required this.state, this.buffer,
  }) : lastHeard=created, lastOffer=created, nextAction=created;

  bool get terminal => const {
    FileTransferState.completed, FileTransferState.rejected, FileTransferState.canceled,
    FileTransferState.expired, FileTransferState.failed,
  }.contains(state);
  bool get canResume => state == FileTransferState.paused || state == FileTransferState.noResponse;
  bool get canCancel => !terminal;
  Map<String,dynamic> toJson({bool storage = false}) => {
    'id':id, 'link':link.toJson(), 'source':source, 'outgoing':outgoing,
    'header':base64Encode(file.header), 'name':file.name,
    'destination':file.destination, 'size':file.size, 'bodySize':file.bodySize,
    'originalSize':file.originalSize, 'created':created.toIso8601String(),
    'state':state.name, 'transferred':transferred, 'error':error, 'savedPath':savedPath,
    'accepted':accepted, 'lastHeard':lastHeard.toIso8601String(),
    'lastOffer':lastOffer.toIso8601String(),
    if (storage && buffer != null) 'data':base64Encode(buffer!.bytes),
    if (storage && buffer != null) 'holes':[
      for (final h in buffer!.missing) [h.offset,h.length],
    ],
  };

  factory FileTransfer.restore(Map<String,dynamic> json, {bool recovering = true}) {
    final file = PacsatFile.parse(base64Decode(json['header'] as String));
    final originalState = FileTransferState.values.byName(json['state'] as String);
    final transfer = FileTransfer(
      id:json['id'] as String, link:FileTransferLink.fromJson(
        Map<String,dynamic>.from(json['link'] as Map)),
      source:normalizeFileCallsign(json['source'] as String),
      outgoing:json['outgoing'] as bool, file:file,
      created:DateTime.parse(json['created'] as String), state:originalState,
    )..transferred=json['transferred'] as int
     ..accepted=json['accepted'] as bool
     ..error=json['error'] as String?
     ..savedPath=json['savedPath'] as String?
     ..lastHeard=DateTime.parse(json['lastHeard'] as String)
     ..lastOffer=DateTime.parse(json['lastOffer'] as String);
    if (json['data'] is String) {
      final data = base64Decode(json['data'] as String);
      if (data.length != file.size) throw const FormatException('Invalid stored file size');
      final buffer = PacsatBuffer(file.size)..bytes.setAll(0,data);
      buffer.missing = [
        for (final raw in json['holes'] as List)
          FileHole((raw as List)[0] as int,raw[1] as int),
      ];
      var end = 0;
      for (final hole in buffer.missing) {
        if (hole.offset < end || hole.length <= 0 || hole.end > file.size) {
          throw const FormatException('Invalid stored file holes');
        }
        end = hole.end;
      }
      transfer.buffer = buffer;
    }
    if (recovering && !transfer.terminal && (transfer.outgoing || transfer.accepted)) {
      transfer.state = FileTransferState.paused;
    }
    return transfer;
  }
}

class _Directory {
  final PacsatBuffer buffer = PacsatBuffer(65535);
  int? end;
  DateTime heard;
  _Directory(this.heard);
}

typedef FilePacketSender = bool Function(
  FileTransfer transfer, int pid, String destination, Uint8List information);

/// Runs independently of Comms widgets. The host supplies live radio delivery
/// and a periodic clock; capture replay is filtered before this boundary.
class FileTransferEngine {
  final FilePacketSender send;
  final bool Function(FileTransferLink) available;
  final void Function(FileTransfer) cancelPackets;
  final void Function() changed;
  final void Function(FileTransfer,Uint8List) receivedFile;
  final Random random;
  final List<FileTransfer> transfers = [];
  final Map<String,_Directory> _directories = {};
  final Map<String,DateTime> _peers = {};
  final Map<String,DateTime> _heard = {};
  final Map<String,DateTime> _busyUntil = {};
  bool _disposed = false;

  FileTransferEngine({
    required this.send, required this.available, required this.cancelPackets,
    required this.changed, required this.receivedFile, Random? random,
  }) : random = random ?? Random.secure();

  void addOutgoing(FileTransfer transfer) {
    if (transfer.file.destination=='ALL') {
      throw StateError('This version sends files to one station at a time');
    }
    if (transfers.where((t)=>t.outgoing && !t.terminal).length >= 5) {
      throw StateError('The outgoing file queue is full');
    }
    transfers.add(transfer);
    changed();
  }

  FileTransfer? _find(String id) {
    for (final t in transfers) {
      if (t.id==id) return t;
    }
    return null;
  }

  void act(String id, String action, DateTime now) {
    final t = _find(id);
    if (t==null) throw StateError('File transfer no longer exists');
    switch(action) {
      case 'accept':
        if (t.outgoing || t.state!=FileTransferState.offering) {
          throw StateError('This file offer is not awaiting acceptance');
        }
        if (transfers.where((v)=>!v.outgoing && v.accepted && !v.terminal).length>=4) {
          throw StateError('Too many incoming transfers');
        }
        if (!available(t.link)) throw StateError('Radio or transfer channel is unavailable');
        t.buffer = PacsatBuffer(t.file.size)..add(0,t.file.header);
        t.accepted=true;
        t.state=FileTransferState.receiving;
        t.lastHeard=now;
        t.nextAction=_requestTime(t,now);
        t.reminders=0;
        t.headerReply=false;
      case 'reject':
      case 'cancel':
        if (!t.canCancel) return;
        cancelPackets(t);
        if (!t.outgoing) {
          // Deferred to a quiet channel; retain the offer's decline response.
          t.nextAction=_requestTime(t,now);
        }
        t.state=action=='reject' ? FileTransferState.rejected : FileTransferState.canceled;
        t.reminders=0;
        t.requestFrames=[];
        t.autoResumeUntil=null;
        t.lastHeard=now;
        t.buffer=null;
      case 'resume':
        if (!t.canResume || t.buffer==null) throw StateError('Transfer cannot be resumed');
        if (!available(t.link)) throw StateError('Radio or transfer channel is unavailable');
        t.error=null;
        t.nextAction=_requestTime(t,now);
        t.lastHeard=now;
        t.reminders=0;
        t.requestFrames=[];
        t.headerReply=false;
        t.autoResumeUntil=null;
        if (t.outgoing) {
          t.state=FileTransferState.queued;
          t.offers=0;
          t.waiting=false;
          t.pending=[];
        } else {
          t.state=FileTransferState.receiving;
        }
      default:
        throw StateError('Unknown file transfer action');
    }
    changed();
  }

  DateTime _requestTime(FileTransfer t, DateTime now, {bool checkIn=false}) =>
    now.add(Duration(milliseconds:checkIn
      ? 500 + random.nextInt(t.file.destination=='ALL' ? 3001 : 151)
      : max(2000,(1.6*250*1000/t.rate).ceil())));

  void hear(FileTransferLink link, String source, DateTime now, {int bytes=0}) {
    _heard[link.key]=now;
    if (bytes>0) _peers['${link.key}|$source']=now;
  }

  void busy(FileTransferLink link, DateTime now) {
    _busyUntil[link.key]=now.add(const Duration(milliseconds:500));
  }

  void receivePiece(FileTransferLink link, String source, String local,
      PacsatPiece piece, DateTime now) {
    source=normalizeFileCallsign(source);
    hear(link,source,now,bytes:piece.directory ? 0 : piece.bytes.length);
    final key='${link.key}|$source|${piece.fileId}';
    if (piece.directory) {
      _directories.removeWhere((_,d)=>now.difference(d.heard).inMinutes>=10);
      if (!_directories.containsKey(key) && _directories.length>=20) {
        final oldest=_directories.entries.reduce((a,b)=>a.value.heard.isBefore(b.value.heard)?a:b);
        _directories.remove(oldest.key);
      }
      final d=_directories.putIfAbsent(key,()=>_Directory(now));
      d.heard=now;
      d.buffer.add(piece.offset,piece.bytes);
      if (piece.last) d.end=piece.offset+piece.bytes.length;
      final end=d.end;
      if (end==null || d.buffer.missing.any((h)=>h.offset<end)) return;
      final file=PacsatFile.parse(Uint8List.sublistView(d.buffer.bytes,0,end));
      if (file.fileId!=piece.fileId) throw const FormatException('Directory file ID mismatch');
      if (file.destination!='ALL' && file.destination!=normalizeFileCallsign(local)) return;
      FileTransfer? t;
      for (final v in transfers) {
        if (!v.outgoing && v.link.key==link.key && v.source==source && v.file.fileId==file.fileId) t=v;
      }
      if (t==null) {
        final offers=transfers.where((v)=>!v.outgoing && v.state==FileTransferState.offering).toList();
        final fromSource=offers.where((v)=>v.source==source).toList();
        if (fromSource.length>=5) transfers.remove(fromSource.first);
        if (offers.length>=20) transfers.remove(offers.first);
        t=FileTransfer(
          id:'rx_${now.microsecondsSinceEpoch}_${random.nextInt(0x7fffffff)}',
          link:link,source:source,outgoing:false,file:file,created:now,
          state:FileTransferState.offering,
        );
        transfers.add(t);
      } else if (!listEquals(t.file.header,file.header)) {
        fail(t,'Conflicting file offer');
        return;
      }
      t.lastOffer=now;
      t.headerReply=true;
      t.requestFrames=[];
      if (t.state==FileTransferState.rejected && now.difference(t.lastHeard).inSeconds>=60) {
        t.state=FileTransferState.offering;
      }
      if (t.state==FileTransferState.rejected || t.state==FileTransferState.canceled) {
        t.nextAction=_requestTime(t,now,checkIn:true);
      } else if (t.state==FileTransferState.completed) {
        t.completionReports=0;
        t.nextAction=_requestTime(t,now,checkIn:true);
      } else if (t.accepted && t.buffer!=null && t.state!=FileTransferState.verifying) {
        t.state=FileTransferState.receiving;
        t.lastHeard=now;
        t.reminders=0;
        t.nextAction=_requestTime(t,now,checkIn:true);
        _finishIfReady(t);
      }
      changed();
      return;
    }
    for (final t in transfers) {
      if (t.outgoing || t.link.key!=link.key || t.source!=source ||
          t.file.fileId!=piece.fileId || !t.accepted || t.buffer==null ||
          t.terminal || t.state==FileTransferState.verifying) {
        continue;
      }
      if (piece.fileType!=t.file.fileType ||
          (piece.last && piece.offset+piece.bytes.length!=t.file.size)) {
        fail(t,'File piece type or final offset mismatch');
        return;
      }
      final count=t.buffer!.received;
      t.buffer!.add(piece.offset,piece.bytes);
      final previous=t.previousPiece;
      if (previous!=null && t.buffer!.received>count) {
        final ms=now.difference(previous).inMilliseconds;
        if (ms>100 && ms<10000) {
          t.rate=(t.rate*0.75+piece.bytes.length*1000/ms*0.25).clamp(20,1200);
          t.measured=true;
        }
      }
      if (t.buffer!.received>count) t.previousPiece=now;
      t.transferred=t.buffer!.received;
      t.state=FileTransferState.receiving;
      t.lastHeard=now;
      t.reminders=0;
      if (t.requestFrames.isEmpty) {
        t.nextAction=now.add(const Duration(seconds:20));
        t.headerReply=false;
      }
      _finishIfReady(t);
      changed();
    }
  }

  void _finishIfReady(FileTransfer t) {
    if (!t.buffer!.complete) return;
    try {
      final content=t.file.verify(t.buffer!.bytes);
      t.state=FileTransferState.verifying;
      receivedFile(t,content);
    } on FormatException catch(e) {
      fail(t,e.message);
    }
  }

  void completeReceive(FileTransfer t, String path, DateTime now) {
    if (t.state!=FileTransferState.verifying) return;
    t.savedPath=path;
    t.state=FileTransferState.completed;
    t.transferred=t.file.size;
    t.buffer=null;
    t.requestFrames=[];
    t.headerReply=true;
    t.completionReports=0;
    t.nextAction=_requestTime(t,now,checkIn:true);
    changed();
  }

  void receiveRequest(FileTransferLink link, String source,
      PacsatRequest request, DateTime now) {
    source=normalizeFileCallsign(source);
    hear(link,source,now);
    for (final t in transfers) {
      if (!t.outgoing || t.link.key!=link.key || t.file.fileId!=request.fileId ||
          t.file.destination!=source || t.terminal || t.state==FileTransferState.queued) {
        continue;
      }
      if (t.state==FileTransferState.paused) return;
      if (t.state==FileTransferState.noResponse &&
          now.difference(t.lastHeard).inMinutes>=10) {
        return;
      }
      if (request.holes.any((h)=>h.end>t.file.size)) {
        throw const FormatException('Requested hole outside file');
      }
      t.lastHeard=now;
      if (t.waiting && t.rateStarted!=null) {
        final ms=now.difference(t.rateStarted!).inMilliseconds;
        if (ms>500 && t.airBytes>0) {
          t.rate=(t.rate*0.75+t.airBytes*1000/ms*0.25).clamp(20,1200);
          t.measured=true;
        }
        t.rateStarted=null;
        t.airBytes=0;
      }
      t.error=null;
      t.missedCheckIns=0;
      t.checkRetries=0;
      if (request.command==1) {
        cancelPackets(t);
        t.state=FileTransferState.rejected;
        t.buffer=null;
      } else if (request.command==2 && request.holes.isEmpty) {
        cancelPackets(t);
        t.state=FileTransferState.completed;
        t.transferred=t.file.size;
        t.buffer=null;
      } else {
        final starting=t.state==FileTransferState.offering || t.state==FileTransferState.noResponse;
        t.state=FileTransferState.sending;
        if (request.command==0) {
          t.pending=[FileHole(0,t.file.size)];
          t.waiting=false;
          t.nextAction=now.add(const Duration(milliseconds:500));
        } else {
          if (starting || t.replyAt==null) t.replies=[];
          t.replies.addAll(request.holes);
          t.replyAt=now;
          t.waiting=true;
          t.nextAction=now.add(Duration(milliseconds:max(3000,(1.6*270000/t.rate).ceil())));
        }
        // Piece-size negotiation is kept in the pending splitter.
        _pieceSizes[t.id]=request.pieceSize;
      }
      changed();
    }
  }
  final Map<String,int> _pieceSizes={};

  bool _send(FileTransfer t, int pid, String to, Uint8List bytes, DateTime now) {
    if (!send(t,pid,to,bytes)) {
      fail(t,'Radio did not accept the file packet');
      return false;
    }
    if (t.outgoing) {
      t.rateStarted ??= now;
      t.airBytes+=bytes.length+18;
    }
    final duration=Duration(milliseconds:((bytes.length+18)*1000/t.rate).ceil()+300);
    _busyUntil[t.link.key]=now.add(duration);
    return true;
  }

  bool _directory(FileTransfer t, DateTime now) {
    for (var at=0;at<t.file.header.length;at+=237) {
      final end=min(at+237,t.file.header.length);
      if (!_send(t,0xbd,'QST-1',PacsatPiece(
        directory:true,last:end==t.file.header.length,fileId:t.file.fileId,
        offset:at,uploadTime:t.file.uploadTime,
        bytes:Uint8List.sublistView(t.file.header,at,end),
      ).encode(),now)) {
        return false;
      }
    }
    // Include every fragment's estimated drain, not just the last submission.
    _busyUntil[t.link.key]=now.add(Duration(milliseconds:
      ((t.file.header.length+35*((t.file.header.length+236)~/237))*1000/t.rate).ceil()+500));
    return true;
  }

  bool _quiet(FileTransfer t, DateTime now) {
    if ((_busyUntil[t.link.key]?.isAfter(now) ?? false)) return false;
    final heard=_heard[t.link.key];
    return heard==null || now.difference(heard).inMilliseconds>=500;
  }

  void tick(DateTime now) {
    if (_disposed) return;
    _peers.removeWhere((_,v)=>now.difference(v).inSeconds>=20);
    FileTransfer? active;
    for (final t in transfers) {
      if (t.outgoing && (t.state==FileTransferState.offering || t.state==FileTransferState.sending)) {
        active=t; break;
      }
    }
    for (final t in transfers.toList()) {
      if (!t.durable) continue;
      if (t.state==FileTransferState.paused && t.autoResumeUntil!=null &&
          now.isBefore(t.autoResumeUntil!) && available(t.link)) {
        act(t.id,'resume',now);
      }
      if (!t.outgoing) {
        if (t.state==FileTransferState.receiving && !available(t.link)) {
          t.state=FileTransferState.paused;
          t.error='Radio or transfer channel is unavailable';
          t.autoResumeUntil=now.add(const Duration(minutes:2));
          changed();
        }
        if (t.state==FileTransferState.offering && now.difference(t.lastOffer).inMinutes>=10) {
          t.state=FileTransferState.expired; changed();
        }
        if (t.state==FileTransferState.receiving && now.difference(t.lastHeard).inMinutes>=3) {
          t.state=FileTransferState.noResponse; changed();
        }
        final heard=_heard[t.link.key];
        final requestQuiet=t.headerReply || heard==null ||
          now.difference(heard).inMilliseconds>=max(2000,(1.6*250*1000/t.rate).ceil());
        if (!now.isBefore(t.nextAction) && available(t.link) && _quiet(t,now) && requestQuiet) {
          int? command;
          if (t.requestFrames.isNotEmpty) {
            command=2;
          } else if (t.state==FileTransferState.completed && t.completionReports<3) {
            command=2; t.completionReports++;
          } else if ((t.state==FileTransferState.rejected || t.state==FileTransferState.canceled) &&
              t.reminders==0) {
            command=1; t.reminders++;
          } else if (t.state==FileTransferState.receiving && t.reminders<7) {
            command=t.reminders==0 && t.buffer!.received==t.file.header.length ? 0 : 2;
            t.reminders++;
          }
          if (command!=null) {
            if (t.requestFrames.isEmpty) {
              final holes=command==2 ? t.buffer?.requestHoles() ?? <FileHole>[] : <FileHole>[];
              if (holes.isEmpty) {
                t.requestFrames.add(PacsatRequest(command,t.file.fileId).encode());
              } else {
                for (var at=0;at<holes.length;at+=49) {
                  t.requestFrames.add(PacsatRequest(2,t.file.fileId,
                    holes:holes.sublist(at,min(at+49,holes.length))).encode());
                }
              }
            }
            if (!_send(t,0xbb,t.source,t.requestFrames.removeAt(0),now)) continue;
            t.nextAction=t.requestFrames.isNotEmpty ? _busyUntil[t.link.key]! :
              now.add(Duration(seconds:t.state==FileTransferState.completed ? 15 : 20));
            changed();
          }
        }
        continue;
      }
      if (t.state==FileTransferState.queued && active==null &&
          t.durable && available(t.link) && !_peers.keys.any((k)=>k.startsWith('${t.link.key}|'))) {
        t.state=FileTransferState.offering;
        t.lastOffer=now;
        t.nextAction=now;
        active=t;
        changed();
      }
      if (t!=active || now.isBefore(t.nextAction) || !_quiet(t,now)) continue;
      if (!available(t.link)) {
        cancelPackets(t);
        t.state=FileTransferState.paused;
        t.error='Radio, channel, callsign or transmit permission changed';
        t.autoResumeUntil=now.add(const Duration(minutes:2));
        changed();
        continue;
      }
      if (_peers.keys.any((k)=>k.startsWith('${t.link.key}|') &&
          k.split('|').last.compareTo(t.source)<0)) {
        continue;
      }
      if (t.state==FileTransferState.offering) {
        if (now.difference(t.lastOffer).inSeconds>=120) {
          t.state=FileTransferState.noResponse;
          t.lastHeard=now;
          changed();
        } else if (t.offers<4) {
          _directory(t,now);
          t.offers++;
          t.nextAction=now.add(const Duration(seconds:10));
          changed();
        }
        continue;
      }
      if (t.state!=FileTransferState.sending) continue;
      if (t.replyAt!=null) {
        final sorted=t.replies.toList()..sort((a,b)=>a.offset.compareTo(b.offset));
        final merged=<FileHole>[];
        for (final h in sorted) {
          if (merged.isNotEmpty && h.offset<=merged.last.end) {
            final last=merged.removeLast();
            merged.add(FileHole(last.offset,max(last.end,h.end)-last.offset));
          } else { merged.add(h); }
        }
        t.pending=merged;
        t.transferred=t.file.size-merged.fold<int>(0,(n,h)=>n+h.length);
        t.replies=[];
        t.replyAt=null;
        t.waiting=false;
        t.piecesInBurst=0;
        changed();
      }
      if (t.waiting) {
        final maxRetries=t.measured ? 2 : 6;
        if (t.checkRetries<maxRetries) {
          _directory(t,now);
          t.checkRetries++;
          final seconds=t.checkRetries<=2 ? 4 : 4*(1<<(t.checkRetries-2));
          t.nextAction=_busyUntil[t.link.key]!.add(Duration(seconds:seconds));
        } else {
          t.checkRetries=0;
          t.missedCheckIns++;
          if (t.missedCheckIns>=3) {
            t.state=FileTransferState.noResponse;
            t.lastHeard=now;
            t.error='Three check-ins received no reply';
          } else {
            t.waiting=false;
          }
        }
        changed();
        continue;
      }
      final budget=max(1,(15*t.rate/pacsatPieceSize).floor());
      if (t.pending.isEmpty || t.piecesInBurst>=budget) {
        t.bursts++;
        t.piecesInBurst=0;
        if (t.pending.isEmpty || t.bursts==1 || t.bursts%4==0) {
          if (!_directory(t,now)) continue;
          t.waiting=true;
          t.nextAction=_busyUntil[t.link.key]!.add(const Duration(seconds:4));
        } else {
          t.nextAction=now.add(const Duration(seconds:2));
        }
        changed();
        continue;
      }
      final hole=t.pending.removeAt(0);
      final size=min(hole.length,_pieceSizes[t.id] ?? pacsatPieceSize);
      final end=hole.offset+size;
      if (size<hole.length) t.pending.insert(0,FileHole(end,hole.length-size));
      if (_send(t,0xbb,'QST-1',PacsatPiece(
        directory:false,last:end==t.file.size,fileId:t.file.fileId,
        fileType:t.file.fileType,offset:hole.offset,
        bytes:Uint8List.sublistView(t.buffer!.bytes,hole.offset,end),
      ).encode(),now)) {
        t.piecesInBurst++;
        t.nextAction=_busyUntil[t.link.key]!;
      }
    }
  }

  void fail(FileTransfer t, String error) {
    cancelPackets(t);
    t.requestFrames=[];
    t.state=FileTransferState.failed;
    t.error=error;
    changed();
  }

  void dispose() {
    _disposed=true;
    for (final t in transfers) {
      if (!t.terminal) cancelPackets(t);
    }
  }
}
