/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using GMap.NET;
using GMap.NET.MapProviders;
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace HTCommander
{
    public class CustomTilePrefetcher
    {
        public async Task PrefetchAsync(
        GMapProvider provider,
        RectLatLng area,
        int minZoom,
        int maxZoom,
        IProgress<(int completed, int total)> progress = null,
        CancellationToken cancellationToken = default)
        {
            if (provider == null || area.IsEmpty)
                throw new ArgumentException("Invalid provider or area");

            var projection = provider.Projection;
            var allTiles = new List<(int zoom, long x, long y)>();

            for (int zoom = minZoom; zoom <= maxZoom; zoom++)
            {
                var topLeft = area.LocationTopLeft;
                var bottomRight = new PointLatLng(
                    area.LocationTopLeft.Lat - area.HeightLat,
                    area.LocationTopLeft.Lng + area.WidthLng
                );

                var pxTopLeft = projection.FromLatLngToPixel(topLeft.Lat, topLeft.Lng, zoom);
                var pxBottomRight = projection.FromLatLngToPixel(bottomRight.Lat, bottomRight.Lng, zoom);

                var tileTopLeft = projection.FromPixelToTileXY(pxTopLeft);
                var tileBottomRight = projection.FromPixelToTileXY(pxBottomRight);

                for (long x = tileTopLeft.X; x <= tileBottomRight.X; x++)
                {
                    for (long y = tileTopLeft.Y; y <= tileBottomRight.Y; y++)
                    {
                        allTiles.Add((zoom, x, y));
                    }
                }
            }

            int completed = 0;
            int total = allTiles.Count;

            await Task.Run(() =>
            {
                foreach (var (zoom, x, y) in allTiles)
                {
                    if (cancellationToken.IsCancellationRequested)
                        break;

                    try
                    {
                        Exception ex;
                        GMaps.Instance.GetImageFrom(provider, new GPoint(x, y), zoom, out ex);
                        if (ex != null)
                        {
                            // Handle exceptions if needed
                            Console.WriteLine($"Error fetching tile ({zoom}, {x}, {y}): {ex.Message}");
                        }
                        //provider.GetTileImage(new GMap.NET.GPoint(x, y), zoom);
                    }
                    catch
                    {
                        // Silent fail
                    }

                    completed++;
                    progress?.Report((completed, total));
                }
            }, cancellationToken);
        }
    }
}