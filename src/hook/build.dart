// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'dart_modem.dart';
import 'gsm.dart';
import 'telemetry.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    if (os != OS.windows &&
        os != OS.linux &&
        os != OS.macOS &&
        os != OS.android) {
      return;
    }
    await CBuilder.library(
      name: 'ht_radio_audio',
      assetName: 'radio_audio_codec',
      sources: ['native/radio_audio_codec.cpp'],
      includes: ['native'],
      language: Language.cpp,
      std: 'c++17',
      flags: [if (os == OS.windows) '/EHsc'],
      cppLinkStdLib: os == OS.android ? 'c++_static' : null,
    ).run(input: input, output: output);
    output.dependencies.addAll([
      input.packageRoot.resolve('native/radio_audio_codec.h'),
      input.packageRoot.resolve('native/radio_audio_codec_tables.h'),
    ]);
    await CBuilder.library(
      name: 'ht_xara_dsp',
      assetName: 'xara_dsp',
      sources: ['native/xara_dsp.cpp'],
      includes: ['native'],
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
        ],
      ],
      cppLinkStdLib: os == OS.android ? 'c++_static' : null,
    ).run(input: input, output: output);
    output.dependencies.add(input.packageRoot.resolve('native/xara_dsp.h'));
    await CBuilder.library(
      name: 'ht_packet_modem',
      assetName: 'packet_modem',
      sources: ['native/packet_modem.cpp'],
      includes: ['native'],
      language: Language.cpp,
      std: 'c++17',
      flags: [
        if (os == OS.windows) ...[
          '/EHsc',
          '/O2',
          '/fp:precise',
        ] else ...[
          '-O3',
          '-ffp-contract=off',
        ],
      ],
      cppLinkStdLib: os == OS.android ? 'c++_static' : null,
    ).run(input: input, output: output);
    output.dependencies.add(input.packageRoot.resolve('native/packet_modem.h'));
    await CBuilder.library(
      name: 'ht_sstv_dsp',
      assetName: 'sstv_dsp',
      sources: ['native/sstv_dsp.cpp', 'native/sstv_encoder.cpp'],
      includes: ['native'],
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
        ],
      ],
      cppLinkStdLib: os == OS.android ? 'c++_static' : null,
    ).run(input: input, output: output);
    output.dependencies.add(input.packageRoot.resolve('native/sstv_dsp.h'));
    await buildDartModem(input, output);
    await buildGsm(input, output);
    await buildTelemetry(input, output);
  });
}
