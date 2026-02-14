/*
Numerically controlled oscillator
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public class Phasor
    {
        private readonly Complex value;
        private readonly Complex delta;

        public Phasor(double freq, double rate)
        {
            value = new Complex(1, 0);
            double omega = 2 * Math.PI * freq / rate;
            delta = new Complex((float)Math.Cos(omega), (float)Math.Sin(omega));
        }

        public Complex Rotate()
        {
            return value.Div(value.Mul(delta).Abs());
        }
    }
}
