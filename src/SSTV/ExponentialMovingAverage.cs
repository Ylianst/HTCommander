/*
Exponential Moving Average
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public class ExponentialMovingAverage
    {
        private float alpha;
        private float prev;

        public ExponentialMovingAverage()
        {
            alpha = 1;
        }

        public float Avg(float input)
        {
            return prev = prev * (1 - alpha) + alpha * input;
        }

        public void Alpha(double alpha)
        {
            this.alpha = (float)alpha;
        }

        public void Alpha(double alpha, int order)
        {
            Alpha(Math.Pow(alpha, 1.0 / order));
        }

        public void Cutoff(double freq, double rate, int order)
        {
            double x = Math.Cos(2 * Math.PI * freq / rate);
            Alpha(x - 1 + Math.Sqrt(x * (x - 4) + 3), order);
        }

        public void Cutoff(double freq, double rate)
        {
            Cutoff(freq, rate, 1);
        }

        public void Reset()
        {
            prev = 0;
        }
    }
}
