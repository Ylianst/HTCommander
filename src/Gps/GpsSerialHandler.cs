/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.IO.Ports;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace HTCommander.Gps
{
    /// <summary>
    /// Data Broker handler that reads NMEA sentences from a GPS serial port.
    /// Reads the "GpsSerialPort" and "GpsBaudRate" settings from device 0
    /// (as configured in SettingsForm). Parses incoming NMEA sentences and
    /// dispatches a <see cref="GpsData"/> object on Device 1 under key "GpsData".
    /// </summary>
    public class GpsSerialHandler : IDisposable
    {
        private readonly DataBrokerClient broker;
        private SerialPort _port;
        private readonly StringBuilder _lineBuffer = new StringBuilder();
        private readonly object _portLock = new object();
        private volatile SerialPort _pendingPort;        // port being opened in background task
        private string _currentPortName;
        private int _currentBaudRate;
        private GpsData _gpsData = new GpsData();
        private bool _isCommunicating;
        private bool _disposed;

        public GpsSerialHandler()
        {
            broker = new DataBrokerClient();

            // Subscribe to GPS serial port setting changes on device 0
            broker.Subscribe(0, "GpsSerialPort", OnSettingChanged);

            // Subscribe to GPS baud rate setting changes on device 0
            broker.Subscribe(0, "GpsBaudRate", OnSettingChanged);

            // Read current settings and open port if already configured
            _currentPortName = DataBroker.GetValue<string>(0, "GpsSerialPort", "None");
            _currentBaudRate = DataBroker.GetValue<int>(0, "GpsBaudRate", 4800);
            StartPort(_currentPortName, _currentBaudRate);
        }

        // ------------------------------------------------------------------
        // Settings change handler
        // ------------------------------------------------------------------

        private void OnSettingChanged(int deviceId, string name, object value)
        {
            string newPort = DataBroker.GetValue<string>(0, "GpsSerialPort", "None");
            int newBaud = DataBroker.GetValue<int>(0, "GpsBaudRate", 4800);

            // Only restart if something actually changed
            if (newPort == _currentPortName && newBaud == _currentBaudRate)
                return;

            _currentPortName = newPort;
            _currentBaudRate = newBaud;

            // Close previous port (dispatches "Disconnected")
            StopPort();

            bool portConfigured = !string.IsNullOrEmpty(_currentPortName) && _currentPortName != "None";
            if (portConfigured)
            {
                // Override "Disconnected" with "Connecting" while async open is in progress
                broker.Dispatch(1, "GpsStatus", "Connecting", store: true);
                StartPort(_currentPortName, _currentBaudRate);
            }
            else
            {
                // Port explicitly set to None — override to "Disabled"
                broker.Dispatch(1, "GpsStatus", "Disabled", store: true);
            }
        }

        // ------------------------------------------------------------------
        // Serial port lifecycle
        // ------------------------------------------------------------------

        private void StartPort(string portName, int baudRate)
        {
            if (string.IsNullOrEmpty(portName) || portName == "None")
                return;

            SerialPort port;
            try
            {
                port = new SerialPort(portName, baudRate)
                {
                    Parity      = Parity.None,
                    DataBits    = 8,
                    StopBits    = StopBits.One,
                    Handshake   = Handshake.None,
                    ReadTimeout = 2000,
                    NewLine     = "\r\n",
                    DtrEnable   = true,
                    RtsEnable   = true,
                    Encoding    = Encoding.ASCII,
                };
            }
            catch (Exception) { return; }

            // Expose the port so StopPort() can Dispose() it to interrupt a blocking Open()
            _pendingPort = port;

            // Open on a background thread so the UI never blocks.
            Task.Run(() =>
            {
                bool opened = false;
                try
                {
                    port.Open();   // may throw if _pendingPort was disposed by StopPort()
                    opened = true;
                }
                catch (Exception)
                {
                    try { port.Dispose(); } catch { }
                }
                finally
                {
                    // Clear the pending reference only if it still points to this port
                    if (_pendingPort == port) _pendingPort = null;
                }

                if (!opened)
                {
                    // Notify failure only when the port is still the intended one
                    if (!_disposed && _currentPortName == portName)
                        broker.Dispatch(1, "GpsStatus", "PortError", store: true);
                    return;
                }

                // Staleness check: settings may have changed while Open() was running
                if (_disposed || _currentPortName != portName)
                {
                    try { port.Close(); } catch { }
                    try { port.Dispose(); } catch { }
                    return;
                }

                port.DataReceived += OnDataReceived;
                lock (_portLock) { _port = port; }
            });
        }

        private void StopPort()
        {
            // Interrupt any in-flight Open() by disposing the pending port.
            // SerialPort.Dispose() closes the underlying handle, which causes the
            // blocking Open() call on the background thread to throw and return.
            var pending = _pendingPort;
            _pendingPort = null;
            if (pending != null)
            {
                try { pending.Close();   } catch { }
                try { pending.Dispose(); } catch { }
            }

            // Close the already-open port (if any)
            SerialPort port;
            lock (_portLock)
            {
                port  = _port;
                _port = null;
            }

            if (port != null && port != pending)   // avoid double-close
            {
                try { port.DataReceived -= OnDataReceived; } catch { }
                try { if (port.IsOpen) port.Close(); }      catch { }
                try { port.Dispose(); }                     catch { }
            }

            _lineBuffer.Clear();
            _gpsData = new GpsData();
            _isCommunicating = false;
            // Clear stale GPS data and update status immediately
            broker.Dispatch(1, "GpsData",   (GpsData)null,    store: true);
            broker.Dispatch(1, "GpsStatus", "Disconnected",   store: true);
        }

        // ------------------------------------------------------------------
        // Serial data reception
        // ------------------------------------------------------------------

        private void OnDataReceived(object sender, SerialDataReceivedEventArgs e)
        {
            if (_disposed || _port == null || !_port.IsOpen)
                return;

            try
            {
                string incoming = _port.ReadExisting();
                foreach (char ch in incoming)
                {
                    if (ch == '\n')
                    {
                        // Strip trailing CR if present
                        string line = _lineBuffer.ToString().TrimEnd('\r');
                        _lineBuffer.Clear();
                        if (line.Length > 0)
                            ProcessNmeaLine(line);
                    }
                    else
                    {
                        _lineBuffer.Append(ch);
                    }
                }
            }
            catch (Exception) { /* ignore read errors */ }
        }

        // ------------------------------------------------------------------
        // NMEA processing
        // ------------------------------------------------------------------

        private void ProcessNmeaLine(string line)
        {
            // NMEA sentences start with '$' and end with '*XX' checksum
            if (line.Length < 6 || line[0] != '$')
                return;

            // Validate checksum
            int starIdx = line.LastIndexOf('*');
            if (starIdx > 0 && starIdx < line.Length - 1)
            {
                if (!ValidateChecksum(line, starIdx))
                    return;
                line = line.Substring(0, starIdx); // strip checksum suffix
            }

            string[] fields = line.Split(',');
            if (fields.Length < 2)
                return;

            // First valid sentence — notify listeners the device is alive
            if (!_isCommunicating)
            {
                _isCommunicating = true;
                broker.Dispatch(1, "GpsStatus", "Communicating", store: true);
            }

            // Accept both GP (single-constellation) and GN (multi-constellation) prefixes
            string type = fields[0].Length >= 6 ? fields[0].Substring(1) : string.Empty;

            if (type == "GPRMC" || type == "GNRMC")
                ParseRmc(fields);
            else if (type == "GPGGA" || type == "GNGGA")
                ParseGga(fields);
        }

        /// <summary>
        /// Validates the NMEA XOR checksum.
        /// Returns true when the computed checksum matches the two hex digits after '*'.
        /// </summary>
        private static bool ValidateChecksum(string sentence, int starIdx)
        {
            try
            {
                byte computed = 0;
                for (int i = 1; i < starIdx; i++)
                    computed ^= (byte)sentence[i];
                string hexStr = sentence.Substring(starIdx + 1, 2);
                byte expected = Convert.ToByte(hexStr, 16);
                return computed == expected;
            }
            catch
            {
                return false;
            }
        }

        // ------------------------------------------------------------------
        // $GPRMC / $GNRMC
        // $GPRMC,hhmmss.ss,A,ddmm.mmmm,N,dddmm.mmmm,E,speed,heading,ddmmyy,,...
        // ------------------------------------------------------------------
        private void ParseRmc(string[] f)
        {
            // Minimum field count for a useful RMC sentence
            if (f.Length < 10) return;

            // Status: A = active (valid fix), V = void
            bool isFixed = f.Length > 2 && f[2] == "A";
            _gpsData.IsFixed = isFixed;

            if (!string.IsNullOrEmpty(f[1]) && f[1].Length >= 6)
                _gpsData.GpsTime = ParseNmeaDateTime(f[1], f.Length > 9 ? f[9] : string.Empty);

            if (!string.IsNullOrEmpty(f[3]) && !string.IsNullOrEmpty(f[4]))
            {
                double lat = NmeaDegreesToDecimal(f[3]);
                if (f[4] == "S") lat = -lat;
                _gpsData.Latitude = lat;
            }

            if (!string.IsNullOrEmpty(f[5]) && !string.IsNullOrEmpty(f[6]))
            {
                double lon = NmeaDegreesToDecimal(f[5]);
                if (f[6] == "W") lon = -lon;
                _gpsData.Longitude = lon;
            }

            if (!string.IsNullOrEmpty(f[7]) && double.TryParse(f[7], System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out double speed))
                _gpsData.Speed = speed;

            if (!string.IsNullOrEmpty(f[8]) && double.TryParse(f[8], System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out double heading))
                _gpsData.Heading = heading;

            broker.Dispatch(1, "GpsData", _gpsData, store: true);
        }

        // ------------------------------------------------------------------
        // $GPGGA / $GNGGA
        // $GPGGA,hhmmss.ss,ddmm.mmmm,N,dddmm.mmmm,E,q,ss,hdop,alt,M,...
        // ------------------------------------------------------------------
        private void ParseGga(string[] f)
        {
            if (f.Length < 10) return;

            if (!string.IsNullOrEmpty(f[2]) && !string.IsNullOrEmpty(f[3]))
            {
                double lat = NmeaDegreesToDecimal(f[2]);
                if (f[3] == "S") lat = -lat;
                _gpsData.Latitude = lat;
            }

            if (!string.IsNullOrEmpty(f[4]) && !string.IsNullOrEmpty(f[5]))
            {
                double lon = NmeaDegreesToDecimal(f[4]);
                if (f[5] == "W") lon = -lon;
                _gpsData.Longitude = lon;
            }

            if (!string.IsNullOrEmpty(f[6]) && int.TryParse(f[6], out int fixQuality))
                _gpsData.FixQuality = fixQuality;

            if (!string.IsNullOrEmpty(f[7]) && int.TryParse(f[7], out int sats))
                _gpsData.Satellites = sats;

            if (f.Length > 9 && !string.IsNullOrEmpty(f[9]) &&
                double.TryParse(f[9], System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out double alt))
                _gpsData.Altitude = alt;

            broker.Dispatch(1, "GpsData", _gpsData, store: true);
        }

        // ------------------------------------------------------------------
        // NMEA helpers
        // ------------------------------------------------------------------

        /// <summary>
        /// Converts an NMEA coordinate string (ddmm.mmmm or dddmm.mmmm) to
        /// decimal degrees.
        /// </summary>
        private static double NmeaDegreesToDecimal(string nmea)
        {
            if (string.IsNullOrEmpty(nmea)) return 0.0;

            double raw;
            if (!double.TryParse(nmea, System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out raw))
                return 0.0;

            // Integer part contains degrees × 100, fractional part contains minutes
            int degrees = (int)(raw / 100);
            double minutes = raw - degrees * 100.0;
            return degrees + minutes / 60.0;
        }

        /// <summary>
        /// Parses NMEA time (hhmmss or hhmmss.ss) and date (ddmmyy) strings
        /// into a UTC <see cref="DateTime"/>.
        /// </summary>
        private static DateTime ParseNmeaDateTime(string timeStr, string dateStr)
        {
            try
            {
                int h = int.Parse(timeStr.Substring(0, 2));
                int m = int.Parse(timeStr.Substring(2, 2));
                double s = double.Parse(timeStr.Substring(4),
                    System.Globalization.CultureInfo.InvariantCulture);
                int sec = (int)s;
                int ms = (int)((s - sec) * 1000);

                if (!string.IsNullOrEmpty(dateStr) && dateStr.Length == 6)
                {
                    int day = int.Parse(dateStr.Substring(0, 2));
                    int mon = int.Parse(dateStr.Substring(2, 2));
                    int yr = 2000 + int.Parse(dateStr.Substring(4, 2));
                    return new DateTime(yr, mon, day, h, m, sec, ms, DateTimeKind.Utc);
                }

                DateTime today = DateTime.UtcNow;
                return new DateTime(today.Year, today.Month, today.Day, h, m, sec, ms, DateTimeKind.Utc);
            }
            catch
            {
                return DateTime.MinValue;
            }
        }

        // ------------------------------------------------------------------
        // IDisposable
        // ------------------------------------------------------------------

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            StopPort();
            broker.Dispose();
        }
    }
}