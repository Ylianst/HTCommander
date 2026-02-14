/*
Fast Fourier Transform
Ported to C# from https://github.com/xdsopl/robot36
*/

using System;

namespace HTCommander.SSTV
{
    public class FastFourierTransform
    {
        private readonly Complex[] tf;
        private readonly Complex tmpA, tmpB, tmpC, tmpD, tmpE, tmpF, tmpG, tmpH, tmpI, tmpJ, tmpK, tmpL, tmpM;
        private readonly Complex tin0, tin1, tin2, tin3, tin4, tin5, tin6;

        public FastFourierTransform(int length)
        {
            int rest = length;
            while (rest > 1)
            {
                if (rest % 2 == 0)
                    rest /= 2;
                else if (rest % 3 == 0)
                    rest /= 3;
                else if (rest % 5 == 0)
                    rest /= 5;
                else if (rest % 7 == 0)
                    rest /= 7;
                else
                    break;
            }
            if (rest != 1)
                throw new ArgumentException(
                    "Transform length must be a composite of 2, 3, 5 and 7, but was: " + length);
            tf = new Complex[length];
            for (int i = 0; i < length; ++i)
            {
                double x = -(2.0 * Math.PI * i) / length;
                float a = (float)Math.Cos(x);
                float b = (float)Math.Sin(x);
                tf[i] = new Complex(a, b);
            }
            tmpA = new Complex();
            tmpB = new Complex();
            tmpC = new Complex();
            tmpD = new Complex();
            tmpE = new Complex();
            tmpF = new Complex();
            tmpG = new Complex();
            tmpH = new Complex();
            tmpI = new Complex();
            tmpJ = new Complex();
            tmpK = new Complex();
            tmpL = new Complex();
            tmpM = new Complex();
            tin0 = new Complex();
            tin1 = new Complex();
            tin2 = new Complex();
            tin3 = new Complex();
            tin4 = new Complex();
            tin5 = new Complex();
            tin6 = new Complex();
        }

        private static bool IsPowerOfTwo(int n)
        {
            return n > 0 && (n & (n - 1)) == 0;
        }

        private static bool IsPowerOfFour(int n)
        {
            return IsPowerOfTwo(n) && (n & 0x55555555) != 0;
        }

        private static float Cos(int n, int N)
        {
            return (float)Math.Cos(n * 2.0 * Math.PI / N);
        }

        private static float Sin(int n, int N)
        {
            return (float)Math.Sin(n * 2.0 * Math.PI / N);
        }

        private void Dft2(Complex out0, Complex out1, Complex in0, Complex in1)
        {
            out0.Set(in0).Add(in1);
            out1.Set(in0).Sub(in1);
        }

        private void Radix2(Complex[] output, Complex[] input, int O, int I, int N, int S, bool F)
        {
            if (N == 2)
            {
                Dft2(output[O], output[O + 1], input[I], input[I + S]);
            }
            else
            {
                int Q = N / 2;
                Dit(output, input, O, I, Q, 2 * S, F);
                Dit(output, input, O + Q, I + S, Q, 2 * S, F);
                for (int k0 = O, k1 = O + Q, l1 = 0; k0 < O + Q; ++k0, ++k1, l1 += S)
                {
                    tin1.Set(tf[l1]);
                    if (!F)
                        tin1.Conj();
                    tin0.Set(output[k0]);
                    tin1.Mul(output[k1]);
                    Dft2(output[k0], output[k1], tin0, tin1);
                }
            }
        }

        private void Fwd3(Complex out0, Complex out1, Complex out2, Complex in0, Complex in1, Complex in2)
        {
            tmpA.Set(in1).Add(in2);
            tmpB.Set(in1.Imag - in2.Imag, in2.Real - in1.Real);
            tmpC.Set(tmpA).Mul(Cos(1, 3));
            tmpD.Set(tmpB).Mul(Sin(1, 3));
            out0.Set(in0).Add(tmpA);
            out1.Set(in0).Add(tmpC).Add(tmpD);
            out2.Set(in0).Add(tmpC).Sub(tmpD);
        }

        private void Radix3(Complex[] output, Complex[] input, int O, int I, int N, int S, bool F)
        {
            if (N == 3)
            {
                if (F)
                    Fwd3(output[O], output[O + 1], output[O + 2],
                        input[I], input[I + S], input[I + 2 * S]);
                else
                    Fwd3(output[O], output[O + 2], output[O + 1],
                        input[I], input[I + S], input[I + 2 * S]);
            }
            else
            {
                int Q = N / 3;
                Dit(output, input, O, I, Q, 3 * S, F);
                Dit(output, input, O + Q, I + S, Q, 3 * S, F);
                Dit(output, input, O + 2 * Q, I + 2 * S, Q, 3 * S, F);
                for (int k0 = O, k1 = O + Q, k2 = O + 2 * Q, l1 = 0, l2 = 0;
                        k0 < O + Q; ++k0, ++k1, ++k2, l1 += S, l2 += 2 * S)
                {
                    tin1.Set(tf[l1]);
                    tin2.Set(tf[l2]);
                    if (!F)
                    {
                        tin1.Conj();
                        tin2.Conj();
                    }
                    tin0.Set(output[k0]);
                    tin1.Mul(output[k1]);
                    tin2.Mul(output[k2]);
                    if (F)
                        Fwd3(output[k0], output[k1], output[k2], tin0, tin1, tin2);
                    else
                        Fwd3(output[k0], output[k2], output[k1], tin0, tin1, tin2);
                }
            }
        }

        private void Fwd4(Complex out0, Complex out1, Complex out2, Complex out3,
                Complex in0, Complex in1, Complex in2, Complex in3)
        {
            tmpA.Set(in0).Add(in2);
            tmpB.Set(in0).Sub(in2);
            tmpC.Set(in1).Add(in3);
            tmpD.Set(in1.Imag - in3.Imag, in3.Real - in1.Real);
            out0.Set(tmpA).Add(tmpC);
            out1.Set(tmpB).Add(tmpD);
            out2.Set(tmpA).Sub(tmpC);
            out3.Set(tmpB).Sub(tmpD);
        }

        private void Radix4(Complex[] output, Complex[] input, int O, int I, int N, int S, bool F)
        {
            if (N == 4)
            {
                if (F)
                    Fwd4(output[O], output[O + 1], output[O + 2], output[O + 3],
                        input[I], input[I + S], input[I + 2 * S], input[I + 3 * S]);
                else
                    Fwd4(output[O], output[O + 3], output[O + 2], output[O + 1],
                        input[I], input[I + S], input[I + 2 * S], input[I + 3 * S]);
            }
            else
            {
                int Q = N / 4;
                Radix4(output, input, O, I, Q, 4 * S, F);
                Radix4(output, input, O + Q, I + S, Q, 4 * S, F);
                Radix4(output, input, O + 2 * Q, I + 2 * S, Q, 4 * S, F);
                Radix4(output, input, O + 3 * Q, I + 3 * S, Q, 4 * S, F);
                for (int k0 = O, k1 = O + Q, k2 = O + 2 * Q, k3 = O + 3 * Q, l1 = 0, l2 = 0, l3 = 0;
                        k0 < O + Q; ++k0, ++k1, ++k2, ++k3, l1 += S, l2 += 2 * S, l3 += 3 * S)
                {
                    tin1.Set(tf[l1]);
                    tin2.Set(tf[l2]);
                    tin3.Set(tf[l3]);
                    if (!F)
                    {
                        tin1.Conj();
                        tin2.Conj();
                        tin3.Conj();
                    }
                    tin0.Set(output[k0]);
                    tin1.Mul(output[k1]);
                    tin2.Mul(output[k2]);
                    tin3.Mul(output[k3]);
                    if (F)
                        Fwd4(output[k0], output[k1], output[k2], output[k3], tin0, tin1, tin2, tin3);
                    else
                        Fwd4(output[k0], output[k3], output[k2], output[k1], tin0, tin1, tin2, tin3);
                }
            }
        }

        private void Fwd5(Complex out0, Complex out1, Complex out2, Complex out3, Complex out4,
                Complex in0, Complex in1, Complex in2, Complex in3, Complex in4)
        {
            tmpA.Set(in1).Add(in4);
            tmpB.Set(in2).Add(in3);
            tmpC.Set(in1.Imag - in4.Imag, in4.Real - in1.Real);
            tmpD.Set(in2.Imag - in3.Imag, in3.Real - in2.Real);
            tmpF.Set(tmpA).Mul(Cos(1, 5)).Add(tmpE.Set(tmpB).Mul(Cos(2, 5)));
            tmpG.Set(tmpC).Mul(Sin(1, 5)).Add(tmpE.Set(tmpD).Mul(Sin(2, 5)));
            tmpH.Set(tmpA).Mul(Cos(2, 5)).Add(tmpE.Set(tmpB).Mul(Cos(1, 5)));
            tmpI.Set(tmpC).Mul(Sin(2, 5)).Sub(tmpE.Set(tmpD).Mul(Sin(1, 5)));
            out0.Set(in0).Add(tmpA).Add(tmpB);
            out1.Set(in0).Add(tmpF).Add(tmpG);
            out2.Set(in0).Add(tmpH).Add(tmpI);
            out3.Set(in0).Add(tmpH).Sub(tmpI);
            out4.Set(in0).Add(tmpF).Sub(tmpG);
        }

        private void Radix5(Complex[] output, Complex[] input, int O, int I, int N, int S, bool F)
        {
            if (N == 5)
            {
                if (F)
                    Fwd5(output[O], output[O + 1], output[O + 2], output[O + 3], output[O + 4],
                        input[I], input[I + S], input[I + 2 * S], input[I + 3 * S], input[I + 4 * S]);
                else
                    Fwd5(output[O], output[O + 4], output[O + 3], output[O + 2], output[O + 1],
                        input[I], input[I + S], input[I + 2 * S], input[I + 3 * S], input[I + 4 * S]);
            }
            else
            {
                int Q = N / 5;
                Dit(output, input, O, I, Q, 5 * S, F);
                Dit(output, input, O + Q, I + S, Q, 5 * S, F);
                Dit(output, input, O + 2 * Q, I + 2 * S, Q, 5 * S, F);
                Dit(output, input, O + 3 * Q, I + 3 * S, Q, 5 * S, F);
                Dit(output, input, O + 4 * Q, I + 4 * S, Q, 5 * S, F);
                for (int k0 = O, k1 = O + Q, k2 = O + 2 * Q, k3 = O + 3 * Q, k4 = O + 4 * Q, l1 = 0, l2 = 0, l3 = 0, l4 = 0;
                        k0 < O + Q; ++k0, ++k1, ++k2, ++k3, ++k4, l1 += S, l2 += 2 * S, l3 += 3 * S, l4 += 4 * S)
                {
                    tin1.Set(tf[l1]);
                    tin2.Set(tf[l2]);
                    tin3.Set(tf[l3]);
                    tin4.Set(tf[l4]);
                    if (!F)
                    {
                        tin1.Conj();
                        tin2.Conj();
                        tin3.Conj();
                        tin4.Conj();
                    }
                    tin0.Set(output[k0]);
                    tin1.Mul(output[k1]);
                    tin2.Mul(output[k2]);
                    tin3.Mul(output[k3]);
                    tin4.Mul(output[k4]);
                    if (F)
                        Fwd5(output[k0], output[k1], output[k2], output[k3], output[k4], tin0, tin1, tin2, tin3, tin4);
                    else
                        Fwd5(output[k0], output[k4], output[k3], output[k2], output[k1], tin0, tin1, tin2, tin3, tin4);
                }
            }
        }

        private void Fwd7(Complex out0, Complex out1, Complex out2, Complex out3, Complex out4, Complex out5, Complex out6,
                Complex in0, Complex in1, Complex in2, Complex in3, Complex in4, Complex in5, Complex in6)
        {
            tmpA.Set(in1).Add(in6);
            tmpB.Set(in2).Add(in5);
            tmpC.Set(in3).Add(in4);
            tmpD.Set(in1.Imag - in6.Imag, in6.Real - in1.Real);
            tmpE.Set(in2.Imag - in5.Imag, in5.Real - in2.Real);
            tmpF.Set(in3.Imag - in4.Imag, in4.Real - in3.Real);
            tmpH.Set(tmpA).Mul(Cos(1, 7)).Add(tmpG.Set(tmpB).Mul(Cos(2, 7))).Add(tmpG.Set(tmpC).Mul(Cos(3, 7)));
            tmpI.Set(tmpD).Mul(Sin(1, 7)).Add(tmpG.Set(tmpE).Mul(Sin(2, 7))).Add(tmpG.Set(tmpF).Mul(Sin(3, 7)));
            tmpJ.Set(tmpA).Mul(Cos(2, 7)).Add(tmpG.Set(tmpB).Mul(Cos(3, 7))).Add(tmpG.Set(tmpC).Mul(Cos(1, 7)));
            tmpK.Set(tmpD).Mul(Sin(2, 7)).Sub(tmpG.Set(tmpE).Mul(Sin(3, 7))).Sub(tmpG.Set(tmpF).Mul(Sin(1, 7)));
            tmpL.Set(tmpA).Mul(Cos(3, 7)).Add(tmpG.Set(tmpB).Mul(Cos(1, 7))).Add(tmpG.Set(tmpC).Mul(Cos(2, 7)));
            tmpM.Set(tmpD).Mul(Sin(3, 7)).Sub(tmpG.Set(tmpE).Mul(Sin(1, 7))).Add(tmpG.Set(tmpF).Mul(Sin(2, 7)));
            out0.Set(in0).Add(tmpA).Add(tmpB).Add(tmpC);
            out1.Set(in0).Add(tmpH).Add(tmpI);
            out2.Set(in0).Add(tmpJ).Add(tmpK);
            out3.Set(in0).Add(tmpL).Add(tmpM);
            out4.Set(in0).Add(tmpL).Sub(tmpM);
            out5.Set(in0).Add(tmpJ).Sub(tmpK);
            out6.Set(in0).Add(tmpH).Sub(tmpI);
        }

        private void Radix7(Complex[] output, Complex[] input, int O, int I, int N, int S, bool F)
        {
            if (N == 7)
            {
                if (F)
                    Fwd7(output[O], output[O + 1], output[O + 2], output[O + 3], output[O + 4], output[O + 5], output[O + 6],
                        input[I], input[I + S], input[I + 2 * S], input[I + 3 * S], input[I + 4 * S], input[I + 5 * S], input[I + 6 * S]);
                else
                    Fwd7(output[O], output[O + 6], output[O + 5], output[O + 4], output[O + 3], output[O + 2], output[O + 1],
                        input[I], input[I + S], input[I + 2 * S], input[I + 3 * S], input[I + 4 * S], input[I + 5 * S], input[I + 6 * S]);
            }
            else
            {
                int Q = N / 7;
                Dit(output, input, O, I, Q, 7 * S, F);
                Dit(output, input, O + Q, I + S, Q, 7 * S, F);
                Dit(output, input, O + 2 * Q, I + 2 * S, Q, 7 * S, F);
                Dit(output, input, O + 3 * Q, I + 3 * S, Q, 7 * S, F);
                Dit(output, input, O + 4 * Q, I + 4 * S, Q, 7 * S, F);
                Dit(output, input, O + 5 * Q, I + 5 * S, Q, 7 * S, F);
                Dit(output, input, O + 6 * Q, I + 6 * S, Q, 7 * S, F);
                for (int k0 = O, k1 = O + Q, k2 = O + 2 * Q, k3 = O + 3 * Q, k4 = O + 4 * Q, k5 = O + 5 * Q, k6 = O + 6 * Q, l1 = 0, l2 = 0, l3 = 0, l4 = 0, l5 = 0, l6 = 0;
                        k0 < O + Q; ++k0, ++k1, ++k2, ++k3, ++k4, ++k5, ++k6, l1 += S, l2 += 2 * S, l3 += 3 * S, l4 += 4 * S, l5 += 5 * S, l6 += 6 * S)
                {
                    tin1.Set(tf[l1]);
                    tin2.Set(tf[l2]);
                    tin3.Set(tf[l3]);
                    tin4.Set(tf[l4]);
                    tin5.Set(tf[l5]);
                    tin6.Set(tf[l6]);
                    if (!F)
                    {
                        tin1.Conj();
                        tin2.Conj();
                        tin3.Conj();
                        tin4.Conj();
                        tin5.Conj();
                        tin6.Conj();
                    }
                    tin0.Set(output[k0]);
                    tin1.Mul(output[k1]);
                    tin2.Mul(output[k2]);
                    tin3.Mul(output[k3]);
                    tin4.Mul(output[k4]);
                    tin5.Mul(output[k5]);
                    tin6.Mul(output[k6]);
                    if (F)
                        Fwd7(output[k0], output[k1], output[k2], output[k3], output[k4], output[k5], output[k6], tin0, tin1, tin2, tin3, tin4, tin5, tin6);
                    else
                        Fwd7(output[k0], output[k6], output[k5], output[k4], output[k3], output[k2], output[k1], tin0, tin1, tin2, tin3, tin4, tin5, tin6);
                }
            }
        }

        private void Dit(Complex[] output, Complex[] input, int O, int I, int N, int S, bool F)
        {
            if (N == 1)
                output[O].Set(input[I]);
            else if (IsPowerOfFour(N))
                Radix4(output, input, O, I, N, S, F);
            else if (N % 7 == 0)
                Radix7(output, input, O, I, N, S, F);
            else if (N % 5 == 0)
                Radix5(output, input, O, I, N, S, F);
            else if (N % 3 == 0)
                Radix3(output, input, O, I, N, S, F);
            else if (N % 2 == 0)
                Radix2(output, input, O, I, N, S, F);
        }

        public void Forward(Complex[] output, Complex[] input)
        {
            if (input.Length != tf.Length)
                throw new ArgumentException("Input array length (" + input.Length
                    + ") must be equal to Transform length (" + tf.Length + ")");
            if (output.Length != tf.Length)
                throw new ArgumentException("Output array length (" + output.Length
                    + ") must be equal to Transform length (" + tf.Length + ")");
            Dit(output, input, 0, 0, tf.Length, 1, true);
        }

        public void Backward(Complex[] output, Complex[] input)
        {
            if (input.Length != tf.Length)
                throw new ArgumentException("Input array length (" + input.Length
                    + ") must be equal to Transform length (" + tf.Length + ")");
            if (output.Length != tf.Length)
                throw new ArgumentException("Output array length (" + output.Length
                    + ") must be equal to Transform length (" + tf.Length + ")");
            Dit(output, input, 0, 0, tf.Length, 1, false);
        }
    }
}
