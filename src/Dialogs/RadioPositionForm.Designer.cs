namespace HTCommander
{
    partial class RadioPositionForm
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(RadioPositionForm));
            closeButton = new System.Windows.Forms.Button();
            refreshButton = new System.Windows.Forms.Button();
            mainListView = new System.Windows.Forms.ListView();
            columnHeader1 = new System.Windows.Forms.ColumnHeader();
            columnHeader2 = new System.Windows.Forms.ColumnHeader();
            SuspendLayout();
            // 
            // closeButton
            // 
            closeButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            closeButton.Location = new System.Drawing.Point(357, 285);
            closeButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            closeButton.Name = "closeButton";
            closeButton.Size = new System.Drawing.Size(100, 35);
            closeButton.TabIndex = 1;
            closeButton.Text = "Close";
            closeButton.UseVisualStyleBackColor = true;
            closeButton.Click += closeButton_Click;
            // 
            // refreshButton
            // 
            refreshButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            refreshButton.Location = new System.Drawing.Point(249, 285);
            refreshButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            refreshButton.Name = "refreshButton";
            refreshButton.Size = new System.Drawing.Size(100, 35);
            refreshButton.TabIndex = 2;
            refreshButton.Text = "Refresh";
            refreshButton.UseVisualStyleBackColor = true;
            refreshButton.Click += refreshButton_Click;
            // 
            // mainListView
            // 
            mainListView.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            mainListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] { columnHeader1, columnHeader2 });
            mainListView.FullRowSelect = true;
            mainListView.GridLines = true;
            mainListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.None;
            mainListView.Location = new System.Drawing.Point(13, 16);
            mainListView.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mainListView.Name = "mainListView";
            mainListView.Size = new System.Drawing.Size(443, 258);
            mainListView.TabIndex = 2;
            mainListView.UseCompatibleStateImageBehavior = false;
            mainListView.View = System.Windows.Forms.View.Details;
            // 
            // columnHeader1
            // 
            columnHeader1.Text = "Name";
            columnHeader1.Width = 140;
            // 
            // columnHeader2
            // 
            columnHeader2.Text = "Value";
            columnHeader2.Width = 180;
            // 
            // RadioPositionForm
            // 
            AcceptButton = closeButton;
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            ClientSize = new System.Drawing.Size(469, 336);
            Controls.Add(mainListView);
            Controls.Add(refreshButton);
            Controls.Add(closeButton);
            FormBorderStyle = System.Windows.Forms.FormBorderStyle.FixedDialog;
            Icon = (System.Drawing.Icon)resources.GetObject("$this.Icon");
            Margin = new System.Windows.Forms.Padding(3, 4, 3, 4);
            MaximizeBox = false;
            MinimizeBox = false;
            Name = "RadioPositionForm";
            StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            Text = "Radio Position";
            FormClosed += RadioPositionForm_FormClosed;
            ResumeLayout(false);

        }

        #endregion
        private System.Windows.Forms.Button closeButton;
        private System.Windows.Forms.Button refreshButton;
        private System.Windows.Forms.ListView mainListView;
        private System.Windows.Forms.ColumnHeader columnHeader1;
        private System.Windows.Forms.ColumnHeader columnHeader2;
    }
}