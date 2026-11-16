// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> buildSatellite(BuildInput input, BuildOutputBuilder output) async {
  final os = input.config.code.targetOS;
  if (os != OS.windows &&
      os != OS.linux &&
      os != OS.macOS &&
      os != OS.android) {
    return;
  }
  await CBuilder.library(
    name: 'ht_satellite_sgp4',
    assetName: 'satellite_sgp4',
    sources: ['native/satellite_sgp4.cpp'],
    language: Language.cpp,
    std: 'c++17',
    flags: [
      if (os == OS.windows) ...[
        '/EHsc',
        '/O2',
        '/fp:strict',
      ] else ...[
        '-O3',
        '-ffp-contract=off',
        '-fno-fast-math',
        '-fvisibility=hidden',
      ],
    ],
    cppLinkStdLib: os == OS.android ? 'c++_static' : null,
  ).run(input: input, output: output);
  output.dependencies.add(
    input.packageRoot.resolve('native/satellite_sgp4.LICENSE'),
  );
}
