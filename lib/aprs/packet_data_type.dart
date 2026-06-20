/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

/// APRS packet data type, derived from the first character of the
/// information field. Mirrors the C# `PacketDataType` enum.
enum PacketDataType {
  unknown,
  beacon,
  micECurrent, // 0x1C Current Mic-E Data (Rev 0 beta)
  micEOld, // 0x1D Old Mic-E Data (Rev 0 beta)
  position, // '!' Position without timestamp (no APRS messaging)
  peetBrosUII1, // '#' Peet Bros U-II Weather Station
  rawGPSorU2K, // '$' Raw GPS data or Ultimeter 2000
  microFinder, // '%' Agrelo DFJr / MicroFinder
  mapFeature, // '&' [Reserved - Map Feature]
  tmd700, // '\'' Old Mic-E Data (but current for TM-D700)
  item, // ')' Item
  peetBrosUII2, // '*' Peet Bros U-II Weather Station
  shelterData, // '+' [Reserved - Shelter data with time]
  invalidOrTestData, // ',' Invalid data or test data
  spaceWeather, // '.' [Reserved - Space Weather]
  positionTime, // '/' Position with timestamp (no APRS messaging)
  message, // ':' Message
  object, // ';' Object
  stationCapabilities, // '<' Station Capabilities
  positionMsg, // '=' Position without timestamp (with APRS messaging)
  status, // '>' Status
  query, // '?' Query
  positionTimeMsg, // '@' Position with timestamp (with APRS messaging)
  telemetry, // 'T' Telemetry data
  maidenheadGridLoc, // '[' Maidenhead grid locator beacon (obsolete)
  weatherReport, // '_' Weather Report (without position)
  micE, // '`' Current Mic-E data
  userDefined, // '{' User-Defined APRS packet format
  thirdParty, // '}' Third-party traffic
}

/// Maps the leading information-field character to a [PacketDataType].
class AprsDataType {
  static PacketDataType getDataType(int ch) {
    switch (ch) {
      case 0x00:
        return PacketDataType.unknown;
      case 0x20: // ' '
        return PacketDataType.beacon;
      case 0x1C:
        return PacketDataType.micECurrent;
      case 0x1D:
        return PacketDataType.micEOld;
      case 0x21: // '!'
        return PacketDataType.position;
      case 0x23: // '#'
        return PacketDataType.peetBrosUII1;
      case 0x24: // '$'
        return PacketDataType.rawGPSorU2K;
      case 0x25: // '%'
        return PacketDataType.microFinder;
      case 0x26: // '&'
        return PacketDataType.mapFeature;
      case 0x27: // '\''
        return PacketDataType.tmd700;
      case 0x2A: // '*'
        return PacketDataType.peetBrosUII2;
      case 0x2B: // '+'
        return PacketDataType.shelterData;
      case 0x2C: // ','
        return PacketDataType.invalidOrTestData;
      case 0x2E: // '.'
        return PacketDataType.spaceWeather;
      case 0x2F: // '/'
        return PacketDataType.positionTime;
      case 0x3A: // ':'
        return PacketDataType.message;
      case 0x3B: // ';'
        return PacketDataType.object;
      case 0x3C: // '<'
        return PacketDataType.stationCapabilities;
      case 0x3D: // '='
        return PacketDataType.positionMsg;
      case 0x3E: // '>'
        return PacketDataType.status;
      case 0x3F: // '?'
        return PacketDataType.query;
      case 0x40: // '@'
        return PacketDataType.positionTimeMsg;
      case 0x54: // 'T'
        return PacketDataType.telemetry;
      case 0x5B: // '['
        return PacketDataType.maidenheadGridLoc;
      case 0x5F: // '_'
        return PacketDataType.weatherReport;
      case 0x60: // '`'
        return PacketDataType.micE;
      case 0x7B: // '{'
        return PacketDataType.userDefined;
      case 0x7D: // '}'
        return PacketDataType.thirdParty;
      default:
        return PacketDataType.unknown;
    }
  }
}
