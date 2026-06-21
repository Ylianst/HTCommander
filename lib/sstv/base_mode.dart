/*
Base class for all modes
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:typed_data';
import 'i_mode.dart';

abstract class BaseMode implements IMode {
  @override
  Int32List postProcessScopeImage(Int32List pixels, int width, int height) =>
      pixels;
}
