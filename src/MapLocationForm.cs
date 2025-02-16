/*
Copyright 2025 Ylian Saint-Hilaire

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
using System.Windows.Forms;
#if !__MonoCS__
using GMap.NET.MapProviders;
using GMap.NET.WindowsForms;
using GMap.NET.WindowsForms.Markers;
#endif

namespace HTCommander
{
    public partial class MapLocationForm : Form
    {
        private MainForm parent = null;
        private string callsign = null;
        public string Callsign { get { return callsign; } }
#if !__MonoCS__
        public GMapOverlay mapMarkersOverlay = new GMapOverlay("Markers");
#endif

        public void SetPosition(double lat, double lng)
        {
#if !__MonoCS__
            mapControl.Position = new GMap.NET.PointLatLng(lat, lng);
            mapControl.Update();
            mapControl.Refresh();
#endif
        }

#if !__MonoCS__
        public void SetMarkers(GMarkerGoogle[] markers)
        {
            foreach (GMarkerGoogle marker in markers) { mapMarkersOverlay.Markers.Add(marker); }
        }
#endif

        public MapLocationForm(MainForm parent, string callsign)
        {
#if !__MonoCS__
            this.parent = parent;
            this.callsign = callsign;
            InitializeComponent();
            this.Text += " - " + callsign;

            // 
            // mapControl
            // 
            this.mapControl = new GMap.NET.WindowsForms.GMapControl();
            this.mapControl.Bearing = 0F;
            this.mapControl.BorderStyle = System.Windows.Forms.BorderStyle.Fixed3D;
            this.mapControl.CanDragMap = true;
            this.mapControl.Dock = System.Windows.Forms.DockStyle.Fill;
            this.mapControl.EmptyTileColor = System.Drawing.Color.Navy;
            this.mapControl.GrayScaleMode = false;
            this.mapControl.HelperLineOption = GMap.NET.WindowsForms.HelperLineOptions.DontShow;
            this.mapControl.LevelsKeepInMemory = 5;
            this.mapControl.Location = new System.Drawing.Point(0, 0);
            this.mapControl.Margin = new System.Windows.Forms.Padding(2);
            this.mapControl.MarkersEnabled = true;
            this.mapControl.MaxZoom = 2;
            this.mapControl.MinZoom = 2;
            this.mapControl.MouseWheelZoomEnabled = true;
            this.mapControl.MouseWheelZoomType = GMap.NET.MouseWheelZoomType.MousePositionAndCenter;
            this.mapControl.Name = "mapControl";
            this.mapControl.NegativeMode = false;
            this.mapControl.PolygonsEnabled = true;
            this.mapControl.RetryLoadTile = 0;
            this.mapControl.RoutesEnabled = true;
            this.mapControl.ScaleMode = GMap.NET.WindowsForms.ScaleModes.Integer;
            this.mapControl.SelectedAreaFillColor = System.Drawing.Color.FromArgb(((int)(((byte)(33)))), ((int)(((byte)(65)))), ((int)(((byte)(105)))), ((int)(((byte)(225)))));
            this.mapControl.ShowTileGridLines = false;
            this.mapControl.Size = new System.Drawing.Size(383, 315);
            this.mapControl.TabIndex = 0;
            this.mapControl.Zoom = 0D;
            this.Controls.Add(this.mapControl);

            mapControl.MapProvider = GMapProviders.OpenStreetMap;
            mapControl.ShowCenter = false;
            mapControl.MinZoom = 3;
            mapControl.MaxZoom = 20;
            //mapControl.CanDragMap = true;
            mapControl.MouseWheelZoomType = GMap.NET.MouseWheelZoomType.MousePositionAndCenter;
            mapControl.IgnoreMarkerOnMouseWheel = true; // Optional, depending on marker usage
            //mapControl.DragButton = MouseButtons.Left; // Set the mouse button for dragging

            // Add the overlay to the map
            mapControl.Overlays.Add(mapMarkersOverlay);
            mapControl.Zoom = 10;
            mapControl.Update();
            mapControl.Refresh();
#endif
        }

        private void mapZoomInbutton_Click(object sender, EventArgs e)
        {
#if !__MonoCS__
            mapControl.Zoom = Math.Max(mapControl.Zoom + 1, mapControl.MinZoom);
            mapControl.Update();
            mapControl.Refresh();
#endif
        }

        private void mapZoomOutButton_Click(object sender, EventArgs e)
        {
#if !__MonoCS__
            mapControl.Zoom = Math.Min(mapControl.Zoom - 1, mapControl.MaxZoom);
            mapControl.Update();
            mapControl.Refresh();
#endif
        }

        private void MapLocationForm_FormClosing(object sender, FormClosingEventArgs e)
        {
#if !__MonoCS__
            parent.mapLocationForms.Remove(this);
#endif
        }
    }
}
