using System;

namespace GameEngine
{
    static partial class Advent
    {
        static int _seed;
        static int Seed
        {
            get
            {
                _seed = DateTime.Now.Millisecond;
                return _seed;
            }
            set => _seed = value;
        }

        static Random _rnd;

        static string _RoomView = null;
        static string _RoomItems = null;

        public static GameData GameData { get; set; } = null;

        static public string GameName => GameData.GameName;
        static public bool ISGameOver => GameData.EndGame;
        static public int TurnCounter => GameData.TurnCounter;

    }
}
