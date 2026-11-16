# Native satellite propagation

`SatelliteComputation`, `SatelliteObservation`, `SatellitePredictor`,
`SatelliteGlobeWorker` and `SatelliteHandler` default to **`useNative: true`**.
Windows, Linux, macOS and Android use native propagation by default; web and
iOS always use Dart. Explicit `useNative: false` selects the Dart reference
on every platform. Missing/incompatible native assets and allocation failures
on supported platforms are errors, never silent Dart fallback.
`SatelliteComputation.isNative` exposes the backend actually selected.

## Measured performance

Windows x64 AOT benchmarks measured complete 48-hour pass searches at
**1.31-1.46x faster** across LEO, MEO, HEO and GEO cases. For example, ISS
improved from **4.022 ms to 2.838 ms**, and AMC-4 from **4.638 ms to 3.179 ms**.
161/241-sample orbit batches improved **1.12-1.17x**. All benchmark
position/velocity/pass parity checks passed.

Single-sample calls do not amortize FFI/allocation overhead and measured
approximately 2-8% slower in most cases. The optimization targets batched
orbits and prediction grids, not a universal scalar speedup. Measurements
are local medians and exclude initialization; repeat on target hardware.

## Implementation and integration

The build hook calls `buildSatellite(input, output)` from
`src/hook/satellite.dart` inside the supported-platform guard in
`src/hook/build.dart`. It registers
`package:htcommander/satellite_sgp4` from `native/satellite_sgp4.cpp`.
No new dependency is required.

The kernel is a numerical translation of the **installed
satellite_observer 1.0.1** SGP4/SDP4 propagation step, including lunar/solar
periodics, low-inclination Lyddane handling and both resonance integrators.
Native pass grids also translate the package's GMST and WGS-84 topocentric
look-angle/range-rate transforms, retaining its double arithmetic/order.
It is not a two-body approximation. WGS-72 coefficients are initialised once
by the original package's `sgp4init` in Dart, then copied to native storage.
This intentionally uses package implementation imports in the coefficient
bridge `satellite_coefficients.dart` and the pass facade
`satellite_computation.dart`. When upgrading satellite_observer, audit those
bridges, the package pass-finder evaluation phases and the translated routines
together, update the ABI if necessary,
and rerun parity validation. A field-count/ABI check detects stale binaries,
not numerical changes in a future dependency.

The original MIT notice is retained in `native/satellite_sgp4.LICENSE`;
source comments retain Maciej Starosielec, python-sgp4/Brandon Rhodes and
Vallado attribution. Include this notice with distributions.

Native calls process at most 256 samples per FFI transition. The API copies
results into Dart-owned buffers; no pointer escapes and buffers are local
to each engine/worker. Explicit disposal and a native finalizer release
storage. Calls are non-leaf, allowing normal VM coordination.
Compile with strict double arithmetic, no fast-math and no FP contraction;
the helper sets `/fp:strict` or `-ffp-contract=off -fno-fast-math`.
SIMD/float32 reassociation is intentionally not used for this sensitive kernel.

## Preserved behavior

- TLE parsing and validation are still the package's implementation.
- TEME positions/velocities, UTC microsecond offsets, negative-time modulo,
  deep-space rewinds and Vallado error codes are preserved.
- Scalar geometry, geodetic subpoints, Earth-rotation range rate/Doppler and
  adaptive pass refinements remain the original package code.
- The default 48-hour pass scan computes its original 30-second grid directly
  as flat native topocentric rows. This eliminates the former duplicate
  DateTime list, EciState/Vector3 object graph, hash cache and Dart transforms
  from the coarse phase. The original package `findPasses` consumes these rows
  during its initial ordered coarse sampling phase; later crossing/peak/event
  evaluations use original scalar geometry. Errors remain attached to their
  original sample index. The package still decides every crossing/culmination.
  Only fully bracketed passes are returned, with the original 10-degree
  default, inclusive final endpoint and 0.1/0.05-second refinement tolerances.
- Horizon LOS retains its independent zero-degree threshold, 15-second grid,
  2,880-sample limit and one-second bisection. Native look-ahead is bounded
  to 64 grid samples and does not change the first crossing selected.
- Worker queue/error behavior, five-minute pass cache/in-flight sharing and
  one-second tracking cadence are unchanged.
- Globe orbit samples retain their exact timestamps/counts, 120-second
  refresh/cache policy and existing snapshot-time Earth rotation. Bad
  satellites remain independently skippable. Ground tracks batch their
  original 101 samples; failed samples are still individually skipped.
- Web's cooperative yielding and ordered local worker fallback are retained.

Scalar FFI calls and Dart result allocation can outweigh native savings for
small workloads. The primary targets are complete orbit sampling and coarse
pass/LOS grids. Native initialization still costs Dart work, and full pass
searches still include Dart geometry for adaptive refinement; this is
intentional to avoid changing pass policy. Measure complete searches rather
than inferring speedup from raw propagation throughput.

## Central validation

From `src` (do not run concurrent native builds):

```powershell
dart format lib\satellite hook\satellite.dart test\native_satellite_test.dart test\support\satellite_cases.dart benchmark\satellite_benchmark.dart lib\handlers\satellite_handler.dart
flutter analyze lib\satellite lib\handlers\satellite_handler.dart hook\satellite.dart test\native_satellite_test.dart test\support\satellite_cases.dart benchmark\satellite_benchmark.dart
flutter test test\native_satellite_test.dart test\satellite_predictor_test.dart test\satellite_globe_test.dart test\satellite_test.dart
dart run benchmark\satellite_benchmark.dart
```

The tests assert native-by-default selection on supported platforms, exact
explicit-Dart results, and errors for incompatible native coefficient ABIs.
Unsupported platforms exercise Dart fallback and skip native-only tests.
The predictor reference tests explicitly select Dart; native worker and globe
comparisons exercise the default constructors. Validate web/iOS builds in
the normal platform CI.

Focused comparisons include LEO, eccentric near-earth, resonant Molniya HEO,
nonresonant GPS MEO, inclined/near-equatorial GEO, negative-time Lyddane cases,
synthetic circular/retrograde and near-225-minute branch cases. Samples span
±30 days, microseconds, shuffled/rewound times and batch boundaries.
Independent Vallado Vanguard epoch/+360-minute position/velocity vectors
guard against comparing two equally misconfigured engines.

Position tolerance is 1e-6 km (1 mm); velocity tolerance is 1e-9 km/s
(1 micrometre/s). Pass rise/set times must agree within 0.1 s, culmination
within 0.05 s, peak elevation within 1e-5 degrees; geometry/range rate and
decay errors are compared separately. These are implementation-parity bounds,
not claims of physical orbit/TLE prediction accuracy.

The flat native grid additionally compares every azimuth, elevation, range
and range-rate against package geometry across all orbital regimes, three
observer sites (including a pole), microsecond steps, unaligned endpoints,
multiple 256-row boundaries and pre-1970 UTC. Native ABI 2 includes these
topocentric grid exports; stale ABI 1 binaries fail explicitly.

The benchmark shares the offline verification TLE inputs with the tests,
requires a genuinely native backend, and checks position/velocity plus all
three pass thresholds before reporting anything. It reports seven-trial
medians for 161/241-sample orbit batches, full 48-hour pass searches and scalar
propagation, including conversion/allocation/copy costs. It reports ratios,
not a machine-independent performance requirement.

