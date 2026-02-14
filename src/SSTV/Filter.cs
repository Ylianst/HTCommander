/*
FIR Filter
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public static class Filter
    {
        public static double Sinc(double x)
        {
            if (x == 0)
                return 1;
            x *= Math.PI;
            return Math.Sin(x) / x;
        }

        public static double LowPass(double cutoff, double rate, int n, int N)
        {
            double f = 2 * cutoff / rate;
            double x = n - (N - 1) / 2.0;
            return f * Sinc(f * x);
        }
    }
}
