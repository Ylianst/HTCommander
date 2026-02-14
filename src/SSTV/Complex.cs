/*
Complex math
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public class Complex
    {
        public float Real, Imag;

        public Complex()
        {
            Real = 0;
            Imag = 0;
        }

        public Complex(float real, float imag)
        {
            Real = real;
            Imag = imag;
        }

        public Complex Set(Complex other)
        {
            Real = other.Real;
            Imag = other.Imag;
            return this;
        }

        public Complex Set(float real, float imag)
        {
            Real = real;
            Imag = imag;
            return this;
        }

        public Complex Set(float real)
        {
            return Set(real, 0);
        }

        public float Norm()
        {
            return Real * Real + Imag * Imag;
        }

        public float Abs()
        {
            return (float)Math.Sqrt(Norm());
        }

        public float Arg()
        {
            return (float)Math.Atan2(Imag, Real);
        }

        public Complex Polar(float a, float b)
        {
            Real = a * (float)Math.Cos(b);
            Imag = a * (float)Math.Sin(b);
            return this;
        }

        public Complex Conj()
        {
            Imag = -Imag;
            return this;
        }

        public Complex Add(Complex other)
        {
            Real += other.Real;
            Imag += other.Imag;
            return this;
        }

        public Complex Sub(Complex other)
        {
            Real -= other.Real;
            Imag -= other.Imag;
            return this;
        }

        public Complex Mul(float value)
        {
            Real *= value;
            Imag *= value;
            return this;
        }

        public Complex Mul(Complex other)
        {
            float tmp = Real * other.Real - Imag * other.Imag;
            Imag = Real * other.Imag + Imag * other.Real;
            Real = tmp;
            return this;
        }

        public Complex Div(float value)
        {
            Real /= value;
            Imag /= value;
            return this;
        }

        public Complex Div(Complex other)
        {
            float den = other.Norm();
            float tmp = (Real * other.Real + Imag * other.Imag) / den;
            Imag = (Imag * other.Real - Real * other.Imag) / den;
            Real = tmp;
            return this;
        }
    }
}
