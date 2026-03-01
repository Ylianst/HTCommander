namespace HTCommander.Dialogs
{
    partial class GpsDetailsForm
    {
        private System.ComponentModel.IContainer components = null;

        protected override void Dispose(bool disposing)
        {
            if (disposing && (components != null))
            {
                components.Dispose();
            }
            base.Dispose(disposing);
        }

        #region Windows Form Designer generated code

        private void InitializeComponent()
        {
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(GpsDetailsForm));
            closeButton = new System.Windows.Forms.Button();
            groupBox1 = new System.Windows.Forms.GroupBox();
            gpsListView = new System.Windows.Forms.ListView();
            columnName = new System.Windows.Forms.ColumnHeader();
            columnValue = new System.Windows.Forms.ColumnHeader();
            headerLabel = new System.Windows.Forms.Label();
            groupBox1.SuspendLayout();
            SuspendLayout();
            // 
            // closeButton
            // 
            closeButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            closeButton.Location = new System.Drawing.Point(492, 581);
            closeButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            closeButton.Name = "closeButton";
            closeButton.Size = new System.Drawing.Size(100, 35);
            closeButton.TabIndex = 0;
            closeButton.Text = "Close";
            closeButton.UseVisualStyleBackColor = true;
            closeButton.Click += closeButton_Click;
            // 
            // groupBox1
            // 
            groupBox1.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            groupBox1.Controls.Add(gpsListView);
            groupBox1.Location = new System.Drawing.Point(16, 69);
            groupBox1.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            groupBox1.Name = "groupBox1";
            groupBox1.Padding = new System.Windows.Forms.Padding(4, 5, 4, 5);
            groupBox1.Size = new System.Drawing.Size(576, 504);
            groupBox1.TabIndex = 4;
            groupBox1.TabStop = false;
            groupBox1.Text = "GPS Details";
            // 
            // gpsListView
            // 
            gpsListView.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            gpsListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] { columnName, columnValue });
            gpsListView.FullRowSelect = true;
            gpsListView.GridLines = true;
            gpsListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.None;
            gpsListView.Location = new System.Drawing.Point(8, 29);
            gpsListView.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            gpsListView.Name = "gpsListView";
            gpsListView.Size = new System.Drawing.Size(560, 463);
            gpsListView.TabIndex = 1;
            gpsListView.UseCompatibleStateImageBehavior = false;
            gpsListView.View = System.Windows.Forms.View.Details;
            // 
            // columnName
            // 
            columnName.Text = "Field";
            columnName.Width = 150;
            // 
            // columnValue
            // 
            columnValue.Text = "Value";
            columnValue.Width = 230;
            // 
            // headerLabel
            // 
            headerLabel.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            headerLabel.Location = new System.Drawing.Point(16, 14);
            headerLabel.Margin = new System.Windows.Forms.Padding(4, 0, 4, 0);
            headerLabel.Name = "headerLabel";
            headerLabel.Size = new System.Drawing.Size(576, 46);
            headerLabel.TabIndex = 5;
            headerLabel.Text = "Live GPS data received from the serial GPS receiver. Values update automatically as new NMEA sentences arrive.";
            // 
            // GpsDetailsForm
            // 
            AcceptButton = closeButton;
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            ClientSize = new System.Drawing.Size(608, 635);
            Controls.Add(groupBox1);
            Controls.Add(headerLabel);
            Controls.Add(closeButton);
            Icon = (System.Drawing.Icon)resources.GetObject("$this.Icon");
            Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            MinimumSize = new System.Drawing.Size(501, 682);
            Name = "GpsDetailsForm";
            StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            Text = "GPS Details";
            groupBox1.ResumeLayout(false);
            ResumeLayout(false);
        }

        #endregion

        private System.Windows.Forms.Button closeButton;
        private System.Windows.Forms.GroupBox groupBox1;
        private System.Windows.Forms.ListView gpsListView;
        private System.Windows.Forms.ColumnHeader columnName;
        private System.Windows.Forms.ColumnHeader columnValue;
        private System.Windows.Forms.Label headerLabel;
    }
}