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

// Ax25Link.cs, AX.25 Data Link State Machine

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;

namespace HamLib
{
    // Limits and defaults for parameters
    public static class Ax25LinkConstants
    {
        // Max bytes in Information part of frame
        public const int AX25_N1_PACLEN_MIN = 1;
        public const int AX25_N1_PACLEN_DEFAULT = 256;  // some v2.0 implementations have 128
        public const int AX25_N1_PACLEN_MAX = 2048;     // AX25_MAX_INFO_LEN
        
        // Number of times to retry before giving up
        public const int AX25_N2_RETRY_MIN = 1;
        public const int AX25_N2_RETRY_DEFAULT = 10;
        public const int AX25_N2_RETRY_MAX = 15;
        
        // Number of seconds to wait before retrying
        public const int AX25_T1V_FRACK_MIN = 1;
        public const int AX25_T1V_FRACK_DEFAULT = 3;    // KPC-3+ has 4, TM-D710A has 3
        public const int AX25_T1V_FRACK_MAX = 15;
        
        // Window size - number of I frames to send before waiting for ack
        public const int AX25_K_MAXFRAME_BASIC_MIN = 1;
        public const int AX25_K_MAXFRAME_BASIC_DEFAULT = 4;
        public const int AX25_K_MAXFRAME_BASIC_MAX = 7;
        
        public const int AX25_K_MAXFRAME_EXTENDED_MIN = 1;
        public const int AX25_K_MAXFRAME_EXTENDED_DEFAULT = 32;
        public const int AX25_K_MAXFRAME_EXTENDED_MAX = 63;  // In theory 127 but restricted
        
        public const double T3_DEFAULT = 300.0;  // 5 minutes of inactivity
        public const int GENEROUS_K = 63;        // For SREJ window calculations
        
        public const int MAGIC1 = 0x11592201;
        public const int MAGIC2 = 0x02221201;
        public const int MAGIC3 = 0x03331301;
        public const int RC_MAGIC = 0x08291951;
    }
    
    // Data link state machine states
    public enum DlsmState
    {
        Disconnected = 0,
        AwaitingConnection = 1,
        AwaitingRelease = 2,
        Connected = 3,
        TimerRecovery = 4,
        AwaitingV22Connection = 5
    }
    
    // SREJ enable options
    public enum SrejEnable
    {
        None = 0,
        Single = 1,
        Multi = 2,
        NotSpecified = 99
    }
    
    // MDL (Management Data Link) state
    public enum MdlState
    {
        Ready = 0,
        Negotiating = 1
    }
    
    // Connected data block for transmit/receive queues
    public class CData
    {
        public int Pid { get; set; }
        public byte[] Data { get; set; }
        public int Len { get; set; }
        public int Size { get; set; }  // Allocated size
        public CData Next { get; set; }
        
        public CData(int pid, byte[] data, int len)
        {
            Pid = pid;
            if (data != null && len > 0)
            {
                Data = new byte[len];
                Array.Copy(data, Data, Math.Min(len, data.Length));
                Len = len;
                Size = len;
            }
            else
            {
                Data = Array.Empty<byte>();
                Len = 0;
                Size = 0;
            }
        }
        
        public CData(int pid, string str, int len)
        {
            Pid = pid;
            if (!string.IsNullOrEmpty(str))
            {
                Data = Encoding.ASCII.GetBytes(str);
                Len = Math.Min(len, Data.Length);
                Size = Data.Length;
            }
            else
            {
                Data = Array.Empty<byte>();
                Len = 0;
                Size = 0;
            }
        }
    }
    
    // Registered callsign for incoming connections
    public class RegCallsign
    {
        public string Callsign { get; set; }
        public int Chan { get; set; }
        public int Client { get; set; }
        public RegCallsign Next { get; set; }
        public int Magic { get; set; } = Ax25LinkConstants.RC_MAGIC;
    }
    
    // AX.25 Data Link State Machine
    public class Ax25Dlsm
    {
        public int Magic1 { get; set; } = Ax25LinkConstants.MAGIC1;
        public Ax25Dlsm Next { get; set; }
        
        public int StreamId { get; set; }
        public int Chan { get; set; }
        public int Client { get; set; }
        
        public string[] Addrs { get; set; } = new string[10];
        public int NumAddr { get; set; }
        
        public const int OWNCALL = 0;   // AX25_SOURCE
        public const int PEERCALL = 1;  // AX25_DESTINATION
        
        public double StartTime { get; set; }
        public DlsmState State { get; set; }
        
        public int Modulo { get; set; }
        public SrejEnable SrejEnable { get; set; }
        
        public int N1Paclen { get; set; }
        public int N2Retry { get; set; }
        public int KMaxframe { get; set; }
        
        public int Rc { get; set; }
        public int Vs { get; set; }
        public int Va { get; set; }
        public int Vr { get; set; }
        
        public bool LayerThreeInitiated { get; set; }
        
        // Exception conditions
        public bool PeerReceiverBusy { get; set; }
        public bool RejectException { get; set; }
        public bool OwnReceiverBusy { get; set; }
        public bool AcknowledgePending { get; set; }
        
        // Timing
        public float Srt { get; set; }
        public float T1v { get; set; }
        
        public bool RadioChannelBusy { get; set; }
        
        // Timer T1
        public double T1Exp { get; set; }
        public double T1PausedAt { get; set; }
        public float T1RemainingWhenLastStopped { get; set; } = -999;
        public bool T1HadExpired { get; set; }
        
        // Timer T3
        public double T3Exp { get; set; }
        
        // Statistics
        public int[] CountRecvFrameType { get; set; } = new int[20];
        public int PeakRcValue { get; set; }
        
        // Transmit/Receive queues
        public CData IFrameQueue { get; set; }
        public CData[] TxdataByNs { get; set; } = new CData[128];
        public int Magic3 { get; set; } = Ax25LinkConstants.MAGIC3;
        public CData[] RxdataByNs { get; set; } = new CData[128];
        public int Magic2 { get; set; } = Ax25LinkConstants.MAGIC2;
        
        // MDL state machine for XID exchange
        public MdlState MdlState { get; set; }
        public int MdlRc { get; set; }
        public double Tm201Exp { get; set; }
        public double Tm201PausedAt { get; set; }
        
        // Segment reassembler
        public CData RaBuff { get; set; }
        public int RaFollowing { get; set; }
    }
    
    // Placeholder for misc config
    public class MiscConfig
    {
        public double Frack { get; set; } = 3.0;
        public int Paclen { get; set; } = 256;
        public int MaxframeBasic { get; set; } = 4;
        public int MaxframeExtended { get; set; } = 32;
        public int Retry { get; set; } = 10;
        public int Maxv22 { get; set; } = 3;
        public List<string> V20Addrs { get; set; } = new List<string>();
        public int V20Count => V20Addrs.Count;
        public List<string> NoxidAddrs { get; set; } = new List<string>();
        public int NoxidCount => NoxidAddrs.Count;
    }
    
    // Main Ax25Link class
    public class Ax25Link
    {
        private static Ax25Dlsm _listHead = null;
        private static RegCallsign _regCallsignList = null;
        private static int _nextStreamId = 0;
        
        // Debug switches
        private static bool _sDebugProtocolErrors = false;
        private static bool _sDebugClientApp = false;
        private static bool _sDebugRadio = false;
        private static bool _sDebugVariables = false;
        private static bool _sDebugRetry = false;
        private static bool _sDebugTimers = false;
        private static bool _sDebugLinkHandle = false;
        private static bool _sDebugStats = false;
        private static bool _sDebugMisc = false;
        
        // Configuration
        private static MiscConfig _gMiscConfigP;
        
        // DCD and PTT status per channel
        private static bool[] _dcdStatus = new bool[16];
        private static bool[] _pttStatus = new bool[16];
        
        // Initialize the ax25_link module
        public static void Ax25LinkInit(MiscConfig pconfig, int debug)
        {
            _gMiscConfigP = pconfig;
            
            if (debug >= 1)
            {
                _sDebugProtocolErrors = true;
                _sDebugClientApp = true;
                _sDebugRadio = true;
                _sDebugVariables = true;
                _sDebugRetry = true;
                _sDebugLinkHandle = true;
                _sDebugStats = true;
                _sDebugMisc = true;
                _sDebugTimers = true;
            }
        }
        
        // ============================================================================
        // HELPER FUNCTIONS
        // ============================================================================
        
        // Modulo arithmetic helper
        private static int Ax25Modulo(int n, int m, string file, string func, int line)
        {
            if (m != 8 && m != 128)
            {
                Console.WriteLine($"INTERNAL ERROR: {n} modulo {m}, {file}, {func}, {line}");
                m = 8;
            }
            // Use masking so negative numbers are handled properly
            return n & (m - 1);
        }
        
        // Test whether we can send more frames (within window size)
        private static bool WithinWindowSize(Ax25Dlsm s)
        {
            return s.Vs != Ax25Modulo(s.Va + s.KMaxframe, s.Modulo, nameof(Ax25Link), nameof(WithinWindowSize), 0);
        }
        
        // Get current time in seconds (floating point)
        private static double GetTime()
        {
            return DateTime.UtcNow.Subtract(new DateTime(1970, 1, 1)).TotalSeconds;
        }
        
        // Set variables with debug output
        private static void SetVs(Ax25Dlsm s, int n)
        {
            s.Vs = n;
            if (_sDebugVariables)
            {
                Console.WriteLine($"V(S) = {s.Vs}");
            }
            Debug.Assert(s.Vs >= 0 && s.Vs < s.Modulo);
        }
        
        private static void SetVa(Ax25Dlsm s, int n)
        {
            s.Va = n;
            if (_sDebugVariables)
            {
                Console.WriteLine($"V(A) = {s.Va}");
            }
            Debug.Assert(s.Va >= 0 && s.Va < s.Modulo);
            
            // Clear out acknowledged frames
            int x = Ax25Modulo(n - 1, s.Modulo, nameof(Ax25Link), nameof(SetVa), 0);
            while (s.TxdataByNs[x] != null)
            {
                s.TxdataByNs[x] = null;
                x = Ax25Modulo(x - 1, s.Modulo, nameof(Ax25Link), nameof(SetVa), 0);
            }
        }
        
        private static void SetVr(Ax25Dlsm s, int n)
        {
            s.Vr = n;
            if (_sDebugVariables)
            {
                Console.WriteLine($"V(R) = {s.Vr}");
            }
            Debug.Assert(s.Vr >= 0 && s.Vr < s.Modulo);
        }
        
        private static void SetRc(Ax25Dlsm s, int n)
        {
            s.Rc = n;
            if (_sDebugVariables)
            {
                Console.WriteLine($"rc = {s.Rc}, state = {s.State}");
            }
        }
        
        // Enter new state
        private static void EnterNewState(Ax25Dlsm s, DlsmState newState, string fromFunc, int fromLine)
        {
            if (_sDebugVariables)
            {
                Console.WriteLine($"\n>>> NEW STATE = {newState}, previously {s.State}, called from {fromFunc} {fromLine} <<<\n");
            }
            
            Debug.Assert((int)newState >= 0 && (int)newState <= 5);
            
            // Handle connected indicator
            if ((newState == DlsmState.Connected || newState == DlsmState.TimerRecovery) &&
                (s.State != DlsmState.Connected && s.State != DlsmState.TimerRecovery))
            {
                // Turn on connected indicator
            }
            else if ((newState != DlsmState.Connected && newState != DlsmState.TimerRecovery) &&
                     (s.State == DlsmState.Connected || s.State == DlsmState.TimerRecovery))
            {
                // Turn off connected indicator
            }
            
            s.State = newState;
        }
        
        // Initialize T1V and SRT
        private static void InitT1vSrt(Ax25Dlsm s)
        {
            s.T1v = (float)(_gMiscConfigP.Frack * (2 * (s.NumAddr - 2) + 1));
            s.Srt = s.T1v / 2.0f;
        }
        
        // ============================================================================
        // TIMER FUNCTIONS
        // ============================================================================
        
        // Start T1 timer
        private static void StartT1(Ax25Dlsm s, string fromFunc, int fromLine)
        {
            double now = GetTime();
            
            if (_sDebugTimers)
            {
                Console.WriteLine($"Start T1 for t1v = {s.T1v:F3} sec, rc = {s.Rc}, [now={now - s.StartTime:F3}] from {fromFunc} {fromLine}");
            }
            
            s.T1Exp = now + s.T1v;
            if (s.RadioChannelBusy)
            {
                s.T1PausedAt = now;
            }
            else
            {
                s.T1PausedAt = 0;
            }
            s.T1HadExpired = false;
        }
        
        // Stop T1 timer
        private static void StopT1(Ax25Dlsm s, string fromFunc, int fromLine)
        {
            double now = GetTime();
            
            ResumeT1(s, fromFunc, fromLine); // Adjust expire time if paused
            
            if (s.T1Exp == 0.0)
            {
                // Was already stopped
            }
            else
            {
                s.T1RemainingWhenLastStopped = (float)(s.T1Exp - now);
                if (s.T1RemainingWhenLastStopped < 0) s.T1RemainingWhenLastStopped = 0;
            }
            
            if (_sDebugTimers)
            {
                if (s.T1Exp == 0.0)
                {
                    Console.WriteLine($"Stop T1. Wasn't running, [now={now - s.StartTime:F3}] from {fromFunc} {fromLine}");
                }
                else
                {
                    Console.WriteLine($"Stop T1, {s.T1RemainingWhenLastStopped:F3} remaining, [now={now - s.StartTime:F3}] from {fromFunc} {fromLine}");
                }
            }
            
            s.T1Exp = 0.0;
            s.T1HadExpired = false;
        }
        
        // Check if T1 is running
        private static bool IsT1Running(Ax25Dlsm s, string fromFunc, int fromLine)
        {
            bool result = s.T1Exp != 0.0;
            
            if (_sDebugTimers)
            {
                Console.WriteLine($"is_t1_running? returns {result}");
            }
            
            return result;
        }
        
        // Pause T1 timer
        private static void PauseT1(Ax25Dlsm s, string fromFunc, int fromLine)
        {
            if (s.T1Exp == 0.0)
            {
                // Stopped so nothing to do
            }
            else if (s.T1PausedAt == 0.0)
            {
                // Running and not paused
                double now = GetTime();
                s.T1PausedAt = now;
                
                if (_sDebugTimers)
                {
                    Console.WriteLine($"Paused T1 with {s.T1Exp - now:F3} still remaining, [now={now - s.StartTime:F3}] from {fromFunc} {fromLine}");
                }
            }
            else
            {
                if (_sDebugTimers)
                {
                    Console.WriteLine("T1 error: Didn't expect pause when already paused.");
                }
            }
        }
        
        // Resume T1 timer
        private static void ResumeT1(Ax25Dlsm s, string fromFunc, int fromLine)
        {
            if (s.T1Exp == 0.0)
            {
                // Stopped so nothing to do
            }
            else if (s.T1PausedAt == 0.0)
            {
                // Running but not paused
            }
            else
            {
                double now = GetTime();
                double pausedForSec = now - s.T1PausedAt;
                
                s.T1Exp += pausedForSec;
                s.T1PausedAt = 0.0;
                
                if (_sDebugTimers)
                {
                    Console.WriteLine($"Resumed T1 after pausing for {pausedForSec:F3} sec, {s.T1Exp - now:F3} still remaining, [now={now - s.StartTime:F3}]");
                }
            }
        }
        
        // Start T3 timer
        private static void StartT3(Ax25Dlsm s, string fromFunc, int fromLine)
        {
            double now = GetTime();
            
            if (_sDebugTimers)
            {
                Console.WriteLine($"Start T3 for {Ax25LinkConstants.T3_DEFAULT:F3} sec, [now={now - s.StartTime:F3}] from {fromFunc} {fromLine}");
            }
            
            s.T3Exp = now + Ax25LinkConstants.T3_DEFAULT;
        }
        
        // Stop T3 timer
        private static void StopT3(Ax25Dlsm s, string fromFunc, int fromLine)
        {
            if (_sDebugTimers)
            {
                double now = GetTime();
                
                if (s.T3Exp == 0.0)
                {
                    Console.WriteLine("Stop T3. Wasn't running.");
                }
                else
                {
                    Console.WriteLine($"Stop T3, {s.T3Exp - now:F3} remaining, [now={now - s.StartTime:F3}] from {fromFunc} {fromLine}");
                }
            }
            s.T3Exp = 0.0;
        }
        
        // Start TM201 timer
        private static void StartTm201(Ax25Dlsm s, string fromFunc, int fromLine)
        {
            double now = GetTime();
            
            if (_sDebugTimers)
            {
                Console.WriteLine($"Start TM201 for t1v = {s.T1v:F3} sec, rc = {s.Rc}, [now={now - s.StartTime:F3}] from {fromFunc} {fromLine}");
            }
            
            s.Tm201Exp = now + s.T1v;
            if (s.RadioChannelBusy)
            {
                s.Tm201PausedAt = now;
            }
            else
            {
                s.Tm201PausedAt = 0;
            }
        }
        
        // Stop TM201 timer
        private static void StopTm201(Ax25Dlsm s, string fromFunc, int fromLine)
        {
            double now = GetTime();
            
            if (_sDebugTimers)
            {
                Console.WriteLine($"Stop TM201. [now={now - s.StartTime:F3}] from {fromFunc} {fromLine}");
            }
            
            s.Tm201Exp = 0.0;
        }
        
        // Pause TM201 timer
        private static void PauseTm201(Ax25Dlsm s, string fromFunc, int fromLine)
        {
            if (s.Tm201Exp == 0.0)
            {
                // Stopped so nothing to do
            }
            else if (s.Tm201PausedAt == 0.0)
            {
                // Running and not paused
                double now = GetTime();
                s.Tm201PausedAt = now;
                
                if (_sDebugTimers)
                {
                    Console.WriteLine($"Paused TM201 with {s.Tm201Exp - now:F3} still remaining, [now={now - s.StartTime:F3}] from {fromFunc} {fromLine}");
                }
            }
            else
            {
                if (_sDebugTimers)
                {
                    Console.WriteLine("TM201 error: Didn't expect pause when already paused.");
                }
            }
        }
        
        // Resume TM201 timer
        private static void ResumeTm201(Ax25Dlsm s, string fromFunc, int fromLine)
        {
            if (s.Tm201Exp == 0.0)
            {
                // Stopped so nothing to do
            }
            else if (s.Tm201PausedAt == 0.0)
            {
                // Running but not paused
            }
            else
            {
                double now = GetTime();
                double pausedForSec = now - s.Tm201PausedAt;
                
                s.Tm201Exp += pausedForSec;
                s.Tm201PausedAt = 0.0;
                
                if (_sDebugTimers)
                {
                    Console.WriteLine($"Resumed TM201 after pausing for {pausedForSec:F3} sec, {s.Tm201Exp - now:F3} still remaining, [now={now - s.StartTime:F3}]");
                }
            }
        }
        
        // ============================================================================
        // TIMER EXPIRY FUNCTIONS
        // ============================================================================
        
        // Timer expiry check
        public static void DlTimerExpiry()
        {
            double now = GetTime();
            
            // Process T1 expiry
            Ax25Dlsm p = _listHead;
            while (p != null)
            {
                var pNext = p.Next;
                if (p.T1Exp != 0 && p.T1PausedAt == 0 && p.T1Exp <= now)
                {
                    p.T1Exp = 0;
                    p.T1PausedAt = 0;
                    p.T1HadExpired = true;
                    T1Expiry(p);
                }
                p = pNext;
            }
            
            // Process T3 expiry
            p = _listHead;
            while (p != null)
            {
                var pNext = p.Next;
                if (p.T3Exp != 0 && p.T3Exp <= now)
                {
                    p.T3Exp = 0;
                    T3Expiry(p);
                }
                p = pNext;
            }
            
            // Process TM201 expiry
            p = _listHead;
            while (p != null)
            {
                var pNext = p.Next;
                if (p.Tm201Exp != 0 && p.Tm201PausedAt == 0 && p.Tm201Exp <= now)
                {
                    p.Tm201Exp = 0;
                    p.Tm201PausedAt = 0;
                    Tm201Expiry(p);
                }
                p = pNext;
            }
        }
        
        // T1 timer expiry
        private static void T1Expiry(Ax25Dlsm s)
        {
            if (_sDebugTimers)
            {
                double now = GetTime();
                Console.WriteLine($"t1_expiry(), [now={now - s.StartTime:F3}], state={s.State}, rc={s.Rc}");
            }
            
            switch (s.State)
            {
                case DlsmState.Disconnected:
                    // Ignore it
                    break;
                    
                case DlsmState.AwaitingConnection:
                case DlsmState.AwaitingV22Connection:
                    // MAXV22 hack for compatibility
                    if (s.State == DlsmState.AwaitingV22Connection && s.Rc == _gMiscConfigP.Maxv22)
                    {
                        SetVersion20(s);
                        EnterNewState(s, DlsmState.AwaitingConnection, nameof(T1Expiry), 0);
                    }
                    
                    if (s.Rc == s.N2Retry)
                    {
                        DiscardIQueue(s);
                        Console.WriteLine($"Failed to connect to {s.Addrs[Ax25Dlsm.PEERCALL]} after {s.N2Retry} tries.");
                        // server_link_terminated would be called here
                        EnterNewState(s, DlsmState.Disconnected, nameof(T1Expiry), 0);
                        DlConnectionTerminated(s);
                    }
                    else
                    {
                        SetRc(s, s.Rc + 1);
                        if (s.Rc > s.PeakRcValue) s.PeakRcValue = s.Rc;
                        
                        // Would send SABME or SABM here
                        SelectT1Value(s);
                        StartT1(s, nameof(T1Expiry), 0);
                    }
                    break;
                    
                case DlsmState.AwaitingRelease:
                    if (s.Rc == s.N2Retry)
                    {
                        Console.WriteLine($"Stream {s.StreamId}: Disconnected from {s.Addrs[Ax25Dlsm.PEERCALL]}.");
                        // server_link_terminated would be called here
                        EnterNewState(s, DlsmState.Disconnected, nameof(T1Expiry), 0);
                        DlConnectionTerminated(s);
                    }
                    else
                    {
                        SetRc(s, s.Rc + 1);
                        if (s.Rc > s.PeakRcValue) s.PeakRcValue = s.Rc;
                        
                        // Would send DISC here
                        SelectT1Value(s);
                        StartT1(s, nameof(T1Expiry), 0);
                    }
                    break;
                    
                case DlsmState.Connected:
                    SetRc(s, 1);
                    TransmitEnquiry(s);
                    EnterNewState(s, DlsmState.TimerRecovery, nameof(T1Expiry), 0);
                    break;
                    
                case DlsmState.TimerRecovery:
                    if (s.Rc == s.N2Retry)
                    {
                        if (s.Va != s.Vs)
                        {
                            if (_sDebugProtocolErrors)
                            {
                                Console.WriteLine($"Stream {s.StreamId}: AX.25 Protocol Error I: {s.N2Retry} timeouts: unacknowledged sent data.");
                            }
                        }
                        else if (s.PeerReceiverBusy)
                        {
                            if (_sDebugProtocolErrors)
                            {
                                Console.WriteLine($"Stream {s.StreamId}: AX.25 Protocol Error U: {s.N2Retry} timeouts: extended peer busy condition.");
                            }
                        }
                        else
                        {
                            if (_sDebugProtocolErrors)
                            {
                                Console.WriteLine($"Stream {s.StreamId}: AX.25 Protocol Error T: {s.N2Retry} timeouts: no response to enquiry.");
                            }
                        }
                        
                        Console.WriteLine($"Stream {s.StreamId}: Disconnected from {s.Addrs[Ax25Dlsm.PEERCALL]} due to timeouts.");
                        // server_link_terminated would be called here
                        
                        DiscardIQueue(s);
                        
                        // Would send DM here
                        
                        EnterNewState(s, DlsmState.Disconnected, nameof(T1Expiry), 0);
                        DlConnectionTerminated(s);
                    }
                    else
                    {
                        SetRc(s, s.Rc + 1);
                        if (s.Rc > s.PeakRcValue) s.PeakRcValue = s.Rc;
                        
                        TransmitEnquiry(s);
                    }
                    break;
            }
        }
        
        // T3 timer expiry
        private static void T3Expiry(Ax25Dlsm s)
        {
            if (_sDebugTimers)
            {
                double now = GetTime();
                Console.WriteLine($"t3_expiry(), [now={now - s.StartTime:F3}]");
            }
            
            switch (s.State)
            {
                case DlsmState.Disconnected:
                case DlsmState.AwaitingConnection:
                case DlsmState.AwaitingV22Connection:
                case DlsmState.AwaitingRelease:
                case DlsmState.TimerRecovery:
                    break;
                    
                case DlsmState.Connected:
                    SetRc(s, 1);
                    TransmitEnquiry(s);
                    EnterNewState(s, DlsmState.TimerRecovery, nameof(T3Expiry), 0);
                    break;
            }
        }
        
        // TM201 timer expiry
        private static void Tm201Expiry(Ax25Dlsm s)
        {
            if (_sDebugTimers)
            {
                double now = GetTime();
                Console.WriteLine($"tm201_expiry(), [now={now - s.StartTime:F3}], state={s.State}, rc={s.Rc}");
            }
            
            switch (s.MdlState)
            {
                case MdlState.Ready:
                    // Timer shouldn't be running
                    break;
                    
                case MdlState.Negotiating:
                    s.MdlRc++;
                    if (s.MdlRc > s.N2Retry)
                    {
                        Console.WriteLine($"Stream {s.StreamId}: AX.25 Protocol Error MDL-C: Management retry limit exceeded.");
                        s.MdlState = MdlState.Ready;
                    }
                    else
                    {
                        // Would send XID command again here
                        StartTm201(s, nameof(Tm201Expiry), 0);
                    }
                    break;
            }
        }
        
        // Get next timer expiry time
        public static double Ax25LinkGetNextTimerExpiry()
        {
            double tnext = 0;
            
            for (var p = _listHead; p != null; p = p.Next)
            {
                // Consider if running and not paused
                if (p.T1Exp != 0 && p.T1PausedAt == 0)
                {
                    if (tnext == 0 || p.T1Exp < tnext)
                    {
                        tnext = p.T1Exp;
                    }
                }
                
                if (p.T3Exp != 0)
                {
                    if (tnext == 0 || p.T3Exp < tnext)
                    {
                        tnext = p.T3Exp;
                    }
                }
                
                if (p.Tm201Exp != 0 && p.Tm201PausedAt == 0)
                {
                    if (tnext == 0 || p.Tm201Exp < tnext)
                    {
                        tnext = p.Tm201Exp;
                    }
                }
            }
            
            return tnext;
        }
        
        // ============================================================================
        // LINK MANAGEMENT FUNCTIONS
        // ============================================================================
        
        // Get or create link handle
        private static Ax25Dlsm GetLinkHandle(string[] addrs, int numAddr, int chan, int client, bool create)
        {
            if (_sDebugLinkHandle)
            {
                Console.WriteLine($"get_link_handle ({addrs[0]}>{addrs[1]}, chan={chan}, client={client}, create={create})");
            }
            
            // Look for existing
            if (client == -1)  // from the radio
            {
                for (var p = _listHead; p != null; p = p.Next)
                {
                    if (p.Chan == chan &&
                        string.Equals(addrs[1], p.Addrs[Ax25Dlsm.OWNCALL], StringComparison.OrdinalIgnoreCase) &&
                        string.Equals(addrs[0], p.Addrs[Ax25Dlsm.PEERCALL], StringComparison.OrdinalIgnoreCase))
                    {
                        if (_sDebugLinkHandle)
                        {
                            Console.WriteLine($"get_link_handle returns existing stream id {p.StreamId} for incoming.");
                        }
                        return p;
                    }
                }
            }
            else  // from client app
            {
                for (var p = _listHead; p != null; p = p.Next)
                {
                    if (p.Chan == chan &&
                        p.Client == client &&
                        string.Equals(addrs[0], p.Addrs[Ax25Dlsm.OWNCALL], StringComparison.OrdinalIgnoreCase) &&
                        string.Equals(addrs[1], p.Addrs[Ax25Dlsm.PEERCALL], StringComparison.OrdinalIgnoreCase))
                    {
                        if (_sDebugLinkHandle)
                        {
                            Console.WriteLine($"get_link_handle returns existing stream id {p.StreamId} for outgoing.");
                        }
                        return p;
                    }
                }
            }
            
            // Could not find existing
            if (!create)
            {
                if (_sDebugLinkHandle)
                {
                    Console.WriteLine("get_link_handle: Search failed. Do not create new.");
                }
                return null;
            }
            
            // Check registered callsigns if from radio
            int incomingForClient = -1;
            if (client == -1)
            {
                RegCallsign found = null;
                for (var r = _regCallsignList; r != null && found == null; r = r.Next)
                {
                    if (string.Equals(addrs[1], r.Callsign, StringComparison.OrdinalIgnoreCase) && chan == r.Chan)
                    {
                        found = r;
                        incomingForClient = r.Client;
                    }
                }
                
                if (found == null)
                {
                    if (_sDebugLinkHandle)
                    {
                        Console.WriteLine("get_link_handle: not for me. Ignore it.");
                    }
                    return null;
                }
            }
            
            // Create new data link state machine
            var newS = new Ax25Dlsm
            {
                Magic1 = Ax25LinkConstants.MAGIC1,
                StartTime = GetTime(),
                StreamId = _nextStreamId++,
                Modulo = 8,
                Chan = chan,
                NumAddr = numAddr,
                State = DlsmState.Disconnected,
                T1RemainingWhenLastStopped = -999,
                Magic2 = Ax25LinkConstants.MAGIC2,
                Magic3 = Ax25LinkConstants.MAGIC3
            };
            
            // Set addresses
            if (incomingForClient >= 0)
            {
                // Swap source/destination and reverse digi path for incoming
                newS.Addrs[0] = addrs[1];
                newS.Addrs[1] = addrs[0];
                
                int j = 2;
                int k = numAddr - 1;
                while (k >= 2)
                {
                    newS.Addrs[j] = addrs[k];
                    j++;
                    k--;
                }
                
                newS.Client = incomingForClient;
            }
            else
            {
                Array.Copy(addrs, newS.Addrs, numAddr);
                newS.Client = client;
            }
            
            // Add to linked list
            newS.Next = _listHead;
            _listHead = newS;
            
            if (_sDebugLinkHandle)
            {
                Console.WriteLine($"get_link_handle returns NEW stream id {newS.StreamId}");
            }
            
            return newS;
        }
        
        // Connection cleanup
        private static void DlConnectionCleanup(Ax25Dlsm s)
        {
            if (_sDebugStats)
            {
                Console.WriteLine($"{s.CountRecvFrameType[0]} I frames received");
                Console.WriteLine($"{s.PeakRcValue} peak retry count");
            }
            
            if (_sDebugClientApp)
            {
                Console.WriteLine($"dl_connection_cleanup: remove {s.Addrs[0]}>{s.Addrs[1]}");
            }
            
            DiscardIQueue(s);
            
            for (int n = 0; n < 128; n++)
            {
                if (s.TxdataByNs[n] != null)
                {
                    s.TxdataByNs[n] = null;
                }
            }
            
            for (int n = 0; n < 128; n++)
            {
                if (s.RxdataByNs[n] != null)
                {
                    s.RxdataByNs[n] = null;
                }
            }
            
            if (s.RaBuff != null)
            {
                s.RaBuff = null;
            }
            
            EnterNewState(s, DlsmState.Disconnected, nameof(DlConnectionCleanup), 0);
            
            s.Magic1 = 0;
            s.Magic2 = 0;
            s.Magic3 = 0;
        }
        
        // Connection terminated
        private static void DlConnectionTerminated(Ax25Dlsm s)
        {
            Debug.Assert(s.Magic1 == Ax25LinkConstants.MAGIC1);
            Debug.Assert(s.Magic2 == Ax25LinkConstants.MAGIC2);
            Debug.Assert(s.Magic3 == Ax25LinkConstants.MAGIC3);
            
            // Remove from list
            Ax25Dlsm dlprev = null;
            Ax25Dlsm dlentry = _listHead;
            while (dlentry != s)
            {
                dlprev = dlentry;
                dlentry = dlentry.Next;
            }
            
            if (dlprev == null)
            {
                _listHead = dlentry.Next;
            }
            else
            {
                dlprev.Next = dlentry.Next;
            }
            
            DlConnectionCleanup(s);
        }
        
        // ============================================================================
        // UTILITY FUNCTIONS
        // ============================================================================
        
        // Discard I frame queue
        private static void DiscardIQueue(Ax25Dlsm s)
        {
            while (s.IFrameQueue != null)
            {
                var t = s.IFrameQueue;
                s.IFrameQueue = s.IFrameQueue.Next;
            }
        }
        
        // Clear exception conditions
        private static void ClearExceptionConditions(Ax25Dlsm s)
        {
            s.PeerReceiverBusy = false;
            s.RejectException = false;
            s.OwnReceiverBusy = false;
            s.AcknowledgePending = false;
            
            // Clear out of sequence incoming I frames
            for (int n = 0; n < 128; n++)
            {
                if (s.RxdataByNs[n] != null)
                {
                    s.RxdataByNs[n] = null;
                }
            }
        }
        
        // Establish data link
        private static void EstablishDataLink(Ax25Dlsm s)
        {
            ClearExceptionConditions(s);
            SetRc(s, 1);
            
            // Would send SABME or SABM here
            
            StopT3(s, nameof(EstablishDataLink), 0);
            StartT1(s, nameof(EstablishDataLink), 0);
        }
        
        // Set version 2.0
        private static void SetVersion20(Ax25Dlsm s)
        {
            s.SrejEnable = SrejEnable.None;
            s.Modulo = 8;
            s.N1Paclen = _gMiscConfigP.Paclen;
            s.KMaxframe = _gMiscConfigP.MaxframeBasic;
            s.N2Retry = _gMiscConfigP.Retry;
        }
        
        // Set version 2.2
        private static void SetVersion22(Ax25Dlsm s)
        {
            s.SrejEnable = SrejEnable.Single;
            s.Modulo = 128;
            s.N1Paclen = _gMiscConfigP.Paclen;
            s.KMaxframe = _gMiscConfigP.MaxframeExtended;
            s.N2Retry = _gMiscConfigP.Retry;
        }
        
        // Transmit enquiry
        private static void TransmitEnquiry(Ax25Dlsm s)
        {
            if (_sDebugRetry)
            {
                Console.WriteLine($"\n****** TRANSMIT ENQUIRY RR/RNR cmd P=1 ****** state={s.State}, rc={s.Rc}\n");
            }
            
            // Would send RR or RNR command with P=1 here
            
            s.AcknowledgePending = false;
            StartT1(s, nameof(TransmitEnquiry), 0);
        }
        
        // Select T1 value
        private static void SelectT1Value(Ax25Dlsm s)
        {
            float oldSrt = s.Srt;
            
            if (s.Rc == 0)
            {
                if (s.T1RemainingWhenLastStopped >= 0)
                {
                    s.Srt = 7.0f / 8.0f * s.Srt + 1.0f / 8.0f * (s.T1v - s.T1RemainingWhenLastStopped);
                }
                
                if (s.Srt < 1)
                {
                    s.Srt = 1;
                    if (s.NumAddr > 2)
                    {
                        s.Srt += 2 * (s.NumAddr - 2);
                    }
                }
                
                s.T1v = s.Srt * 2;
            }
            else
            {
                if (s.T1HadExpired)
                {
                    s.T1v = s.Rc * 0.25f + s.Srt * 2;
                }
            }
            
            if (_sDebugTimers)
            {
                Console.WriteLine($"Stream {s.StreamId}: select_t1_value, rc = {s.Rc}, t1 remaining = {s.T1RemainingWhenLastStopped:F3}, old srt = {oldSrt:F3}, new srt = {s.Srt:F3}, new t1v = {s.T1v:F3}");
            }
            
            // Guardrails
            float maxT1v = (float)(2 * (_gMiscConfigP.Frack * (2 * (s.NumAddr - 2) + 1)));
            if (s.T1v < 0.25f || s.T1v > maxT1v)
            {
                InitT1vSrt(s);
            }
        }
        
        // Is good N(R)?
        private static bool IsGoodNr(Ax25Dlsm s, int nr)
        {
            int adjustedVa = Ax25Modulo(s.Va - s.Va, s.Modulo, nameof(Ax25Link), nameof(IsGoodNr), 0);
            int adjustedNr = Ax25Modulo(nr - s.Va, s.Modulo, nameof(Ax25Link), nameof(IsGoodNr), 0);
            int adjustedVs = Ax25Modulo(s.Vs - s.Va, s.Modulo, nameof(Ax25Link), nameof(IsGoodNr), 0);
            
            bool result = adjustedVa <= adjustedNr && adjustedNr <= adjustedVs;
            
            if (_sDebugMisc)
            {
                Console.WriteLine($"is_good_nr, V(a) {s.Va} <= nr {nr} <= V(s) {s.Vs}, returns {result}");
            }
            
            return result;
        }
        
        // Check if we can send I frames (pop from queue)
        private static void IFramePopOffQueue(Ax25Dlsm s)
        {
            if (s.IFrameQueue == null)
            {
                return;
            }
            
            switch (s.State)
            {
                case DlsmState.AwaitingConnection:
                case DlsmState.AwaitingV22Connection:
                    if (s.LayerThreeInitiated)
                    {
                        var txdata = s.IFrameQueue;
                        s.IFrameQueue = txdata.Next;
                        // Discard it
                    }
                    break;
                    
                case DlsmState.Connected:
                case DlsmState.TimerRecovery:
                    while (!s.PeerReceiverBusy &&
                           s.IFrameQueue != null &&
                           WithinWindowSize(s))
                    {
                        var txdata = s.IFrameQueue;
                        s.IFrameQueue = txdata.Next;
                        txdata.Next = null;
                        
                        // Would construct and send I frame here
                        // For now, store in sent array
                        int ns = s.Vs;
                        if (s.TxdataByNs[ns] != null)
                        {
                            s.TxdataByNs[ns] = null;
                        }
                        s.TxdataByNs[ns] = txdata;
                        
                        SetVs(s, Ax25Modulo(s.Vs + 1, s.Modulo, nameof(Ax25Link), nameof(IFramePopOffQueue), 0));
                        s.AcknowledgePending = false;
                        
                        StopT3(s, nameof(IFramePopOffQueue), 0);
                        StartT1(s, nameof(IFramePopOffQueue), 0);
                    }
                    break;
                    
                case DlsmState.Disconnected:
                case DlsmState.AwaitingRelease:
                    break;
            }
        }
        
        // Public API functions that would be called from the data link queue
        
        public static void DlConnectRequest(string[] addrs, int numAddr, int chan, int client)
        {
            var s = GetLinkHandle(addrs, numAddr, chan, client, true);
            
            switch (s.State)
            {
                case DlsmState.Disconnected:
                    InitT1vSrt(s);
                    
                    // Check if this is a v2.0 only station
                    bool oldVersion = false;
                    for (int n = 0; n < _gMiscConfigP.V20Count && !oldVersion; n++)
                    {
                        if (string.Equals(addrs[1], _gMiscConfigP.V20Addrs[n], StringComparison.OrdinalIgnoreCase))
                        {
                            oldVersion = true;
                        }
                    }
                    
                    if (oldVersion || _gMiscConfigP.Maxv22 == 0)
                    {
                        SetVersion20(s);
                        EstablishDataLink(s);
                        s.LayerThreeInitiated = true;
                        EnterNewState(s, DlsmState.AwaitingConnection, nameof(DlConnectRequest), 0);
                    }
                    else
                    {
                        SetVersion22(s);
                        EstablishDataLink(s);
                        s.LayerThreeInitiated = true;
                        EnterNewState(s, DlsmState.AwaitingV22Connection, nameof(DlConnectRequest), 0);
                    }
                    break;
                    
                case DlsmState.AwaitingConnection:
                case DlsmState.AwaitingV22Connection:
                    DiscardIQueue(s);
                    s.LayerThreeInitiated = true;
                    break;
                    
                case DlsmState.AwaitingRelease:
                    break;
                    
                case DlsmState.Connected:
                case DlsmState.TimerRecovery:
                    DiscardIQueue(s);
                    EstablishDataLink(s);
                    s.LayerThreeInitiated = true;
                    EnterNewState(s, s.Modulo == 128 ? DlsmState.AwaitingV22Connection : DlsmState.AwaitingConnection, nameof(DlConnectRequest), 0);
                    break;
            }
        }
        
        public static void DlDisconnectRequest(string[] addrs, int numAddr, int chan, int client)
        {
            var s = GetLinkHandle(addrs, numAddr, chan, client, true);
            
            switch (s.State)
            {
                case DlsmState.Disconnected:
                    Console.WriteLine($"Stream {s.StreamId}: Disconnected from {s.Addrs[Ax25Dlsm.PEERCALL]}.");
                    EnterNewState(s, DlsmState.Disconnected, nameof(DlDisconnectRequest), 0);
                    DlConnectionTerminated(s);
                    break;
                    
                case DlsmState.AwaitingConnection:
                case DlsmState.AwaitingV22Connection:
                    Console.WriteLine($"Stream {s.StreamId}: In progress connection attempt to {s.Addrs[Ax25Dlsm.PEERCALL]} terminated by user.");
                    DiscardIQueue(s);
                    SetRc(s, 0);
                    // Would send DISC here
                    StopT1(s, nameof(DlDisconnectRequest), 0);
                    StopT3(s, nameof(DlDisconnectRequest), 0);
                    EnterNewState(s, DlsmState.Disconnected, nameof(DlDisconnectRequest), 0);
                    DlConnectionTerminated(s);
                    break;
                    
                case DlsmState.AwaitingRelease:
                    // Would send DM expedited here
                    Console.WriteLine($"Stream {s.StreamId}: Disconnected from {s.Addrs[Ax25Dlsm.PEERCALL]}.");
                    StopT1(s, nameof(DlDisconnectRequest), 0);
                    EnterNewState(s, DlsmState.Disconnected, nameof(DlDisconnectRequest), 0);
                    DlConnectionTerminated(s);
                    break;
                    
                case DlsmState.Connected:
                case DlsmState.TimerRecovery:
                    DiscardIQueue(s);
                    SetRc(s, 0);
                    // Would send DISC here
                    StopT3(s, nameof(DlDisconnectRequest), 0);
                    StartT1(s, nameof(DlDisconnectRequest), 0);
                    EnterNewState(s, DlsmState.AwaitingRelease, nameof(DlDisconnectRequest), 0);
                    break;
            }
        }
        
        public static void DlDataRequest(string[] addrs, int numAddr, int chan, int client, CData txdata)
        {
            var s = GetLinkHandle(addrs, numAddr, chan, client, true);
            
            // Handle segmentation if data is too large
            if (txdata.Len > s.N1Paclen)
            {
                // Segmentation logic would go here
                // For now, split into max-size chunks
                int offset = 0;
                int remaining = txdata.Len;
                
                while (remaining > 0)
                {
                    int thisLen = Math.Min(remaining, s.N1Paclen);
                    
                    // Create a slice of the data array
                    byte[] dataSlice = new byte[thisLen];
                    Array.Copy(txdata.Data, offset, dataSlice, 0, thisLen);
                    
                    var newTxdata = new CData(txdata.Pid, dataSlice, thisLen);
                    DataRequestGoodSize(s, newTxdata);
                    offset += thisLen;
                    remaining -= thisLen;
                }
                return;
            }
            
            DataRequestGoodSize(s, txdata);
        }
        
        private static void DataRequestGoodSize(Ax25Dlsm s, CData txdata)
        {
            switch (s.State)
            {
                case DlsmState.Disconnected:
                case DlsmState.AwaitingRelease:
                    // Discard it
                    break;
                    
                case DlsmState.AwaitingConnection:
                case DlsmState.AwaitingV22Connection:
                    if (!s.LayerThreeInitiated)
                    {
                        goto case DlsmState.Connected;
                    }
                    break;
                    
                case DlsmState.Connected:
                case DlsmState.TimerRecovery:
                    // Append to queue
                    if (s.IFrameQueue == null)
                    {
                        txdata.Next = null;
                        s.IFrameQueue = txdata;
                    }
                    else
                    {
                        var plast = s.IFrameQueue;
                        while (plast.Next != null)
                        {
                            plast = plast.Next;
                        }
                        txdata.Next = null;
                        plast.Next = txdata;
                    }
                    break;
            }
            
            // Kick off transmission if conditions are right
            if ((s.State == DlsmState.Connected || s.State == DlsmState.TimerRecovery) &&
                !s.PeerReceiverBusy &&
                WithinWindowSize(s))
            {
                s.AcknowledgePending = true;
                // Would call lm_seize_request here
            }
        }
        
        public static void DlRegisterCallsign(string callsign, int chan, int client)
        {
            if (_sDebugClientApp)
            {
                Console.WriteLine($"dl_register_callsign ({callsign}, chan={chan}, client={client})");
            }
            
            var r = new RegCallsign
            {
                Callsign = callsign,
                Chan = chan,
                Client = client,
                Next = _regCallsignList,
                Magic = Ax25LinkConstants.RC_MAGIC
            };
            
            _regCallsignList = r;
        }
        
        public static void DlUnregisterCallsign(string callsign, int chan, int client)
        {
            if (_sDebugClientApp)
            {
                Console.WriteLine($"dl_unregister_callsign ({callsign}, chan={chan}, client={client})");
            }
            
            RegCallsign prev = null;
            RegCallsign r = _regCallsignList;
            
            while (r != null)
            {
                Debug.Assert(r.Magic == Ax25LinkConstants.RC_MAGIC);
                
                if (string.Equals(r.Callsign, callsign, StringComparison.OrdinalIgnoreCase) &&
                    r.Chan == chan &&
                    r.Client == client)
                {
                    if (r == _regCallsignList)
                    {
                        _regCallsignList = r.Next;
                        r = _regCallsignList;
                    }
                    else
                    {
                        prev.Next = r.Next;
                        r = prev.Next;
                    }
                }
                else
                {
                    prev = r;
                    r = r.Next;
                }
            }
        }
        
        public static void DlClientCleanup(int client)
        {
            if (_sDebugClientApp)
            {
                Console.WriteLine($"dl_client_cleanup ({client})");
            }
            
            // Clean up state machines for this client
            Ax25Dlsm dlprev = null;
            Ax25Dlsm s = _listHead;
            
            while (s != null)
            {
                Debug.Assert(s.Magic1 == Ax25LinkConstants.MAGIC1);
                Debug.Assert(s.Magic2 == Ax25LinkConstants.MAGIC2);
                Debug.Assert(s.Magic3 == Ax25LinkConstants.MAGIC3);
                
                if (s.Client == client)
                {
                    if (s == _listHead)
                    {
                        _listHead = s.Next;
                        DlConnectionCleanup(s);
                        s = _listHead;
                    }
                    else
                    {
                        dlprev.Next = s.Next;
                        DlConnectionCleanup(s);
                        s = dlprev.Next;
                    }
                }
                else
                {
                    dlprev = s;
                    s = s.Next;
                }
            }
            
            // Clean up registered callsigns for this client
            RegCallsign rcprev = null;
            RegCallsign r = _regCallsignList;
            
            while (r != null)
            {
                Debug.Assert(r.Magic == Ax25LinkConstants.RC_MAGIC);
                
                if (r.Client == client)
                {
                    if (r == _regCallsignList)
                    {
                        _regCallsignList = r.Next;
                        r = _regCallsignList;
                    }
                    else
                    {
                        rcprev.Next = r.Next;
                        r = rcprev.Next;
                    }
                }
                else
                {
                    rcprev = r;
                    r = r.Next;
                }
            }
        }
        
        // ============================================================================
        // ADDITIONAL HELPER FUNCTIONS
        // ============================================================================
        
        // Check I frame acknowledged
        private static void CheckIFrameAckd(Ax25Dlsm s, int nr)
        {
            if (s.PeerReceiverBusy)
            {
                SetVa(s, nr);
                StartT3(s, nameof(CheckIFrameAckd), 0);
                if (!IsT1Running(s, nameof(CheckIFrameAckd), 0))
                {
                    StartT1(s, nameof(CheckIFrameAckd), 0);
                }
            }
            else if (nr == s.Vs)
            {
                SetVa(s, nr);
                StopT1(s, nameof(CheckIFrameAckd), 0);
                StartT3(s, nameof(CheckIFrameAckd), 0);
                SelectT1Value(s);
            }
            else if (nr != s.Va)
            {
                if (_sDebugMisc)
                {
                    Console.WriteLine($"check_i_frame_ackd n(r)={nr}, v(a)={s.Va}, Set v(a) to new value {nr}");
                }
                
                SetVa(s, nr);
                StartT1(s, nameof(CheckIFrameAckd), 0);
            }
        }
        
        // N(R) error recovery
        private static void NrErrorRecovery(Ax25Dlsm s)
        {
            if (_sDebugProtocolErrors)
            {
                Console.WriteLine($"Stream {s.StreamId}: AX.25 Protocol Error J: N(r) sequence error.");
            }
            EstablishDataLink(s);
            s.LayerThreeInitiated = false;
        }
        
        // Enquiry response
        private static void EnquiryResponse(Ax25Dlsm s, int frameType, int f)
        {
            if (_sDebugRetry)
            {
                Console.WriteLine($"\n****** ENQUIRY RESPONSE F={f} ******\n");
            }
            
            // This is simplified - full implementation would check frame type
            // and handle SREJ enabled cases more completely
            
            // Would send RR or RNR response with F bit here
            s.AcknowledgePending = false;
        }
        
        // Check need for response
        private static void CheckNeedForResponse(Ax25Dlsm s, int frameType, bool isCommand, int pf)
        {
            if (isCommand && pf == 1)
            {
                int f = 1;
                EnquiryResponse(s, frameType, f);
            }
            else if (!isCommand && pf == 1)
            {
                if (_sDebugProtocolErrors)
                {
                    Console.WriteLine($"Stream {s.StreamId}: AX.25 Protocol Error A: F=1 received but P=1 not outstanding.");
                }
            }
        }
        
        // Invoke retransmission
        private static void InvokeRetransmission(Ax25Dlsm s, int nrInput)
        {
            int localVs;
            int sentCount = 0;
            
            if (_sDebugMisc)
            {
                Console.WriteLine($"invoke_retransmission(): starting with {nrInput}, state={s.State}, rc={s.Rc}");
            }
            
            if (s.TxdataByNs[nrInput] == null)
            {
                Console.WriteLine($"Internal Error, Can't resend starting with N(S) = {nrInput}. It is not available.");
                return;
            }
            
            localVs = nrInput;
            do
            {
                if (s.TxdataByNs[localVs] != null)
                {
                    if (_sDebugMisc)
                    {
                        Console.WriteLine($"invoke_retransmission(): Resending N(S) = {localVs}");
                    }
                    
                    // Would construct and send I frame here with:
                    // N(S) = localVs
                    // N(R) = s.Vr
                    // P = 0
                    
                    sentCount++;
                }
                else
                {
                    Console.WriteLine($"Internal Error, state={s.State}, need to retransmit N(S) = {localVs} for REJ but it is not available.");
                }
                localVs = Ax25Modulo(localVs + 1, s.Modulo, nameof(Ax25Link), nameof(InvokeRetransmission), 0);
                
            } while (localVs != s.Vs);
            
            if (sentCount == 0)
            {
                Console.WriteLine($"Internal Error, Nothing to retransmit. N(R)={nrInput}");
            }
        }
        
        // Is N(S) in expected window?
        private static bool IsNsInWindow(Ax25Dlsm s, int ns)
        {
            int adjustedVr = Ax25Modulo(s.Vr - s.Vr, s.Modulo, nameof(Ax25Link), nameof(IsNsInWindow), 0);
            int adjustedNs = Ax25Modulo(ns - s.Vr, s.Modulo, nameof(Ax25Link), nameof(IsNsInWindow), 0);
            int adjustedVrpk = Ax25Modulo(s.Vr + Ax25LinkConstants.GENEROUS_K - s.Vr, s.Modulo, nameof(Ax25Link), nameof(IsNsInWindow), 0);
            
            bool result = adjustedVr < adjustedNs && adjustedNs < adjustedVrpk;
            
            if (_sDebugRetry)
            {
                Console.WriteLine($"is_ns_in_window, V(R) {s.Vr} < N(S) {ns} < V(R)+k {s.Vr + Ax25LinkConstants.GENEROUS_K}, returns {result}");
            }
            
            return result;
        }
        
        // Data indication to client
        private static void DlDataIndication(Ax25Dlsm s, int pid, byte[] data, int len)
        {
            // Segment reassembly would be handled here
            // For now, just pass through
            
            if (_sDebugClientApp)
            {
                Console.WriteLine($"call dl_data_indication() N(S)={s.Vr}, data length={len}");
            }
            
            // Would call server_rec_conn_data here to deliver to client application
        }
        
        // ============================================================================
        // CHANNEL BUSY MANAGEMENT
        // ============================================================================
        
        public static void LmChannelBusy(int chan, bool isDcd, bool status)
        {
            Debug.Assert(chan >= 0 && chan < 16);
            
            if (isDcd)
            {
                if (_sDebugRadio)
                {
                    Console.WriteLine($"lm_channel_busy: DCD chan {chan} = {status}");
                }
                _dcdStatus[chan] = status;
            }
            else
            {
                if (_sDebugRadio)
                {
                    Console.WriteLine($"lm_channel_busy: PTT chan {chan} = {status}");
                }
                _pttStatus[chan] = status;
            }
            
            bool busy = _dcdStatus[chan] || _pttStatus[chan];
            
            // Apply to all state machines for this channel
            for (var s = _listHead; s != null; s = s.Next)
            {
                if (chan == s.Chan)
                {
                    if (busy && !s.RadioChannelBusy)
                    {
                        s.RadioChannelBusy = true;
                        PauseT1(s, nameof(LmChannelBusy), 0);
                        PauseTm201(s, nameof(LmChannelBusy), 0);
                    }
                    else if (!busy && s.RadioChannelBusy)
                    {
                        s.RadioChannelBusy = false;
                        ResumeT1(s, nameof(LmChannelBusy), 0);
                        ResumeTm201(s, nameof(LmChannelBusy), 0);
                    }
                }
            }
        }
        
        // ============================================================================
        // SEIZE CONFIRM (Channel Clear for Transmission)
        // ============================================================================
        
        public static void LmSeizeConfirm(int chan)
        {
            Debug.Assert(chan >= 0 && chan < 16);
            
            for (var s = _listHead; s != null; s = s.Next)
            {
                if (chan == s.Chan)
                {
                    switch (s.State)
                    {
                        case DlsmState.Disconnected:
                        case DlsmState.AwaitingConnection:
                        case DlsmState.AwaitingRelease:
                        case DlsmState.AwaitingV22Connection:
                            break;
                            
                        case DlsmState.Connected:
                        case DlsmState.TimerRecovery:
                            // Transmit I frames from queue if conditions allow
                            IFramePopOffQueue(s);
                            
                            // Send RR if needed
                            if (s.AcknowledgePending)
                            {
                                s.AcknowledgePending = false;
                                EnquiryResponse(s, 0, 0); // frame_not_AX25 case
                            }
                            break;
                    }
                }
            }
        }
        
        // ============================================================================
        // FRAME RECEPTION STUBS
        // ============================================================================
        
        // These are simplified versions showing the state machine logic
        // Full implementation would integrate with Ax25Pad for frame parsing
        
        public static void ProcessSabmFrame(Ax25Dlsm s, bool extended, int p)
        {
            switch (s.State)
            {
                case DlsmState.Disconnected:
                    if (extended)
                    {
                        SetVersion22(s);
                    }
                    else
                    {
                        SetVersion20(s);
                    }
                    
                    // Would send UA response here
                    
                    ClearExceptionConditions(s);
                    SetVs(s, 0);
                    SetVa(s, 0);
                    SetVr(s, 0);
                    
                    Console.WriteLine($"Stream {s.StreamId}: Connected to {s.Addrs[Ax25Dlsm.PEERCALL]}. ({(extended ? "v2.2" : "v2.0")})");
                    
                    // Would call server_link_established here
                    
                    InitT1vSrt(s);
                    StartT3(s, nameof(ProcessSabmFrame), 0);
                    SetRc(s, 0);
                    EnterNewState(s, DlsmState.Connected, nameof(ProcessSabmFrame), 0);
                    break;
                    
                case DlsmState.AwaitingConnection:
                    if (extended)
                    {
                        // Would send DM response here
                        EnterNewState(s, DlsmState.AwaitingV22Connection, nameof(ProcessSabmFrame), 0);
                    }
                    else
                    {
                        // Would send UA response here
                        // Stay in state 1
                    }
                    break;
                    
                case DlsmState.AwaitingV22Connection:
                    if (extended)
                    {
                        // Would send UA response here
                        // Stay in state 5
                    }
                    else
                    {
                        // Would send UA response here
                        EnterNewState(s, DlsmState.AwaitingConnection, nameof(ProcessSabmFrame), 0);
                    }
                    break;
                    
                case DlsmState.AwaitingRelease:
                    // Would send DM response here
                    break;
                    
                case DlsmState.Connected:
                case DlsmState.TimerRecovery:
                    // Would send UA response here
                    
                    if (s.State == DlsmState.TimerRecovery)
                    {
                        if (extended)
                        {
                            SetVersion22(s);
                        }
                        else
                        {
                            SetVersion20(s);
                        }
                    }
                    
                    ClearExceptionConditions(s);
                    if (_sDebugProtocolErrors)
                    {
                        Console.WriteLine($"Stream {s.StreamId}: AX.25 Protocol Error F: Data Link reset; i.e. SABM(e) received in state {s.State}.");
                    }
                    
                    if (s.Vs != s.Va)
                    {
                        DiscardIQueue(s);
                        // Would call server_link_established here
                    }
                    
                    StopT1(s, nameof(ProcessSabmFrame), 0);
                    StartT3(s, nameof(ProcessSabmFrame), 0);
                    SetVs(s, 0);
                    SetVa(s, 0);
                    SetVr(s, 0);
                    SetRc(s, 0);
                    EnterNewState(s, DlsmState.Connected, nameof(ProcessSabmFrame), 0);
                    break;
            }
        }
        
        public static void ProcessDiscFrame(Ax25Dlsm s, int p)
        {
            switch (s.State)
            {
                case DlsmState.Disconnected:
                case DlsmState.AwaitingConnection:
                case DlsmState.AwaitingV22Connection:
                    // Would send DM response here
                    break;
                    
                case DlsmState.AwaitingRelease:
                    // Would send UA response (expedited) here
                    break;
                    
                case DlsmState.Connected:
                case DlsmState.TimerRecovery:
                    DiscardIQueue(s);
                    
                    // Would send UA response here
                    
                    Console.WriteLine($"Stream {s.StreamId}: Disconnected from {s.Addrs[Ax25Dlsm.PEERCALL]}.");
                    // Would call server_link_terminated here
                    
                    StopT1(s, nameof(ProcessDiscFrame), 0);
                    StopT3(s, nameof(ProcessDiscFrame), 0);
                    EnterNewState(s, DlsmState.Disconnected, nameof(ProcessDiscFrame), 0);
                    DlConnectionTerminated(s);
                    break;
            }
        }
        
        public static void ProcessUaFrame(Ax25Dlsm s, int f)
        {
            switch (s.State)
            {
                case DlsmState.Disconnected:
                    if (_sDebugProtocolErrors)
                    {
                        Console.WriteLine($"Stream {s.StreamId}: AX.25 Protocol Error C: Unexpected UA in state {s.State}.");
                    }
                    break;
                    
                case DlsmState.AwaitingConnection:
                case DlsmState.AwaitingV22Connection:
                    if (f == 1)
                    {
                        if (s.LayerThreeInitiated)
                        {
                            Console.WriteLine($"Stream {s.StreamId}: Connected to {s.Addrs[Ax25Dlsm.PEERCALL]}. ({(s.State == DlsmState.AwaitingV22Connection ? "v2.2" : "v2.0")})");
                            // Would call server_link_established here (outgoing=true)
                        }
                        else if (s.Vs != s.Va)
                        {
                            InitT1vSrt(s);
                            StartT3(s, nameof(ProcessUaFrame), 0);
                            
                            Console.WriteLine($"Stream {s.StreamId}: Connected to {s.Addrs[Ax25Dlsm.PEERCALL]}. ({(s.State == DlsmState.AwaitingV22Connection ? "v2.2" : "v2.0")})");
                            // Would call server_link_established here
                        }
                        
                        StopT1(s, nameof(ProcessUaFrame), 0);
                        StartT3(s, nameof(ProcessUaFrame), 0);
                        SetVs(s, 0);
                        SetVa(s, 0);
                        SetVr(s, 0);
                        SelectT1Value(s);
                        
                        // Would call mdl_negotiate_request here for v2.2
                        
                        SetRc(s, 0);
                        EnterNewState(s, DlsmState.Connected, nameof(ProcessUaFrame), 0);
                    }
                    else
                    {
                        if (_sDebugProtocolErrors)
                        {
                            Console.WriteLine($"Stream {s.StreamId}: AX.25 Protocol Error D: UA received without F=1 when SABM or DISC was sent P=1.");
                        }
                    }
                    break;
                    
                case DlsmState.AwaitingRelease:
                    if (f == 1)
                    {
                        Console.WriteLine($"Stream {s.StreamId}: Disconnected from {s.Addrs[Ax25Dlsm.PEERCALL]}.");
                        // Would call server_link_terminated here
                        StopT1(s, nameof(ProcessUaFrame), 0);
                        EnterNewState(s, DlsmState.Disconnected, nameof(ProcessUaFrame), 0);
                        DlConnectionTerminated(s);
                    }
                    else
                    {
                        if (_sDebugProtocolErrors)
                        {
                            Console.WriteLine($"Stream {s.StreamId}: AX.25 Protocol Error D: UA received without F=1 when SABM or DISC was sent P=1.");
                        }
                    }
                    break;
                    
                case DlsmState.Connected:
                case DlsmState.TimerRecovery:
                    if (_sDebugProtocolErrors)
                    {
                        Console.WriteLine($"Stream {s.StreamId}: AX.25 Protocol Error C: Unexpected UA in state {s.State}.");
                    }
                    EstablishDataLink(s);
                    s.LayerThreeInitiated = false;
                    EnterNewState(s, s.Modulo == 128 ? DlsmState.AwaitingV22Connection : DlsmState.AwaitingConnection, nameof(ProcessUaFrame), 0);
                    break;
            }
        }
        
        public static void ProcessDmFrame(Ax25Dlsm s, int f)
        {
            switch (s.State)
            {
                case DlsmState.Disconnected:
                    break;
                    
                case DlsmState.AwaitingConnection:
                    if (f == 1)
                    {
                        DiscardIQueue(s);
                        Console.WriteLine($"Stream {s.StreamId}: Disconnected from {s.Addrs[Ax25Dlsm.PEERCALL]}.");
                        // Would call server_link_terminated here
                        StopT1(s, nameof(ProcessDmFrame), 0);
                        EnterNewState(s, DlsmState.Disconnected, nameof(ProcessDmFrame), 0);
                        DlConnectionTerminated(s);
                    }
                    break;
                    
                case DlsmState.AwaitingRelease:
                    if (f == 1)
                    {
                        Console.WriteLine($"Stream {s.StreamId}: Disconnected from {s.Addrs[Ax25Dlsm.PEERCALL]}.");
                        // Would call server_link_terminated here
                        StopT1(s, nameof(ProcessDmFrame), 0);
                        EnterNewState(s, DlsmState.Disconnected, nameof(ProcessDmFrame), 0);
                        DlConnectionTerminated(s);
                    }
                    break;
                    
                case DlsmState.Connected:
                case DlsmState.TimerRecovery:
                    if (_sDebugProtocolErrors)
                    {
                        Console.WriteLine($"Stream {s.StreamId}: AX.25 Protocol Error E: DM received in state {s.State}.");
                    }
                    Console.WriteLine($"Stream {s.StreamId}: Disconnected from {s.Addrs[Ax25Dlsm.PEERCALL]}.");
                    // Would call server_link_terminated here
                    DiscardIQueue(s);
                    StopT1(s, nameof(ProcessDmFrame), 0);
                    StopT3(s, nameof(ProcessDmFrame), 0);
                    EnterNewState(s, DlsmState.Disconnected, nameof(ProcessDmFrame), 0);
                    DlConnectionTerminated(s);
                    break;
                    
                case DlsmState.AwaitingV22Connection:
                    // Compatibility hack for non-compliant stations
                    if (f == 1)
                    {
                        Console.WriteLine($"{s.Addrs[Ax25Dlsm.PEERCALL]} doesn't understand AX.25 v2.2. Trying v2.0 ...");
                        Console.WriteLine($"You can avoid this failed attempt and speed up the");
                        Console.WriteLine($"process by putting \"V20 {s.Addrs[Ax25Dlsm.PEERCALL]}\" in the configuration file.");
                        
                        InitT1vSrt(s);
                        SetVersion20(s);
                        EstablishDataLink(s);
                        s.LayerThreeInitiated = true;
                        EnterNewState(s, DlsmState.AwaitingConnection, nameof(ProcessDmFrame), 0);
                    }
                    break;
            }
        }
        
        public static void ProcessFrmrFrame(Ax25Dlsm s)
        {
            switch (s.State)
            {
                case DlsmState.Disconnected:
                case DlsmState.AwaitingConnection:
                case DlsmState.AwaitingRelease:
                    // Ignore it
                    break;
                    
                case DlsmState.Connected:
                case DlsmState.TimerRecovery:
                    if (_sDebugProtocolErrors)
                    {
                        Console.WriteLine($"Stream {s.StreamId}: AX.25 Protocol Error K: FRMR not expected in state {s.State}.");
                    }
                    SetVersion20(s);
                    EstablishDataLink(s);
                    s.LayerThreeInitiated = false;
                    EnterNewState(s, DlsmState.AwaitingConnection, nameof(ProcessFrmrFrame), 0);
                    break;
                    
                case DlsmState.AwaitingV22Connection:
                    Console.WriteLine($"{s.Addrs[Ax25Dlsm.PEERCALL]} doesn't understand AX.25 v2.2. Trying v2.0 ...");
                    Console.WriteLine($"You can avoid this failed attempt and speed up the");
                    Console.WriteLine($"process by putting \"V20 {s.Addrs[Ax25Dlsm.PEERCALL]}\" in the configuration file.");
                    
                    InitT1vSrt(s);
                    SetVersion20(s);
                    EstablishDataLink(s);
                    s.LayerThreeInitiated = true;
                    EnterNewState(s, DlsmState.AwaitingConnection, nameof(ProcessFrmrFrame), 0);
                    break;
            }
        }
    }
}
