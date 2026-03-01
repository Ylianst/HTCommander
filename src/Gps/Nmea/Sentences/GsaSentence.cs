using System;
using System.Collections.Generic;
using System.Linq;

namespace GpsTool.Nmea.Sentences;

/// <summary>
/// GSA – GNSS DOP and Active Satellites.
/// </summary>
public sealed class GsaSentence
{
    public string? SelectionMode { get; init; }
    public int? FixType { get; init; }
    public int[] SatellitePrns { get; init; } = [];
    public double? Pdop { get; init; }
    public double? Hdop { get; init; }
    public double? Vdop { get; init; }

    public string FixDescription => FixType switch
    {
        1 => "No Fix",
        2 => "2D Fix",
        3 => "3D Fix",
        _ => "Unknown"
    };

    /// <summary>
    /// Fields: $--GSA,mode,fixType,sv1..sv12,PDOP,HDOP,VDOP*cs
    /// </summary>
    public static GsaSentence Parse(string[] fields)
    {
        var prns = new List<int>();
        for (int i = 3; i <= 14 && i < fields.Length; i++)
        {
            if (NmeaConvert.ToInt(fields[i]) is int prn)
                prns.Add(prn);
        }

        return new GsaSentence
        {
            SelectionMode = fields.ElementAtOrDefault(1),
            FixType       = NmeaConvert.ToInt(fields.ElementAtOrDefault(2) ?? ""),
            SatellitePrns = prns.ToArray(),
            Pdop          = NmeaConvert.ToDouble(fields.ElementAtOrDefault(15) ?? ""),
            Hdop          = NmeaConvert.ToDouble(fields.ElementAtOrDefault(16) ?? ""),
            Vdop          = NmeaConvert.ToDouble(fields.ElementAtOrDefault(17) ?? ""),
        };
    }

    public override string ToString() =>
        $"[GSA] Fix={FixDescription}  Mode={SelectionMode}  " +
        $"PDOP={Pdop:F1}  HDOP={Hdop:F1}  VDOP={Vdop:F1}  " +
        $"SVs=[{string.Join(",", SatellitePrns)}]";
}
