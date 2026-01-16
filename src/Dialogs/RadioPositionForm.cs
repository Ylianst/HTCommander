/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Reflection;
using System.Windows.Forms;
using HTCommander.radio;

namespace HTCommander
{
    public partial class RadioPositionForm : Form
    {
        private int deviceId;
        private DataBrokerClient broker;

        public RadioPositionForm(int deviceId)
        {
            InitializeComponent();
            this.deviceId = deviceId;

            // Enable double buffering on the ListView to prevent flicker
            EnableDoubleBuffering(mainListView);

            // Create data broker client
            broker = new DataBrokerClient();

            // Subscribe to position updates
            broker.Subscribe(deviceId, "Position", OnPositionChanged);

            // Subscribe to friendly name updates
            broker.Subscribe(deviceId, "FriendlyName", OnFriendlyNameChanged);

            // Set initial title with current friendly name
            UpdateTitle();

            // Load current position if available
            RadioPosition position = broker.GetValue<RadioPosition>(deviceId, "Position", null);
            UpdatePosition(position);
        }

        private void UpdateTitle()
        {
            string friendlyName = broker.GetValue<string>(deviceId, "FriendlyName", null);
            if (!string.IsNullOrEmpty(friendlyName))
            {
                this.Text = "Radio Position - " + friendlyName;
            }
            else
            {
                this.Text = "Radio Position";
            }
        }

        private void OnFriendlyNameChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => OnFriendlyNameChanged(deviceId, name, data)));
                return;
            }

            string friendlyName = data as string;
            if (!string.IsNullOrEmpty(friendlyName))
            {
                this.Text = "Radio Position - " + friendlyName;
            }
            else
            {
                this.Text = "Radio Position";
            }
        }

        private void OnPositionChanged(int deviceId, string name, object data)
        {
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => OnPositionChanged(deviceId, name, data)));
                return;
            }

            if (data is RadioPosition position)
            {
                UpdatePosition(position);
            }
        }

        private void refreshButton_Click(object sender, EventArgs e)
        {
            // Request a fresh GPS position by dispatching a command
            // The radio will handle this and dispatch the Position event when received
            broker.Dispatch(deviceId, "GetPosition", null, store: false);
        }

        private void closeButton_Click(object sender, EventArgs e)
        {
            Close();
        }

        private void addItem(string name, string value)
        {
            foreach (ListViewItem l in mainListView.Items)
            {
                if (l.SubItems[0].Text == name) { l.SubItems[1].Text = value; return; }
            }
            mainListView.Items.Add(new ListViewItem(new string[2] { name, value }));
        }

        public void UpdatePosition(RadioPosition position)
        {
            // Use BeginUpdate/EndUpdate to prevent flicker during batch updates
            mainListView.BeginUpdate();
            try
            {
                if ((position != null) && (position.Status == Radio.RadioCommandState.SUCCESS))
                {
                    addItem("Latitude", position.LatitudeStr);
                    addItem("Longitude", position.LongitudeStr);
                    if (position.Time != DateTime.MinValue)
                    {
                        addItem("Accuracy", position.Accuracy.ToString() + " meters");
                        addItem("Altitude", position.Altitude.ToString() + " meters");
                        addItem("Speed", position.Speed.ToString());
                        addItem("Heading", position.Heading.ToString() + " degrees");
                        addItem("Received Time", position.ReceivedTime.ToString("yyyy-MM-dd HH:mm:ss"));
                        addItem("GPS Time Local", position.Time.ToString("yyyy-MM-dd HH:mm:ss"));
                        addItem("GPS Time UTC", position.TimeUTC.ToString("yyyy-MM-dd HH:mm:ss"));
                    }
                    if (position.Locked)
                    {
                        addItem("GPS Lock", "Yes");
                    }
                    else
                    {
                        addItem("GPS Lock", "Acquiring...");
                    }
                }
                else
                {
                    addItem("Status", "No GPS lock");
                }
            }
            finally
            {
                mainListView.EndUpdate();
            }
        }

        private void RadioPositionForm_FormClosed(object sender, FormClosedEventArgs e)
        {
            // Dispose the broker to unsubscribe from all events
            broker?.Dispose();
            broker = null;
        }

        /// <summary>
        /// Enables double buffering on a ListView control using reflection to access the protected DoubleBuffered property.
        /// </summary>
        private static void EnableDoubleBuffering(ListView listView)
        {
            // Use reflection to set the protected DoubleBuffered property
            PropertyInfo prop = typeof(ListView).GetProperty("DoubleBuffered", BindingFlags.Instance | BindingFlags.NonPublic);
            prop?.SetValue(listView, true, null);
        }

    }
}
