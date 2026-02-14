/*
Digital delay line
Ported to C# from https://github.com/xdsopl/robot36
*/

namespace HTCommander.SSTV
{
    public class Delay
    {
        public readonly int Length;
        private readonly float[] buf;
        private int pos;

        public Delay(int length)
        {
            Length = length;
            buf = new float[length];
            pos = 0;
        }

        public float Push(float input)
        {
            float tmp = buf[pos];
            buf[pos] = input;
            if (++pos >= Length)
                pos = 0;
            return tmp;
        }
    }
}
