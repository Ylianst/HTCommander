import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../file_transfer/pacsat.dart';
import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';

class FileTransferDialog extends StatefulWidget {
  final int deviceId;
  const FileTransferDialog({super.key,required this.deviceId});
  @override
  State<FileTransferDialog> createState()=>_FileTransferDialogState();
}

class _FileTransferDialogState extends State<FileTransferDialog> {
  final _callsign=TextEditingController();
  final _broker=DataBrokerClient();
  final _form=GlobalKey<FormState>();
  PlatformFile? _file;
  bool _busy=false;
  String? _error;
  String? _requestId;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    _broker.subscribe(deviceId:1,name:'FileTransferCommandResult',callback:(_,_,data) {
      if (!mounted || data is! Map || data['requestId']!=_requestId) return;
      _timeout?.cancel();
      if (data['accepted']==true) {
        Navigator.of(context).pop();
      } else {
        setState(() { _busy=false; _error=data['error'] as String?; });
      }
    });
  }

  Future<void> _choose() async {
    try {
      final result=await FilePicker.pickFiles();
      if (!mounted || result==null) return;
      final file=result.files.single;
      setState(() {
        _file=file.size<=pacsatMaxOriginal ? file : null;
        _error=file.size>pacsatMaxOriginal ? AppLocalizations.of(context).fileTransferTooLarge : null;
      });
    } on PlatformException catch(e) {
      if (mounted) setState(()=>_error=e.message ?? e.code);
    }
  }

  Future<void> _transmit() async {
    if (_busy || _file==null || !_form.currentState!.validate()) return;
    setState(() { _busy=true; _error=null; });
    try {
      final file=_file!;
      final path=file.path;
      final bytes=file.bytes ?? (path!=null ? await File(path).readAsBytes() : null);
      if (bytes==null) throw const FileSystemException('Selected file could not be read');
      if (!mounted) return;
      _requestId='file-${DateTime.now().microsecondsSinceEpoch}';
      _timeout=Timer(const Duration(seconds:30),() {
        if (mounted) {
          setState(() {
          _busy=false;
          _error=AppLocalizations.of(context).fileTransferUnconfirmed;
        });
        }
      });
      _broker.dispatch(deviceId:1,name:'FileTransferSend',data:{
        'requestId':_requestId,'deviceId':widget.deviceId,
        'name':file.name,'destination':_callsign.text.trim(),
        'data':base64Encode(bytes),
      },store:false);
    } on FileSystemException catch(e) {
      if (mounted) setState(() { _busy=false; _error=e.message; });
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _broker.dispose();
    _callsign.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n=AppLocalizations.of(context);
    return AlertDialog(
      title:Text(l10n.commsTransferFile),
      content:SizedBox(width:460,child:SingleChildScrollView(child:Form(
        key:_form,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Text(l10n.fileTransferWarning),
            const SizedBox(height:16),
            OutlinedButton.icon(onPressed:_busy ? null : _choose,
              icon:const Icon(Icons.attach_file),label:Text(l10n.fileTransferChoose)),
            if (_file!=null) Text(l10n.fileTransferSelectedFile(_file!.name,_file!.size)),
            const SizedBox(height:12),
            TextFormField(controller:_callsign,enabled:!_busy,
              textCapitalization:TextCapitalization.characters,
              decoration:InputDecoration(labelText:l10n.fileTransferCallsign),
              validator:(value) {
                try {
                  final call=normalizeFileCallsign(value ?? '');
                  return call=='ALL' || call=='QST-1' ? l10n.aprsInvalidAddress : null;
                }
                on FormatException { return l10n.aprsInvalidAddress; }
              }),
            if (_busy) const Padding(padding:EdgeInsets.only(top:12),
              child:LinearProgressIndicator()),
            if (_error!=null) Padding(padding:const EdgeInsets.only(top:12),
              child:Text(l10n.fileTransferError(_error!),style:TextStyle(color:Theme.of(context).colorScheme.error))),
          ],
        ),
      ))),
      actions:[
        TextButton(onPressed:_busy ? null : ()=>Navigator.of(context).pop(),
          child:Text(l10n.commonCancel)),
        FilledButton(onPressed:_busy || _file==null ? null : _transmit,
          child:Text(l10n.fileTransferTransmit)),
      ],
    );
  }
}
