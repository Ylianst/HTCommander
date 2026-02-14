/*
Simple Moving Average
Ported to C# from https://github.com/xdsopl/robot36
*/

namespace HTCommander.SSTV
{
    public class SimpleMovingAverage : SimpleMovingSum
    {
        public SimpleMovingAverage(int length) : base(length)
        {
        }

        public float Avg(float input)
        {
            return Sum(input) / Length;
        }
    }
}
