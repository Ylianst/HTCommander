namespace HTCommander
{
    partial class RadioConnectionForm
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(RadioConnectionForm));
            closeButton = new System.Windows.Forms.Button();
            groupBox2 = new System.Windows.Forms.GroupBox();
            renameButton = new System.Windows.Forms.Button();
            connectButton = new System.Windows.Forms.Button();
            disconnectButton = new System.Windows.Forms.Button();
            radiosListView = new System.Windows.Forms.ListView();
            columnHeader1 = new System.Windows.Forms.ColumnHeader();
            columnHeader2 = new System.Windows.Forms.ColumnHeader();
            pictureBox2 = new System.Windows.Forms.PictureBox();
            label4 = new System.Windows.Forms.Label();
            groupBox2.SuspendLayout();
            ((System.ComponentModel.ISupportInitialize)pictureBox2).BeginInit();
            SuspendLayout();
            // 
            // closeButton
            // 
            closeButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            closeButton.DialogResult = System.Windows.Forms.DialogResult.Cancel;
            closeButton.Location = new System.Drawing.Point(494, 344);
            closeButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            closeButton.Name = "closeButton";
            closeButton.Size = new System.Drawing.Size(100, 35);
            closeButton.TabIndex = 5;
            closeButton.Text = "C&lose";
            closeButton.UseVisualStyleBackColor = true;
            closeButton.Click += closeButton_Click;
            // 
            // groupBox2
            // 
            groupBox2.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            groupBox2.Controls.Add(renameButton);
            groupBox2.Controls.Add(connectButton);
            groupBox2.Controls.Add(disconnectButton);
            groupBox2.Controls.Add(radiosListView);
            groupBox2.Location = new System.Drawing.Point(20, 75);
            groupBox2.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            groupBox2.Name = "groupBox2";
            groupBox2.Padding = new System.Windows.Forms.Padding(4, 5, 4, 5);
            groupBox2.Size = new System.Drawing.Size(574, 261);
            groupBox2.TabIndex = 4;
            groupBox2.TabStop = false;
            groupBox2.Text = "Radios";
            // 
            // renameButton
            // 
            renameButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left;
            renameButton.Enabled = false;
            renameButton.Location = new System.Drawing.Point(224, 216);
            renameButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            renameButton.Name = "renameButton";
            renameButton.Size = new System.Drawing.Size(100, 35);
            renameButton.TabIndex = 4;
            renameButton.Text = "&Rename";
            renameButton.UseVisualStyleBackColor = true;
            // 
            // connectButton
            // 
            connectButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left;
            connectButton.Location = new System.Drawing.Point(8, 216);
            connectButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            connectButton.Name = "connectButton";
            connectButton.Size = new System.Drawing.Size(100, 35);
            connectButton.TabIndex = 2;
            connectButton.Text = "&Connect";
            connectButton.UseVisualStyleBackColor = true;
            // 
            // disconnectButton
            // 
            disconnectButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left;
            disconnectButton.Location = new System.Drawing.Point(116, 216);
            disconnectButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            disconnectButton.Name = "disconnectButton";
            disconnectButton.Size = new System.Drawing.Size(100, 35);
            disconnectButton.TabIndex = 3;
            disconnectButton.Text = "&Disconnect";
            disconnectButton.UseVisualStyleBackColor = true;
            // 
            // radiosListView
            // 
            radiosListView.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            radiosListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] { columnHeader1, columnHeader2 });
            radiosListView.FullRowSelect = true;
            radiosListView.GridLines = true;
            radiosListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.None;
            radiosListView.Location = new System.Drawing.Point(8, 29);
            radiosListView.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            radiosListView.Name = "radiosListView";
            radiosListView.Size = new System.Drawing.Size(557, 177);
            radiosListView.TabIndex = 1;
            radiosListView.UseCompatibleStateImageBehavior = false;
            radiosListView.View = System.Windows.Forms.View.Details;
            radiosListView.SelectedIndexChanged += radiosListView_SelectedIndexChanged;
            radiosListView.MouseDoubleClick += radiosListView_MouseDoubleClick;
            // 
            // columnHeader1
            // 
            columnHeader1.Text = "Name";
            columnHeader1.Width = 150;
            // 
            // columnHeader2
            // 
            columnHeader2.Text = "State";
            columnHeader2.Width = 170;
            // 
            // pictureBox2
            // 
            pictureBox2.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Right;
            pictureBox2.Image = Properties.Resources.Radio;
            pictureBox2.Location = new System.Drawing.Point(549, 14);
            pictureBox2.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            pictureBox2.Name = "pictureBox2";
            pictureBox2.Size = new System.Drawing.Size(45, 52);
            pictureBox2.SizeMode = System.Windows.Forms.PictureBoxSizeMode.Zoom;
            pictureBox2.TabIndex = 6;
            pictureBox2.TabStop = false;
            // 
            // label4
            // 
            label4.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            label4.Location = new System.Drawing.Point(16, 14);
            label4.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            label4.Name = "label4";
            label4.Size = new System.Drawing.Size(525, 52);
            label4.TabIndex = 5;
            label4.Text = "Select radios to connect and disconnect. You can be a power user and connect to multiple radios at the same time.";
            // 
            // RadioConnectionForm
            // 
            AcceptButton = closeButton;
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            CancelButton = closeButton;
            ClientSize = new System.Drawing.Size(610, 398);
            Controls.Add(groupBox2);
            Controls.Add(pictureBox2);
            Controls.Add(label4);
            Controls.Add(closeButton);
            FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedDialog;
            Icon = (System.Drawing.Icon)resources.GetObject("$this.Icon");
            Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            MaximizeBox = false;
            MinimizeBox = false;
            Name = "RadioConnectionForm";
            StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            Text = "Radio Connections";
            Load += RadioSelectorForm_Load;
            groupBox2.ResumeLayout(false);
            ((System.ComponentModel.ISupportInitialize)pictureBox2).EndInit();
            ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.Button closeButton;
        private System.Windows.Forms.GroupBox groupBox2;
        private System.Windows.Forms.ListView radiosListView;
        private System.Windows.Forms.ColumnHeader columnHeader1;
        private System.Windows.Forms.ColumnHeader columnHeader2;
        private System.Windows.Forms.PictureBox pictureBox2;
        private System.Windows.Forms.Label label4;
        private System.Windows.Forms.Button connectButton;
        private System.Windows.Forms.Button disconnectButton;
        private System.Windows.Forms.Button renameButton;
    }
}