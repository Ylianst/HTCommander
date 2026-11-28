import 'package:flutter/material.dart';

import '../file_transfer/file_transfer_engine.dart';
import '../l10n/app_localizations.dart';

class FileTransferCard extends StatelessWidget {
  final FileTransfer transfer;
  final ValueChanged<String> onAction;
  final VoidCallback? onSave;
  final bool enabled;
  const FileTransferCard({
    super.key, required this.transfer, required this.onAction, this.onSave,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n=AppLocalizations.of(context);
    final t=transfer;
    final status=switch(t.state) {
      FileTransferState.queued=>l10n.fileTransferQueued,
      FileTransferState.offering=>t.outgoing ? l10n.fileTransferOutgoingOffer : l10n.fileTransferIncomingOffer,
      FileTransferState.receiving=>l10n.fileTransferReceiving,
      FileTransferState.sending=>l10n.fileTransferSending,
      FileTransferState.verifying=>l10n.fileTransferVerifying,
      FileTransferState.completed=>l10n.fileTransferCompleted,
      FileTransferState.rejected=>l10n.fileTransferRejected,
      FileTransferState.canceled=>l10n.fileTransferCanceled,
      FileTransferState.noResponse=>l10n.fileTransferNoResponse,
      FileTransferState.paused=>l10n.fileTransferPaused,
      FileTransferState.expired=>l10n.fileTransferExpired,
      FileTransferState.failed=>l10n.fileTransferFailed,
    };
    final progress=t.state==FileTransferState.receiving ||
      t.state==FileTransferState.sending || t.state==FileTransferState.verifying ||
      t.canResume;
    return SizedBox(
      width:380,
      child:Column(
        mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          Text(t.file.name,style:const TextStyle(fontWeight:FontWeight.bold)),
          const SizedBox(height:4),
          Text(l10n.fileTransferSize(t.file.originalSize,t.file.bodySize)),
          Text(status,style:const TextStyle(fontWeight:FontWeight.w600)),
          if (t.state==FileTransferState.canceled) Text(l10n.fileTransferCancelNote),
          if (progress) ...[
            const SizedBox(height:8),
            LinearProgressIndicator(value:t.state==FileTransferState.verifying ? null :
              (t.transferred/t.file.size).clamp(0,1)),
            const SizedBox(height:4),
            Text(l10n.fileTransferProgress(t.transferred,t.file.size)),
          ],
          if (t.error!=null) Text(t.error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
          const SizedBox(height:8),
          Wrap(spacing:8,runSpacing:4,children:[
            if (!t.outgoing && t.state==FileTransferState.offering) ...[
              FilledButton(onPressed:enabled ? ()=>onAction('accept') : null,child:Text(l10n.fileTransferAccept)),
              TextButton(onPressed:enabled ? ()=>onAction('reject') : null,child:Text(l10n.fileTransferReject)),
            ] else if (t.canCancel)
              TextButton(onPressed:enabled ? ()=>onAction('cancel') : null,child:Text(l10n.commonCancel)),
            if (t.canResume)
              FilledButton(onPressed:enabled ? ()=>onAction('resume') : null,child:Text(l10n.fileTransferResume)),
            if (!t.outgoing && t.state==FileTransferState.completed && onSave!=null)
              FilledButton(onPressed:onSave,child:Text(l10n.fileTransferSave)),
          ]),
        ],
      ),
    );
  }
}
