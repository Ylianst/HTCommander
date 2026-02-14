/*
Complex Convolution
Ported to C# from https://github.com/xdsopl/robot36
*/

namespace HTCommander.SSTV
{
    public class ComplexConvolution
    {
        public readonly int Length;
        public readonly float[] Taps;
        private readonly float[] real;
        private readonly float[] imag;
        private readonly Complex sum;
        private int pos;

        public ComplexConvolution(int length)
        {
            Length = length;
            Taps = new float[length];
            real = new float[length];
            imag = new float[length];
            sum = new Complex();
            pos = 0;
        }

        public Complex Push(Complex input)
        {
            real[pos] = input.Real;
            imag[pos] = input.Imag;
            if (++pos >= Length)
                pos = 0;
            sum.Real = 0;
            sum.Imag = 0;
            for (int i = 0; i < Taps.Length; ++i)
            {
                sum.Real += Taps[i] * real[pos];
                sum.Imag += Taps[i] * imag[pos];
                if (++pos >= Length)
                    pos = 0;
            }
            return sum;
        }
    }
}
