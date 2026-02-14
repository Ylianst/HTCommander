/*
Pixel buffer
Ported to C# from https://github.com/xdsopl/robot36
*/

namespace HTCommander.SSTV
{
    public class PixelBuffer
    {
        public int[] Pixels;
        public int Width;
        public int Height;
        public int Line;

        public PixelBuffer(int width, int height)
        {
            Width = width;
            Height = height;
            Line = 0;
            Pixels = new int[width * height];
        }
    }
}
