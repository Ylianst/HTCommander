namespace GameEngine
{
    static partial class Advent
    {
        public static string PlayerPrompt = "Tell me what to do: ";

        private static int[] _InventoryLocations = { -1, 255 };

        /// <summary>
        /// Used by all scott adams adventure games. Do not change.
        /// </summary>
        enum _Constants : int
        {
            INVENTORY = -1,
            STORE = 0,
            VERB_TAKE = 10,
            VERB_DROP = 18,
            VERB_GO = 1,
            DARKNESSFLAG = 15,
            LIGHOUTFLAG = 16,
            LIGHTSOURCE = 9
        }


        static readonly string[] _Sysmessages = { "OK\r\n" //0
                , " is a word I don't know...sorry!\r\n" //1
                , "I can't go in that direction\r\n" //2
                , "I'm in a " //3
                , "I can see: " //4
                , "Obvious exits: " //5
                , "Tell me what to do" //6
                , "I don't understand\r\n" //7
                , "I'm carrying too much\r\n" //8
                , "I'm carrying:\r\n" //9
                , "Give me a direction too!\r\n" //10
                , "What?\r\n" //11
                , "Nothing\r\n" //12
                , "I've stored {0} treasures. On a scale of 0 to 100, that rates {1}\r\n" //13
                , "It's beyound my power to do that.\r\n" //14
                , "I don't understand your command.\r\n" //15
                , "I can't see. It is too dark!\r\n" //16
                , "Dangerous to move in the dark!\r\n" //17
                , "I fell down and broke my neck.\r\n" //18
                , "Light has run out!\r\n" //19
                , "Your light is growing dim.\r\n" //20
                , "Nothing taken.\r\n" //21
                , "Nothing dropped.\r\n" //22
                , "none.\r\n" //23
                , "I am dead.\r\n" //24
                , "\r\nThis game is now over\r\n"//25
                , "You have collected all the treasures!\r\n"//26
                };
     
        static readonly string[] directionsLong = {  "North", "South", "East", "West", "Up", "Down" };

                
    }
}
