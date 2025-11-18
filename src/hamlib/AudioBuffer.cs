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
// AudioBuffer.cs - Audio sample buffer management
//

using System.Collections.Generic;

namespace HamLib
{
    /// <summary>
    /// Manages audio sample buffers for encoding/decoding
    /// </summary>
    public class AudioBuffer
    {
        private List<short>[] _buffers;
        private object[] _locks;

        public AudioBuffer(int numDevices)
        {
            _buffers = new List<short>[numDevices];
            _locks = new object[numDevices];

            for (int i = 0; i < numDevices; i++)
            {
                _buffers[i] = new List<short>();
                _locks[i] = new object();
            }
        }

        /// <summary>
        /// Add a sample to the buffer for a specific device
        /// </summary>
        public void Put(int device, short sample)
        {
            lock (_locks[device])
            {
                _buffers[device].Add(sample);
            }
        }

        /// <summary>
        /// Get all samples from a device buffer and clear it
        /// </summary>
        public short[] GetAndClear(int device)
        {
            lock (_locks[device])
            {
                short[] samples = _buffers[device].ToArray();
                _buffers[device].Clear();
                return samples;
            }
        }

        /// <summary>
        /// Get the current number of samples in a buffer
        /// </summary>
        public int GetCount(int device)
        {
            lock (_locks[device])
            {
                return _buffers[device].Count;
            }
        }

        /// <summary>
        /// Clear a buffer
        /// </summary>
        public void Clear(int device)
        {
            lock (_locks[device])
            {
                _buffers[device].Clear();
            }
        }

        /// <summary>
        /// Clear all buffers
        /// </summary>
        public void ClearAll()
        {
            for (int i = 0; i < _buffers.Length; i++)
            {
                Clear(i);
            }
        }
    }
}
