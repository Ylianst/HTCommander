/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

//
// aprs_cloud_service_stub.dart - No-op replacement compiled on the web, where
// Firebase Cloud Messaging and dart:io are unavailable. Mirrors the public API
// of the real AprsCloudService so main.dart can import it conditionally.
//

class AprsCloudService {
  AprsCloudService._();

  static final AprsCloudService instance = AprsCloudService._();

  void init() {}

  Future<void> dispose() async {}
}
