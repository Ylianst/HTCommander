// Initialisation bridge to satellite_observer 1.0.1, Copyright (c) 2026
// Maciej Starosielec, MIT; see native/satellite_sgp4.LICENSE.
// The package's Vallado/python-sgp4 initialiser remains the single source of
// truth for both near-earth and deep-space coefficients.
// ignore_for_file: implementation_imports
import 'dart:typed_data';

import 'package:satellite_observer/satellite_observer.dart' as so;
import 'package:satellite_observer/src/propagation/sgp4/gravity_constants.dart';
import 'package:satellite_observer/src/propagation/sgp4/sgp4_init.dart';
import 'package:satellite_observer/src/propagation/sgp4/sgp4_satellite.dart';

Float64List satelliteCoefficients(so.GpElements elements) {
  final s = Sgp4Satellite(GravityConstants.of(so.GravityModel.wgs72))
    ..operationmode = 'i'
    ..bstar = elements.bStar
    ..ndot = elements.meanMotionDot
    ..nddot = elements.meanMotionDdot
    ..ecco = elements.eccentricity
    ..argpo = elements.argPerigeeRad
    ..inclo = elements.inclinationRad
    ..mo = elements.meanAnomalyRad
    ..noKozai = elements.meanMotionRadPerMin
    ..nodeo = elements.raanRad;
  final e = elements.epoch.toUtc();
  final secOfDay =
      e.hour * 3600.0 +
      e.minute * 60.0 +
      e.second +
      e.millisecond / 1.0e3 +
      e.microsecond / 1.0e6;
  final jd =
      367.0 * e.year -
      ((7 * (e.year + ((e.month + 9) ~/ 12))) ~/ 4) +
      ((275 * e.month) ~/ 9) +
      e.day +
      1721013.5 +
      secOfDay / 86400.0;
  s.epochDays1950 = jd - 2433281.5;
  sgp4init(s, epoch: s.epochDays1950);
  // Coefficient order shared with FIELDS in satellite_sgp4.cpp (ABI 2).
  return Float64List.fromList([
    s.bstar,
    s.ecco,
    s.argpo,
    s.inclo,
    s.mo,
    s.noUnkozai,
    s.nodeo,
    s.isimp.toDouble(),
    s.method == 'd' ? 1.0 : 0.0,
    s.aycof,
    s.con41,
    s.cc1,
    s.cc4,
    s.cc5,
    s.d2,
    s.d3,
    s.d4,
    s.delmo,
    s.eta,
    s.argpdot,
    s.omgcof,
    s.sinmao,
    s.t2cof,
    s.t3cof,
    s.t4cof,
    s.t5cof,
    s.x1mth2,
    s.x7thm1,
    s.mdot,
    s.nodedot,
    s.xlcof,
    s.xmcof,
    s.nodecf,
    s.gsto,
    s.irez.toDouble(),
    s.d2201,
    s.d2211,
    s.d3210,
    s.d3222,
    s.d4410,
    s.d4422,
    s.d5220,
    s.d5232,
    s.d5421,
    s.d5433,
    s.dedt,
    s.del1,
    s.del2,
    s.del3,
    s.didt,
    s.dmdt,
    s.dnodt,
    s.domdt,
    s.e3,
    s.ee2,
    s.peo,
    s.pgho,
    s.pho,
    s.pinco,
    s.plo,
    s.se2,
    s.se3,
    s.sgh2,
    s.sgh3,
    s.sgh4,
    s.sh2,
    s.sh3,
    s.si2,
    s.si3,
    s.sl2,
    s.sl3,
    s.sl4,
    s.xfact,
    s.xgh2,
    s.xgh3,
    s.xgh4,
    s.xh2,
    s.xh3,
    s.xi2,
    s.xi3,
    s.xl2,
    s.xl3,
    s.xl4,
    s.xlamo,
    s.zmol,
    s.zmos,
    s.atime,
    s.xli,
    s.xni,
    s.constants.radiusearthkm,
    s.constants.xke,
    s.constants.j2,
    s.constants.j3oj2,
  ]);
}
