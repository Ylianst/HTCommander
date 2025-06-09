using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class RadioPositionForm : Form
    {
        private MainForm parent;
        private Radio radio;

        public RadioPositionForm(MainForm parent, Radio radio)
        {
            InitializeComponent();
            this.parent = parent;
            this.radio = radio;
        }

        private void refrashButton_Click(object sender, EventArgs e)
        {
            radio.GetPosition();
        }

        private void closeButton_Click(object sender, EventArgs e)
        {
            parent.radioPositionForm = null;
            Close();
        }
    }
}
