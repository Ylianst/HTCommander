using System.Drawing;
using System.Windows.Forms;

namespace HTCommander
{
    partial class ChatControl
    {
        /// <summary> 
        /// Required designer variable.
        /// </summary>
        private System.ComponentModel.IContainer components = null;

        /// <summary> 
        /// Clean up any resources being used.
        /// </summary>
        /// <param name="disposing">true if managed resources should be disposed; otherwise, false.</param>
        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Component Designer generated code

        /// <summary> 
        /// Required method for Designer support - do not modify 
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            chatScrollBar = new VScrollBar();
            SuspendLayout();
            // 
            // chatScrollBar
            // 
            chatScrollBar.Dock = DockStyle.Right;
            chatScrollBar.LargeChange = 1;
            chatScrollBar.Location = new Point(634, 0);
            chatScrollBar.Maximum = 0;
            chatScrollBar.Name = "chatScrollBar";
            chatScrollBar.Size = new Size(26, 563);
            chatScrollBar.TabIndex = 0;
            chatScrollBar.Scroll += chatScrollBar_Scroll;
            // 
            // ChatControl
            // 
            AutoScaleDimensions = new SizeF(8F, 20F);
            AutoScaleMode = AutoScaleMode.Font;
            Controls.Add(chatScrollBar);
            DoubleBuffered = true;
            Name = "ChatControl";
            Size = new Size(660, 563);
            Paint += ChatControl_Paint;
            Resize += ChatControl_Resize;
            ResumeLayout(false);

        }

        #endregion

        private VScrollBar chatScrollBar;
    }
}
