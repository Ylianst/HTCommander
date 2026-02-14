/*
Kaiser window
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public class Kaiser
    {
        private readonly double[] summands;

        public Kaiser()
        {
            // i0(x) converges for x inside -3*Pi:3*Pi in less than 35 iterations
            summands = new double[35];
        }

        private static double Square(double value)
        {
            return value * value;
        }

        /*
        i0() implements the zero-th order modified Bessel function of the first kind:
        https://en.wikipedia.org/wiki/Bessel_function#Modified_Bessel_functions:_I%CE%B1,_K%CE%B1
        */
        private double I0(double x)
        {
            summands[0] = 1;
            double val = 1;
            for (int n = 1; n < summands.Length; ++n)
                summands[n] = Square(val *= x / (2 * n));
            Array.Sort(summands);
            double sum = 0;
            for (int n = summands.Length - 1; n >= 0; --n)
                sum += summands[n];
            return sum;
        }

        public double Window(double a, int n, int N)
        {
            return I0(Math.PI * a * Math.Sqrt(1 - Square((2.0 * n) / (N - 1) - 1))) / I0(Math.PI * a);
        }
    }
}
