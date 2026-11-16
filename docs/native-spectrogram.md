# Native spectrogram pipeline

On Windows, Linux, macOS, and Android, the spectrogram batches windowing,
FFT, magnitude extraction, history management, logarithmic scaling, colormap
lookup, and incremental scrolling in the existing XARA native asset. PCM is
uploaded once per input block rather than sending each overlapping FFT window
across FFI. FFT plans, sample storage, history columns, and upload/render
buffers are reused. The FFT uses the existing baseline SSE2/NEON kernel.

The Dart implementation remains available on web/iOS and with
`SpectrogramGenerator(useNative: false)`. Set `HT_SPECTROGRAM_DART=true`
(environment or Dart define) to disable only the new pipeline while retaining
the previous native FFT path. `HT_XARA_DART=true` also disables the pipeline.
Native errors are reported, not silently replayed through Dart.

The controller disposes native storage when reconfigured or closed. Standalone
generator users should call `dispose()`; native finalizers also protect
unreachable instances. Rendering preserves the caller's existing pixels for
incremental updates, including scroll/roll modes, resized histories, and
settings changes.

## Validation and measurement

From `src`:

```powershell
flutter test --no-pub test\spectrogram_test.dart
dart run benchmark\spectrogram_benchmark.dart
dart build cli --target=benchmark\spectrogram_benchmark.dart --output=build\native_performance\spectrogram
.\build\native_performance\spectrogram\bundle\bin\spectrogram_benchmark.exe
$env:HT_SPECTROGRAM_DART = 'true'
.\build\native_performance\spectrogram\bundle\bin\spectrogram_benchmark.exe
Remove-Item Env:\HT_SPECTROGRAM_DART
```

The benchmark verifies exact final RGBA parity and measures five seconds of
32 kHz audio, 512-point FFTs with 25-sample hops, 480 history columns, and 100
incremental renders. A Windows x64 AOT measurement took **51.4 ms** for the
batched pipeline versus **56.1 ms** for the prior native-FFT-only path
(about **8% less processing time**). The all-Dart reference took **84.3 ms**.
These are local medians, not a platform-independent speed guarantee or a
measurement of Flutter image upload/rasterization.
