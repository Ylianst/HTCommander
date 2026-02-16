/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Windows.Forms;
using GMap.NET;
using GMap.NET.MapProviders;
using GMap.NET.WindowsForms;
using GMap.NET.WindowsForms.Markers;

namespace HTCommander
{
    public partial class MapLocationForm : Form
    {
        private string callsign = null;
        public string Callsign { get { return callsign; } }
        public GMapOverlay mapMarkersOverlay = new GMapOverlay("SmallMapMarkers");

        public MapLocationForm(string callsign, double latitude, double longitude)
        {
            this.callsign = callsign;
            InitializeComponent();
            this.Text = "Location - " + callsign;

            InitializeMapControl(latitude, longitude);
        }

        private void InitializeMapControl(double latitude, double longitude)
        {
            //
            // mapControl
            //
            this.mapControl = new GMapControl();
            this.mapControl.Bearing = 0F;
            this.mapControl.BorderStyle = BorderStyle.Fixed3D;
            this.mapControl.CanDragMap = true;
            this.mapControl.Dock = DockStyle.Fill;
            this.mapControl.EmptyTileColor = Color.Navy;
            this.mapControl.GrayScaleMode = false;
            this.mapControl.HelperLineOption = HelperLineOptions.DontShow;
            this.mapControl.LevelsKeepInMemory = 5;
            this.mapControl.Location = new Point(0, 0);
            this.mapControl.Margin = new Padding(2);
            this.mapControl.MarkersEnabled = true;
            this.mapControl.MaxZoom = 20;
            this.mapControl.MinZoom = 3;
            this.mapControl.MouseWheelZoomEnabled = true;
            this.mapControl.MouseWheelZoomType = MouseWheelZoomType.MousePositionAndCenter;
            this.mapControl.Name = "mapControl";
            this.mapControl.NegativeMode = false;
            this.mapControl.PolygonsEnabled = true;
            this.mapControl.RetryLoadTile = 0;
            this.mapControl.RoutesEnabled = true;
            this.mapControl.ScaleMode = ScaleModes.Integer;
            this.mapControl.SelectedAreaFillColor = Color.FromArgb(33, 65, 105, 225);
            this.mapControl.ShowTileGridLines = false;
            this.mapControl.Size = new Size(383, 315);
            this.mapControl.TabIndex = 0;
            this.mapControl.Zoom = 10;
            this.Controls.Add(this.mapControl);

            mapControl.MapProvider = GMapProviders.OpenStreetMap;
            mapControl.ShowCenter = false;
            mapControl.IgnoreMarkerOnMouseWheel = true;

            // Add the overlay to the map
            mapControl.Overlays.Add(mapMarkersOverlay);

            // Set position and add marker
            PointLatLng position = new PointLatLng(latitude, longitude);
            mapControl.Position = position;

            // Add a marker at the position
            GMarkerGoogle marker = new GMarkerGoogle(position, GMarkerGoogleType.red_dot);
            marker.ToolTipText = callsign;
            marker.ToolTipMode = MarkerTooltipMode.OnMouseOver;
            mapMarkersOverlay.Markers.Add(marker);

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
        }
    }
}
