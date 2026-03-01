using System.Linq;

namespace GpsTool.Nmea.Sentences;

/// <summary>
/// VTG – Track Made Good and Ground Speed.
/// </summary>
public sealed class VtgSentence
{
    public double? TrackTrue { get; init; }
    public double? TrackMagnetic { get; init; }
    public double? SpeedKnots { get; init; }
    public double? SpeedKph { get; init; }
    public string? Mode { get; init; }

    /// <summary>
    /// Fields: $--VTG,trackT,T,trackM,M,spdN,N,spdK,K,mode*cs
    /// </summary>
    public static VtgSentence Parse(string[] fields) => new()
    {
        TrackTrue     = NmeaConvert.ToDouble(fields.ElementAtOrDefault(1) ?? ""),
        TrackMagnetic = NmeaConvert.ToDouble(fields.ElementAtOrDefault(3) ?? ""),
        SpeedKnots    = NmeaConvert.ToDouble(fields.ElementAtOrDefault(5) ?? ""),
        SpeedKph      = NmeaConvert.ToDouble(fields.ElementAtOrDefault(7) ?? ""),
        Mode          = fields.ElementAtOrDefault(9),
    };

    public override string ToString() =>
        $"[VTG] TrackTrue={TrackTrue:F1}°  TrackMag={TrackMagnetic:F1}°  " +
        $"Speed={SpeedKnots:F1}kn ({SpeedKph:F1}km/h)  Mode={Mode}";
}
