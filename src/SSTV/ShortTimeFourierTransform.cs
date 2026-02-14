/*
Short Time Fourier Transform
Ported to C# from https://github.com/xdsopl/robot36
*/

namespace HTCommander.SSTV
{
    public class ShortTimeFourierTransform
    {
        private readonly FastFourierTransform fft;
        private readonly Complex[] prev, fold, freq;
        private readonly float[] weight;
        private readonly Complex temp;
        private int index;

        public readonly float[] Power;

        public ShortTimeFourierTransform(int length, int overlap)
        {
            fft = new FastFourierTransform(length);
            prev = new Complex[length * overlap];
            for (int i = 0; i < length * overlap; ++i)
                prev[i] = new Complex();
            fold = new Complex[length];
            for (int i = 0; i < length; ++i)
                fold[i] = new Complex();
            freq = new Complex[length];
            for (int i = 0; i < length; ++i)
                freq[i] = new Complex();
            temp = new Complex();
            Power = new float[length];
            weight = new float[length * overlap];
            for (int i = 0; i < length * overlap; ++i)
                weight[i] = (float)(Filter.LowPass(1, length, i, length * overlap) * Hann.Window(i, length * overlap));
        }

        public bool Push(Complex input)
        {
            prev[index].Set(input);
            index = (index + 1) % prev.Length;
            if (index % fold.Length != 0)
                return false;
            for (int i = 0; i < fold.Length; ++i)
            {
                fold[i].Set(prev[index]).Mul(weight[i]);
                index = (index + 1) % prev.Length;
            }
            for (int i = fold.Length; i < prev.Length; ++i)
            {
                fold[i % fold.Length].Add(temp.Set(prev[index]).Mul(weight[i]));
                index = (index + 1) % prev.Length;
            }
            fft.Forward(freq, fold);
            for (int i = 0; i < Power.Length; ++i)
                Power[i] = freq[i].Norm();
            return true;
        }
    }
}
