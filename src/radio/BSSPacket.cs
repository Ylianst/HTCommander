/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Text;
using System.Collections.Generic;

namespace HTCommander
{
    /// <summary>
    /// Represents a BSS (Binary Short Serialization) packet used for compact data encoding.
    /// The packet format is: 0x01 [length][type][value...] [length][type][value...] ...
    /// Where length includes the type byte (length = 1 + value.Length).
    /// </summary>
    public class BSSPacket
    {
        /// <summary>
        /// BSS packet type identifiers.
        /// </summary>
        public enum FieldType : byte
        {
            Callsign = 0x20,
            Destination = 0x21,
            Message = 0x24,
            Location = 0x25
        }

        /// <summary>
        /// The callsign field (type 0x20).
        /// </summary>
        public string Callsign { get; set; }

        /// <summary>
        /// The Destination field (type 0x21).
        /// </summary>
        public string Destination { get; set; }

        /// <summary>
        /// The message field (type 0x24).
        /// </summary>
        public string Message { get; set; }

        /// <summary>
        /// The location field (type 0x25).
        /// </summary>
        public HTCommander.GpsLocation Location { get; set; }

        /// <summary>
        /// Dictionary containing raw field values for unknown or future field types.
        /// Key is the field type byte, value is the raw byte array.
        /// </summary>
        public Dictionary<byte, byte[]> RawFields { get; private set; }

        /// <summary>
        /// Creates an empty BSS packet.
        /// </summary>
        public BSSPacket()
        {
            RawFields = new Dictionary<byte, byte[]>();
        }

        /// <summary>
        /// Creates a BSS packet with the specified callsign and message.
        /// </summary>
        /// <param name="callsign">The callsign to include in the packet.</param>
        /// <param name="message">The message to include in the packet.</param>
        public BSSPacket(string callsign, string destination, string message = null)
        {
            Callsign = callsign;
            Destination = destination;
            Message = message;
            RawFields = new Dictionary<byte, byte[]>();
        }

        /// <summary>
        /// Decodes a BSS packet from raw byte data.
        /// </summary>
        /// <param name="data">The raw byte data starting with 0x01.</param>
        /// <returns>A BSSPacket instance, or null if the data is invalid.</returns>
        public static BSSPacket Decode(byte[] data)
        {
            if (data == null || data.Length < 2)
                return null;

            // BSS packets must start with 0x01
            if (data[0] != 0x01)
                return null;

            BSSPacket packet = new BSSPacket();
            int index = 1; // Skip the leading 0x01

            while (index < data.Length)
            {
                // Need at least length + type bytes
                if (index + 1 >= data.Length)
                    break;

                byte length = data[index];
                byte fieldType = data[index + 1];

                // Length must allow type (1) + value (0+)
                if (length < 1)
                    break;

                int valueLen = length - 1;

                // Check if we have enough bytes for the value
                if (index + 2 + valueLen > data.Length)
                    break;

                byte[] value = new byte[valueLen];
                if (valueLen > 0)
                {
                    Array.Copy(data, index + 2, value, 0, valueLen);
                }

                // Store the raw field
                packet.RawFields[fieldType] = value;

                // Parse known field types
                switch (fieldType)
                {
                    case (byte)FieldType.Callsign:
                        packet.Callsign = Encoding.UTF8.GetString(value);
                        break;
                    case (byte)FieldType.Destination:
                        packet.Destination = Encoding.UTF8.GetString(value);
                        break;
                    case (byte)FieldType.Message:
                        packet.Message = Encoding.UTF8.GetString(value);
                        break;
                    case (byte)FieldType.Location:
                        packet.Location = HTCommander.GpsLocation.DecodeGpsBytes(value);
                        break;
                }

                // Move to the next field
                index += 2 + valueLen;
            }

            return packet;
        }

        /// <summary>
        /// Encodes this BSS packet to a byte array.
        /// </summary>
        /// <returns>The encoded byte array starting with 0x01.</returns>
        public byte[] Encode()
        {
            List<byte> result = new List<byte>();
            result.Add(0x01); // BSS packet identifier

            // Encode callsign if present
            if (!string.IsNullOrEmpty(Callsign))
            {
                byte[] callsignBytes = Encoding.UTF8.GetBytes(Callsign);
                result.Add((byte)(callsignBytes.Length + 1)); // length = value length + 1 for type
                result.Add((byte)FieldType.Callsign);
                result.AddRange(callsignBytes);
            }

            // Encode destination if present
            if (!string.IsNullOrEmpty(Destination))
            {
                byte[] destinationBytes = Encoding.UTF8.GetBytes(Destination);
                result.Add((byte)(destinationBytes.Length + 1)); // length = value length + 1 for type
                result.Add((byte)FieldType.Destination);
                result.AddRange(destinationBytes);
            }

            // Encode message if present
            if (!string.IsNullOrEmpty(Message))
            {
                byte[] messageBytes = Encoding.UTF8.GetBytes(Message);
                result.Add((byte)(messageBytes.Length + 1)); // length = value length + 1 for type
                result.Add((byte)FieldType.Message);
                result.AddRange(messageBytes);
            }

            // Encode location if present
            if (Location != null)
            {
                byte[] locationBytes = Location.EncodeToGpsBytes();
                result.Add((byte)(locationBytes.Length + 1)); // length = value length + 1 for type
                result.Add((byte)FieldType.Location);
                result.AddRange(locationBytes);
            }

            // Encode any additional raw fields that weren't already encoded
            foreach (var field in RawFields)
            {
                // Skip fields we've already encoded
                if (field.Key == (byte)FieldType.Callsign && !string.IsNullOrEmpty(Callsign))
                    continue;
                if (field.Key == (byte)FieldType.Destination && !string.IsNullOrEmpty(Destination))
                    continue;
                if (field.Key == (byte)FieldType.Message && !string.IsNullOrEmpty(Message))
                    continue;

                result.Add((byte)(field.Value.Length + 1)); // length = value length + 1 for type
                result.Add(field.Key);
                result.AddRange(field.Value);
            }

            return result.ToArray();
        }

        /// <summary>
        /// Checks if the given data appears to be a BSS packet.
        /// </summary>
        /// <param name="data">The data to check.</param>
        /// <returns>True if the data starts with 0x01 and has enough length to be a valid BSS packet.</returns>
        public static bool IsBSSPacket(byte[] data)
        {
            return data != null && data.Length >= 2 && data[0] == 0x01;
        }

        /// <summary>
        /// Gets or sets a raw field value by type.
        /// </summary>
        /// <param name="fieldType">The field type byte.</param>
        /// <returns>The raw byte array value, or null if not present.</returns>
        public byte[] GetRawField(byte fieldType)
        {
            return RawFields.TryGetValue(fieldType, out byte[] value) ? value : null;
        }

        /// <summary>
        /// Sets a raw field value by type.
        /// </summary>
        /// <param name="fieldType">The field type byte.</param>
        /// <param name="value">The raw byte array value.</param>
        public void SetRawField(byte fieldType, byte[] value)
        {
            RawFields[fieldType] = value ?? new byte[0];
        }

        /// <summary>
        /// Returns a string representation of the BSS packet.
        /// </summary>
        /// <returns>A human-readable string describing the packet contents.</returns>
        public override string ToString()
        {
            StringBuilder sb = new StringBuilder();
            bool first = true;

            if (!string.IsNullOrEmpty(Callsign))
            {
                sb.Append("Callsign: " + Callsign);
                first = false;
            }

            if (!string.IsNullOrEmpty(Destination))
            {
                if (!first) sb.Append(", ");
                sb.Append("Dest: " + Destination);
                first = false;
            }

            if (!string.IsNullOrEmpty(Message))
            {
                if (!first) sb.Append(", ");
                sb.Append("Msg: " + Message);
                first = false;
            }

            if (Location != null)
            {
                if (!first) sb.Append(", ");
                sb.Append("Loc: " + Location.ToString());
                first = false;
            }

            // Include any unknown raw fields
            foreach (var field in RawFields)
            {
                if (field.Key == (byte)FieldType.Callsign || field.Key == (byte)FieldType.Destination || field.Key == (byte)FieldType.Message || field.Key == (byte)FieldType.Location)
                    continue;

                if (!first) sb.Append(", ");
                sb.Append(field.Key + ": " + Utils.BytesToHex(field.Value));
                first = false;
            }

            return sb.ToString();
        }
    }
}