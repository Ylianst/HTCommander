/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Windows.Forms;
using HTCommander.Gps;

namespace HTCommander.Dialogs
{
    /// <summary>
    /// Displays live GPS data received from the serial GPS handler.
    /// Subscribes to device 0 for connection settings and device 1 for
    /// <see cref="GpsData"/> updates, refreshing the ListView in real time.
    /// </summary>
    public partial class GpsDetailsForm : Form
    {
        private static GpsDetailsForm _instance;

        /// <summary>
        /// Shows the single application-wide instance of <see cref="GpsDetailsForm"/>.
        /// If the window is already open it is brought to the foreground; otherwise a
        /// new instance is created and shown.
        /// </summary>
        public static void ShowInstance(IWin32Window owner)
        {
            if (_instance == null || _instance.IsDisposed)
            {
                _instance = new GpsDetailsForm();
                _instance.FormClosed += (s, e) => { _instance = null; };
                _instance.Show(owner);
            }
            else
            {
                if (_instance.WindowState == FormWindowState.Minimized)
                    _instance.WindowState = FormWindowState.Normal;
                _instance.Focus();
            }
        }

        private DataBrokerClient broker;

        // ListView groups
        private ListViewGroup grpConnection;
        private ListViewGroup grpFix;
        private ListViewGroup grpPosition;
        private ListViewGroup grpMotion;
        private ListViewGroup grpTime;

        public GpsDetailsForm()
        {
            InitializeComponent();
            SetupListView();

            broker = new DataBrokerClient();
            broker.Subscribe(0, "GpsSerialPort", OnSettingChanged);
            broker.Subscribe(0, "GpsBaudRate", OnSettingChanged);
            broker.Subscribe(1, "GpsData", OnGpsDataChanged);

            // Populate connection info from currently stored settings
            UpdateConnectionInfo();
        }

        // ------------------------------------------------------------------
        // ListView setup — pre-populate all rows with placeholder values
        // ------------------------------------------------------------------

        private void SetupListView()
        {
            // Enable double-buffering on the ListView to prevent flicker during live updates.
            typeof(System.Windows.Forms.ListView)
                .GetProperty("DoubleBuffered",
                    System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)
                ?.SetValue(gpsListView, true);

            grpConnection = new ListViewGroup("grpConnection", "Connection");
            grpFix        = new ListViewGroup("grpFix",        "GPS Fix");
            grpPosition   = new ListViewGroup("grpPosition",   "Position");
            grpMotion     = new ListViewGroup("grpMotion",     "Motion");
            grpTime       = new ListViewGroup("grpTime",       "Time");

            gpsListView.Groups.AddRange(new[] { grpConnection, grpFix, grpPosition, grpMotion, grpTime });

            // Connection
            AddRow("Serial Port",  "-",              grpConnection);
            AddRow("Baud Rate",    "-",              grpConnection);
            AddRow("Port Status",  "Not Configured", grpConnection);

            // Fix
            AddRow("Fix",          "No Data",        grpFix);
            AddRow("Fix Quality",  "-",              grpFix);
            AddRow("Satellites",   "-",              grpFix);

            // Position
            AddRow("Latitude",       "-", grpPosition);
            AddRow("Latitude (DMS)", "-", grpPosition);
            AddRow("Longitude",       "-", grpPosition);
            AddRow("Longitude (DMS)", "-", grpPosition);
            AddRow("Altitude",       "-", grpPosition);

            // Motion
            AddRow("Speed",   "-", grpMotion);
            AddRow("Heading", "-", grpMotion);

            // Time
            AddRow("GPS Time (UTC)", "-", grpTime);
            AddRow("GPS Date",       "-", grpTime);
            AddRow("Last Update",    "-", grpTime);
        }

        private void AddRow(string name, string value, ListViewGroup group)
        {
            var item = new ListViewItem(name);
            item.SubItems.Add(value);
            item.Group = group;
            gpsListView.Items.Add(item);
        }

        /// <summary>Updates the value column of the named row.</summary>
        private void SetRow(string name, string value)
        {
            foreach (ListViewItem item in gpsListView.Items)
            {
                if (item.Text == name)
                {
                    item.SubItems[1].Text = value;
                    return;
                }
            }
        }

        // ------------------------------------------------------------------
        // Broker callbacks
        // ------------------------------------------------------------------

        private void OnSettingChanged(int deviceId, string name, object value)
        {
            UpdateConnectionInfo();
        }

        private void UpdateConnectionInfo()
        {
            string port = DataBroker.GetValue<string>(0, "GpsSerialPort", "None");
            int baud    = DataBroker.GetValue<int>(0, "GpsBaudRate", 4800);

            SetRow("Serial Port", string.IsNullOrEmpty(port) ? "None" : port);
            SetRow("Baud Rate",   baud + " baud");

            bool configured = !string.IsNullOrEmpty(port) && port != "None";
            SetRow("Port Status", configured ? "Configured" : "Not Configured");
        }

        private void OnGpsDataChanged(int deviceId, string name, object value)
        {
            if (!(value is GpsData gps)) return;

            // ---- Fix ----
            SetRow("Fix", gps.IsFixed ? "Active" : "No Fix");

            string qualDesc;
            switch (gps.FixQuality)
            {
                case 1:  qualDesc = "GPS Fix (1)";  break;
                case 2:  qualDesc = "DGPS Fix (2)"; break;
                case 0:  qualDesc = "Invalid (0)";  break;
                default: qualDesc = gps.FixQuality + " (unknown)"; break;
            }
            SetRow("Fix Quality", qualDesc);
            SetRow("Satellites",  gps.Satellites.ToString());

            // ---- Position ----
            if (gps.Latitude != 0.0 || gps.Longitude != 0.0)
            {
                string latDir = gps.Latitude  >= 0 ? "N" : "S";
                string lonDir = gps.Longitude >= 0 ? "E" : "W";
                double absLat = Math.Abs(gps.Latitude);
                double absLon = Math.Abs(gps.Longitude);

                SetRow("Latitude",        string.Format("{0:F6}° {1}", absLat, latDir));
                SetRow("Latitude (DMS)",  FormatDMS(absLat) + " " + latDir);
                SetRow("Longitude",       string.Format("{0:F6}° {1}", absLon, lonDir));
                SetRow("Longitude (DMS)", FormatDMS(absLon) + " " + lonDir);
            }

            SetRow("Altitude", string.Format("{0:F1} m  ({1:F1} ft)",
                gps.Altitude, gps.Altitude * 3.28084));

            // ---- Motion ----
            double kmh = gps.Speed * 1.852;
            double mph = gps.Speed * 1.15078;
            SetRow("Speed",   string.Format("{0:F1} kn  ({1:F1} km/h  /  {2:F1} mph)",
                gps.Speed, kmh, mph));
            SetRow("Heading", string.Format("{0:F1}°  ({1})",
                gps.Heading, HeadingToCompass(gps.Heading)));

            // ---- Time ----
            if (gps.GpsTime != DateTime.MinValue)
            {
                SetRow("GPS Time (UTC)", gps.GpsTime.ToString("HH:mm:ss.f"));
                SetRow("GPS Date",       gps.GpsTime.ToString("dd MMM yyyy"));
            }
            SetRow("Last Update", DateTime.Now.ToString("HH:mm:ss.f"));

            // Once data is flowing the port is confirmed open
            SetRow("Port Status", "Open — Receiving Data");
        }

        // ------------------------------------------------------------------
        // Helpers
        // ------------------------------------------------------------------

        /// <summary>
        /// Converts a positive decimal-degree value to a DDD° MM' SS.SS" string.
        /// </summary>
        private static string FormatDMS(double decDeg)
        {
            int    deg = (int)decDeg;
            double minFull = (decDeg - deg) * 60.0;
            int    min = (int)minFull;
            double sec = (minFull - min) * 60.0;
            return string.Format("{0}° {1:D2}' {2:F2}\"", deg, min, sec);
        }

        /// <summary>
        /// Returns a 16-point compass abbreviation for a true-north heading in degrees.
        /// </summary>
        private static string HeadingToCompass(double heading)
        {
            string[] pts = { "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                             "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW" };
            int index = (int)Math.Round(heading / 22.5) % 16;
            return pts[index < 0 ? index + 16 : index];
        }

        // ------------------------------------------------------------------
        // Form events
        // ------------------------------------------------------------------

        private void closeButton_Click(object sender, EventArgs e)
        {
            Close();
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            broker?.Dispose();
            base.OnFormClosed(e);
        }
    }
}