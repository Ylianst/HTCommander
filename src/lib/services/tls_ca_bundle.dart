/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Shared TLS fallback for runtime downloads. Some machines have an outdated or
broken operating-system trust store and fail to verify legitimate certificate
chains (raising a HandshakeException). Callers try their normal client first —
so the OS store, including any corporate/antivirus proxy roots, is honored — and
only on a handshake failure retry with a SecurityContext that trusts the bundled
Mozilla CA roots (assets/certs/cacert.pem). Verification is never disabled.
*/

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Bundled Mozilla CA roots asset. Refresh via docs/CA-Bundle-Update.md.
const String _caBundleAsset = 'assets/certs/cacert.pem';

SecurityContext? _bundledRoots;
bool _bundledRootsLoaded = false;

/// Lazily builds a [SecurityContext] that trusts only the bundled Mozilla CA
/// roots. Used as a fallback when the machine's own trust store can't verify a
/// server's chain. Returns null if the asset can't be loaded. Cached across
/// calls (including a failed load, which is not retried).
///
/// Do not combine the bundle with `withTrustedRoots: true`: BoringSSL rejects a
/// root already present in the built-in set with `CERT_ALREADY_IN_HASH_TABLE`.
Future<SecurityContext?> bundledCaRootsContext() async {
  if (_bundledRootsLoaded) return _bundledRoots;
  _bundledRootsLoaded = true;
  try {
    final pem = await rootBundle.load(_caBundleAsset);
    _bundledRoots = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(pem.buffer.asUint8List());
  } catch (e) {
    debugPrint('bundledCaRootsContext: CA bundle load failed: $e');
    _bundledRoots = null;
  }
  return _bundledRoots;
}
