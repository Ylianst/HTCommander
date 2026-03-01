using System;
using System.Linq;

namespace GpsTool.Nmea.Sentences;

/// <summary>
/// GLL – Geographic Position – Latitude/Longitude.
/// </summary>
public sealed class GllSentence
{
    public double? Latitude { get; init; }
    public double? Longitude { get; init; }
    public TimeSpan? UtcTime { get; init; }
    public string? Status { get; init; }
    public string? Mode { get; init; }

    public bool IsValid => Status == "A";

    /// <summary>
    /// Fields: $--GLL,lat,N/S,lon,E/W,hhmmss.ss,status,mode*cs
    /// </summary>
    public static GllSentence Parse(string[] fields) => new()
    {
        Latitude  = NmeaConvert.ToDecimalDegrees(fields.ElementAtOrDefault(1) ?? "", fields.ElementAtOrDefault(2) ?? ""),
        Longitude = NmeaConvert.ToDecimalDegrees(fields.ElementAtOrDefault(3) ?? "", fields.ElementAtOrDefault(4) ?? ""),
        UtcTime   = NmeaConvert.ToUtcTime(fields.ElementAtOrDefault(5) ?? ""),
        Status    = fields.ElementAtOrDefault(6),
        Mode      = fields.ElementAtOrDefault(7),
    };

    public override string ToString() =>
        $"[GLL] Lat={Latitude:F6}°  Lon={Longitude:F6}°  Time={UtcTime:hh\\:mm\\:ss}  " +
        $"Status={(IsValid ? "Valid" : "Void")}";
}
