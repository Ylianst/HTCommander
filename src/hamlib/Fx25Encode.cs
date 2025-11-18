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
// Fx25Encode.cs - FX.25 Reed-Solomon encoding
//

using System;

namespace HamLib
{
    /// <summary>
    /// FX.25 Reed-Solomon encoding operations
    /// Direct port of fx25_encode.c
    /// </summary>
    public static class Fx25Encode
    {
        /// <summary>
        /// Encode data with Reed-Solomon forward error correction.
        /// This is the main encoding function that generates check bytes for FX.25 transmission.
        /// </summary>
        /// <param name="rs">Reed-Solomon codec control block containing encoding parameters</param>
        /// <param name="data">Data buffer to encode (input data portion of RS block)</param>
        /// <param name="bb">Output buffer for check bytes (parity symbols). 
        /// Must be at least rs.NRoots bytes in size.</param>
        /// <remarks>
        /// This function implements systematic Reed-Solomon encoding where the original
        /// data is transmitted unchanged, followed by the check bytes. The encoding uses
        /// the generator polynomial stored in the rs structure to compute parity symbols.
        /// 
        /// The algorithm:
        /// 1. Clears the check byte buffer
        /// 2. For each data byte, computes feedback term using Galois field operations
        /// 3. Updates check bytes using generator polynomial coefficients
        /// 4. Shifts check byte register and computes new parity symbol
        /// 
        /// After encoding, transmit: [correlation_tag][data][bb]
        /// </remarks>
        public static void EncodeRs(ReedSolomonCodec rs, byte[] data, byte[] bb)
        {
            // Clear out the FEC data area (check bytes buffer)
            Array.Clear(bb, 0, (int)rs.NRoots);

            // Process each data symbol
            // NN is the total block size (255 for 8-bit symbols)
            // NRoots is the number of check bytes (16, 32, or 64 depending on FX.25 mode)
            // So we process NN - NRoots data bytes (239, 223, or 191 bytes)
            for (int i = 0; i < rs.NN - rs.NRoots; i++)
            {
                // Compute feedback term by XORing current data byte with first check byte
                // and converting to index form using logarithm lookup table
                byte feedback = rs.IndexOf[data[i] ^ bb[0]];

                // If feedback term is non-zero (not A0 which represents log of zero)
                if (feedback != rs.NN)
                {
                    // Update all check bytes using generator polynomial
                    // This is the core of the Reed-Solomon encoding algorithm
                    for (int j = 1; j < rs.NRoots; j++)
                    {
                        // Multiply feedback by generator polynomial coefficient and XOR with check byte
                        // MODNN handles modulo (2^m - 1) arithmetic for Galois field
                        bb[j] ^= rs.AlphaTo[rs.ModNN(feedback + rs.GenPoly[rs.NRoots - j])];
                    }
                }

                // Shift check bytes left by one position
                // This is equivalent to multiplying the polynomial by x
                Array.Copy(bb, 1, bb, 0, (int)rs.NRoots - 1);

                // Compute new last check byte
                if (feedback != rs.NN)
                {
                    // If feedback was non-zero, compute new check byte using generator polynomial
                    bb[rs.NRoots - 1] = rs.AlphaTo[rs.ModNN(feedback + rs.GenPoly[0])];
                }
                else
                {
                    // If feedback was zero, new check byte is zero
                    bb[rs.NRoots - 1] = 0;
                }
            }
        }
    }
}
