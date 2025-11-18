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

namespace HTCommander
{

    /// <summary>
    /// Bitstream reader/writer for SBC encoding and decoding
    /// </summary>
    internal class SbcBitStream
    {
        private readonly byte[] _data;
        private readonly int _maxBytes;
        private readonly bool _isReader;

        private int _bytePosition;
        private uint _accumulator;
        private int _bitsInAccumulator;
        private bool _error;

        public SbcBitStream(byte[] data, int size, bool isReader)
        {
            _data = data;
            _maxBytes = size;
            _isReader = isReader;
            _bytePosition = 0;
            _accumulator = 0;
            _bitsInAccumulator = 0;
            _error = false;
        }

        public bool HasError => _error;

        public int BitPosition => (_bytePosition * 8) + (sizeof(uint) * 8 - _bitsInAccumulator);

        /// <summary>
        /// Read bits from the stream (1-32 bits)
        /// </summary>
        public uint GetBits(int numBits)
        {
            if (numBits == 0)
                return 0;

            if (numBits < 0 || numBits > 32)
            {
                _error = true;
                return 0;
            }

            // Refill accumulator if needed
            while (_bitsInAccumulator < numBits && _bytePosition < _maxBytes)
            {
                _accumulator = (_accumulator << 8) | _data[_bytePosition++];
                _bitsInAccumulator += 8;
            }

            // Check if we have enough bits
            if (_bitsInAccumulator < numBits)
            {
                // Not enough data - return what we have padded with zeros
                uint result = _accumulator << (numBits - _bitsInAccumulator);
                _bitsInAccumulator = 0;
                _accumulator = 0;
                _error = true;
                return result & ((1u << numBits) - 1);
            }

            // Extract the requested bits
            _bitsInAccumulator -= numBits;
            uint value = (_accumulator >> _bitsInAccumulator) & ((1u << numBits) - 1);
            _accumulator &= (1u << _bitsInAccumulator) - 1;

            return value;
        }

        /// <summary>
        /// Read bits and verify they match expected value
        /// </summary>
        public void GetFixedBits(int numBits, uint expectedValue)
        {
            uint value = GetBits(numBits);
            if (value != expectedValue)
                _error = true;
        }

        /// <summary>
        /// Write bits to the stream (0-32 bits)
        /// </summary>
        public void PutBits(uint value, int numBits)
        {
            if (numBits == 0)
                return;

            if (numBits < 0 || numBits > 32)
            {
                _error = true;
                return;
            }

            // Mask the value to the requested number of bits
            value &= (1u << numBits) - 1;

            // Add to accumulator
            _accumulator = (_accumulator << numBits) | value;
            _bitsInAccumulator += numBits;

            // Flush full bytes
            while (_bitsInAccumulator >= 8)
            {
                if (_bytePosition >= _maxBytes)
                {
                    _error = true;
                    return;
                }

                _bitsInAccumulator -= 8;
                _data[_bytePosition++] = (byte)(_accumulator >> _bitsInAccumulator);
                _accumulator &= (1u << _bitsInAccumulator) - 1;
            }
        }

        /// <summary>
        /// Flush any remaining bits in the accumulator to the output
        /// </summary>
        public void Flush()
        {
            if (_bitsInAccumulator > 0)
            {
                if (_bytePosition >= _maxBytes)
                {
                    _error = true;
                    return;
                }

                // Pad with zeros and write the final byte
                _data[_bytePosition++] = (byte)(_accumulator << (8 - _bitsInAccumulator));
                _bitsInAccumulator = 0;
                _accumulator = 0;
            }
        }
    }
}