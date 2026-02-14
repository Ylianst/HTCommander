/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

namespace HTCommander.Controls
{
    /// <summary>
    /// Interface for tab controls that can be associated with a preferred radio device.
    /// This allows a radio selection control to communicate the currently selected radio
    /// to the tab controls.
    /// </summary>
    public interface IRadioDeviceSelector
    {
        /// <summary>
        /// Gets or sets the preferred radio device ID for this control.
        /// A value of -1 or 0 typically indicates no specific radio is selected.
        /// </summary>
        int PreferredRadioDeviceId { get; set; }
    }
}