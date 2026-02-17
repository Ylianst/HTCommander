/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License").
See http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using GMap.NET;
using GMap.NET.WindowsForms;

namespace HTCommander.Airplanes
{
    /// <summary>
    /// A custom GMap marker that renders a rotated airplane icon with altitude-based coloring.
    /// </summary>
    public class AirplaneMarker : GMapMarker
    {
        private float _track;       // heading in degrees (0 = north, clockwise)
        private int _altitude;      // altitude in feet (-1 = unknown)
        private bool _large;        // large or small icon
        private Bitmap _bitmap;

        private static readonly int SmallSize = 16;
        private static readonly int LargeSize = 24;

        public AirplaneMarker(PointLatLng position, float track, int altitude, bool large)
            : base(position)
        {
            _track = track;
            _altitude = altitude;
            _large = large;
            RebuildBitmap();
        }

        /// <summary>
        /// Updates the marker's track (heading), altitude, and size, rebuilding the bitmap if needed.
        /// </summary>
        public void Update(PointLatLng position, float track, int altitude, bool large)
        {
            Position = position;
            bool changed = (Math.Abs(_track - track) > 1f) || (_altitude != altitude) || (_large != large);
            _track = track;
            _altitude = altitude;
            _large = large;
            if (changed) { RebuildBitmap(); }
        }

        private void RebuildBitmap()
        {
            _bitmap?.Dispose();

            int size = _large ? LargeSize : SmallSize;
            Color color = GetAltitudeColor(_altitude);

            _bitmap = new Bitmap(size, size);
            using (Graphics g = Graphics.FromImage(_bitmap))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);

                // Rotate around center
                g.TranslateTransform(size / 2f, size / 2f);
                g.RotateTransform(_track);
                g.TranslateTransform(-size / 2f, -size / 2f);

                float margin = size * 0.1f;
                float w = size - 2 * margin;
                float h = size - 2 * margin;
                float cx = size / 2f;
                float cy = size / 2f;

                using (Brush brush = new SolidBrush(color))
                using (Pen outlinePen = new Pen(Color.FromArgb(180, 0, 0, 0), _large ? 1.2f : 0.8f))
                {
                    // Airplane shape: a simple top-down silhouette
                    // Nose at top, tail at bottom (before rotation, pointing up = north)
                    PointF[] fuselage = new PointF[]
                    {
                        // Nose
                        new PointF(cx, margin),
                        // Right shoulder
                        new PointF(cx + w * 0.08f, cy - h * 0.1f),
                        // Right wing tip
                        new PointF(cx + w * 0.48f, cy + h * 0.05f),
                        // Right wing trailing edge
                        new PointF(cx + w * 0.48f, cy + h * 0.12f),
                        // Right body after wing
                        new PointF(cx + w * 0.08f, cy + h * 0.08f),
                        // Right tail tip
                        new PointF(cx + w * 0.22f, cy + h * 0.38f),
                        // Right tail trailing edge
                        new PointF(cx + w * 0.22f, cy + h * 0.45f),
                        // Tail center
                        new PointF(cx, cy + h * 0.38f),
                        // Left tail trailing edge
                        new PointF(cx - w * 0.22f, cy + h * 0.45f),
                        // Left tail tip
                        new PointF(cx - w * 0.22f, cy + h * 0.38f),
                        // Left body after wing
                        new PointF(cx - w * 0.08f, cy + h * 0.08f),
                        // Left wing trailing edge
                        new PointF(cx - w * 0.48f, cy + h * 0.12f),
                        // Left wing tip
                        new PointF(cx - w * 0.48f, cy + h * 0.05f),
                        // Left shoulder
                        new PointF(cx - w * 0.08f, cy - h * 0.1f),
                    };

                    g.FillPolygon(brush, fuselage);
                    g.DrawPolygon(outlinePen, fuselage);
                }
            }

            // Set the offset so the marker is centered on the position
            Offset = new Point(-size / 2, -size / 2);
            Size = new Size(size, size);
        }

        /// <summary>
        /// Returns a color based on altitude (feet).
        /// Low altitude = green, mid = yellow/orange, high = red, very high = magenta/purple.
        /// Unknown altitude (-1) = gray.
        /// </summary>
        private static Color GetAltitudeColor(int altitude)
        {
            if (altitude < 0) return Color.FromArgb(200, 128, 128, 128); // gray for unknown

            int alt = altitude;

            // Color bands (feet):
            //   0 -  1,000  green
            //   1,000 -  5,000  green -> yellow
            //   5,000 - 15,000  yellow -> orange
            //  15,000 - 30,000  orange -> red
            //  30,000 - 45,000  red -> magenta
            //  45,000+          magenta

            if (alt <= 1000)
                return Color.FromArgb(220, 34, 139, 34);        // forest green
            else if (alt <= 5000)
                return Lerp(Color.FromArgb(220, 34, 139, 34), Color.FromArgb(220, 255, 200, 0), (alt - 1000) / 4000f);
            else if (alt <= 15000)
                return Lerp(Color.FromArgb(220, 255, 200, 0), Color.FromArgb(220, 255, 120, 0), (alt - 5000) / 10000f);
            else if (alt <= 30000)
                return Lerp(Color.FromArgb(220, 255, 120, 0), Color.FromArgb(220, 220, 20, 20), (alt - 15000) / 15000f);
            else if (alt <= 45000)
                return Lerp(Color.FromArgb(220, 220, 20, 20), Color.FromArgb(220, 180, 0, 220), (alt - 30000) / 15000f);
            else
                return Color.FromArgb(220, 180, 0, 220);       // magenta/purple
        }

        private static Color Lerp(Color a, Color b, float t)
        {
            t = Math.Max(0f, Math.Min(1f, t));
            return Color.FromArgb(
                (int)(a.A + (b.A - a.A) * t),
                (int)(a.R + (b.R - a.R) * t),
                (int)(a.G + (b.G - a.G) * t),
                (int)(a.B + (b.B - a.B) * t));
        }

        public override void OnRender(Graphics g)
        {
            if (_bitmap != null)
            {
                g.DrawImageUnscaled(_bitmap, LocalPosition.X, LocalPosition.Y);
            }
        }

        public override void Dispose()
        {
            _bitmap?.Dispose();
            _bitmap = null;
            base.Dispose();
        }
    }
}
