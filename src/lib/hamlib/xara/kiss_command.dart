/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

Ported from XARA (https://github.com/x0rro/xara), MIT License, (c) 2026 x0rro.
*/

/// KISS data commands carried by VARA unconnected frames.
enum KissCommand {
  ax25(0),
  ax25Long(1),
  generic(2);

  const KissCommand(this.byte);

  final int byte;

  static KissCommand? fromByte(int b) => b >= 0 && b <= 2 ? values[b] : null;
}
