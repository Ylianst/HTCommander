﻿/*
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
        public GMapOverlay mapMarkersOverlay = new GMapOverlay("Markers");
        public string Callsign { get { return callsign; } }

        public void SetPosition(double lat, double lng)
        {
            mapControl.Position = new GMap.NET.PointLatLng(lat, lng);
            mapControl.Update();
            mapControl.Refresh();
        }

        public void SetMarkers(GMarkerGoogle[] markers)
        {
            foreach (GMarkerGoogle marker in markers) { mapMarkersOverlay.Markers.Add(marker); }
        }

        public MapLocationForm(MainForm parent, string callsign)
        {
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

        private void MapLocationForm_FormClosing(object sender, FormClosingEventArgs e)
        {
            parent.mapLocationForms.Remove(this);
        }
    }
}
