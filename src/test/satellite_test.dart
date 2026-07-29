/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/satellite/satellite_models.dart';
import 'package:satellite_observer/satellite_observer.dart';

// The bundled seed TLE (assets/satellites/amateur.tle) as a raw 3LE block.
const String _seedTle = '''
ISS (ZARYA)
1 25544U 98067A   26209.15252568  .00010831  00000+0  20282-3 0  9992
2 25544  51.6320  97.3682 0007093 345.6120  14.4666 15.49220842578109
SAUDISAT 1C (SO-50)
1 27607U 02058C   26208.68108592  .00001287  00000+0  16839-3 0  9991
2 27607  64.5529   3.6894 0074146 254.9838 104.3054 14.83123076270467
DIWATA-2B
1 43678U 18084H   26209.18059542  .00001598  00000+0  13154-3 0  9991
2 43678  98.1218  47.1878 0011937  43.4683 316.7478 15.00603078422366
RADFXSAT (FOX-1B)
1 43017U 17073E   26209.14690911  .00007868  00000+0  33964-3 0  9999
2 43017  97.4653  75.5276 0148916 186.4494 173.4825 15.13224540471580
LILACSAT-2
1 40908U 15049K   26209.21111516  .00020547  00000+0  33290-3 0  9994
2 40908  97.4620 247.6414 0008677 103.7627 256.4592 15.52779418602115
TEVEL2-3
1 63218U 25052J   26209.18813017  .00022063  00000+0  64589-3 0  9999
2 63218  97.3830 105.1983 0002696  38.5202 321.6233 15.35247884 76383
''';

void main() {
  group('SatelliteTle.parseThreeLine', () {
    test('parses every seed satellite with the right NORAD ids', () {
      final tles = SatelliteTle.parseThreeLine(_seedTle);
      expect(tles.length, 6);
      expect(
        tles.map((t) => t.noradId).toList(),
        [25544, 27607, 43678, 43017, 40908, 63218],
      );
      expect(tles.first.name, 'ISS (ZARYA)');
      expect(tles.first.line1.startsWith('1 25544'), isTrue);
      expect(tles.first.line2.startsWith('2 25544'), isTrue);
    });

    test('ignores malformed / partial triples without throwing', () {
      final tles = SatelliteTle.parseThreeLine('GARBAGE\n1 only one line\n');
      expect(tles, isEmpty);
    });
  });

  group('SGP4 propagation via satellite_observer', () {
    test('ISS seed TLE yields a plausible LEO sub-point', () {
      final iss =
          SatelliteTle.parseThreeLine(_seedTle).firstWhere((t) => t.noradId == 25544);
      final elements = GpElements.fromTle(iss.line1, iss.line2, name: iss.name);
      final observer = SatelliteObserver(
        elements: elements,
        observer: Observer(latitudeDeg: 47.6, longitudeDeg: -122.3),
      );

      // Propagate at the element epoch so SGP4 error is minimal.
      final sub = observer.subPointAt(elements.epoch);
      expect(sub.latitudeDeg, inInclusiveRange(-90, 90));
      expect(sub.longitudeDeg, inInclusiveRange(-180, 180));
      // The ISS orbits at roughly 400-430 km altitude.
      expect(sub.altitudeKm, inInclusiveRange(300, 500));

      final look = observer.lookAngleAt(elements.epoch);
      expect(look.azimuthDeg, inInclusiveRange(0, 360));
      expect(look.elevationDeg, inInclusiveRange(-90, 90));
      expect(look.rangeKm, greaterThan(0));
    });
  });

  group('SatelliteInfo Doppler correction', () {
    SatelliteInfo makeInfo() {
      final tle = SatelliteTle.parseThreeLine(_seedTle)
          .firstWhere((t) => t.noradId == 25544);
      const transponder = SatelliteTransponder(
        noradId: 25544,
        name: 'ISS',
        uplinkHz: 145990000,
        downlinkHz: 437800000,
        mode: 'FM',
        ctcssHz: 67.0,
        inverting: false,
        status: 'active',
      );
      return SatelliteInfo(tle: tle, transponder: transponder);
    }

    test('receding satellite lowers RX and raises TX', () {
      final info = makeInfo();
      const receding = 5.0; // km/s, moving away
      final rx = info.correctedDownlinkHz(receding)!;
      final tx = info.correctedUplinkHz(receding)!;
      expect(rx, lessThan(437800000));
      expect(tx, greaterThan(145990000));
    });

    test('approaching satellite raises RX and lowers TX', () {
      final info = makeInfo();
      const approaching = -5.0; // km/s, closing in
      final rx = info.correctedDownlinkHz(approaching)!;
      final tx = info.correctedUplinkHz(approaching)!;
      expect(rx, greaterThan(437800000));
      expect(tx, lessThan(145990000));
    });

    test('UHF Doppler at 5 km/s is roughly 7 kHz', () {
      final info = makeInfo();
      final shift = 437800000 - info.correctedDownlinkHz(5.0)!;
      // f * v / c = 437.8e6 * 5 / 299792.458 ~= 7303 Hz.
      expect(shift, inInclusiveRange(7000, 7600));
    });

    test('zero range rate leaves frequencies unchanged', () {
      final info = makeInfo();
      expect(info.correctedDownlinkHz(0), 437800000);
      expect(info.correctedUplinkHz(0), 145990000);
    });
  });
}
