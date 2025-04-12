using System;
using System.Runtime.InteropServices;

namespace HTCommander
{
    public static class LibSbc
    {
        private const string DllName = "libsbc.dll"; // Replace with the actual DLL name if different

        // Constants from the header file
        public const int SBC_FREQ_16000 = 0x00;
        public const int SBC_FREQ_32000 = 0x01;
        public const int SBC_FREQ_44100 = 0x02;
        public const int SBC_FREQ_48000 = 0x03;

        public const int SBC_BLK_4 = 0x00;
        public const int SBC_BLK_8 = 0x01;
        public const int SBC_BLK_12 = 0x02;
        public const int SBC_BLK_16 = 0x03;

        public const int SBC_MODE_MONO = 0x00;
        public const int SBC_MODE_DUAL_CHANNEL = 0x01;
        public const int SBC_MODE_STEREO = 0x02;
        public const int SBC_MODE_JOINT_STEREO = 0x03;

        public const int SBC_AM_LOUDNESS = 0x00;
        public const int SBC_AM_SNR = 0x01;

        public const int SBC_SB_4 = 0x00;
        public const int SBC_SB_8 = 0x01;

        public const int SBC_LE = 0x00;
        public const int SBC_BE = 0x01;

        [StructLayout(LayoutKind.Sequential)]
        public struct sbc_struct
        {
            public uint flags;
            public byte frequency;
            public byte blocks;
            public byte subbands;
            public byte mode; // SBC_MODE_MONO
            public byte allocation;
            public byte bitpool;
            public byte endian;
            public IntPtr priv;
            public IntPtr priv_alloc_base;
        }

        public delegate void sbc_t_delegate(ref sbc_struct sbc);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sbc_init(ref sbc_struct sbc, ulong flags);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sbc_reinit(ref sbc_struct sbc, ulong flags);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sbc_init_msbc(ref sbc_struct sbc, ulong flags);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sbc_reinit_msbc(ref sbc_struct sbc, ulong flags);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sbc_init_a2dp(ref sbc_struct sbc, ulong flags,
                                               IntPtr conf, UIntPtr conf_len);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern int sbc_reinit_a2dp(ref sbc_struct sbc, ulong flags,
                                                IntPtr conf, UIntPtr conf_len);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr sbc_parse(ref sbc_struct sbc, IntPtr input, UIntPtr input_len);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr sbc_decode(ref sbc_struct sbc, IntPtr input, UIntPtr input_len,
                                                IntPtr output, UIntPtr output_len, out UIntPtr written);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern IntPtr sbc_encode(ref sbc_struct sbc, IntPtr input, UIntPtr input_len,
                                                IntPtr output, UIntPtr output_len, out IntPtr written);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern UIntPtr sbc_get_frame_length(ref sbc_struct sbc);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern uint sbc_get_frame_duration(ref sbc_struct sbc);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern UIntPtr sbc_get_codesize(ref sbc_struct sbc);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
        [return: MarshalAs(UnmanagedType.LPStr)]
        public static extern string sbc_get_implementation_info(ref sbc_struct sbc);

        [DllImport(DllName, CallingConvention = CallingConvention.Cdecl)]
        public static extern void sbc_finish(ref sbc_struct sbc);
    }
}