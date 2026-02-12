using System.Drawing;
using System.Windows.Forms;

namespace HTCommander
{
    partial class VoiceControl
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
            this.chatScrollBar = new System.Windows.Forms.VScrollBar();
            this.SuspendLayout();
            // 
            // chatScrollBar
            // 
            this.chatScrollBar.Dock = System.Windows.Forms.DockStyle.Right;
            this.chatScrollBar.LargeChange = 1;
            this.chatScrollBar.Location = new System.Drawing.Point(469, 0);
            this.chatScrollBar.Maximum = 0;
            this.chatScrollBar.Name = "chatScrollBar";
            this.chatScrollBar.Size = new System.Drawing.Size(26, 366);
            this.chatScrollBar.TabIndex = 0;
            this.chatScrollBar.Scroll += new System.Windows.Forms.ScrollEventHandler(this.chatScrollBar_Scroll);
            // 
            // VoiceControl
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.Controls.Add(this.chatScrollBar);
            this.DoubleBuffered = true;
            this.Margin = new System.Windows.Forms.Padding(2);
            this.Name = "VoiceControl";
            this.Size = new System.Drawing.Size(495, 366);
            this.Paint += new System.Windows.Forms.PaintEventHandler(this.VoiceControl_Paint);
            this.Resize += new System.EventHandler(this.VoiceControl_Resize);
            this.ResumeLayout(false);

        }

        #endregion

        private VScrollBar chatScrollBar;
    }
}
