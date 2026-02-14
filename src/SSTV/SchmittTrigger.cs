/*
Schmitt Trigger
Ported to C# from https://github.com/xdsopl/robot36
*/

namespace HTCommander.SSTV
{
    public class SchmittTrigger
    {
        private readonly float low, high;
        private bool previous;

        public SchmittTrigger(float low, float high)
        {
            this.low = low;
            this.high = high;
        }

        public bool Latch(float input)
        {
            if (previous)
            {
                if (input < low)
                    previous = false;
            }
            else
            {
                if (input > high)
                    previous = true;
            }
            return previous;
        }
    }
}
