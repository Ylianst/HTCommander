/*
Simple Moving Sum
Ported to C# from https://github.com/xdsopl/robot36
*/

namespace HTCommander.SSTV
{
    public class SimpleMovingSum
    {
        private readonly float[] tree;
        private int leaf;
        public readonly int Length;

        public SimpleMovingSum(int length)
        {
            Length = length;
            tree = new float[2 * length];
            leaf = length;
        }

        public void Add(float input)
        {
            tree[leaf] = input;
            for (int child = leaf, parent = leaf / 2; parent > 0; child = parent, parent /= 2)
                tree[parent] = tree[child] + tree[child ^ 1];
            if (++leaf >= tree.Length)
                leaf = Length;
        }

        public float Sum()
        {
            return tree[1];
        }

        public float Sum(float input)
        {
            Add(input);
            return Sum();
        }
    }
}
