/*
Copyright 2025 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// ReedSolomonCodec.cs - Reed-Solomon encoding and decoding
//

using System;
using System.Diagnostics;

namespace HamLib
{
    /// <summary>
    /// Reed-Solomon encoding and decoding operations
    /// </summary>
    public static class ReedSolomon
    {
        /// <summary>
        /// Encode data with Reed-Solomon error correction
        /// </summary>
        /// <param name="rs">Reed-Solomon codec control block</param>
        /// <param name="data">Data to encode (will be modified in place)</param>
        /// <param name="bb">Output buffer for check bytes</param>
        public static void Encode(ReedSolomonCodec rs, byte[] data, byte[] bb)
        {
            Array.Clear(bb, 0, (int)rs.NRoots);

            for (int i = 0; i < rs.NN - rs.NRoots; i++)
            {
                byte feedback = (byte)(rs.IndexOf[data[i] ^ bb[0]]);
                if (feedback != rs.NN)
                {
                    // Feedback term is non-zero
                    for (int j = 1; j < rs.NRoots; j++)
                    {
                        bb[j] ^= rs.AlphaTo[rs.ModNN(feedback + rs.GenPoly[rs.NRoots - j])];
                    }
                }

                // Shift
                Array.Copy(bb, 1, bb, 0, (int)rs.NRoots - 1);

                if (feedback != rs.NN)
                {
                    bb[rs.NRoots - 1] = rs.AlphaTo[rs.ModNN(feedback + rs.GenPoly[0])];
                }
                else
                {
                    bb[rs.NRoots - 1] = 0;
                }
            }
        }

        /// <summary>
        /// Decode data with Reed-Solomon error correction
        /// </summary>
        /// <param name="rs">Reed-Solomon codec control block</param>
        /// <param name="data">Data block to decode (will be corrected in place)</param>
        /// <param name="erasPos">Erasure positions (can be null)</param>
        /// <param name="noEras">Number of erasures</param>
        /// <returns>Number of errors corrected, or -1 if uncorrectable</returns>
        public static int Decode(ReedSolomonCodec rs, byte[] data, int[] erasPos, int noEras)
        {
            int deg_lambda, el;
            int i, j, r, k;
            byte u, q, tmp, num1, num2, den, discr_r;
            byte[] lambda = new byte[rs.NRoots + 1]; // Error locator polynomial
            byte[] s = new byte[rs.NRoots];          // Syndrome vector
            byte[] b = new byte[rs.NRoots + 1];
            byte[] t = new byte[rs.NRoots + 1];
            byte[] omega = new byte[rs.NRoots + 1];  // Error evaluator polynomial
            byte[] root = new byte[rs.NRoots];
            byte[] reg = new byte[rs.NRoots + 1];
            byte[] loc = new byte[rs.NRoots];
            int syn_error, count;

            // Form the syndromes; i.e., evaluate data(x) at roots of g(x)
            for (i = 0; i < rs.NRoots; i++)
                s[i] = data[0];

            for (j = 1; j < rs.NN; j++)
            {
                for (i = 0; i < rs.NRoots; i++)
                {
                    if (s[i] == 0)
                    {
                        s[i] = data[j];
                    }
                    else
                    {
                        s[i] = (byte)(data[j] ^ rs.AlphaTo[rs.ModNN(rs.IndexOf[s[i]] + (rs.Fcr + i) * rs.Prim)]);
                    }
                }
            }

            // Convert syndromes to index form, checking for nonzero condition
            syn_error = 0;
            for (i = 0; i < rs.NRoots; i++)
            {
                syn_error |= s[i];
                s[i] = rs.IndexOf[s[i]];
            }

            if (syn_error == 0)
            {
                // If syndrome is zero, data is OK (no errors)
                count = 0;
                return count;
            }

            Array.Clear(lambda, 1, (int)rs.NRoots);
            lambda[0] = 1;

            if (noEras > 0)
            {
                // Init lambda to be the erasure locator polynomial
                lambda[1] = rs.AlphaTo[rs.ModNN(rs.Prim * ((int)rs.NN - 1 - erasPos[0]))];
                for (i = 1; i < noEras; i++)
                {
                    u = rs.AlphaTo[rs.ModNN(rs.Prim * ((int)rs.NN - 1 - erasPos[i]))];
                    for (j = i + 1; j > 0; j--)
                    {
                        tmp = rs.IndexOf[lambda[j - 1]];
                        if (tmp != rs.NN)
                            lambda[j] ^= rs.AlphaTo[rs.ModNN(u + tmp)];
                    }
                }
            }

            for (i = 0; i < rs.NRoots + 1; i++)
                b[i] = rs.IndexOf[lambda[i]];

            // Begin Berlekamp-Massey algorithm to determine error locator polynomial
            r = noEras;
            el = noEras;
            while (++r <= rs.NRoots)
            {
                // Compute discrepancy at the r-th step
                discr_r = 0;
                for (i = 0; i < r; i++)
                {
                    if ((lambda[i] != 0) && (s[r - i - 1] != rs.NN))
                    {
                        discr_r ^= rs.AlphaTo[rs.ModNN(rs.IndexOf[lambda[i]] + s[r - i - 1])];
                    }
                }
                discr_r = rs.IndexOf[discr_r];

                if (discr_r == (byte)rs.NN)
                {
                    // B(x) <-- x*B(x)
                    Array.Copy(b, 0, b, 1, (int)rs.NRoots);
                    b[0] = (byte)rs.NN;
                }
                else
                {
                    // T(x) <-- lambda(x) - discr_r*x*b(x)
                    t[0] = lambda[0];
                    for (i = 0; i < rs.NRoots; i++)
                    {
                        if (b[i] != rs.NN)
                            t[i + 1] = (byte)(lambda[i + 1] ^ rs.AlphaTo[rs.ModNN(discr_r + b[i])]);
                        else
                            t[i + 1] = lambda[i + 1];
                    }
                    if (2 * el <= r + noEras - 1)
                    {
                        el = r + noEras - el;
                        // B(x) <-- inv(discr_r) * lambda(x)
                        for (i = 0; i <= rs.NRoots; i++)
                        b[i] = (lambda[i] == 0) ? (byte)rs.NN : (byte)rs.ModNN(rs.IndexOf[lambda[i]] - discr_r + (int)rs.NN);
                    }
                    else
                    {
                        // B(x) <-- x*B(x)
                        Array.Copy(b, 0, b, 1, (int)rs.NRoots);
                        b[0] = (byte)rs.NN;
                    }
                    Array.Copy(t, 0, lambda, 0, (int)rs.NRoots + 1);
                }
            }

            // Convert lambda to index form and compute deg(lambda(x))
            deg_lambda = 0;
            for (i = 0; i < rs.NRoots + 1; i++)
            {
                lambda[i] = rs.IndexOf[lambda[i]];
                if (lambda[i] != (byte)rs.NN)
                    deg_lambda = i;
            }

            // Compute error evaluator polynomial omega(x) = s(x)*lambda(x) (modulo x**NROOTS)
            // Also find deg(omega)
            int deg_omega = 0;
            for (i = 0; i < rs.NRoots; i++)
            {
                tmp = 0;
                for (j = (deg_lambda < i) ? deg_lambda : i; j >= 0; j--)
                {
                    if ((s[i - j] != (byte)rs.NN) && (lambda[j] != (byte)rs.NN))
                        tmp ^= rs.AlphaTo[rs.ModNN(s[i - j] + lambda[j])];
                }
                if (tmp != 0)
                    deg_omega = i;
                omega[i] = rs.IndexOf[tmp];
            }
            omega[rs.NRoots] = (byte)rs.NN;

            // Find roots of the error locator polynomial by Chien search
            Array.Copy(lambda, 1, reg, 1, (int)rs.NRoots);
            count = 0;
            for (i = 1, k = rs.IPrim - 1; i <= rs.NN; i++, k = rs.ModNN(k + rs.IPrim))
            {
                q = 1;
                for (j = deg_lambda; j > 0; j--)
                {
                    if (reg[j] != rs.NN)
                    {
                        reg[j] = (byte)rs.ModNN(reg[j] + j);
                        q ^= rs.AlphaTo[reg[j]];
                    }
                }
                if (q != 0)
                    continue; // Not a root

                // Store root (index-form) and error location number
                root[count] = (byte)i;
                loc[count] = (byte)k;

                // If we've already found max possible roots, abort the search
                if (++count == deg_lambda)
                    break;
            }

            if (deg_lambda != count)
            {
                // deg(lambda) unequal to number of roots => uncorrectable error detected
                count = -1;
                return count;
            }

            // Compute error values in poly-form. num1 = omega(inv(X(l))), num2 = inv(X(l))**(FCR-1)
            // and den = lambda_pr(inv(X(l))) all in poly-form
            for (j = count - 1; j >= 0; j--)
            {
                num1 = 0;
                for (i = deg_omega; i >= 0; i--)
                {
                    if (omega[i] != (byte)rs.NN)
                        num1 ^= rs.AlphaTo[rs.ModNN(omega[i] + i * root[j])];
                }

                num2 = rs.AlphaTo[rs.ModNN(root[j] * (rs.Fcr - 1) + (int)rs.NN)];
                den = 0;

                // lambda[i+1] for i even is the formal derivative lambda_pr of lambda[i]
                for (i = Math.Min(deg_lambda, (int)rs.NRoots - 1) & ~1; i >= 0; i -= 2)
                {
                    if (lambda[i + 1] != (byte)rs.NN)
                        den ^= rs.AlphaTo[rs.ModNN(lambda[i + 1] + i * root[j])];
                }

                if (den == 0)
                {
                    count = -1;
                    return count;
                }

                // Apply error to data
                if (num1 != 0 && loc[j] < rs.NN)
                {
                    data[loc[j]] ^= rs.AlphaTo[rs.ModNN(rs.IndexOf[num1] + rs.IndexOf[num2] + (int)rs.NN - rs.IndexOf[den])];
                }
            }

            return count;
        }
    }
}
