using System;
using System.Text;
using System.Collections.Generic;
using static HTCommander.AX25Packet;

namespace HTCommander.AprsParser
{
    internal class AprsAuth
    {
        public static string addAprsAuth(List<StationInfoClass> stations, string srcAddress, string destAddress, string aprsMessage, int msgId, DateTime time, out bool authApplied)
        {
            // APRS Address
            string aprsAddr = destAddress;
            while (aprsAddr.Length < 9) { aprsAddr += " "; }

            // Search for a APRS authentication key
            string authPassword = null;
            foreach (StationInfoClass station in stations)
            {
                if ((station.StationType == StationInfoClass.StationTypes.APRS) && (station.Callsign.CompareTo(destAddress) == 0) && !string.IsNullOrEmpty(station.AuthPassword)) { authPassword = station.AuthPassword; }
            }

            // If the auth key is not present, send without authentication
            if (string.IsNullOrEmpty(authPassword)) { authApplied = false; return ":" + aprsAddr + ":" + aprsMessage + "{" + msgId; }

            // Compute the current time in minutes
            DateTime truncated = new DateTime(time.Year, time.Month, time.Day, time.Hour, time.Minute, 0);
            DateTime unixEpoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            TimeSpan timeSinceEpoch = time.ToUniversalTime() - unixEpoch;
            long minutesSinceEpoch = (long)timeSinceEpoch.TotalMinutes;

            // Compute authentication token
            byte[] authKey = Utils.ComputeSha256Hash(UTF8Encoding.UTF8.GetBytes(authPassword));
            //Console.WriteLine("AuthKey: " + Utils.BytesToHex(authKey));
            string x1 = minutesSinceEpoch + ":" + srcAddress + ":" + aprsAddr.Trim() + ":" + aprsMessage + "{" + msgId;
            //Console.WriteLine("Hash: " + x1);
            byte[] authCode = Utils.ComputeHmacSha256Hash(authKey, UTF8Encoding.UTF8.GetBytes(minutesSinceEpoch + ":" + srcAddress + ":" + aprsAddr.Trim() + ":" + aprsMessage + "{" + msgId));
            //Console.WriteLine("authHash (hex): " + Utils.BytesToHex(authCode));
            //Console.WriteLine("authHash (base64): " + Convert.ToBase64String(authCode));
            string authCodeBase64 = Convert.ToBase64String(authCode).Substring(0, 6);
            //Console.WriteLine("authCodeBase64: " + authCodeBase64);

            // Add authentication token to APRS message
            authApplied = true;
            return ":" + aprsAddr + ":" + aprsMessage + "}" + authCodeBase64 + "{" + msgId;
        }

        public static string addAprsAuthNoMsgId(List<StationInfoClass> stations, string srcAddress, string destAddress, string aprsMessage, DateTime time, out bool authApplied)
        {
            // APRS Address
            string aprsAddr = destAddress;
            while (aprsAddr.Length < 9) { aprsAddr += " "; }

            // Search for a APRS authentication key
            string authPassword = null;
            foreach (StationInfoClass station in stations)
            {
                if ((station.StationType == StationInfoClass.StationTypes.APRS) && (station.Callsign.CompareTo(destAddress) == 0) && !string.IsNullOrEmpty(station.AuthPassword)) { authPassword = station.AuthPassword; }
            }

            // If the auth key is not present, send without authentication
            if (string.IsNullOrEmpty(authPassword)) { authApplied = false; return ":" + aprsAddr + aprsMessage; }

            // Compute the current time in minutes
            DateTime truncated = new DateTime(time.Year, time.Month, time.Day, time.Hour, time.Minute, 0);
            DateTime unixEpoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            TimeSpan timeSinceEpoch = time.ToUniversalTime() - unixEpoch;
            long minutesSinceEpoch = (long)timeSinceEpoch.TotalMinutes;

            // Compute authentication token
            byte[] authKey = Utils.ComputeSha256Hash(UTF8Encoding.UTF8.GetBytes(authPassword));
            //Console.WriteLine("AuthKey: " + Utils.BytesToHex(authKey));
            string x1 = minutesSinceEpoch + ":" + srcAddress + ":" + aprsAddr.Trim() + aprsMessage;
            //Console.WriteLine("Hash: " + x1);
            byte[] authCode = Utils.ComputeHmacSha256Hash(authKey, UTF8Encoding.UTF8.GetBytes(minutesSinceEpoch + ":" + srcAddress + ":" + aprsAddr.Trim() + aprsMessage));
            //Console.WriteLine("authHash (hex): " + Utils.BytesToHex(authCode));
            //Console.WriteLine("authHash (base64): " + Convert.ToBase64String(authCode));
            string authCodeBase64 = Convert.ToBase64String(authCode).Substring(0, 6);
            //Console.WriteLine("authCodeBase64: " + authCodeBase64);

            // Add authentication token to APRS message
            authApplied = true;
            return ":" + aprsAddr + aprsMessage + "}" + authCodeBase64;
        }

        public static AX25Packet.AuthState checkAprsAuth(List<StationInfoClass> stations, bool sender, string srcAddress, string aprsMessage, DateTime time)
        {
            string keyAddr = null;
            string aprsAddr = aprsMessage.Substring(1, 9);

            if (sender)
            {
                // We are the sender, so get the outbound address auth key
                keyAddr = aprsAddr.Trim();
            }
            else
            {
                // We are the receiver, we use the source address auth key
                keyAddr = srcAddress;
            }

            // Search for a APRS authentication key
            string authPassword = null;
            foreach (StationInfoClass station in stations)
            {
                if ((station.StationType == StationInfoClass.StationTypes.APRS) && (station.Callsign.CompareTo(keyAddr) == 0) && !string.IsNullOrEmpty(station.AuthPassword)) { authPassword = station.AuthPassword; }
            }

            // No auth key found
            if (string.IsNullOrEmpty(authPassword)) return AuthState.None;

            string msgId = null;
            bool msgIdPresent = false;
            string[] msplit1 = aprsMessage.Substring(11).Split('{');
            if (msplit1.Length == 2) { msgIdPresent = true; msgId = msplit1[1]; }
            string[] msplit2 = msplit1[0].Split('}');
            if (msplit2.Length != 2) return 0;
            string authCodeBase64Check = msplit2[1];
            aprsMessage = msplit2[0];

            // Compute the current time in minutes
            DateTime truncated = new DateTime(time.Year, time.Month, time.Day, time.Hour, time.Minute, 0);
            DateTime unixEpoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            TimeSpan timeSinceEpoch = time.ToUniversalTime() - unixEpoch;
            long minutesSinceEpoch = (long)timeSinceEpoch.TotalMinutes - 2;
            byte[] authKey = Utils.ComputeSha256Hash(UTF8Encoding.UTF8.GetBytes(authPassword));
            string hashMsg = ":" + srcAddress + ":" + aprsAddr.Trim() + ":" + aprsMessage;
            if (msgIdPresent) { hashMsg += "{" + msgId; }

            for (long x = minutesSinceEpoch; x < (minutesSinceEpoch + 5); x++)
            {
                //string x1 = x + ":" + srcAddress + ":" + aprsAddr + ":" + aprsMessage + "{" + msgId;
                string authCodeBase64 = Convert.ToBase64String(Utils.ComputeHmacSha256Hash(authKey, UTF8Encoding.UTF8.GetBytes(x + hashMsg))).Substring(0, 6);
                if (authCodeBase64Check == authCodeBase64) return AuthState.Success; // Verified authentication
            }

            return AuthState.Failed; // Bad auth
        }
    }
}
