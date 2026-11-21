// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> buildCw(BuildInput input, BuildOutputBuilder output) async {
  final os = input.config.code.targetOS;
  await CBuilder.library(
    name: 'ht_cw_dsp',
    assetName: 'cw_dsp',
    sources: ['native/cw_dsp.cpp'],
    includes: ['native'],
    language: Language.cpp,
    std: 'c++17',
    flags: [
      if (os == OS.android) '-Wl,--no-undefined',
      if (os == OS.windows) ...[
        '/EHsc',
        '/O2',
        '/fp:strict',
      ] else ...[
        '-O3',
        '-ffp-contract=off',
      ],
    ],
    libraries: [if (os == OS.android) 'm'],
    cppLinkStdLib: os == OS.android ? 'c++_static' : null,
  ).run(input: input, output: output);
  output.dependencies.add(input.packageRoot.resolve('native/cw_dsp.h'));
}
