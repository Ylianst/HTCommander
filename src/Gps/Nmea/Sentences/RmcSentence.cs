using System;
using System.Linq;

namespace GpsTool.Nmea.Sentences;

/// <summary>
/// RMC – Recommended Minimum Specific GNSS Data.
/// </summary>
public sealed class RmcSentence
{
    public TimeSpan? UtcTime { get; init; }
    public string? Status { get; init; }
    public double? Latitude { get; init; }
    public double? Longitude { get; init; }
    public double? SpeedKnots { get; init; }
    public double? TrackAngle { get; init; }
    public DateOnly? Date { get; init; }
    public double? MagneticVariation { get; init; }
    public string? MagneticDirection { get; init; }
    public string? Mode { get; init; }

    public double? SpeedKph => SpeedKnots.HasValue ? SpeedKnots.Value * 1.852 : null;

    public bool IsActive => Status == "A";

    /// <summary>
    /// Fields: $--RMC,hhmmss.ss,status,lat,N/S,lon,E/W,spd,cog,ddmmyy,mv,mvE/W,mode*cs
    /// </summary>
    public static RmcSentence Parse(string[] fields) => new()
    {
        UtcTime            = NmeaConvert.ToUtcTime(fields.ElementAtOrDefault(1) ?? ""),
        Status             = fields.ElementAtOrDefault(2),
        Latitude           = NmeaConvert.ToDecimalDegrees(fields.ElementAtOrDefault(3) ?? "", fields.ElementAtOrDefault(4) ?? ""),
        Longitude          = NmeaConvert.ToDecimalDegrees(fields.ElementAtOrDefault(5) ?? "", fields.ElementAtOrDefault(6) ?? ""),
        SpeedKnots         = NmeaConvert.ToDouble(fields.ElementAtOrDefault(7) ?? ""),
        TrackAngle         = NmeaConvert.ToDouble(fields.ElementAtOrDefault(8) ?? ""),
        Date               = NmeaConvert.ToDate(fields.ElementAtOrDefault(9) ?? ""),
        MagneticVariation  = NmeaConvert.ToDouble(fields.ElementAtOrDefault(10) ?? ""),
        MagneticDirection  = fields.ElementAtOrDefault(11),
        Mode               = fields.ElementAtOrDefault(12),
    };

    public override string ToString() =>
        $"[RMC] Time={UtcTime:hh\\:mm\\:ss}  Date={Date}  Status={(IsActive ? "Active" : "Void")}  " +
        $"Lat={Latitude:F6}°  Lon={Longitude:F6}°  Speed={SpeedKnots:F1}kn ({SpeedKph:F1}km/h)  " +
        $"Track={TrackAngle:F1}°";
}
