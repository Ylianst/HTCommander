/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Windows.Forms;

namespace HTCommander.Dialogs
{
    /// <summary>
    /// A form that can display any UserControl from the TabControls folder in a detached window.
    /// </summary>
    public partial class DetachedTabForm : Form
    {
        private UserControl _control;

        /// <summary>
        /// Creates a new DetachedTabForm with an instance of the specified control type.
        /// </summary>
        /// <typeparam name="T">The type of UserControl to create and display.</typeparam>
        /// <returns>A new DetachedTabForm containing the specified control.</returns>
        public static DetachedTabForm Create<T>() where T : UserControl, new()
        {
            return new DetachedTabForm(typeof(T));
        }

        /// <summary>
        /// Creates a new DetachedTabForm with an instance of the specified control type.
        /// </summary>
        /// <typeparam name="T">The type of UserControl to create and display.</typeparam>
        /// <param name="title">The title for the form window.</param>
        /// <returns>A new DetachedTabForm containing the specified control.</returns>
        public static DetachedTabForm Create<T>(string title) where T : UserControl, new()
        {
            var form = new DetachedTabForm(typeof(T));
            form.Text = title;
            return form;
        }

        /// <summary>
        /// Creates a new DetachedTabForm with the specified existing control instance.
        /// </summary>
        /// <param name="control">The control instance to display.</param>
        /// <returns>A new DetachedTabForm containing the specified control.</returns>
        public static DetachedTabForm Create(UserControl control)
        {
            return new DetachedTabForm(control);
        }

        /// <summary>
        /// Creates a new DetachedTabForm with the specified existing control instance.
        /// </summary>
        /// <param name="control">The control instance to display.</param>
        /// <param name="title">The title for the form window.</param>
        /// <returns>A new DetachedTabForm containing the specified control.</returns>
        public static DetachedTabForm Create(UserControl control, string title)
        {
            var form = new DetachedTabForm(control);
            form.Text = title;
            return form;
        }

        /// <summary>
        /// Default constructor for designer support.
        /// </summary>
        public DetachedTabForm()
        {
            InitializeComponent();
        }

        /// <summary>
        /// Creates a new DetachedTabForm with an instance of the specified control type.
        /// </summary>
        /// <param name="controlType">The type of UserControl to create and display. Must have a parameterless constructor.</param>
        public DetachedTabForm(Type controlType)
        {
            if (controlType == null)
                throw new ArgumentNullException(nameof(controlType));
            if (!typeof(UserControl).IsAssignableFrom(controlType))
                throw new ArgumentException("Type must be a UserControl", nameof(controlType));

            InitializeComponent();

            // Create an instance of the control
            _control = (UserControl)Activator.CreateInstance(controlType);
            _control.Dock = DockStyle.Fill;
            Controls.Add(_control);
        }

        /// <summary>
        /// Creates a new DetachedTabForm with the specified existing control instance.
        /// </summary>
        /// <param name="control">The control instance to display.</param>
        public DetachedTabForm(UserControl control)
        {
            if (control == null)
                throw new ArgumentNullException(nameof(control));

            InitializeComponent();

            _control = control;
            _control.Dock = DockStyle.Fill;
            Controls.Add(_control);
        }

        /// <summary>
        /// Gets the hosted control.
        /// </summary>
        public UserControl HostedControl => _control;

        /// <summary>
        /// Gets the hosted control cast to the specified type.
        /// </summary>
        /// <typeparam name="T">The type to cast the control to.</typeparam>
        /// <returns>The control cast to type T, or null if the cast fails.</returns>
        public T GetHostedControl<T>() where T : UserControl
        {
            return _control as T;
        }
    }
}
