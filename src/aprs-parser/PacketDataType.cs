using System;

namespace aprsparser
{
    // ReSharper disable InconsistentNaming
    public enum PacketDataType
    {
        Unknown,
        Beacon,                //
        MicECurrent,           //#$1C Current Mic-E Data (Rev 0 beta)
        MicEOld,               //#$1D Old Mic-E Data (Rev 0 beta)
        Position,              //'!'  Position without timestamp (no APRS messaging), or Ultimeter 2000 WX Station
        PeetBrosUII1,          //'#'  Peet Bros U-II Weather Station
        RawGPSorU2K,           //'$'  Raw GPS data or Ultimeter 2000
        MicroFinder,           //'%'  Agrelo DFJr / MicroFinder
        MapFeature,            //'&'  [Reserved - Map Feature]
        TMD700,                //'''' Old Mic-E Data (but current for TM-D700)
        Item,                  //')'  Item
        PeetBrosUII2,          //'*'  Peet Bros U-II Weather Station
        ShelterData,           //'+'  [Reserved - Shelter data with time]
        InvalidOrTestData,     //','  Invalid data or test data
        SpaceWeather,          //'.'  [Reserved - Space Weather]
        PositionTime,          //'/'  Position with timestamp (no APRS messaging)
        Message,               //':'  Message
        Object,                //';'  Object
        StationCapabilities,   //'<'  Station Capabilities
        PositionMsg,           //'='  Position without timestamp (with APRS messaging)
        Status,                //'>'  Status
        Query,                 //'?'  Query
        PositionTimeMsg,       //'@'  Position with timestamp (with APRS messaging)
        Telemetry,             //'T'  Telemetry data
        MaidenheadGridLoc,     //'['  Maidenhead grid locator beacon (obsolete)
        WeatherReport,         //'_'  Weather Report (without position)
        MicE,                  //'`'  Current Mic-E data
        UserDefined,           //'{'  User-Defined APRS packet format
        ThirdParty             //'}'  Third-party traffic
    }

    public static class AprsDataType
    {
        public static PacketDataType GetDataType(Char ch)
        {
            switch (ch)
            {
                case (char)0x00: return PacketDataType.Unknown;
                case ' ': return PacketDataType.Beacon;
                case (char)0x1C: return PacketDataType.MicECurrent;
                case (char)0x1D: return PacketDataType.MicEOld;
                case '!': return PacketDataType.Position;
                case '#': return PacketDataType.PeetBrosUII1;
                case '$': return PacketDataType.RawGPSorU2K;
                case '%': return PacketDataType.MicroFinder;
                case '&': return PacketDataType.MapFeature;
                case '\'': return PacketDataType.TMD700;
                case '*': return PacketDataType.PeetBrosUII2;
                case '+': return PacketDataType.ShelterData;
                case ',': return PacketDataType.InvalidOrTestData;
                case '.': return PacketDataType.SpaceWeather;
                case '/': return PacketDataType.PositionTime;
                case ':': return PacketDataType.Message;
                case ';': return PacketDataType.Object;
                case '<': return PacketDataType.StationCapabilities;
                case '=': return PacketDataType.PositionMsg;
                case '>': return PacketDataType.Status;
                case '?': return PacketDataType.Query;
                case '@': return PacketDataType.PositionTimeMsg;
                case 'T': return PacketDataType.Telemetry;
                case '[': return PacketDataType.MaidenheadGridLoc;
                case '_': return PacketDataType.WeatherReport;
                case '`': return PacketDataType.MicE;
                case '{': return PacketDataType.UserDefined;
                case '}': return PacketDataType.ThirdParty;
                //treat all the rest as unknown
                default: return PacketDataType.Unknown;
            }
        }
    }

}


