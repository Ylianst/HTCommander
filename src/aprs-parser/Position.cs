namespace aprsparser
{
    public class Position
    {
        public CoordinateSet CoordinateSet;
        public byte Ambiguity;
        public int Course;
        public int Speed;
        public int Altitude;
        public string Gridsquare;

        public Position()
        {
            CoordinateSet = new CoordinateSet();
        }

        public void Clear()
        {
            CoordinateSet.Clear();
            Ambiguity = 0;
            Course = 0;
            Speed = 0;
            Altitude = 0;
            Gridsquare = string.Empty;
        }

        public bool IsValid()
        {
            return CoordinateSet.IsValid();
        }

    }
}
