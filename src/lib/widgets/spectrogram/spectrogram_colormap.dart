/*
Colormaps for the spectrogram widget.

The C# Spectrogram component maps an 8-bit intensity (0..255) to an RGB color
using ScottPlot colormaps (Viridis, Magma, etc.). Here we reproduce the most
useful ones with compact analytic polynomial approximations (public-domain
approximations by Matt Zucker) instead of shipping large 256-entry tables.

Each colormap precomputes three 256-entry byte lookup tables on construction so
per-pixel mapping during rendering is a single array index.
*/

import 'dart:typed_data';

/// Maps an intensity value (0..255) to an RGB color via a precomputed lookup.
class SpectrogramColormap {
  /// Human-readable name (matches the C# colormap names where possible).
  final String name;

  /// Red/green/blue lookup tables, each indexed by an intensity byte (0..255).
  final Uint8List r;
  final Uint8List g;
  final Uint8List b;

  SpectrogramColormap._(this.name, this.r, this.g, this.b);

  /// Build a colormap from a function returning normalized RGB (each 0..1) for
  /// a fraction in the range 0..1.
  factory SpectrogramColormap._fromFunction(
    String name,
    List<double> Function(double t) f,
  ) {
    final r = Uint8List(256);
    final g = Uint8List(256);
    final b = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      final rgb = f(i / 255.0);
      r[i] = _toByte(rgb[0]);
      g[i] = _toByte(rgb[1]);
      b[i] = _toByte(rgb[2]);
    }
    return SpectrogramColormap._(name, r, g, b);
  }

  static int _toByte(double v) {
    final x = (v * 255.0).round();
    if (x < 0) return 0;
    if (x > 255) return 255;
    return x;
  }

  static double _poly(
    double t,
    double c0,
    double c1,
    double c2,
    double c3,
    double c4,
    double c5,
    double c6,
  ) => c0 + t * (c1 + t * (c2 + t * (c3 + t * (c4 + t * (c5 + t * c6)))));

  /// The default perceptually-uniform colormap (matches the C# default).
  static final SpectrogramColormap viridis = SpectrogramColormap._fromFunction(
    'Viridis',
    (t) => [
      _poly(
        t,
        0.2777273272,
        0.1050930431,
        -0.3308618287,
        -4.6342304990,
        6.2282699363,
        4.7763849977,
        -5.4354558559,
      ),
      _poly(
        t,
        0.0054073445,
        1.4046135299,
        0.2148475595,
        -5.7991009734,
        14.1799333668,
        -13.7451453777,
        4.6458526122,
      ),
      _poly(
        t,
        0.3340998053,
        1.3845901626,
        0.0950951630,
        -19.3324409563,
        56.6905526007,
        -65.3530326334,
        26.3124352496,
      ),
    ],
  );

  static final SpectrogramColormap magma = SpectrogramColormap._fromFunction(
    'Magma',
    (t) => [
      _poly(
        t,
        -0.0021364851,
        0.2516605407,
        8.3537172792,
        -27.6687330858,
        52.1761398123,
        -50.7685253647,
        18.6557050659,
      ),
      _poly(
        t,
        -0.0007496551,
        0.6775232437,
        -3.5777195150,
        14.2647307810,
        -27.9436060717,
        29.0465828213,
        -11.4897735200,
      ),
      _poly(
        t,
        -0.0053861279,
        2.4940265993,
        0.3144679030,
        -13.6492131881,
        12.9441694424,
        4.2341529938,
        -5.6019615087,
      ),
    ],
  );

  static final SpectrogramColormap inferno = SpectrogramColormap._fromFunction(
    'Inferno',
    (t) => [
      _poly(
        t,
        0.0002189404,
        0.1065134195,
        11.6024930825,
        -41.7039961314,
        77.1629356994,
        -71.3194282450,
        25.1311262248,
      ),
      _poly(
        t,
        0.0016510046,
        0.5639564368,
        -3.9728539657,
        17.4363988821,
        -33.4023589421,
        32.6260642640,
        -12.2426689524,
      ),
      _poly(
        t,
        -0.0194808984,
        3.9327123889,
        -15.9423941063,
        44.3541451987,
        -81.8073092574,
        73.2095198580,
        -23.0703250029,
      ),
    ],
  );

  static final SpectrogramColormap plasma = SpectrogramColormap._fromFunction(
    'Plasma',
    (t) => [
      _poly(
        t,
        0.0587323439,
        2.1765146342,
        -2.6894604765,
        6.1303483459,
        -11.1074361906,
        10.0230655765,
        -3.6587138428,
      ),
      _poly(
        t,
        0.0233367089,
        0.2383834171,
        -7.4558511357,
        42.3461881477,
        -82.6663110943,
        71.4136177010,
        -22.9315346546,
      ),
      _poly(
        t,
        0.5433401827,
        0.7539604600,
        3.1107999397,
        -28.5188546533,
        60.1398476742,
        -54.0721865556,
        18.1919077854,
      ),
    ],
  );

  /// Plain grayscale (intensity to white).
  static final SpectrogramColormap grayscale =
      SpectrogramColormap._fromFunction('Grayscale', (t) => [t, t, t]);

  /// All built-in colormaps, in display order.
  static final List<SpectrogramColormap> all = [
    viridis,
    magma,
    inferno,
    plasma,
    grayscale,
  ];

  /// Look up a colormap by [name] (case-insensitive); returns [viridis] when
  /// no match is found.
  static SpectrogramColormap byName(String name) {
    for (final cmap in all) {
      if (cmap.name.toLowerCase() == name.toLowerCase()) return cmap;
    }
    return viridis;
  }
}
