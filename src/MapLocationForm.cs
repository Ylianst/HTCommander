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
using GMap.NET.MapProviders;
using GMap.NET.WindowsForms;
using GMap.NET.WindowsForms.Markers;

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

        public void SetMarkers(GMarkerGoogle[] markers)
        {
#if !__MonoCS__
            foreach (GMarkerGoogle marker in markers) { mapMarkersOverlay.Markers.Add(marker); }
#endif
        }

        public MapLocationForm(MainForm parent, string callsign)
        {
#if !__MonoCS__
            this.parent = parent;
            this.callsign = callsign;
            InitializeComponent();
            this.Text += " - " + callsign;

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
