using System;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace GameEngine
{
    /// <summary>
    /// Load the DAT game file and break it into tokens which can be either numbers or string.
    /// 
    /// The DAT file can contain multiline comments, which will be stripped out.
    /// </summary>
    public static class DATToChunks
    {
        private static string[] tokens = null;

        public static void Load(string pFile)
        {
            var r = new Regex
                            (
                                "([\"][^\"]*?[\"])" //string
                                + "|(/\\*(?:(?!\\*/).)*\\*/)"   //multiline comment
                                + "|(\\d+)" //number
                                , RegexOptions.Singleline
                            );

            tokens = r.Matches(File.ReadAllText(pFile))
                        .Cast<Match>()
                        .Where(m => !m.ToString().StartsWith("/"))//remove the comments
                        .Select(m => m.ToString().Trim(new char[] { '"' }))
                        .ToArray();

            pos = 0;
        }

        private static int pos = 0;

        private static bool EOF { get { return !(pos < tokens.Length); } }

        /// <summary>
        /// Get the required number of DAT chunks as string
        /// </summary>
        /// <param name="pCount">Number of tokens to return</param>
        /// <returns>string array</returns>
        public static string[] getTokens(int pCount)
        {
            string[] retval =
                tokens.Skip(pos).Take(pCount).ToArray();

            pos += pCount;

            return retval;
        }

        /// <summary>
        /// Get the required number of DAT tokens as int
        /// </summary>
        /// <param name="pCount"></param>
        /// <returns></returns>
        public static int[] GetTokensAsInt(int pCount)
        {
            return getTokens(pCount).Select(i => Convert.ToInt32(i)).ToArray();
        }

    }
}
