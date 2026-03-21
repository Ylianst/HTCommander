using System;
using System.IO;
using ABI.System;
using GameEngine;

namespace Adventurer
{
    public class GameRunner
    {
        private string _GameView;
        private string _GameItems;
        private string _GameMessage;

        public GameRunner()
        {
            Advent.RoomView += Advent_RoomView;
            Advent.GameMessages += Advent_GameMessages;
        }

        public string RunTurn(string gameFilePath, string saveFilePath, string userInput)
        {
            bool ok = false;
            if ((saveFilePath != null) && (File.Exists(saveFilePath))) {
                try
                {
                    Advent.RestoreGame(gameFilePath, saveFilePath);
                    ok = true;
                }
                catch (System.Exception) { }
            }
            if (ok == false) { Advent.LoadGame(gameFilePath); }
            if (userInput != null) { Advent.ProcessText(userInput); }
            string output = BuildOutput();
            if (Advent.ISGameOver) { File.Delete(saveFilePath); } else { Advent.SaveGame(saveFilePath); }
            return output;
        }

        private string BuildOutput()
        {
            string output = "";
            output += _GameView + "\n";
            if (!string.IsNullOrEmpty(_GameItems)) { output += _GameItems + "\n"; }
            if (_GameMessage != null) { output += _GameMessage.TrimEnd() + "\n"; }
            return output;
        }

        private void Advent_RoomView(object sender, Advent.Roomview e)
        {
            _GameView = e.View;
            _GameItems = e.Items;
        }

        private void Advent_GameMessages(object sender, Advent.GameOuput e)
        {
            _GameMessage = e.Refresh ? e.Message : _GameMessage + e.Message;
        }
    }
}