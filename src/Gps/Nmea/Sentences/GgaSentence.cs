using System;
using System.Linq;

namespace GpsTool.Nmea.Sentences;

/// <summary>
/// GGA – Global Positioning System Fix Data.
/// </summary>
public sealed class GgaSentence
{
    public TimeSpan? UtcTime { get; init; }
    public double? Latitude { get; init; }
    public double? Longitude { get; init; }
    public int? FixQuality { get; init; }
    public int? SatelliteCount { get; init; }
    public double? Hdop { get; init; }
    public double? AltitudeMeters { get; init; }
    public double? GeoidSeparation { get; init; }

    public string FixQualityDescription => FixQuality switch
    {
        0 => "Invalid",
        1 => "GPS Fix (SPS)",
        2 => "DGPS Fix",
        3 => "PPS Fix",
        4 => "RTK Fixed",
        5 => "RTK Float",
        6 => "Estimated (DR)",
        7 => "Manual Input",
        8 => "Simulation",
        _ => "Unknown"
    };

    /// <summary>
    /// Parses a GGA sentence from already-split NMEA fields.
    /// Fields: $--GGA,hhmmss.ss,lat,N/S,lon,E/W,quality,numSV,HDOP,alt,M,sep,M,diffAge,diffStation*cs
    /// </summary>
    public static GgaSentence Parse(string[] fields) => new()
    {
        UtcTime        = NmeaConvert.ToUtcTime(fields.ElementAtOrDefault(1) ?? ""),
        Latitude       = NmeaConvert.ToDecimalDegrees(fields.ElementAtOrDefault(2) ?? "", fields.ElementAtOrDefault(3) ?? ""),
        Longitude      = NmeaConvert.ToDecimalDegrees(fields.ElementAtOrDefault(4) ?? "", fields.ElementAtOrDefault(5) ?? ""),
        FixQuality     = NmeaConvert.ToInt(fields.ElementAtOrDefault(6) ?? ""),
        SatelliteCount = NmeaConvert.ToInt(fields.ElementAtOrDefault(7) ?? ""),
        Hdop           = NmeaConvert.ToDouble(fields.ElementAtOrDefault(8) ?? ""),
        AltitudeMeters = NmeaConvert.ToDouble(fields.ElementAtOrDefault(9) ?? ""),
        GeoidSeparation = NmeaConvert.ToDouble(fields.ElementAtOrDefault(11) ?? ""),
    };

    public override string ToString() =>
        $"[GGA] Time={UtcTime:hh\\:mm\\:ss\\.fff}  Fix={FixQualityDescription}  " +
        $"Lat={Latitude:F6}°  Lon={Longitude:F6}°  Alt={AltitudeMeters:F1}m  " +
        $"Sats={SatelliteCount}  HDOP={Hdop:F1}";
}
