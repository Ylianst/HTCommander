/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using GMap.NET;
using GMap.NET.MapProviders;
using GMap.NET.WindowsForms;
using GMap.NET.WindowsForms.Markers;

namespace HTCommander.Controls
{
    public partial class MapTabUserControl : UserControl
    {
        private MainForm mainForm;
        private CancellationTokenSource cts = null;
        private CustomTilePrefetcher prefetcher = null;
        private Point startPoint;
        private Rectangle selectionRect;
        private bool isSelecting = false;
        public GMapOverlay mapMarkersOverlay = new GMapOverlay("AprsMarkers");
        public Dictionary<string, GMapRoute> mapRoutes = new Dictionary<string, GMapRoute>();

        public GMapControl MapControl { get { return mapControl; } }
        public GMapOverlay MapMarkersOverlay { get { return mapMarkersOverlay; } }

        public MapTabUserControl()
        {
            InitializeComponent();
        }

        public void Initialize(MainForm mainForm)
        {
            this.mainForm = mainForm;

            // Initialize the map control
            InitializeMapControl();

            // Load settings from registry
            LoadSettings();
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

            // Load saved position and zoom
            //if (double.TryParse(mainForm.registry.ReadString("MapZoom", "3"), out double zoom) == false) { zoom = 3; }
            //mapControl.Zoom = zoom;

            //if (double.TryParse(mainForm.registry.ReadString("MapLatitude", "0"), out double lat) == false) { lat = 0; }
            //if (double.TryParse(mainForm.registry.ReadString("MapLongetude", "0"), out double lng) == false) { lng = 0; }
            //mapControl.Position = new PointLatLng(lat, lng);

            // Add the overlay to the map
            mapControl.Overlays.Add(mapMarkersOverlay);
            mapControl.Update();
            mapControl.Refresh();
        }

        private void LoadSettings()
        {
            /*
            offlineModeToolStripMenuItem.Checked = (mainForm.registry.ReadInt("MapOfflineMode", 0) == 1);
            cacheAreaToolStripMenuItem.Enabled = !offlineModeToolStripMenuItem.Checked;
            mapControl.Manager.Mode = offlineModeToolStripMenuItem.Checked ? AccessMode.CacheOnly : AccessMode.ServerAndCache;
            mapTopLabel.Text = offlineModeToolStripMenuItem.Checked ? "Offline Map" : "Map";
            showTracksToolStripMenuItem.Checked = (mainForm.registry.ReadInt("MapShowTracks", 1) == 1);
            largeMarkersToolStripMenuItem.Checked = (mainForm.registry.ReadInt("MapLargeMarkers", 1) == 1);

            int mapFilterMinutes = (int)mainForm.registry.ReadInt("MapTimeFilter", 0);
            foreach (ToolStripMenuItem i in showMarkersToolStripMenuItem.DropDownItems)
            {
                i.Checked = (int.Parse((string)((ToolStripMenuItem)i).Tag) == mapFilterMinutes);
            }
            */
        }

        public void UpdateCenterToGpsButton(bool enabled)
        {
            centerToGpsButton.Enabled = enabled;
            centerToGPSToolStripMenuItem.Enabled = enabled;
        }

        public void AddMapMarker(string callsign, double lat, double lng, DateTime time)
        {
            /*
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
            route.IsVisible = showTracksToolStripMenuItem.Checked && ((mainForm.mapFilterMinutes == 0) || (DateTime.Now.CompareTo(time.AddMinutes(mainForm.mapFilterMinutes)) <= 0));

            foreach (GMapMarker m in mapMarkersOverlay.Markers)
            {
                if (m.ToolTipText.StartsWith("\r\n" + callsign + "\r\n"))
                {
                    m.IsVisible = ((mainForm.mapFilterMinutes == 0) || (DateTime.Now.CompareTo(time.AddMinutes(mainForm.mapFilterMinutes)) <= 0));
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
            marker.IsVisible = ((mainForm.mapFilterMinutes == 0) || (DateTime.Now.CompareTo(time.AddMinutes(mainForm.mapFilterMinutes)) <= 0));
            mapMarkersOverlay.Markers.Add(marker);
            */
        }

        public void UpdateMapMarkers()
        {
            /*
            DateTime now = DateTime.Now;
            foreach (GMapMarker m in mapMarkersOverlay.Markers)
            {
                m.IsVisible = ((mainForm.mapFilterMinutes == 0) || (now.CompareTo(((DateTime)m.Tag).AddMinutes(mainForm.mapFilterMinutes)) <= 0));
            }
            foreach (GMapRoute r in mapMarkersOverlay.Routes)
            {
                r.IsVisible = showTracksToolStripMenuItem.Checked && ((mainForm.mapFilterMinutes == 0) || (now.CompareTo(((DateTime)r.Tag).AddMinutes(mainForm.mapFilterMinutes)) <= 0));
            }
            */
        }

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
            //mainForm.registry.WriteString("MapZoom", mapControl.Zoom.ToString());
            mapTopLabel.Text = offlineModeToolStripMenuItem.Checked ? "Offline Map" : "Map";
        }

        private void mapControl_OnPositionChanged(PointLatLng point)
        {
            //mainForm.registry.WriteString("MapLatitude", mapControl.Position.Lat.ToString());
            //mainForm.registry.WriteString("MapLongetude", mapControl.Position.Lng.ToString());
        }

        private void mapControl_OnMarkerDoubleClick(GMapMarker item, MouseEventArgs e)
        {
            string[] s = item.ToolTipText.Replace("\r\n", "\r").Split('\r');
            if (s.Length >= 3)
            {
                // Notify MainForm to update APRS destination
                // This could be done via an event or direct call
            }
        }

        private void centerToGpsButton_Click(object sender, EventArgs e)
        {
            /*
            if ((mainForm.radio.Position != null) && (mainForm.radio.Position.Status == Radio.RadioCommandState.SUCCESS))
            {
                mapControl.Position = new PointLatLng(mainForm.radio.Position.Latitude, mainForm.radio.Position.Longitude);
            }
            */
        }

        private void mapMenuPictureBox_MouseClick(object sender, MouseEventArgs e)
        {
            mapTabContextMenuStrip.Show(mapMenuPictureBox, e.Location);
        }

        private void offlineModeToolStripMenuItem_Click(object sender, EventArgs e)
        {
            //mainForm.registry.WriteInt("MapOfflineMode", offlineModeToolStripMenuItem.Checked ? 1 : 0);
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
            //mainForm.registry.WriteInt("MapShowTracks", showTracksToolStripMenuItem.Checked ? 1 : 0);
            foreach (GMapRoute route in mapRoutes.Values)
            {
                route.IsVisible = showTracksToolStripMenuItem.Checked;
            }
        }

        private void allToolStripMenuItem_Click(object sender, EventArgs e)
        {
            foreach (ToolStripMenuItem i in showMarkersToolStripMenuItem.DropDownItems) { i.Checked = (i == sender); }
            //mainForm.mapFilterMinutes = int.Parse((string)((ToolStripMenuItem)sender).Tag);
            //mainForm.registry.WriteInt("MapTimeFilter", mainForm.mapFilterMinutes);
            UpdateMapMarkers();
        }

        private void largeMarkersToolStripMenuItem_Click(object sender, EventArgs e)
        {
            //mainForm.registry.WriteInt("MapLargeMarkers", largeMarkersToolStripMenuItem.Checked ? 1 : 0);

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
            mapMarkersOverlay.Markers.Clear();
            foreach (GMarkerGoogle marker in markersToReplace) { mapMarkersOverlay.Markers.Add(marker); }
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
    }
}