namespace HTCommander
{
    partial class SpectrogramForm
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

        #region Windows Form Designer generated code

        /// <summary>
        /// Required method for Designer support - do not modify
        /// the contents of this method with the code editor.
        /// </summary>
        private void InitializeComponent()
        {
            this.components = new System.ComponentModel.Container();
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(SpectrogramForm));
            this.pbSpectrogram = new System.Windows.Forms.PictureBox();
            this.updateTimer = new System.Windows.Forms.Timer(this.components);
            this.mainMenuStrip = new System.Windows.Forms.MenuStrip();
            this.fileToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.maxFreqencyToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.hzToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.hzToolStripMenuItem1 = new System.Windows.Forms.ToolStripMenuItem();
            this.hzToolStripMenuItem2 = new System.Windows.Forms.ToolStripMenuItem();
            this.scaleToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.rollToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.largeToolStripMenuItem1 = new System.Windows.Forms.ToolStripMenuItem();
            this.toolStripMenuItem1 = new System.Windows.Forms.ToolStripSeparator();
            this.closeToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            this.pbScaleVert = new System.Windows.Forms.PictureBox();
            this.colorsToolStripMenuItem = new System.Windows.Forms.ToolStripMenuItem();
            ((System.ComponentModel.ISupportInitialize)(this.pbSpectrogram)).BeginInit();
            this.mainMenuStrip.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pbScaleVert)).BeginInit();
            this.SuspendLayout();
            // 
            // pbSpectrogram
            // 
            this.pbSpectrogram.BackColor = System.Drawing.Color.Black;
            this.pbSpectrogram.Dock = System.Windows.Forms.DockStyle.Fill;
            this.pbSpectrogram.Location = new System.Drawing.Point(0, 28);
            this.pbSpectrogram.Name = "pbSpectrogram";
            this.pbSpectrogram.Size = new System.Drawing.Size(680, 292);
            this.pbSpectrogram.TabIndex = 0;
            this.pbSpectrogram.TabStop = false;
            // 
            // updateTimer
            // 
            this.updateTimer.Enabled = true;
            this.updateTimer.Tick += new System.EventHandler(this.updateTimer_Tick);
            // 
            // mainMenuStrip
            // 
            this.mainMenuStrip.ImageScalingSize = new System.Drawing.Size(20, 20);
            this.mainMenuStrip.Items.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.fileToolStripMenuItem,
            this.colorsToolStripMenuItem});
            this.mainMenuStrip.Location = new System.Drawing.Point(0, 0);
            this.mainMenuStrip.Name = "mainMenuStrip";
            this.mainMenuStrip.Size = new System.Drawing.Size(817, 28);
            this.mainMenuStrip.TabIndex = 1;
            this.mainMenuStrip.Text = "menuStrip1";
            // 
            // fileToolStripMenuItem
            // 
            this.fileToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.maxFreqencyToolStripMenuItem,
            this.scaleToolStripMenuItem,
            this.rollToolStripMenuItem,
            this.largeToolStripMenuItem1,
            this.toolStripMenuItem1,
            this.closeToolStripMenuItem});
            this.fileToolStripMenuItem.Name = "fileToolStripMenuItem";
            this.fileToolStripMenuItem.Size = new System.Drawing.Size(46, 24);
            this.fileToolStripMenuItem.Text = "&File";
            // 
            // maxFreqencyToolStripMenuItem
            // 
            this.maxFreqencyToolStripMenuItem.DropDownItems.AddRange(new System.Windows.Forms.ToolStripItem[] {
            this.hzToolStripMenuItem,
            this.hzToolStripMenuItem1,
            this.hzToolStripMenuItem2});
            this.maxFreqencyToolStripMenuItem.Name = "maxFreqencyToolStripMenuItem";
            this.maxFreqencyToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            this.maxFreqencyToolStripMenuItem.Text = "Max Freqency";
            // 
            // hzToolStripMenuItem
            // 
            this.hzToolStripMenuItem.Checked = true;
            this.hzToolStripMenuItem.CheckState = System.Windows.Forms.CheckState.Checked;
            this.hzToolStripMenuItem.Name = "hzToolStripMenuItem";
            this.hzToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            this.hzToolStripMenuItem.Text = "16000 Hz";
            this.hzToolStripMenuItem.Click += new System.EventHandler(this.hzToolStripMenuItem_Click);
            // 
            // hzToolStripMenuItem1
            // 
            this.hzToolStripMenuItem1.Name = "hzToolStripMenuItem1";
            this.hzToolStripMenuItem1.Size = new System.Drawing.Size(224, 26);
            this.hzToolStripMenuItem1.Text = "8000 Hz";
            this.hzToolStripMenuItem1.Click += new System.EventHandler(this.hzToolStripMenuItem1_Click);
            // 
            // hzToolStripMenuItem2
            // 
            this.hzToolStripMenuItem2.Name = "hzToolStripMenuItem2";
            this.hzToolStripMenuItem2.Size = new System.Drawing.Size(224, 26);
            this.hzToolStripMenuItem2.Text = "4000 Hz";
            this.hzToolStripMenuItem2.Click += new System.EventHandler(this.hzToolStripMenuItem2_Click);
            // 
            // scaleToolStripMenuItem
            // 
            this.scaleToolStripMenuItem.CheckOnClick = true;
            this.scaleToolStripMenuItem.Name = "scaleToolStripMenuItem";
            this.scaleToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            this.scaleToolStripMenuItem.Text = "&Scale";
            this.scaleToolStripMenuItem.Click += new System.EventHandler(this.scaleToolStripMenuItem_Click);
            // 
            // rollToolStripMenuItem
            // 
            this.rollToolStripMenuItem.CheckOnClick = true;
            this.rollToolStripMenuItem.Name = "rollToolStripMenuItem";
            this.rollToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            this.rollToolStripMenuItem.Text = "&Roll";
            this.rollToolStripMenuItem.Click += new System.EventHandler(this.rollToolStripMenuItem_Click);
            // 
            // largeToolStripMenuItem1
            // 
            this.largeToolStripMenuItem1.CheckOnClick = true;
            this.largeToolStripMenuItem1.Name = "largeToolStripMenuItem1";
            this.largeToolStripMenuItem1.Size = new System.Drawing.Size(224, 26);
            this.largeToolStripMenuItem1.Text = "&Large";
            this.largeToolStripMenuItem1.Click += new System.EventHandler(this.largeToolStripMenuItem1_Click);
            // 
            // toolStripMenuItem1
            // 
            this.toolStripMenuItem1.Name = "toolStripMenuItem1";
            this.toolStripMenuItem1.Size = new System.Drawing.Size(221, 6);
            // 
            // closeToolStripMenuItem
            // 
            this.closeToolStripMenuItem.Name = "closeToolStripMenuItem";
            this.closeToolStripMenuItem.Size = new System.Drawing.Size(224, 26);
            this.closeToolStripMenuItem.Text = "&Close";
            this.closeToolStripMenuItem.Click += new System.EventHandler(this.closeToolStripMenuItem_Click);
            // 
            // pbScaleVert
            // 
            this.pbScaleVert.Dock = System.Windows.Forms.DockStyle.Right;
            this.pbScaleVert.Location = new System.Drawing.Point(680, 28);
            this.pbScaleVert.Name = "pbScaleVert";
            this.pbScaleVert.Size = new System.Drawing.Size(137, 292);
            this.pbScaleVert.TabIndex = 2;
            this.pbScaleVert.TabStop = false;
            this.pbScaleVert.Visible = false;
            // 
            // colorsToolStripMenuItem
            // 
            this.colorsToolStripMenuItem.Name = "colorsToolStripMenuItem";
            this.colorsToolStripMenuItem.Size = new System.Drawing.Size(65, 24);
            this.colorsToolStripMenuItem.Text = "&Colors";
            // 
            // SpectrogramForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(8F, 16F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(817, 320);
            this.Controls.Add(this.pbSpectrogram);
            this.Controls.Add(this.pbScaleVert);
            this.Controls.Add(this.mainMenuStrip);
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.MainMenuStrip = this.mainMenuStrip;
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "SpectrogramForm";
            this.Text = "Spectrogram";
            this.FormClosing += new System.Windows.Forms.FormClosingEventHandler(this.SpectrogramForm_FormClosing);
            this.Load += new System.EventHandler(this.SpectrogramForm_Load);
            ((System.ComponentModel.ISupportInitialize)(this.pbSpectrogram)).EndInit();
            this.mainMenuStrip.ResumeLayout(false);
            this.mainMenuStrip.PerformLayout();
            ((System.ComponentModel.ISupportInitialize)(this.pbScaleVert)).EndInit();
            this.ResumeLayout(false);
            this.PerformLayout();

        }

        #endregion

        private System.Windows.Forms.PictureBox pbSpectrogram;
        private System.Windows.Forms.Timer updateTimer;
        private System.Windows.Forms.MenuStrip mainMenuStrip;
        private System.Windows.Forms.ToolStripMenuItem fileToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem closeToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem largeToolStripMenuItem1;
        private System.Windows.Forms.ToolStripSeparator toolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem rollToolStripMenuItem;
        private System.Windows.Forms.PictureBox pbScaleVert;
        private System.Windows.Forms.ToolStripMenuItem scaleToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem maxFreqencyToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem hzToolStripMenuItem;
        private System.Windows.Forms.ToolStripMenuItem hzToolStripMenuItem1;
        private System.Windows.Forms.ToolStripMenuItem hzToolStripMenuItem2;
        private System.Windows.Forms.ToolStripMenuItem colorsToolStripMenuItem;
    }
}