using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;

namespace GameEngine
{
    /// <summary>
    /// Game processing goes on in here.
    /// </summary>
    static partial class Advent
    {
        /// <summary>
        /// Process the user input from the game
        /// </summary>
        /// <param name="pWords">User input</param>
        /// <remarks>
        /// Raises the events:
        ///     GameOutput
        /// </remarks>
        public static void ProcessText(string pInput)
        {
            GameData.TurnCounter++;
            SendGameMessages("", true);

            pInput = pInput.Trim();

            string V = null;
            string N = null;
            int? iV = null;
            int? iN = null;

            try
            {
                string[] spl = pInput.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                V = ShrinkWord(spl[0].ToUpper());
                N = ShrinkWord(spl[1].ToUpper());
            }
            catch { }

            if (V != null)
            { 
                if (CompareString(V, "i"))
                    V = GameData.Verbs.First(v => v.StartsWith("INV"));

                if ((iV = SearchWordList(GameData.Verbs, V)) != null)
                {
                    //a verb has been identified
                    if (N != null) 
                        iN = SearchWordList(GameData.Nouns, N);
                }
                else//see if a direction has been entered
                {
                    int temp = 0;
                    if ((temp = IsDirection(V)) > -1) //is direction?
                    {
                        iV = (int)_Constants.VERB_GO;
                        N = V;
                        iN = temp;
                        V = "GO";
                    }
                }
            }

            //start examining the input
            if (iV == null && V == null)
            {
                SendGameMessages(_Sysmessages[11], true); //what
                GameData.PlayerNoun = "";
            }
            else if ( iV == null && V != null)//first word present but not recognised
            {
                SendGameMessages(string.Format("\"{0}\" {1}", V, _Sysmessages[1]), true); //{0} is a word I don't know...sorry!
            }
            else if (
                        (iV == (int)_Constants.VERB_TAKE || iV == (int)_Constants.VERB_DROP)
                        && iN == null)   //take or drop specified with no noun)
            {
                SendGameMessages(_Sysmessages[11], true); //What?
            }
            else if (iV == (int)_Constants.VERB_GO && iN > -1 && iN < 7)    //player is moving
            {

                if (GameData.Rooms[GameData.CurrentRoom].Exits[(int)iN - 1] > 0)
                {
                    //direction being moved in exists
                    //note the subtratcion - north is always 1, remove 1
                    PerformActionEffect(54, GameData.Rooms[GameData.CurrentRoom].Exits[(int)iN - 1], 0);

                    SendGameMessages(
                        IsDark()
                                   ? _Sysmessages[17]    //dangerous to move in dark
                                   : _Sysmessages[0]    //can move
                            , true
                        );
                }
                else
                {
                    //can't go in that direction
                    if (IsDark())
                    {
                        SendGameMessages(_Sysmessages[18], true); // "I fell down and broke my neck.\r\n"
                        PerformActionEffect(63, 0, 0);   //game over
                    }
                    else
                        SendGameMessages(_Sysmessages[2], true);    //I can't go in that direction
                }
            }
            else
                SearchActions((int)iV, iN == null ? 0: (int)iN);//we've exhausted the standard actions, so look for a specific action


            //Check lamp life, provide the lightsource in the the game and lit
            if (CheckCondition(13, (int)_Constants.LIGHTSOURCE) & GameData.LampLife > 0)
                GameData.LampLife--;



            SearchActions(0, 0);

        }

        /// <summary>
        /// Shrink the provided word down to the game's word length
        /// </summary>
        /// <param name="pWord">Word to shrink</param>
        /// <returns>Shrunk word</returns>
        static string ShrinkWord(string pWord)
        {
            return (pWord.Length > GameData.Header.WordLength
                   ? pWord.Substring(0, GameData.Header.WordLength)
                   : pWord)
                   .ToUpper();
        }


        /// <summary>
        /// Is it dark?
        /// </summary>
        /// <returns></returns>
        static bool IsDark()
        {
            return (GameData.BitFlags[(int)_Constants.DARKNESSFLAG] && CheckCondition(12, (int)_Constants.LIGHTSOURCE));
        }

        /// <summary>
        /// Look for direction incuding alisises
        /// </summary>
        /// <param name="pDir"></param>
        /// <returns></returns>
        private static int IsDirection(string pDir)
        {
            //directions are always 1 to 6 in the NOUN list
            int retVal = -1;
            for (int d = 1; d < 7; d++)
            {
                if (GameData.Nouns[d].StartsWith(pDir))
                {
                    retVal = d;
                    break;
                }
            }
            return retVal;
        }

        /// <summary>
        /// Attemp to execute the provided action
        /// </summary>
        /// <param name="pAction"></param>
        /// <returns></returns>
        private static bool ExcecuteAction(GameData.Action pAction)
        {
            if (ActionTest(pAction.Conditions))
            {
                //step through the components
                foreach (int[] act in pAction.Effects.Where(a => a[0] > 0))
                    PerformActionEffect(act[0], act[1], act[2]);

                return true;
            }
            return false;
        }

        /// <summary>
        ///  Examine the enture actions list for entries with a matching verb/noun
        /// </summary>
        /// <param name="pVerb">Int</param>
        /// <param name="pNoun">Int</param>
        private static void SearchActions(int pVerb, int pNoun)
        {

            //determines if we output a message upon completion
            //0 no message, 1 don't understand, 2 beyond my power
            //message used if input is via a user, pVerb > 0
            var msg = pVerb > 0 ? 1 : 0;

            var parentOutcome = false;

            List<GameData.Action> candidates =
                        GameData.Actions.Where(a =>
                            ((pVerb == 0 && a.Verb == pVerb)
                                & (
                                    (pNoun == 0 && (a.Noun == pNoun || a.Noun == 100)   //0 or 100 actions occur automatically
                                    ||
                                    ((_rnd.Next(100) + 1) < a.Noun)     //probabability based action
                                ))
                            )
                            //user entered actions
                            || (pVerb == a.Verb && pNoun == a.Noun)
                            || (pVerb == a.Verb && a.Noun == 0)
                        ).ToList();

            foreach (GameData.Action act in candidates)
            {
                //now attempt to execute
                if (parentOutcome = ExcecuteAction(act))
                {
                    if (act.Children != null)
                        ChildActions(act.Children);
                }

                //do more stuff
                if (GameData.EndGame)
                {
                    PerformActionEffect(64, 0, 0); //look
                    return;
                }

                if (pVerb > 0 && parentOutcome)
                {
                    //this is user input, and the same verb noun combination may be used
                    //under different conditions, so bail if we've successfully processed
                    //user input
                    break;
                }
            }

            //output a can't do that message if we recognise a player verb in the list, but not a noun
            if (pVerb > 0 && !parentOutcome & GameData.Actions.Count(act => act.Verb == pVerb) > 0)
                msg = 2;

            if (pVerb > 0)
            { //only do after user input

                if (!parentOutcome)
                {
                    if (msg == 1) //don't understand
                        SendGameMessages(_Sysmessages[15], true);
                    else if (msg == 2) //Can't do that yet
                        SendGameMessages(_Sysmessages[14], true);
                }
                SearchActions(0, 0); //auto actions
            }

            //lamp stuff, is it in the game
            if (CheckCondition(13, (int)_Constants.LIGHTSOURCE))
            {

                if (GameData.LampLife == 0)
                {
                    GameData.ChangeBitFlag((int)_Constants.LIGHOUTFLAG, true);
                    SendGameMessages(_Sysmessages[19], false);
                    GameData.LampLife = 0;
                }
                else if (GameData.LampLife > 0 && GameData.LampLife < 25 &&
                  CheckCondition(3, (int)_Constants.LIGHTSOURCE) &&
                  GameData.LampLife % 5 == 0)
                    SendGameMessages(_Sysmessages[20], false); //light growing dim
            }

            PerformActionEffect(64, 0, 0); //look
        }

        /// <summary>
        /// recurse through any children
        /// </summary>
        /// <param name="pActions"></param>
        private static void ChildActions(GameData.Action[] pActions)
        {
            foreach (GameData.Action c in pActions)
            {
                ExcecuteAction(c);
                if (c.Children != null)
                    ChildActions(c.Children);
            }
        }

        /// <summary>
        /// Check the provided condition
        /// </summary>
        /// <param name="pCon">Condition</param>
        /// <param name="pArg">Argument</param>
        /// <returns>Condition met</returns>
        private static bool CheckCondition(int pCon, int pArg)
        {
            bool retVal = false;

            switch (pCon)
            {
                case 1: //item carried
                    retVal = _InventoryLocations.Contains(GameData.Items[pArg].Location);
                    break;

                case 2: //item in room with player
                    retVal = GameData.Items[pArg].Location == GameData.CurrentRoom;
                    break;

                case 3: //item carried or in room with player
                    retVal = CheckCondition(1, pArg) || CheckCondition(2, pArg);
                    break;

                case 4: //player in room X
                    retVal = GameData.CurrentRoom == pArg;
                    break;

                case 5: //item not in room with player
                    retVal = GameData.Items[pArg].Location != GameData.CurrentRoom;
                    break;

                case 6: //item not carried
                    retVal = !_InventoryLocations.Contains(GameData.Items[pArg].Location);
                    break;

                case 7: //player not it room
                    retVal = GameData.CurrentRoom != pArg;
                    break;

                case 8: //bitflag X is set
                    retVal = GameData.BitFlags[pArg] == true;
                    break;

                case 9: //bitflag X is false
                    retVal = GameData.BitFlags[pArg] != true;
                    break;

                case 10: //something carried
                    return GameData.Items.Count(i => _InventoryLocations.Contains(i.Location) == true) > 0;

                case 11: //nothing carried
                    return GameData.Items.Count(i => _InventoryLocations.Contains(i.Location) == true) == 0;

                case 12: //item not carried or in room with player
                    retVal = CheckCondition(6, pArg) & CheckCondition(5, pArg);
                    break;

                case 13: //item in game
                    retVal = (GameData.Items[pArg].Location != (int)_Constants.STORE);
                    break;

                case 14: //item not in game
                    retVal = GameData.Items[pArg].Location == (int)_Constants.STORE;
                    break;

                case 15: //current counter less than arg
                    retVal = GameData.CurrentCounter <= pArg;
                    break;

                case 16: //current counter greater than arg
                    retVal = GameData.CurrentCounter > pArg;
                    break;

                case 17: //object in initial location
                    retVal = GameData.Items[pArg].Moved() == false;
                    break;

                case 18: //object not in initial location
                    retVal = GameData.Items[pArg].Moved() == true;
                    break;

                case 19: //current counter equals
                    retVal = GameData.CurrentCounter == pArg;
                    break;
            }

            return retVal;
        }



        /// <summary>
        /// Search the provided word list
        /// </summary>
        /// <param name="pWordList">Arry to search</param>
        /// <param name="pWord">word to search</param>
        /// <returns>null not present, else index of match</returns>
        private static int? SearchWordList(string[] pWordList, string pWord)
        {
            pWord = ShrinkWord(pWord);

            //value of the length of the array indicates no match, 0 the first match etc
            int retVal = pWordList.TakeWhile(
                    w => !(w.StartsWith("*") ? w.Substring(1) : w)
                            .Equals(pWord, StringComparison.OrdinalIgnoreCase)//remove aliase marker                            
                                                                              //reduce to word length
                ).Count();

            if (retVal == pWordList.Count())
                return null;
            else if (pWordList[retVal].StartsWith("*"))//alias located
            {
                do
                {   //reverse up the list until the first none star
                    retVal--;
                } while (pWordList[retVal].StartsWith("*"));
            }

            return retVal;
        }

        /// <summary>
        /// Perform string comparison
        /// </summary>
        /// <param name="a"></param>
        /// <param name="b"></param>
        /// <returns></returns>
        private static bool CompareString(string a, string b)
        {
            return a.Equals(b, StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Perform the provded action effect
        /// </summary>
        /// <param name="pEffectID">Effect</param>
        /// <param name="pArg1">Action argument 1</param>
        /// <param name="pArg2">Action argument 1</param>
        private static void PerformActionEffect(int pEffectID, int pArg1, int pArg2)
        {

            if (pEffectID < 52 || pEffectID > 101)
            {
                SendGameMessages(GameData.Messages[pEffectID - (pEffectID > 101 ? 50 : 0)], false);
                PerformActionEffect(86, 0, 0);//carriage return
            }
            else
            {
                switch (pEffectID)
                {

                    case 52: //get item, check if can carry
                        GameData.TakeSuccessful = false;
                        if (GetItemsAt(_InventoryLocations).Count() < GameData.Header.MaxCarry)
                        {
                            GameData.Items[pArg1].Location = (int)_Constants.INVENTORY;
                            GameData.TakeSuccessful = true;
                        }
                        else
                            SendGameMessages(_Sysmessages[8], true);
                        break;

                    case 53: //drops item into current room
                        GameData.ChangeItemLocation(pArg1, GameData.CurrentRoom);
                        break;

                    case 54: //move room
                        GameData.CurrentRoom = pArg1;
                        PerformActionEffect(64, 0, 0);
                        break;

                    case 55: //Item <arg> is removed from the game (put in room 0)
                    case 59:
                        GameData.ChangeItemLocation(pArg1, (int)_Constants.STORE);
                        break;

                    case 56: //set darkness flag
                        GameData.ChangeBitFlag((int)_Constants.DARKNESSFLAG, true);
                        break;

                    case 57: //clear darkness flag
                        GameData.ChangeBitFlag((int)_Constants.DARKNESSFLAG, false);
                        break;

                    case 58: //set pArg1 flag
                        GameData.ChangeBitFlag(pArg1, true);
                        break;

                    case 60: //set pArg1 flag
                        GameData.ChangeBitFlag(pArg1, false);
                        break;

                    case 61: //Death, clear dark flag, move to last room NOT GAME OVER, move to limbo room
                        PerformActionEffect(57, 0, 0);
                        GameData.CurrentRoom = GameData.Rooms.Count() - 1;
                        SendGameMessages(_Sysmessages[24], false);
                        SendGameOver();
                        break;

                    case 62: //item is moved to room
                        GameData.ChangeItemLocation(pArg1, pArg2);
                        break;

                    case 63: //game over
                        GameData.EndGame = true;
                        SendGameMessages(_Sysmessages[25], false);
                        SendGameOver();
                        break;

                    case 64: //look
                    case 76:

                        if (GameData.BitFlags[(int)_Constants.DARKNESSFLAG] && CheckCondition(12, (int)_Constants.LIGHTSOURCE))
                            _RoomView = _Sysmessages[16];
                        else
                        {

                            string roomitems = String.Join(", ", GameData.Items.Where(i => i.Location == GameData.CurrentRoom)
                                                .Select(i => i.Description)
                                                .ToArray()
                                                );

                            _RoomItems = roomitems == "" ? "" : _Sysmessages[4] + roomitems;

                            string desc = GameData.Rooms[GameData.CurrentRoom].Description;

                            _RoomView =
                                (
                                    (desc.StartsWith("*")
                                    ? desc = desc.Substring(1)
                                    : _Sysmessages[3] + desc)
                                );


                        }

                        SetRoomView();

                        break;

                    case 65: //score
                        int storedItems = GameData.Items.Count(i => i.Location == GameData.Header.TreasureRoom
                                && i.Description.StartsWith("*"));

                        SendGameMessages(string.Format(
                                            _Sysmessages[13]
                                            , storedItems
                                            , Math.Floor((storedItems * 1.0 / GameData.Header.TotalTreasures) * 100)), false);

                        if (storedItems == GameData.Header.TotalTreasures)
                        {
                            SendGameMessages(_Sysmessages[26], true);
                            PerformActionEffect(63, 0, 0);
                        }

                        break;

                    case 66: // output inventory

                        string[] items = GetItemsAt(_InventoryLocations)
                                        .Select(i => i.Description)
                                        .ToArray();

                        SendGameMessages(_Sysmessages[9] +
                                        (items.GetLength(0) == 0
                                        ? _Sysmessages[12]
                                        : String.Join(", ", items)), false);

                        PerformActionEffect(86, 0, 0);
                        PerformActionEffect(86, 0, 0);

                        break;

                    case 67:
                        GameData.ChangeBitFlag(0, true);
                        break;

                    case 68:
                        GameData.ChangeBitFlag(0, false);
                        break;

                    case 69: //refill lamp
                        GameData.LampLife = GameData.Header.LightDuration;
                        GameData.ChangeBitFlag((int)_Constants.LIGHOUTFLAG, false);
                        GameData.ChangeItemLocation((int)_Constants.LIGHTSOURCE, (int)_Constants.INVENTORY);
                        break;

                    case 70: //clear screen
                        SendGameMessages("", true);
                        _RoomView = null;
                        break;

                    case 71: //save game                        
                        //SaveGame();
                        break;

                    case 72: // swap item locations
                        int loc = GameData.Items[pArg1].Location;
                        GameData.ChangeItemLocation(pArg1, GameData.Items[pArg2].Location);
                        GameData.ChangeItemLocation(pArg2, loc);
                        break;

                    case 73: //continue with next action
                        break;

                    case 74: //take item, no check done to see if can carry
                        GameData.ChangeItemLocation(pArg1, (int)_Constants.INVENTORY);
                        break;

                    case 75: //put item 1 with item2
                        GameData.ChangeItemLocation(pArg1, GameData.Items[pArg2].Location);
                        break;

                    case 77: //decement current counter
                        if (GameData.CurrentCounter > 0)
                            GameData.CurrentCounter--;
                        break;

                    case 78: //output current counter
                        SendGameMessages(GameData.CurrentCounter + Environment.NewLine, false);
                        break;

                    case 79: //set current counter value
                        GameData.CurrentCounter = pArg1;
                        break;

                    case 80: //swap location with saved location
                        int j = GameData.CurrentRoom;
                        GameData.CurrentRoom = GameData.SavedRoom;
                        GameData.SavedRoom = j;
                        break;

                    case 81: //"Select a counter. Current counter is swapped with backup counter @".replace("@", pValue1);
                        int temp = GameData.CurrentCounter;
                        GameData.CurrentCounter = GameData.Counters[pArg1];
                        GameData.ChangeCounter(pArg1, temp);
                        break;

                    case 82: //add to current counter
                        GameData.CurrentCounter += pArg1;
                        break;

                    case 83: //subtract from current counter
                        GameData.CurrentCounter -= pArg1;
                        if (GameData.CurrentCounter < -1)
                            GameData.CurrentCounter = -1;
                        break;

                    case 84: //echo noun without cr
                        SendGameMessages(GameData.PlayerNoun, false);
                        break;

                    case 85: //echo noun
                        SendGameMessages(GameData.PlayerNoun + Environment.NewLine, false);
                        break;

                    case 86: //Carriage Return"
                        SendGameMessages(Environment.NewLine, false);
                        break;

                    case 87: //Swap current location value with backup location-swap value
                        int temp1 = GameData.CurrentRoom;
                        GameData.CurrentRoom = GameData.SavedRooms[pArg1];
                        GameData.SavedRooms[pArg1] = temp1;
                        break;

                    case 88: //wait 2 seconds
                        Thread.Sleep(2000);
                        break;
                }
            }
        }

        /// <summary>
        /// Check the provided conditions
        /// </summary>
        /// <param name="pConds">Condition block</param>
        /// <returns>Have they been met</returns>
        private static bool ActionTest(int[][] pConds)
        {
            foreach (int[] con in pConds.Where(c => c[0] > 0))
            {
                if (!CheckCondition(con[0], con[1]))
                    return false;
            }
            return true;
        }

        /// <summary>
        /// get the items at the specified location
        /// </summary>
        /// <param name="pLocation">RoomID</param>
        /// <returns>Array of items</returns>
        private static GameData.Item[] GetItemsAt(int pLocation)
        {
            return GameData.Items.Where(i => i.Location == pLocation).ToArray();
        }

        /// <summary>
        /// get the items at the specified location
        /// </summary>
        /// <param name="pLocation">RoomID</param>
        /// <returns>Array of items</returns>
        private static GameData.Item[] GetItemsAt(int[] pLocation)
        {
            return GameData.Items.Where(i => pLocation.Contains(i.Location)).ToArray();
        }
    }
}