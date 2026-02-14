/*
Hann window
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public static class Hann
    {
        public static double Window(int n, int N)
        {
            return 0.5 * (1.0 - Math.Cos((2.0 * Math.PI * n) / (N - 1)));
        }
    }
}
