/*
Simple Moving Sum
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'dart:typed_data';

class SimpleMovingSum {
  final Float64List _tree;
  int _leaf;
  final int length;

  SimpleMovingSum(this.length)
    : _tree = Float64List(2 * length),
      _leaf = length;

  void add(double input) {
    _tree[_leaf] = input;
    for (
      int child = _leaf, parent = _leaf ~/ 2;
      parent > 0;
      child = parent, parent ~/= 2
    ) {
      _tree[parent] = _tree[child] + _tree[child ^ 1];
    }
    if (++_leaf >= _tree.length) _leaf = length;
  }

  double sum() => _tree[1];

  double sumInput(double input) {
    add(input);
    return sum();
  }
}
