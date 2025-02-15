namespace GameEngine
{
    /// <summary>
    /// Load new games and save games
    /// </summary>
    static partial class Advent
    {
        /// <summary>
        /// Load a game
        /// </summary>
        /// <param name="pFile">Game file</param>
        public static void LoadGame(string pFile)
        {
            GameData = GameData.Load(pFile);
            _rnd = new System.Random(GameData.Seed);
            SearchActions(0, 0);
        }

        /// <summary>
        /// Restore a saved game
        /// </summary>
        /// <param name="pAdvGame">Game to load</param>
        /// <param name="pSnapShot">save game data</param>
        public static void RestoreGame(string pAdvGame, string pSnapShot)
        {
            GameData = GameData.LoadSnapShot(pAdvGame, pSnapShot);
            _rnd = new System.Random(GameData.Seed);
            PerformActionEffect(64, 0, 0);//look
        }

        public static void RestoreGame(GameData pData)
        {
            GameData = pData;
            _rnd = new System.Random(GameData.Seed);
            PerformActionEffect(64, 0, 0);//look
        }

        /// <summary>
        /// Save a game
        /// </summary>
        public static void SaveGame(string filename)
        {
            SendGameMessages(string.Format("Game saved: {0}", GameData.SaveSnapshot(filename)), true);
            PerformActionEffect(86, 0, 0);   //carriage return
        }

    }
}