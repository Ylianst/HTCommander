// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> buildGsm(BuildInput input, BuildOutputBuilder output) async {
  final windows = input.config.code.targetOS == OS.windows;
  await CBuilder.library(
    name: 'ht_echolink_gsm',
    assetName: 'echolink_gsm',
    sources: [
      'native/echolink_gsm.c',
      for (final name in [
        'add',
        'code',
        'debug',
        'decode',
        'long_term',
        'lpc',
        'preprocess',
        'rpe',
        'gsm_decode',
        'gsm_encode',
        'short_term',
        'table',
      ])
        'native/gsm/src/$name.c',
    ],
    includes: ['native', 'native/gsm/inc'],
    language: Language.c,
    std: 'c11',
    defines: {'NDEBUG': null, 'SASR': null, 'NeedFunctionPrototypes': '1'},
    flags: windows ? ['/O2'] : ['-O3', '-fvisibility=hidden'],
  ).run(input: input, output: output);
  output.dependencies.addAll([
    for (final name in ['config', 'gsm', 'private', 'proto', 'unproto'])
      input.packageRoot.resolve('native/gsm/inc/$name.h'),
    input.packageRoot.resolve('native/echolink_gsm.h'),
    input.packageRoot.resolve('native/gsm_simd.h'),
  ]);
}
