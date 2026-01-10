/*
Copyright 2026 Ylian Saint-Hilaire

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
// IHdlcReceiver.cs - Interface for HDLC receivers
//

namespace HamLib
{
    /// <summary>
    /// Interface for HDLC bit receivers that can be used with demodulators
    /// </summary>
    public interface IHdlcReceiver
    {
        /// <summary>
        /// Process a single received bit
        /// </summary>
        void RecBit(int chan, int subchan, int slice, int raw, bool isScrambled, int notUsedRemove);

        /// <summary>
        /// Handle DCD (Data Carrier Detect) state change
        /// </summary>
        void DcdChange(int chan, int subchan, int slice, bool dcdOn);
    }
}
