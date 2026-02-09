/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Threading;
using System.Windows.Forms;
using System.Collections.Generic;
using GMap.NET;
using GMap.NET.MapProviders;
using GMap.NET.WindowsForms;
using GMap.NET.WindowsForms.Markers;
using HTCommander.Dialogs;
using HTCommander.radio;
using aprsparser;

namespace HTCommander.Controls
{
    public partial class MapTabUserControl : UserControl
    {
        private DataBrokerClient broker;
        private bool _showDetach = false;

        /// <summary>
        /// Gets or sets whether the "Detach..." menu item is visible.
        /// </summary>
        [System.ComponentModel.Category("Behavior")]
        [System.ComponentModel.Description("Gets or sets whether the Detach menu item is visible.")]
        [System.ComponentModel.DefaultValue(false)]
        public bool ShowDetach
        {
            get { return _showDetach; }
            set
            {
                _showDetach = value;
                if (detachToolStripMenuItem != null)
                {
                    detachToolStripMenuItem.Visible = value;
                    toolStripMenuItemDetachSeparator.Visible = value;
                }
            }
        }
        private CancellationTokenSource cts = null;
        private CustomTilePrefetcher prefetcher = null;
        private Point startPoint;
        private Rectangle selectionRect;
        private bool isSelecting = false;
        public GMapOverlay mapMarkersOverlay = new GMapOverlay("AprsMarkers");
        public Dictionary<string, GMapRoute> mapRoutes = new Dictionary<string, GMapRoute>();

        // Radio markers keyed by device ID
        private Dictionary<int, GMapMarker> radioMarkers = new Dictionary<int, GMapMarker>();

        // Index for cycling through radio positions when clicking "Center to GPS"
        private int centerToGpsCycleIndex = 0;

        public GMapControl MapControl { get { return mapControl; } }
        public GMapOverlay MapMarkersOverlay { get { return mapMarkersOverlay; } }

        public MapTabUserControl()
        {
            InitializeComponent();

            // Initialize the DataBroker client
            broker = new DataBrokerClient();

            // Initialize the map control
            InitializeMapControl();

            // Load settings from DataBroker
            LoadSettings();

            // Load initial positions for any already connected radios
            LoadInitialRadioPositions();

            // Subscribe to Position updates from all devices
            broker.Subscribe(DataBroker.AllDevices, "Position", OnPositionChanged);

            // Subscribe to APRS events for map markers
            broker.Subscribe(1, "AprsFrame", OnAprsFrame);
            broker.Subscribe(1, "AprsStoreReady", OnAprsStoreReady);
            broker.Subscribe(1, "AprsPacketList", OnAprsPacketList);

            // Request the current packet list from AprsHandler on-demand
            broker.Dispatch(1, "RequestAprsPackets", null, store: false);
        }

        private void LoadInitialRadioPositions()
        {
            // Read connected radios from DataBroker
            var connectedRadios = broker.GetValue<System.Collections.IList>(1, "ConnectedRadios", null);
            if (connectedRadios == null)
            {
                UpdateCenterToGpsButtonState();
                return;
            }

            foreach (var radioObj in connectedRadios)
            {
                if (radioObj == null) continue;

                // Get DeviceId from the anonymous type
                var radioType = radioObj.GetType();
                var deviceIdProp = radioType.GetProperty("DeviceId");
                if (deviceIdProp == null) continue;

                int deviceId = (int)deviceIdProp.GetValue(radioObj);
                if (deviceId <= 0) continue;

                // Try to get the position for this device
                RadioPosition position = broker.GetValue<RadioPosition>(deviceId, "Position", null);
                if (position != null && position.Status == Radio.RadioCommandState.SUCCESS && position.IsGpsLocked())
                {
                    UpdateRadioMarker(deviceId, position);
                }
            }

            // Update button state after loading initial positions
            UpdateCenterToGpsButtonState();
        }

        private void InitializeMapControl()
        {
            mapControl.MapProvider = GMapProviders.OpenStreetMap;
            mapControl.ShowCenter = false;
            mapControl.MinZoom = 3;
            mapControl.MaxZoom = 20;
            mapControl.CanDragMap = true;
            mapControl.MouseWheelZoomType = GMap.NET.MouseWheelZoomType.MousePositionAndCenter;
            mapControl.IgnoreMarkerOnMouseWheel = true;
            mapControl.DragButton = MouseButtons.Left;
            mapControl.DisableFocusOnMouseEnter = true;

            // Load saved position and zoom from DataBroker (device 0 persists to registry)
            double zoom = broker.GetValue<int>(0, "MapZoom", 3);
            mapControl.Zoom = zoom;

            string latStr = broker.GetValue<string>(0, "MapLatitude", "0");
            string lngStr = broker.GetValue<string>(0, "MapLongitude", "0");
            if (!double.TryParse(latStr, out double lat)) { lat = 0; }
            if (!double.TryParse(lngStr, out double lng)) { lng = 0; }
            mapControl.Position = new PointLatLng(lat, lng);

            // Add the overlay to the map
            mapControl.Overlays.Add(mapMarkersOverlay);
            mapControl.Update();
            mapControl.Refresh();
        }

        private void LoadSettings()
        {
            int offlineMode = broker.GetValue<int>(0, "MapOfflineMode", 0);
            offlineModeToolStripMenuItem.Checked = (offlineMode == 1);
            cacheAreaToolStripMenuItem.Enabled = !offlineModeToolStripMenuItem.Checked;
            mapControl.Manager.Mode = offlineModeToolStripMenuItem.Checked ? AccessMode.CacheOnly : AccessMode.ServerAndCache;
            mapTopLabel.Text = offlineModeToolStripMenuItem.Checked ? "Offline Map" : "Map";

            int showTracks = broker.GetValue<int>(0, "MapShowTracks", 1);
            showTracksToolStripMenuItem.Checked = (showTracks == 1);

            int largeMarkers = broker.GetValue<int>(0, "MapLargeMarkers", 1);
            largeMarkersToolStripMenuItem.Checked = (largeMarkers == 1);

            int mapFilterMinutes = broker.GetValue<int>(0, "MapTimeFilter", 0);
            foreach (ToolStripMenuItem i in showMarkersToolStripMenuItem.DropDownItems)
            {
                i.Checked = (int.Parse((string)((ToolStripMenuItem)i).Tag) == mapFilterMinutes);
            }
        }

        private void OnPositionChanged(int deviceId, string name, object data)
        {
            if (deviceId <= 0) return; // Ignore device 0 (app settings)

            if (data == null)
            {
                // Position is null - remove the marker for this device
                RemoveRadioMarker(deviceId);
            }
            else if (data is RadioPosition position)
            {
                if (position.Status == Radio.RadioCommandState.SUCCESS && position.IsGpsLocked())
                {
                    // Valid position - add or update marker
                    UpdateRadioMarker(deviceId, position);
                }
                else
                {
                    // Invalid position or GPS not locked - remove marker
                    RemoveRadioMarker(deviceId);
                }
            }

            // Update the Center to GPS button state based on available radio markers
            UpdateCenterToGpsButtonState();
        }

        private void UpdateRadioMarker(int deviceId, RadioPosition position)
        {
            // Get the radio's friendly name for the tooltip
            string friendlyName = broker.GetValue<string>(deviceId, "FriendlyName", $"Radio {deviceId}");
            string tooltipText = $"\r\n{friendlyName}\r\n{position.ReceivedTime}";

            if (radioMarkers.TryGetValue(deviceId, out GMapMarker existingMarker))
            {
                // Update existing marker
                existingMarker.Position = new PointLatLng(position.Latitude, position.Longitude);
                existingMarker.ToolTipText = tooltipText;
                existingMarker.Tag = position.ReceivedTime;
            }
            else
            {
                // Create new marker (blue for connected radios)
                GMarkerGoogleType markerType = largeMarkersToolStripMenuItem.Checked
                    ? GMarkerGoogleType.blue_dot
                    : GMarkerGoogleType.blue_small;

                GMapMarker marker = new GMarkerGoogle(
                    new PointLatLng(position.Latitude, position.Longitude),
                    markerType);
                marker.Tag = position.ReceivedTime;
                marker.ToolTipText = tooltipText;
                marker.ToolTipMode = MarkerTooltipMode.OnMouseOver;
                marker.ToolTip.TextPadding = new Size(4, 8);
                marker.IsVisible = true;

                radioMarkers[deviceId] = marker;
                mapMarkersOverlay.Markers.Add(marker);
            }
        }

        private void RemoveRadioMarker(int deviceId)
        {
            if (radioMarkers.TryGetValue(deviceId, out GMapMarker marker))
            {
                mapMarkersOverlay.Markers.Remove(marker);
                radioMarkers.Remove(deviceId);

                // Reset cycle index if it's now out of bounds
                if (centerToGpsCycleIndex >= radioMarkers.Count)
                {
                    centerToGpsCycleIndex = 0;
                }
            }
        }

        public void UpdateCenterToGpsButton(bool enabled)
        {
            centerToGpsButton.Enabled = enabled;
            centerToGPSToolStripMenuItem.Enabled = enabled;
        }

        private void UpdateCenterToGpsButtonState()
        {
            // Enable the button if there's at least one radio marker with a valid position
            bool hasValidPosition = radioMarkers.Count > 0;
            centerToGpsButton.Enabled = hasValidPosition;
            centerToGPSToolStripMenuItem.Enabled = hasValidPosition;
        }

        #region APRS Marker Code

        // Flag to prevent loading historical packets multiple times
        private bool _historicalPacketsLoaded = false;

        /// <summary>
        /// Handles the AprsStoreReady event - the store is now ready, request packets.
        /// </summary>
        private void OnAprsStoreReady(int deviceId, string name, object data)
        {
            // Ignore if we've already loaded historical packets
            if (_historicalPacketsLoaded) return;
            // The APRS store is ready, request the packet list
            broker.Dispatch(1, "RequestAprsPackets", null, store: false);
        }

        /// <summary>
        /// Handles the AprsPacketList event - loads APRS packets from the on-demand request.
        /// </summary>
        private void OnAprsPacketList(int deviceId, string name, object data)
        {
            // Ignore if we've already loaded historical packets
            if (_historicalPacketsLoaded) return;
            if (!(data is List<AprsPacket> packets)) return;
            _historicalPacketsLoaded = true;
            LoadHistoricalAprsPackets(packets);
        }

        /// <summary>
        /// Handles incoming AprsFrame events from the Data Broker.
        /// </summary>
        private void OnAprsFrame(int deviceId, string name, object data)
        {
            if (!(data is AprsFrameEventArgs args)) return;
            if (args.AprsPacket == null) return;

            ProcessAprsPacketForMap(args.AprsPacket);
        }

        /// <summary>
        /// Loads historical APRS packets onto the map.
        /// </summary>
        private void LoadHistoricalAprsPackets(List<AprsPacket> historicalPackets)
        {
            if (historicalPackets == null) return;

            foreach (AprsPacket aprsPacket in historicalPackets)
            {
                ProcessAprsPacketForMap(aprsPacket);
            }
        }

        /// <summary>
        /// Processes an APRS packet and adds it to the map if it has a valid position.
        /// </summary>
        private void ProcessAprsPacketForMap(AprsPacket aprsPacket)
        {
            if (aprsPacket?.Packet == null) return;
            if (aprsPacket.Position == null) return;

            // Check if position is valid (non-zero coordinates)
            double lat = aprsPacket.Position.CoordinateSet.Latitude.Value;
            double lng = aprsPacket.Position.CoordinateSet.Longitude.Value;
            if (lat == 0 && lng == 0) return;

            // Get the callsign from the packet
            AX25Packet packet = aprsPacket.Packet;
            if (packet.addresses == null || packet.addresses.Count < 2) return;

            string callsign = packet.addresses[1].CallSignWithId;
            DateTime time = packet.time;

            // Add the marker to the map (this handles tracks and updates existing markers)
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => AddMapMarker(callsign, lat, lng, time)));
            }
            else
            {
                AddMapMarker(callsign, lat, lng, time);
            }
        }

        public void AddMapMarker(string callsign, double lat, double lng, DateTime time)
        {
            int mapFilterMinutes = broker.GetValue<int>(0, "MapTimeFilter", 0);

            GMapRoute route = null;
            if (mapRoutes.ContainsKey(callsign))
            {
                route = mapRoutes[callsign];
            }
            else
            {
                route = new GMapRoute(callsign) { Stroke = new Pen(callsign == "Self" ? Color.Blue : Color.Red, 1) };
                mapRoutes.Add(callsign, route);
                mapMarkersOverlay.Routes.Add(route);
            }

            if (route.Points.Count == 0)
            {
                route.Points.Add(new PointLatLng(lat, lng));
            }
            else
            {
                PointLatLng lastPoint = route.Points[route.Points.Count - 1];
                if ((lastPoint.Lat != lat) || (lastPoint.Lng != lng))
                {
                    route.Points.Add(new PointLatLng(lat, lng));
                }
            }
            route.Tag = time;
            route.IsVisible = showTracksToolStripMenuItem.Checked && ((mapFilterMinutes == 0) || (DateTime.Now.CompareTo(time.AddMinutes(mapFilterMinutes)) <= 0));

            foreach (GMapMarker m in mapMarkersOverlay.Markers)
            {
                if (m.ToolTipText != null && m.ToolTipText.StartsWith("\r\n" + callsign + "\r\n"))
                {
                    m.IsVisible = ((mapFilterMinutes == 0) || (DateTime.Now.CompareTo(time.AddMinutes(mapFilterMinutes)) <= 0));
                    m.ToolTipText = "\r\n" + callsign + "\r\n" + time.ToString();
                    m.Position = new PointLatLng(lat, lng);
                    m.Tag = time;
                    return;
                }
            }

            GMapMarker marker = new GMarkerGoogle(new PointLatLng(lat, lng), largeMarkersToolStripMenuItem.Checked ? GMarkerGoogleType.red_dot : GMarkerGoogleType.red_small);
            marker.Tag = time;
            marker.ToolTipText = "\r\n" + callsign + "\r\n" + time.ToString();
            marker.ToolTipMode = MarkerTooltipMode.OnMouseOver;
            marker.ToolTip.TextPadding = new Size(4, 8);
            marker.IsVisible = ((mapFilterMinutes == 0) || (DateTime.Now.CompareTo(time.AddMinutes(mapFilterMinutes)) <= 0));
            mapMarkersOverlay.Markers.Add(marker);
        }

        public void UpdateMapMarkers()
        {
            int mapFilterMinutes = broker.GetValue<int>(0, "MapTimeFilter", 0);
            DateTime now = DateTime.Now;
            foreach (GMapMarker m in mapMarkersOverlay.Markers)
            {
                // Skip radio markers (they're managed separately)
                if (radioMarkers.ContainsValue(m)) continue;

                m.IsVisible = ((mapFilterMinutes == 0) || (now.CompareTo(((DateTime)m.Tag).AddMinutes(mapFilterMinutes)) <= 0));
            }
            foreach (GMapRoute r in mapMarkersOverlay.Routes)
            {
                r.IsVisible = showTracksToolStripMenuItem.Checked && ((mapFilterMinutes == 0) || (now.CompareTo(((DateTime)r.Tag).AddMinutes(mapFilterMinutes)) <= 0));
            }
        }

        #endregion

        private void mapZoomInbutton_Click(object sender, EventArgs e)
        {
            mapControl.Zoom = Math.Max(mapControl.Zoom + 1, mapControl.MinZoom);
            mapControl.Update();
            mapControl.Refresh();
        }

        private void mapZoomOutButton_Click(object sender, EventArgs e)
        {
            mapControl.Zoom = Math.Min(mapControl.Zoom - 1, mapControl.MaxZoom);
            mapControl.Update();
            mapControl.Refresh();
        }

        private void mapControl_OnMapZoomChanged()
        {
            // Save zoom level to DataBroker (device 0 persists to registry)
            broker.Dispatch(0, "MapZoom", (int)mapControl.Zoom);
            mapTopLabel.Text = offlineModeToolStripMenuItem.Checked ? "Offline Map" : "Map";
        }

        private void mapControl_OnPositionChanged(PointLatLng point)
        {
            // Save position to DataBroker (device 0 persists to registry)
            broker.Dispatch(0, "MapLatitude", mapControl.Position.Lat.ToString());
            broker.Dispatch(0, "MapLongitude", mapControl.Position.Lng.ToString());
        }

        private void mapControl_OnMarkerDoubleClick(GMapMarker item, MouseEventArgs e)
        {
            string[] s = item.ToolTipText.Replace("\r\n", "\r").Split('\r');
            if (s.Length >= 3)
            {
                // Notify via DataBroker - could be used for APRS destination selection
                // broker.Dispatch(0, "AprsDestinationSelected", s[1]);
            }
        }

        private void centerToGpsButton_Click(object sender, EventArgs e)
        {
            if (radioMarkers.Count == 0) return;

            // Get list of device IDs with valid positions
            List<int> deviceIds = new List<int>(radioMarkers.Keys);

            // Ensure cycle index is valid
            if (centerToGpsCycleIndex >= deviceIds.Count)
            {
                centerToGpsCycleIndex = 0;
            }

            // Try to find a valid position starting from current cycle index
            int startIndex = centerToGpsCycleIndex;
            int attempts = 0;

            while (attempts < deviceIds.Count)
            {
                int deviceId = deviceIds[centerToGpsCycleIndex];
                RadioPosition position = broker.GetValue<RadioPosition>(deviceId, "Position", null);

                // Move to next index for the next click (cycle)
                centerToGpsCycleIndex = (centerToGpsCycleIndex + 1) % deviceIds.Count;

                if (position != null && position.IsGpsLocked())
                {
                    mapControl.Position = new PointLatLng(position.Latitude, position.Longitude);
                    return;
                }

                attempts++;
            }
        }

        private void mapMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            mapTabContextMenuStrip.Show(mapMenuPictureBox, e.Location);
        }

        private void offlineModeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            broker.Dispatch(0, "MapOfflineMode", offlineModeToolStripMenuItem.Checked ? 1 : 0);
            mapTopLabel.Text = offlineModeToolStripMenuItem.Checked ? "Offline Map" : "Map";
            cacheAreaToolStripMenuItem.Enabled = !offlineModeToolStripMenuItem.Checked;
            if (offlineModeToolStripMenuItem.Checked)
            {
                mapControl.Manager.Mode = AccessMode.CacheOnly;
            }
            else
            {
                mapControl.Manager.Mode = AccessMode.ServerAndCache;
            }
        }

        private async void cacheAreaToolStripMenuItem_Click(object sender, EventArgs e)
        {
            if (prefetcher != null) return;

            var area = mapControl.SelectedArea;
            if (area.IsEmpty) { MessageBox.Show("Select an area on the map using right-click + drag."); return; }
            int zoom = (int)mapControl.Zoom;
            int zoomMin = zoom - 2;
            int zoomMax = zoom + 3;
            if (zoomMin < 1) zoomMin = 1;
            if (zoomMin > 20) zoomMin = 20;
            if (zoomMax > 20) zoomMax = 20;

            cts = new CancellationTokenSource();
            prefetcher = new CustomTilePrefetcher();
            downloadMapLabel.Text = "Downloading...";
            downloadMapPanel.Visible = true;
            await prefetcher.PrefetchAsync(
                mapControl.MapProvider,
                area,
                zoomMin, zoomMax,
                new Progress<(int done, int total)>(p => { downloadMapLabel.Text = $"Downloading {p.done}/{p.total}..."; }),
                cts.Token);
            downloadMapPanel.Visible = false;
            prefetcher = null;
            cts = null;
            selectionRect = Rectangle.Empty;
            mapControl.SelectedArea = RectLatLng.Empty;
            isSelecting = false;
            mapControl.ReloadMap();
        }

        private void cancelMapDownloadButton_Click(object sender, EventArgs e)
        {
            cts?.Cancel();
        }

        private void showTracksToolStripMenuItem_Click(object sender, EventArgs e)
        {
            broker.Dispatch(0, "MapShowTracks", showTracksToolStripMenuItem.Checked ? 1 : 0);
            foreach (GMapRoute route in mapRoutes.Values)
            {
                route.IsVisible = showTracksToolStripMenuItem.Checked;
            }
        }

        private void allToolStripMenuItem_Click(object sender, EventArgs e)
        {
            foreach (ToolStripMenuItem i in showMarkersToolStripMenuItem.DropDownItems) { i.Checked = (i == sender); }
            int mapFilterMinutes = int.Parse((string)((ToolStripMenuItem)sender).Tag);
            broker.Dispatch(0, "MapTimeFilter", mapFilterMinutes);
            UpdateMapMarkers();
        }

        private void largeMarkersToolStripMenuItem_Click(object sender, EventArgs e)
        {
            broker.Dispatch(0, "MapLargeMarkers", largeMarkersToolStripMenuItem.Checked ? 1 : 0);

            List<GMapMarker> markersToReplace = new List<GMapMarker>();
            foreach (GMarkerGoogle m in mapMarkersOverlay.Markers)
            {
                GMarkerGoogleType t = m.Type;
                if (largeMarkersToolStripMenuItem.Checked)
                {
                    if (t == GMarkerGoogleType.red_small) t = GMarkerGoogleType.red_dot;
                    if (t == GMarkerGoogleType.blue_small) t = GMarkerGoogleType.blue_dot;
                    if (t == GMarkerGoogleType.green_small) t = GMarkerGoogleType.green_dot;
                }
                else
                {
                    if (t == GMarkerGoogleType.red_dot) t = GMarkerGoogleType.red_small;
                    if (t == GMarkerGoogleType.blue_dot) t = GMarkerGoogleType.blue_small;
                    if (t == GMarkerGoogleType.green_dot) t = GMarkerGoogleType.green_small;
                }
                GMarkerGoogle marker = new GMarkerGoogle(m.Position, t);
                marker.Tag = m.Tag;
                marker.ToolTipText = m.ToolTipText;
                marker.ToolTipMode = m.ToolTipMode;
                marker.ToolTip.TextPadding = m.ToolTip.TextPadding;
                marker.IsVisible = m.IsVisible;
                markersToReplace.Add(marker);
            }

            // Update radio markers dictionary with new marker references
            Dictionary<int, GMapMarker> newRadioMarkers = new Dictionary<int, GMapMarker>();
            foreach (var kvp in radioMarkers)
            {
                int index = mapMarkersOverlay.Markers.IndexOf(kvp.Value);
                if (index >= 0 && index < markersToReplace.Count)
                {
                    newRadioMarkers[kvp.Key] = markersToReplace[index];
                }
            }

            mapMarkersOverlay.Markers.Clear();
            foreach (GMarkerGoogle marker in markersToReplace) { mapMarkersOverlay.Markers.Add(marker); }
            radioMarkers = newRadioMarkers;
        }

        private void mapControl_MouseEnter(object sender, EventArgs e)
        {
            // Prevent the GMap control from bringing the form to the front
            // by not allowing the control to take focus when mouse enters
        }

        private void mapControl_MouseDown(object sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
            {
                startPoint = e.Location;
                selectionRect = new Rectangle();
                isSelecting = true;
                mapControl.Invalidate();
            }
        }

        private void mapControl_MouseMove(object sender, MouseEventArgs e)
        {
            if (isSelecting)
            {
                int width = e.X - startPoint.X;
                int height = e.Y - startPoint.Y;

                selectionRect = new Rectangle(
                    Math.Min(e.X, startPoint.X),
                    Math.Min(e.Y, startPoint.Y),
                    Math.Abs(width),
                    Math.Abs(height));

                mapControl.Invalidate();
            }
        }

        private void mapControl_MouseUp(object sender, MouseEventArgs e)
        {
            if (isSelecting && e.Button == MouseButtons.Right)
            {
                isSelecting = false;
                if (selectionRect.Width > 10 && selectionRect.Height > 10)
                {
                    PointLatLng p1 = mapControl.FromLocalToLatLng(selectionRect.Left, selectionRect.Top);
                    PointLatLng p2 = mapControl.FromLocalToLatLng(selectionRect.Right, selectionRect.Bottom);

                    RectLatLng area = RectLatLng.FromLTRB(
                        Math.Min(p1.Lng, p2.Lng),
                        Math.Max(p1.Lat, p2.Lat),
                        Math.Max(p1.Lng, p2.Lng),
                        Math.Min(p1.Lat, p2.Lat));

                    mapControl.SelectedArea = area;
                }

                mapControl.Invalidate();
            }
        }

        private void mapControl_Paint(object sender, PaintEventArgs e)
        {
            if (isSelecting && selectionRect != Rectangle.Empty)
            {
                using (Pen pen = new Pen(Color.Red, 2))
                {
                    pen.DashStyle = System.Drawing.Drawing2D.DashStyle.Dash;
                    e.Graphics.DrawRectangle(pen, selectionRect);
                }
            }
        }

        private void detachToolStripMenuItem_Click(object sender, EventArgs e)
        {
            var form = DetachedTabForm.Create<MapTabUserControl>("Map");
            form.Show();
        }
    }
}
