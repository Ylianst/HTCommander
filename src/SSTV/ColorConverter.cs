/*
ColorConverter class
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public static class ColorConverter
    {
        private static int Clamp(int value)
        {
            return Math.Min(Math.Max(value, 0), 255);
        }

        private static float Clamp(float value)
        {
            return Math.Min(Math.Max(value, 0), 1);
        }

        private static int Float2Int(float level)
        {
            int intensity = (int)MathF.Round(255 * level);
            return Clamp(intensity);
        }

        private static int Compress(float level)
        {
            float compressed = (float)Math.Sqrt(Clamp(level));
            return Float2Int(compressed);
        }

        private static int YUV2RGB(int Y, int U, int V)
        {
            Y -= 16;
            U -= 128;
            V -= 128;
            int R = Clamp((298 * Y + 409 * V + 128) >> 8);
            int G = Clamp((298 * Y - 100 * U - 208 * V + 128) >> 8);
            int B = Clamp((298 * Y + 516 * U + 128) >> 8);
            return unchecked((int)0xff000000) | (R << 16) | (G << 8) | B;
        }

        public static int GRAY(float level)
        {
            return unchecked((int)0xff000000) | 0x00010101 * Compress(level);
        }

        public static int RGB(float red, float green, float blue)
        {
            return unchecked((int)0xff000000) | (Float2Int(red) << 16) | (Float2Int(green) << 8) | Float2Int(blue);
        }

        public static int YUV2RGB(float Y, float U, float V)
        {
            return YUV2RGB(Float2Int(Y), Float2Int(U), Float2Int(V));
        }

        public static int YUV2RGB(int YUV)
        {
            return YUV2RGB((YUV & 0x00ff0000) >> 16, (YUV & 0x0000ff00) >> 8, YUV & 0x000000ff);
        }
    }
}
