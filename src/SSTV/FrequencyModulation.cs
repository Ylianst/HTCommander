/*
Frequency Modulation
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public class FrequencyModulation
    {
        private float prev;
        private readonly float scale;
        private readonly float Pi, TwoPi;

        public FrequencyModulation(double bandwidth, double sampleRate)
        {
            Pi = (float)Math.PI;
            TwoPi = 2 * Pi;
            scale = (float)(sampleRate / (bandwidth * Math.PI));
        }

        private float Wrap(float value)
        {
            if (value < -Pi)
                return value + TwoPi;
            if (value > Pi)
                return value - TwoPi;
            return value;
        }

        public float Demod(Complex input)
        {
            float phase = input.Arg();
            float delta = Wrap(phase - prev);
            prev = phase;
            return scale * delta;
        }
    }
}
