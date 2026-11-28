/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

enum AprsLinkPolicy {
  automatic,
  rfOnly,
  internetOnly,
  both;

  bool get permitsRf => this == rfOnly || this == both;
  bool get permitsInternet => this == internetOnly || this == both;

  AprsLinkPolicy resolve({required int radioDeviceId, required bool internetEnabled}) {
    if (this != automatic) return this;
    if (radioDeviceId < 0) return internetOnly;
    return internetEnabled ? both : rfOnly;
  }
}
