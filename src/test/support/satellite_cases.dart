// Vallado verification TLEs: public-domain AIAA 2006-6753 reference data,
// inspected in the installed satellite_observer 1.0.1 verification fixtures.
import 'package:htcommander/satellite/satellite_models.dart';
import 'package:satellite_observer/satellite_observer.dart' as so;

const satelliteCases = [
  SatelliteTle(
    name: 'Vanguard',
    noradId: 5,
    line1:
        '1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753',
    line2:
        '2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667',
  ),
  SatelliteTle(
    name: 'ISS',
    noradId: 25544,
    line1:
        '1 25544U 98067A   26209.15252568  .00010831  00000+0  20282-3 0  9992',
    line2:
        '2 25544  51.6320  97.3682 0007093 345.6120  14.4666 15.49220842578109',
  ),
  SatelliteTle(
    name: 'Molniya resonant HEO',
    noradId: 8195,
    line1:
        '1 08195U 75081A   06176.33215444  .00000099  00000-0  11873-3 0   813',
    line2:
        '2 08195  64.1586 279.0717 6877146 264.7651  20.2257  2.00491383225656',
  ),
  SatelliteTle(
    name: 'GPS nonresonant MEO',
    noradId: 28129,
    line1:
        '1 28129U 03058A   06175.57071136 -.00000104  00000-0  10000-3 0   459',
    line2:
        '2 28129  54.7298 324.8098 0048506 266.2640  93.1663  2.00562768 18443',
  ),
  SatelliteTle(
    name: 'ITALSAT inclined GEO',
    noradId: 24208,
    line1:
        '1 24208U 96044A   06177.04061740 -.00000094  00000-0  10000-3 0  1600',
    line2:
        '2 24208   3.8536  80.0121 0026640 311.0977  48.3000  1.00778054 36119',
  ),
  SatelliteTle(
    name: 'AMC-4 low inclination GEO',
    noradId: 25954,
    line1:
        '1 25954U 99060A   04039.68057285 -.00000108  00000-0  00000-0 0  6847',
    line2:
        '2 25954   0.0004 243.8136 0001765  15.5294  22.7134  1.00271289 15615',
  ),
  SatelliteTle(
    name: 'Lyddane negative-time',
    noradId: 4632,
    line1:
        '1 04632U 70093B   04031.91070959 -.00000084  00000-0  10000-3 0  9955',
    line2:
        '2 04632  11.4628 273.1101 1450506 207.6000 143.9350  1.20231981 44145',
  ),
];

const decayingSatellite = SatelliteTle(
  name: 'Minotaur decay',
  noradId: 28872,
  line1:
      '1 28872U 05037B   05333.02012661  .25992681  00000-0  24476-3 0  1534',
  line2:
      '2 28872  96.4736 157.9986 0303955 244.0492 110.6523 16.46015938 10708',
);

so.GpElements elementsFor(SatelliteTle tle) =>
    so.GpElements.fromTle(tle.line1, tle.line2, name: tle.name);
