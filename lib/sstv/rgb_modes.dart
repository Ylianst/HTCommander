/*
RGB modes
Ported to Dart from C# (originally from https://github.com/xdsopl/robot36)
*/

import 'rgb_decoder.dart';

class RGBModes {
  static RGBDecoder martin(
    String name,
    int code,
    double channelSeconds,
    int sampleRate,
  ) {
    const double syncPulseSeconds = 0.004862;
    const double separatorSeconds = 0.000572;
    final double scanLineSeconds =
        syncPulseSeconds +
        separatorSeconds +
        3 * (channelSeconds + separatorSeconds);
    const double greenBeginSeconds = separatorSeconds;
    final double greenEndSeconds = greenBeginSeconds + channelSeconds;
    final double blueBeginSeconds = greenEndSeconds + separatorSeconds;
    final double blueEndSeconds = blueBeginSeconds + channelSeconds;
    final double redBeginSeconds = blueEndSeconds + separatorSeconds;
    final double redEndSeconds = redBeginSeconds + channelSeconds;
    return RGBDecoder(
      'Martin $name',
      code,
      320,
      256,
      0,
      scanLineSeconds,
      greenBeginSeconds,
      redBeginSeconds,
      redEndSeconds,
      greenBeginSeconds,
      greenEndSeconds,
      blueBeginSeconds,
      blueEndSeconds,
      redEndSeconds,
      sampleRate,
    );
  }

  static RGBDecoder scottie(
    String name,
    int code,
    double channelSeconds,
    int sampleRate,
  ) {
    const double syncPulseSeconds = 0.009;
    const double separatorSeconds = 0.0015;
    final double firstSyncPulseSeconds =
        syncPulseSeconds + 2 * (separatorSeconds + channelSeconds);
    final double scanLineSeconds =
        syncPulseSeconds + 3 * (channelSeconds + separatorSeconds);
    const double blueEndSeconds = -syncPulseSeconds;
    final double blueBeginSeconds = blueEndSeconds - channelSeconds;
    final double greenEndSeconds = blueBeginSeconds - separatorSeconds;
    final double greenBeginSeconds = greenEndSeconds - channelSeconds;
    const double redBeginSeconds = separatorSeconds;
    final double redEndSeconds = redBeginSeconds + channelSeconds;
    return RGBDecoder(
      'Scottie $name',
      code,
      320,
      256,
      firstSyncPulseSeconds,
      scanLineSeconds,
      greenBeginSeconds,
      redBeginSeconds,
      redEndSeconds,
      greenBeginSeconds,
      greenEndSeconds,
      blueBeginSeconds,
      blueEndSeconds,
      redEndSeconds,
      sampleRate,
    );
  }

  static RGBDecoder wraaseSc2180(int sampleRate) {
    const double syncPulseSeconds = 0.0055225;
    const double syncPorchSeconds = 0.0005;
    const double channelSeconds = 0.235;
    const double scanLineSeconds =
        syncPulseSeconds + syncPorchSeconds + 3 * channelSeconds;
    const double redBeginSeconds = syncPorchSeconds;
    const double redEndSeconds = redBeginSeconds + channelSeconds;
    const double greenBeginSeconds = redEndSeconds;
    const double greenEndSeconds = greenBeginSeconds + channelSeconds;
    const double blueBeginSeconds = greenEndSeconds;
    const double blueEndSeconds = blueBeginSeconds + channelSeconds;
    return RGBDecoder(
      'Wraase SC2\u2013180',
      55,
      320,
      256,
      0,
      scanLineSeconds,
      redBeginSeconds,
      redBeginSeconds,
      redEndSeconds,
      greenBeginSeconds,
      greenEndSeconds,
      blueBeginSeconds,
      blueEndSeconds,
      blueEndSeconds,
      sampleRate,
    );
  }
}
