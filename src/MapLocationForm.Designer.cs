namespace HTCommander
{
    partial class MapLocationForm
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
            System.ComponentModel.ComponentResourceManager resources = new System.ComponentModel.ComponentResourceManager(typeof(MapLocationForm));
            this.mapZoomOutButton = new System.Windows.Forms.Button();
            this.mapZoomInbutton = new System.Windows.Forms.Button();
            this.SuspendLayout();
            // 
            // mapZoomOutButton
            // 
            this.mapZoomOutButton.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.mapZoomOutButton.Location = new System.Drawing.Point(12, 52);
            this.mapZoomOutButton.Name = "mapZoomOutButton";
            this.mapZoomOutButton.Size = new System.Drawing.Size(28, 32);
            this.mapZoomOutButton.TabIndex = 7;
            this.mapZoomOutButton.Text = "-";
            this.mapZoomOutButton.UseVisualStyleBackColor = true;
            this.mapZoomOutButton.Click += new System.EventHandler(this.mapZoomOutButton_Click);
            // 
            // mapZoomInbutton
            // 
            this.mapZoomInbutton.Font = new System.Drawing.Font("Microsoft Sans Serif", 15.75F, System.Drawing.FontStyle.Regular, System.Drawing.GraphicsUnit.Point, ((byte)(0)));
            this.mapZoomInbutton.Location = new System.Drawing.Point(12, 12);
            this.mapZoomInbutton.Name = "mapZoomInbutton";
            this.mapZoomInbutton.Size = new System.Drawing.Size(28, 32);
            this.mapZoomInbutton.TabIndex = 6;
            this.mapZoomInbutton.Text = "+";
            this.mapZoomInbutton.UseVisualStyleBackColor = true;
            this.mapZoomInbutton.Click += new System.EventHandler(this.mapZoomInbutton_Click);
            // 
            // MapLocationForm
            // 
            this.AutoScaleDimensions = new System.Drawing.SizeF(6F, 13F);
            this.AutoScaleMode = System.Windows.Forms.AutoScaleMode.Font;
            this.ClientSize = new System.Drawing.Size(383, 315);
            this.Controls.Add(this.mapZoomOutButton);
            this.Controls.Add(this.mapZoomInbutton);
            this.Icon = ((System.Drawing.Icon)(resources.GetObject("$this.Icon")));
            this.Margin = new System.Windows.Forms.Padding(2);
            this.MaximizeBox = false;
            this.MinimizeBox = false;
            this.Name = "MapLocationForm";
            this.StartPosition = System.Windows.Forms.FormStartPosition.CenterParent;
            this.Text = "Location";
            this.FormClosing += new System.Windows.Forms.FormClosingEventHandler(this.MapLocationForm_FormClosing);
            this.ResumeLayout(false);
        }
#endregion

#if !__MonoCS__
        private GMap.NET.WindowsForms.GMapControl mapControl;
#endif
        private System.Windows.Forms.Button mapZoomOutButton;
        private System.Windows.Forms.Button mapZoomInbutton;
    }
}