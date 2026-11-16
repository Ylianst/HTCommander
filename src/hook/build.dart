// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

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
  });
}
