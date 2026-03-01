using System.Collections.Generic;
using System.Linq;

namespace GpsTool.Nmea.Sentences;

/// <summary>
/// GSV – GNSS Satellites in View.
/// </summary>
public sealed class GsvSentence
{
    public int? TotalMessages { get; init; }
    public int? MessageNumber { get; init; }
    public int? SatellitesInView { get; init; }
    public SatelliteInfo[] Satellites { get; init; } = [];

    public sealed class SatelliteInfo
    {
        public int Prn { get; init; }
        public int? ElevationDeg { get; init; }
        public int? AzimuthDeg { get; init; }
        public int? Snr { get; init; }

        public override string ToString() =>
            $"PRN {Prn,2}: El={ElevationDeg,3}°  Az={AzimuthDeg,3}°  SNR={Snr?.ToString() ?? "--"}dB";
    }

    /// <summary>
    /// Fields: $--GSV,totalMsgs,msgNum,satInView, [prn,elev,az,snr] x 1..4 *cs
    /// </summary>
    public static GsvSentence Parse(string[] fields)
    {
        var sats = new List<SatelliteInfo>();
        int idx = 4;
        while (idx + 3 < fields.Length)
        {
            var prn = NmeaConvert.ToInt(fields[idx]);
            if (prn is null) break;

            sats.Add(new SatelliteInfo
            {
                Prn          = prn.Value,
                ElevationDeg = NmeaConvert.ToInt(fields.ElementAtOrDefault(idx + 1) ?? ""),
                AzimuthDeg   = NmeaConvert.ToInt(fields.ElementAtOrDefault(idx + 2) ?? ""),
                Snr          = NmeaConvert.ToInt(fields.ElementAtOrDefault(idx + 3) ?? ""),
            });
            idx += 4;
        }

        return new GsvSentence
        {
            TotalMessages   = NmeaConvert.ToInt(fields.ElementAtOrDefault(1) ?? ""),
            MessageNumber   = NmeaConvert.ToInt(fields.ElementAtOrDefault(2) ?? ""),
            SatellitesInView = NmeaConvert.ToInt(fields.ElementAtOrDefault(3) ?? ""),
            Satellites       = sats.ToArray(),
        };
    }

    public override string ToString()
    {
        var satLines = string.Join("  |  ", Satellites.Select(s => s.ToString()));
        return $"[GSV] Msg {MessageNumber}/{TotalMessages}  InView={SatellitesInView}  {satLines}";
    }
}
