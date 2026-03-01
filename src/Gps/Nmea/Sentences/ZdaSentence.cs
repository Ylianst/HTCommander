using System;
using System.Linq;

namespace GpsTool.Nmea.Sentences;

/// <summary>
/// ZDA – Time &amp; Date.
/// </summary>
public sealed class ZdaSentence
{
    public TimeSpan? UtcTime { get; init; }
    public int? Day { get; init; }
    public int? Month { get; init; }
    public int? Year { get; init; }
    public int? LocalZoneHours { get; init; }
    public int? LocalZoneMinutes { get; init; }

    /// <summary>
    /// Fields: $--ZDA,hhmmss.ss,day,month,year,ltzh,ltzm*cs
    /// </summary>
    public static ZdaSentence Parse(string[] fields) => new()
    {
        UtcTime          = NmeaConvert.ToUtcTime(fields.ElementAtOrDefault(1) ?? ""),
        Day              = NmeaConvert.ToInt(fields.ElementAtOrDefault(2) ?? ""),
        Month            = NmeaConvert.ToInt(fields.ElementAtOrDefault(3) ?? ""),
        Year             = NmeaConvert.ToInt(fields.ElementAtOrDefault(4) ?? ""),
        LocalZoneHours   = NmeaConvert.ToInt(fields.ElementAtOrDefault(5) ?? ""),
        LocalZoneMinutes = NmeaConvert.ToInt(fields.ElementAtOrDefault(6) ?? ""),
    };

    public override string ToString() =>
        $"[ZDA] {Year:D4}-{Month:D2}-{Day:D2}  {UtcTime:hh\\:mm\\:ss} UTC  " +
        $"LocalOffset={LocalZoneHours:+0;-0}:{LocalZoneMinutes:D2}";
}
