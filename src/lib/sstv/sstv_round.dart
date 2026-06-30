/*
Rounding helper that mirrors .NET's Math.Round / MathF.Round default behavior
(MidpointRounding.ToEven, a.k.a. banker's rounding). Dart's double.round()
rounds halves away from zero, which would shift some sample-timing values by
one sample compared to the C# reference, so the SSTV port uses this helper
everywhere the C# code used (int)Math.Round(...).
*/

int sstvRound(double v) {
  final floor = v.floorToDouble();
  final diff = v - floor;
  if (diff < 0.5) return floor.toInt();
  if (diff > 0.5) return floor.toInt() + 1;
  // Exactly halfway: round to the nearest even integer.
  final fi = floor.toInt();
  return fi.isEven ? fi : fi + 1;
}
