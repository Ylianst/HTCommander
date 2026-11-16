// Numerical translation of satellite_observer 1.0.1 sgp4_core.dart,
// deep_space.dart (dpper/dspace), GMST and topocentric transforms,
// Copyright (c) 2026 Maciej Starosielec, MIT.
// Ported there from MIT-licensed python-sgp4 (Brandon Rhodes), derived from
// Vallado, Crawford, Hujsak, Kelso, "Revisiting Spacetrack Report #3",
// AIAA 2006-6753 (public-domain reference). See satellite_sgp4.LICENSE.
//
// Initialisation remains in the original Dart package. No orbital model,
// gravity constant, integration step or convergence policy is approximated.
#include <cmath>
#include <new>
#include <cstdint>

#if defined(_WIN32)
#define EXPORT extern "C" __declspec(dllexport)
#else
#define EXPORT extern "C" __attribute__((visibility("default")))
#endif

namespace {
constexpr double pi = 3.14159265358979323846;
constexpr double twopi = 2.0 * pi;
constexpr int capacity = 256;
// This order is the ABI with satellite_coefficients.dart.
#define FIELDS(X) \
 X(bstar) X(ecco) X(argpo) X(inclo) X(mo) X(noUnkozai) X(nodeo) \
 X(isimp) X(method) X(aycof) X(con41) X(cc1) X(cc4) X(cc5) \
 X(d2) X(d3) X(d4) X(delmo) X(eta) X(argpdot) X(omgcof) X(sinmao) \
 X(t2cof) X(t3cof) X(t4cof) X(t5cof) X(x1mth2) X(x7thm1) X(mdot) \
 X(nodedot) X(xlcof) X(xmcof) X(nodecf) X(gsto) X(irez) \
 X(d2201) X(d2211) X(d3210) X(d3222) X(d4410) X(d4422) X(d5220) \
 X(d5232) X(d5421) X(d5433) X(dedt) X(del1) X(del2) X(del3) \
 X(didt) X(dmdt) X(dnodt) X(domdt) X(e3) X(ee2) X(peo) X(pgho) \
 X(pho) X(pinco) X(plo) X(se2) X(se3) X(sgh2) X(sgh3) X(sgh4) \
 X(sh2) X(sh3) X(si2) X(si3) X(sl2) X(sl3) X(sl4) X(xfact) \
 X(xgh2) X(xgh3) X(xgh4) X(xh2) X(xh3) X(xi2) X(xi3) X(xl2) \
 X(xl3) X(xl4) X(xlamo) X(zmol) X(zmos) X(atime) X(xli) X(xni) \
 X(radiusearthkm) X(xke) X(j2) X(j3oj2)
#define DECLARE(name) double name = 0.0;
struct Satellite { FIELDS(DECLARE) double t = 0.0; };
#undef DECLARE
#define COUNT(name) + 1
constexpr int coefficientCount = 0 FIELDS(COUNT);
#undef COUNT

// Dart % is Euclidean, unlike C++ fmod for negative operands. In particular
// negative-time SDP4/Lyddane cases require this exact distinction.
double mod(double x) {
  double r = std::fmod(x, twopi);
  if (r < 0.0) r += twopi;
  return r == 0.0 ? 0.0 : r;
}

void dspace(Satellite& s, double& em, double& argpm, double& inclm,
            double& mm, double& nodem, double& nm) {
  constexpr double fasx2 = 0.13130908, fasx4 = 2.8843198, fasx6 = 0.37448087;
  constexpr double g22 = 5.7686396, g32 = 0.95240898, g44 = 1.8014998;
  constexpr double g52 = 1.0508330, g54 = 4.4108898;
  constexpr double rptim = 4.37526908801129966e-3;
  constexpr double stepp = 720.0, stepn = -720.0, step2 = 259200.0;
  const double no = s.noUnkozai, argpo = s.argpo, argpdot = s.argpdot;
  double atime = s.atime, xli = s.xli, xni = s.xni;
  const double theta = mod(s.gsto + s.t * rptim);
  em = em + s.dedt * s.t;
  inclm = inclm + s.didt * s.t;
  argpm = argpm + s.domdt * s.t;
  nodem = nodem + s.dnodt * s.t;
  mm = mm + s.dmdt * s.t;
  double ft = 0.0;
  if (s.irez != 0) {
    if (atime == 0.0 || s.t * atime <= 0.0 || std::abs(s.t) < std::abs(atime)) {
      atime = 0.0;
      xni = no;
      xli = s.xlamo;
    }
    const double delt = s.t > 0.0 ? stepp : stepn;
    int iretn = 381;
    double xndt = 0.0, xldot = 0.0, xnddt = 0.0;
    while (iretn == 381) {
      if (s.irez != 2) {
        xndt = s.del1 * std::sin(xli - fasx2) +
            s.del2 * std::sin(2.0 * (xli - fasx4)) +
            s.del3 * std::sin(3.0 * (xli - fasx6));
        xldot = xni + s.xfact;
        xnddt = s.del1 * std::cos(xli - fasx2) +
            2.0 * s.del2 * std::cos(2.0 * (xli - fasx4)) +
            3.0 * s.del3 * std::cos(3.0 * (xli - fasx6));
        xnddt = xnddt * xldot;
      } else {
        const double xomi = argpo + argpdot * atime;
        const double x2omi = xomi + xomi, x2li = xli + xli;
        xndt = s.d2201 * std::sin(x2omi + xli - g22) +
            s.d2211 * std::sin(xli - g22) +
            s.d3210 * std::sin(xomi + xli - g32) +
            s.d3222 * std::sin(-xomi + xli - g32) +
            s.d4410 * std::sin(x2omi + x2li - g44) +
            s.d4422 * std::sin(x2li - g44) +
            s.d5220 * std::sin(xomi + xli - g52) +
            s.d5232 * std::sin(-xomi + xli - g52) +
            s.d5421 * std::sin(xomi + x2li - g54) +
            s.d5433 * std::sin(-xomi + x2li - g54);
        xldot = xni + s.xfact;
        xnddt = s.d2201 * std::cos(x2omi + xli - g22) +
            s.d2211 * std::cos(xli - g22) +
            s.d3210 * std::cos(xomi + xli - g32) +
            s.d3222 * std::cos(-xomi + xli - g32) +
            s.d5220 * std::cos(xomi + xli - g52) +
            s.d5232 * std::cos(-xomi + xli - g52) +
            2.0 * (s.d4410 * std::cos(x2omi + x2li - g44) +
                    s.d4422 * std::cos(x2li - g44) +
                    s.d5421 * std::cos(xomi + x2li - g54) +
                    s.d5433 * std::cos(-xomi + x2li - g54));
        xnddt = xnddt * xldot;
      }
      if (std::abs(s.t - atime) >= stepp) {
        iretn = 381;
      } else {
        ft = s.t - atime;
        iretn = 0;
      }
      if (iretn == 381) {
        xli = xli + xldot * delt + xndt * step2;
        xni = xni + xndt * delt + xnddt * step2;
        atime = atime + delt;
      }
    }
    nm = xni + xndt * ft + xnddt * ft * ft * 0.5;
    const double xl = xli + xldot * ft + xndt * ft * ft * 0.5;
    if (s.irez != 1) {
      mm = xl - 2.0 * nodem + 2.0 * theta;
    } else {
      mm = xl - nodem - argpm + theta;
    }
    const double dndt = nm - no;
    nm = no + dndt;
  }
  s.atime = atime;
  s.xli = xli;
  s.xni = xni;
}

// sgp4Step only calls dpper with init='n', operationmode='i'.
void dpper(const Satellite& s, double& ep, double& inclp, double& nodep,
           double& argpp, double& mp) {
  constexpr double zns = 1.19459e-5, zes = 0.01675;
  constexpr double znl = 1.5835218e-4, zel = 0.05490;
  double zm = s.zmos + zns * s.t;
  double zf = zm + 2.0 * zes * std::sin(zm);
  double sinzf = std::sin(zf);
  double f2 = 0.5 * sinzf * sinzf - 0.25;
  double f3 = -0.5 * sinzf * std::cos(zf);
  const double ses = s.se2 * f2 + s.se3 * f3;
  const double sis = s.si2 * f2 + s.si3 * f3;
  const double sls = s.sl2 * f2 + s.sl3 * f3 + s.sl4 * sinzf;
  const double sghs = s.sgh2 * f2 + s.sgh3 * f3 + s.sgh4 * sinzf;
  const double shs = s.sh2 * f2 + s.sh3 * f3;
  zm = s.zmol + znl * s.t;
  zf = zm + 2.0 * zel * std::sin(zm);
  sinzf = std::sin(zf);
  f2 = 0.5 * sinzf * sinzf - 0.25;
  f3 = -0.5 * sinzf * std::cos(zf);
  const double sel = s.ee2 * f2 + s.e3 * f3;
  const double sil = s.xi2 * f2 + s.xi3 * f3;
  const double sll = s.xl2 * f2 + s.xl3 * f3 + s.xl4 * sinzf;
  const double sghl = s.xgh2 * f2 + s.xgh3 * f3 + s.xgh4 * sinzf;
  const double shll = s.xh2 * f2 + s.xh3 * f3;
  double pe = ses + sel, pinc = sis + sil, pl = sls + sll;
  double pgh = sghs + sghl, ph = shs + shll;
  pe = pe - s.peo;
  pinc = pinc - s.pinco;
  pl = pl - s.plo;
  pgh = pgh - s.pgho;
  ph = ph - s.pho;
  inclp = inclp + pinc;
  ep = ep + pe;
  const double sinip = std::sin(inclp), cosip = std::cos(inclp);
  if (inclp >= 0.2) {
    ph /= sinip;
    pgh -= cosip * ph;
    argpp += pgh;
    nodep += ph;
    mp += pl;
  } else {
    const double sinop = std::sin(nodep), cosop = std::cos(nodep);
    double alfdp = sinip * sinop, betdp = sinip * cosop;
    const double dalf = ph * cosop + pinc * cosip * sinop;
    const double dbet = -ph * sinop + pinc * cosip * cosop;
    alfdp = alfdp + dalf;
    betdp = betdp + dbet;
    nodep = nodep >= 0.0 ? mod(nodep) : -mod(-nodep);
    const double xls = mp + argpp + pl + pgh + (cosip - pinc * sinip) * nodep;
    const double xnoh = nodep;
    nodep = std::atan2(alfdp, betdp);
    if (std::abs(xnoh - nodep) > pi) {
      if (nodep < xnoh) nodep = nodep + twopi;
      else nodep = nodep - twopi;
    }
    mp += pl;
    argpp = xls - mp - cosip * nodep;
  }
}

int step(Satellite& s, double tsince, double* out) {
  constexpr double temp4 = 1.5e-12, x2o3 = 2.0 / 3.0;
  const double vkmpersec = s.radiusearthkm * s.xke / 60.0;
  s.t = tsince;
  const double xmdf = s.mo + s.mdot * s.t;
  const double argpdf = s.argpo + s.argpdot * s.t;
  const double nodedf = s.nodeo + s.nodedot * s.t;
  double argpm = argpdf, mm = xmdf;
  const double t2 = s.t * s.t;
  double nodem = nodedf + s.nodecf * t2;
  double tempa = 1.0 - s.cc1 * s.t;
  double tempe = s.bstar * s.cc4 * s.t;
  double templ = s.t2cof * t2;
  if (s.isimp != 1) {
    const double delomg = s.omgcof * s.t;
    const double delmtemp = 1.0 + s.eta * std::cos(xmdf);
    const double delm = s.xmcof * (delmtemp * delmtemp * delmtemp - s.delmo);
    const double temp = delomg + delm;
    mm = xmdf + temp;
    argpm = argpdf - temp;
    const double t3 = t2 * s.t, t4 = t3 * s.t;
    tempa = tempa - s.d2 * t2 - s.d3 * t3 - s.d4 * t4;
    tempe = tempe + s.bstar * s.cc5 * (std::sin(mm) - s.sinmao);
    templ = templ + s.t3cof * t3 + t4 * (s.t4cof + s.t * s.t5cof);
  }
  double nm = s.noUnkozai, em = s.ecco, inclm = s.inclo;
  if (s.method == 1) dspace(s, em, argpm, inclm, mm, nodem, nm);
  if (nm <= 0.0) return 2;
  const double am = std::pow(s.xke / nm, x2o3) * tempa * tempa;
  nm = s.xke / std::pow(am, 1.5);
  em = em - tempe;
  if (em >= 1.0 || em < -0.001) return 1;
  if (em < 1.0e-6) em = 1.0e-6;
  mm = mm + s.noUnkozai * templ;
  double xlm = mm + argpm + nodem;
  nodem = nodem >= 0.0 ? mod(nodem) : -mod(-nodem);
  argpm = mod(argpm);
  xlm = mod(xlm);
  mm = mod(xlm - argpm - nodem);
  const double sinim = std::sin(inclm), cosim = std::cos(inclm);
  double ep = em, xincp = inclm, argpp = argpm, nodep = nodem, mp = mm;
  double sinip = sinim, cosip = cosim;
  if (s.method == 1) {
    dpper(s, ep, xincp, nodep, argpp, mp);
    if (xincp < 0.0) {
      xincp = -xincp;
      nodep = nodep + pi;
      argpp = argpp - pi;
    }
    if (ep < 0.0 || ep > 1.0) return 3;
  }
  if (s.method == 1) {
    sinip = std::sin(xincp);
    cosip = std::cos(xincp);
    s.aycof = -0.5 * s.j3oj2 * sinip;
    if (std::abs(cosip + 1.0) > 1.5e-12) {
      s.xlcof = -0.25 * s.j3oj2 * sinip * (3.0 + 5.0 * cosip) / (1.0 + cosip);
    } else {
      s.xlcof = -0.25 * s.j3oj2 * sinip * (3.0 + 5.0 * cosip) / temp4;
    }
  }
  const double axnl = ep * std::cos(argpp);
  double temp = 1.0 / (am * (1.0 - ep * ep));
  const double aynl = ep * std::sin(argpp) + temp * s.aycof;
  const double xl = mp + argpp + nodep + temp * s.xlcof * axnl;
  const double u = mod(xl - nodep);
  double eo1 = u, tem5 = 9999.9, sineo1 = 0.0, coseo1 = 0.0;
  int ktr = 1;
  while (std::abs(tem5) >= 1.0e-12 && ktr <= 10) {
    sineo1 = std::sin(eo1);
    coseo1 = std::cos(eo1);
    tem5 = 1.0 - coseo1 * axnl - sineo1 * aynl;
    tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / tem5;
    if (std::abs(tem5) >= 0.95) tem5 = tem5 > 0.0 ? 0.95 : -0.95;
    eo1 = eo1 + tem5;
    ktr = ktr + 1;
  }
  const double ecose = axnl * coseo1 + aynl * sineo1;
  const double esine = axnl * sineo1 - aynl * coseo1;
  const double el2 = axnl * axnl + aynl * aynl;
  const double pl = am * (1.0 - el2);
  if (pl < 0.0) return 4;
  const double rl = am * (1.0 - ecose);
  const double rdotl = std::sqrt(am) * esine / rl;
  const double rvdotl = std::sqrt(pl) / rl;
  const double betal = std::sqrt(1.0 - el2);
  temp = esine / (1.0 + betal);
  const double sinu = am / rl * (sineo1 - aynl - axnl * temp);
  const double cosu = am / rl * (coseo1 - axnl + aynl * temp);
  double su = std::atan2(sinu, cosu);
  const double sin2u = (cosu + cosu) * sinu;
  const double cos2u = 1.0 - 2.0 * sinu * sinu;
  temp = 1.0 / pl;
  const double temp1 = 0.5 * s.j2 * temp, temp2 = temp1 * temp;
  if (s.method == 1) {
    const double cosisq = cosip * cosip;
    s.con41 = 3.0 * cosisq - 1.0;
    s.x1mth2 = 1.0 - cosisq;
    s.x7thm1 = 7.0 * cosisq - 1.0;
  }
  const double mrt = rl * (1.0 - 1.5 * temp2 * betal * s.con41) +
      0.5 * temp1 * s.x1mth2 * cos2u;
  su = su - 0.25 * temp2 * s.x7thm1 * sin2u;
  const double xnode = nodep + 1.5 * temp2 * cosip * sin2u;
  const double xinc = xincp + 1.5 * temp2 * cosip * sinip * cos2u;
  const double mvt = rdotl - nm * temp1 * s.x1mth2 * sin2u / s.xke;
  const double rvdot = rvdotl +
      nm * temp1 * (s.x1mth2 * cos2u + 1.5 * s.con41) / s.xke;
  const double sinsu = std::sin(su), cossu = std::cos(su);
  const double snod = std::sin(xnode), cnod = std::cos(xnode);
  const double sini = std::sin(xinc), cosi = std::cos(xinc);
  const double xmx = -snod * cosi, xmy = cnod * cosi;
  const double ux = xmx * sinsu + cnod * cossu;
  const double uy = xmy * sinsu + snod * cossu, uz = sini * sinsu;
  const double vx = xmx * cossu - cnod * sinsu;
  const double vy = xmy * cossu - snod * sinsu, vz = sini * cossu;
  const double mr = mrt * s.radiusearthkm;
  out[0] = mr * ux;
  out[1] = mr * uy;
  out[2] = mr * uz;
  out[3] = (mvt * ux + rvdot * vx) * vkmpersec;
  out[4] = (mvt * uy + rvdot * vy) * vkmpersec;
  out[5] = (mvt * uz + rvdot * vz) * vkmpersec;
  if (mrt < 1.0) return 6;
  for (int i = 0; i < 6; ++i) if (!std::isfinite(out[i])) return 99;
  return 0;
}

struct Engine {
  Satellite satellite;
  double coefficients[coefficientCount]{};
  double times[capacity]{};
  double rows[capacity * 7]{};
  double sinLat = 0.0, cosLat = 1.0, sinLon = 0.0, cosLon = 1.0;
  double obsX = 0.0, obsY = 0.0, obsZ = 0.0;
};

// Exact algebra/order of domain/time/gmst.dart's calendar Julian date.
// The integer JDN is equivalently Unix day + 2440588; retain the package's
// separate second/millisecond/microsecond additions for the fractional day.
double gmst(int64_t utcUs) {
  constexpr int64_t dayUs = 86400000000LL;
  int64_t day = utcUs / dayUs, rem = utcUs % dayUs;
  if (rem < 0) { --day; rem += dayUs; }
  const int hour = static_cast<int>(rem / 3600000000LL);
  rem %= 3600000000LL;
  const int minute = static_cast<int>(rem / 60000000LL);
  rem %= 60000000LL;
  const int second = static_cast<int>(rem / 1000000LL);
  rem %= 1000000LL;
  const int millisecond = static_cast<int>(rem / 1000LL);
  const int microsecond = static_cast<int>(rem % 1000LL);
  const double secondsOfDay = hour * 3600.0 + minute * 60.0 + second +
      millisecond / 1000.0 + microsecond / 1e6;
  const double jd = (day + 2440588) - 0.5 + secondsOfDay / 86400.0;
  const double t = (jd - 2451545.0) / 36525.0;
  const double gmstSeconds = 67310.54841 +
      (876600.0 * 3600.0 + 8640184.812866) * t +
      0.093104 * t * t - 6.2e-6 * t * t * t;
  double seconds = std::fmod(gmstSeconds, 86400.0);
  if (seconds < 0.0) seconds += 86400.0;
  return mod(seconds / 86400.0 * twopi);
}

void sez(const Engine& e, double x, double y, double z, double* out) {
  out[0] = e.sinLat * e.cosLon * x + e.sinLat * e.sinLon * y - e.cosLat * z;
  out[1] = -e.sinLon * x + e.cosLon * y;
  out[2] = e.cosLat * e.cosLon * x + e.cosLat * e.sinLon * y + e.sinLat * z;
}

int lookAngle(const Engine& e, int64_t utcUs, const double* state, double* out) {
  const double theta = gmst(utcUs), c = std::cos(theta), s = std::sin(theta);
  const double x = c * state[0] + s * state[1];
  const double y = -s * state[0] + c * state[1], z = state[2];
  double relative[3];
  sez(e, x - e.obsX, y - e.obsY, z - e.obsZ, relative);
  const double range = std::sqrt(relative[0] * relative[0] +
      relative[1] * relative[1] + relative[2] * relative[2]);
  // Private wire status, decoded as the original GeometryException in Dart.
  if (range == 0.0 || !std::isfinite(range)) return 100;
  constexpr double omega = 7.292115146706979e-5;
  const double vxRot = c * state[3] + s * state[4];
  const double vyRot = -s * state[3] + c * state[4];
  double velocity[3];
  sez(e, vxRot + omega * y, vyRot - omega * x, state[5], velocity);
  out[0] = mod(std::atan2(relative[1], -relative[0])) * (180.0 / pi);
  out[1] = std::asin(relative[2] / range) * (180.0 / pi);
  out[2] = range;
  out[3] = (relative[0] * velocity[0] + relative[1] * velocity[1] +
      relative[2] * velocity[2]) / range;
  return 0;
}
}

EXPORT int32_t ht_satellite_abi() { return 2; }
EXPORT int32_t ht_satellite_coefficient_count() { return coefficientCount; }
EXPORT Engine* ht_satellite_create() { return new (std::nothrow) Engine; }
EXPORT void ht_satellite_destroy(Engine* e) { delete e; }
EXPORT double* ht_satellite_coefficients(Engine* e) { return e->coefficients; }
EXPORT double* ht_satellite_times(Engine* e) { return e->times; }
EXPORT double* ht_satellite_rows(Engine* e) { return e->rows; }
EXPORT void ht_satellite_init(Engine* e) {
  int i = 0;
#define LOAD(name) e->satellite.name = e->coefficients[i++];
  FIELDS(LOAD)
#undef LOAD
}
EXPORT int32_t ht_satellite_batch(Engine* e, int32_t count) {
  if (!e || count < 0 || count > capacity) return -1;
  for (int i = 0; i < count; ++i) {
    auto* row = e->rows + i * 7;
    row[0] = step(e->satellite, e->times[i], row + 1);
  }
  return 0;
}

EXPORT void ht_satellite_observer(Engine* e, double latitude, double longitude,
                                   double altitudeMeters) {
  const double lat = latitude * (pi / 180.0);
  const double lon = longitude * (pi / 180.0);
  const double h = altitudeMeters / 1000.0;
  e->sinLat = std::sin(lat);
  e->cosLat = std::cos(lat);
  e->sinLon = std::sin(lon);
  e->cosLon = std::cos(lon);
  constexpr double a = 6378.137, f = 1.0 / 298.257223563;
  constexpr double e2 = f * (2.0 - f);
  const double n = a / std::sqrt(1.0 - e2 * e->sinLat * e->sinLat);
  e->obsX = (n + h) * e->cosLat * e->cosLon;
  e->obsY = (n + h) * e->cosLat * e->sinLon;
  e->obsZ = (n * (1.0 - e2) + h) * e->sinLat;
}

// Grid timestamps are generated in native code, avoiding a second DateTime
// list, EciState/Vector3 object graph, hash map and repeated Dart transforms.
// Package findPasses retains its grid walk and all adaptive refinements.
EXPORT int32_t ht_satellite_look_grid(Engine* e, int64_t epochUs,
    int64_t startUs, int64_t stepUs, int64_t toUs, int32_t count) {
  if (!e || count < 0 || count > capacity || stepUs <= 0) return -1;
  for (int i = 0; i < count; ++i) {
    const int64_t candidate = startUs + stepUs * i;
    const int64_t gridUs = candidate < toUs ? candidate : toUs;
    // findPasses converts grid integers to doubles, then rounds them back
    // before propagation. Match even outside the exact-integer double range.
    const int64_t utcUs = std::llround(static_cast<double>(gridUs));
    double state[6];
    auto* row = e->rows + i * 5;
    int status = step(e->satellite, (utcUs - epochUs) / 6.0e7, state);
    if (status == 0) status = lookAngle(*e, utcUs, state, row + 1);
    row[0] = status;
  }
  return 0;
}
