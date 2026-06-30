/*
Schmitt Trigger
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

class SchmittTrigger {
  final double _low;
  final double _high;
  bool _previous = false;

  SchmittTrigger(this._low, this._high);

  bool latch(double input) {
    if (_previous) {
      if (input < _low) _previous = false;
    } else {
      if (input > _high) _previous = true;
    }
    return _previous;
  }
}
