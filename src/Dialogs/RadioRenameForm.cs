using System;
using System.Drawing;
using System.Windows.Forms;

namespace HTCommander.Dialogs
{
    public partial class RadioRenameForm : Form
    {
        private string _placeholderText = "";
        private bool _isPlaceholderActive = false;
        private Color _normalForeColor;

        public string RadioName
        {
            get => _isPlaceholderActive ? "" : radioNameTextBox.Text;
            set
            {
                if (string.IsNullOrEmpty(value))
                {
                    ShowPlaceholder();
                }
                else
                {
                    HidePlaceholder();
                    radioNameTextBox.Text = value;
                }
            }
        }

        public string PlaceholderText
        {
            get => _placeholderText;
            set
            {
                _placeholderText = value;
                // If the textbox is currently empty or showing placeholder, update it
                if (_isPlaceholderActive || string.IsNullOrEmpty(radioNameTextBox.Text))
                {
                    ShowPlaceholder();
                }
            }
        }

        public RadioRenameForm()
        {
            InitializeComponent();
            _normalForeColor = radioNameTextBox.ForeColor;
            
            radioNameTextBox.GotFocus += TextBox1_GotFocus;
            radioNameTextBox.LostFocus += TextBox1_LostFocus;
            
            okButton.Click += OkButton_Click;
            cancelButton.Click += CancelButton_Click;
        }

        private void ShowPlaceholder()
        {
            if (!string.IsNullOrEmpty(_placeholderText))
            {
                _isPlaceholderActive = true;
                radioNameTextBox.Text = _placeholderText;
                radioNameTextBox.ForeColor = Color.Gray;
            }
        }

        private void HidePlaceholder()
        {
            _isPlaceholderActive = false;
            radioNameTextBox.ForeColor = _normalForeColor;
        }

        private void TextBox1_GotFocus(object sender, EventArgs e)
        {
            if (_isPlaceholderActive)
            {
                HidePlaceholder();
                radioNameTextBox.Text = "";
            }
        }

        private void TextBox1_LostFocus(object sender, EventArgs e)
        {
            if (string.IsNullOrEmpty(radioNameTextBox.Text))
            {
                ShowPlaceholder();
            }
        }

        private void OkButton_Click(object sender, EventArgs e)
        {
            DialogResult = DialogResult.OK;
            Close();
        }

        private void CancelButton_Click(object sender, EventArgs e)
        {
            DialogResult = DialogResult.Cancel;
            Close();
        }
    }
}
