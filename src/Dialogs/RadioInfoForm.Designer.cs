namespace HTCommander
{
    partial class RadioInfoForm
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(RadioInfoForm));
            okButton = new System.Windows.Forms.Button();
            mainListView = new System.Windows.Forms.ListView();
            columnHeader1 = new System.Windows.Forms.ColumnHeader();
            columnHeader2 = new System.Windows.Forms.ColumnHeader();
            radioSelectionComboBox = new System.Windows.Forms.ComboBox();
            SuspendLayout();
            // 
            // okButton
            // 
            okButton.Anchor = System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Right;
            okButton.Location = new System.Drawing.Point(402, 358);
            okButton.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            okButton.Name = "okButton";
            okButton.Size = new System.Drawing.Size(100, 35);
            okButton.TabIndex = 0;
            okButton.Text = "OK";
            okButton.UseVisualStyleBackColor = true;
            okButton.Click += okButton_Click;
            // 
            // mainListView
            // 
            mainListView.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Bottom | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            mainListView.Columns.AddRange(new System.Windows.Forms.ColumnHeader[] { columnHeader1, columnHeader2 });
            mainListView.FullRowSelect = true;
            mainListView.GridLines = true;
            mainListView.HeaderStyle = System.Windows.Forms.ColumnHeaderStyle.None;
            mainListView.Location = new System.Drawing.Point(16, 48);
            mainListView.Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            mainListView.Name = "mainListView";
            mainListView.Size = new System.Drawing.Size(486, 300);
            mainListView.TabIndex = 1;
            mainListView.UseCompatibleStateImageBehavior = false;
            mainListView.View = System.Windows.Forms.View.Details;
            // 
            // columnHeader1
            // 
            columnHeader1.Text = "Name";
            columnHeader1.Width = 160;
            // 
            // columnHeader2
            // 
            columnHeader2.Text = "Value";
            columnHeader2.Width = 250;
            // 
            // radioSelectionComboBox
            // 
            radioSelectionComboBox.Anchor = System.Windows.Forms.AnchorStyles.Top | System.Windows.Forms.AnchorStyles.Left | System.Windows.Forms.AnchorStyles.Right;
            radioSelectionComboBox.DropDownStyle = System.Windows.Forms.ComboBoxStyle.DropDownList;
            radioSelectionComboBox.FormattingEnabled = true;
            radioSelectionComboBox.Location = new System.Drawing.Point(16, 12);
            radioSelectionComboBox.Name = "radioSelectionComboBox";
            radioSelectionComboBox.Size = new System.Drawing.Size(486, 28);
            radioSelectionComboBox.TabIndex = 2;
            // 
            // RadioInfoForm
            // 
            AcceptButton = okButton;
            AutoScaleDimensions = new System.Drawing.SizeF(8F, 20F);
            AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            ClientSize = new System.Drawing.Size(520, 407);
            Controls.Add(radioSelectionComboBox);
            Controls.Add(mainListView);
            Controls.Add(okButton);
            Icon = (System.Drawing.Icon)resources.GetObject("$this.Icon");
            Margin = new System.Windows.Forms.Padding(4, 5, 4, 5);
            Name = "RadioInfoForm";
            StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            Text = "Radio Information";
            Load += RadioInfoForm_Load;
            ResumeLayout(false);

        }

        #endregion

        private System.Windows.Forms.Button okButton;
        private System.Windows.Forms.ListView mainListView;
        private System.Windows.Forms.ColumnHeader columnHeader1;
        private System.Windows.Forms.ColumnHeader columnHeader2;
        private System.Windows.Forms.ComboBox radioSelectionComboBox;
    }
}