using System;
using System.Windows.Forms;

namespace HTCommander
{
    public partial class CantConnectForm: Form
    {
        public CantConnectForm()
        {
            InitializeComponent();
        }

        private void closeButton_Click(object sender, EventArgs e)
        {
            Close();
        }
    }
}
