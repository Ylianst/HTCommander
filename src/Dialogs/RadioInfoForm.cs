/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

using System;
using System.Reflection;
using System.Collections;
using System.Windows.Forms;
using HTCommander.radio;

namespace HTCommander
{
    public partial class RadioInfoForm : Form
    {
        private int deviceId;
        private RadioDevInfo Info;
        private RadioHtStatus HtStatus;
        private RadioSettings Settings;
        private RadioBssSettings BssSettings;
        private RadioPosition Position;
        private DataBrokerClient broker;
        private bool isUpdatingComboBox = false;

        // Helper class for combobox items that stores device information
        private class RadioComboBoxItem
        {
            public int DeviceId { get; set; }
            public string MacAddress { get; set; }
            public string FriendlyName { get; set; }

            public override string ToString()
            {
                if (!string.IsNullOrEmpty(FriendlyName))
                    return $"{FriendlyName} ({MacAddress})";
                return MacAddress;
            }
        }

        // ListViewGroup for device information
        private ListViewGroup groupDeviceInfo;
        private ListViewGroup groupDeviceStatus;
        private ListViewGroup groupDeviceSettings;
        private ListViewGroup groupBssSettings;
        private ListViewGroup groupPosition;

        // ListViewItem references for updating device info values
        private ListViewItem itemProductId;
        private ListViewItem itemVendorId;
        private ListViewItem itemDmrSupport;
        private ListViewItem itemGmrsSupport;
        private ListViewItem itemHwSpeaker;
        private ListViewItem itemHwVersion;
        private ListViewItem itemSwVersion;
        private ListViewItem itemRegionCount;
        private ListViewItem itemMediumPower;
        private ListViewItem itemChannelCount;
        private ListViewItem itemNoaa;
        private ListViewItem itemRadio;
        private ListViewItem itemVfo;
        private ListViewItem itemFreqRangeCount;

        // ListViewItem references for updating device status values
        private ListViewItem itemPowerOn;
        private ListViewItem itemInTx;
        private ListViewItem itemIsSq;
        private ListViewItem itemInRx;
        private ListViewItem itemDoubleChannel;
        private ListViewItem itemScanning;
        private ListViewItem itemRadioStatus;
        private ListViewItem itemCurrentChannelId;
        private ListViewItem itemGpsLocked;
        private ListViewItem itemHfpConnected;
        private ListViewItem itemAocConnected;
        private ListViewItem itemRssi;
        private ListViewItem itemCurrentRegion;

        // ListViewItem references for updating device settings values
        private ListViewItem itemVfoA;
        private ListViewItem itemVfoB;
        private ListViewItem itemScan;
        private ListViewItem itemAghfpCallMode;
        private ListViewItem itemDoubleChannelSetting;
        private ListViewItem itemSquelchLevel;
        private ListViewItem itemTailElim;
        private ListViewItem itemAutoRelayEn;
        private ListViewItem itemAutoPowerOn;
        private ListViewItem itemKeepAghfpLink;
        private ListViewItem itemMicGain;
        private ListViewItem itemTxHoldTime;
        private ListViewItem itemTxTimeLimit;
        private ListViewItem itemLocalSpeaker;
        private ListViewItem itemBtMicGain;
        private ListViewItem itemAdaptiveResponse;
        private ListViewItem itemDisTone;
        private ListViewItem itemPowerSavingMode;
        private ListViewItem itemAutoPowerOff;
        private ListViewItem itemAutoShareLocCh;
        private ListViewItem itemHmSpeaker;
        private ListViewItem itemPositioningSystem;
        private ListViewItem itemTimeOffset;
        private ListViewItem itemUseFreqRange2;
        private ListViewItem itemPttLock;
        private ListViewItem itemLeadingSyncBitEn;
        private ListViewItem itemPairingAtPowerOn;
        private ListViewItem itemScreenTimeout;
        private ListViewItem itemVfoX;
        private ListViewItem itemImperialUnit;
        private ListViewItem itemWxMode;
        private ListViewItem itemNoaaCh;
        private ListViewItem itemVfolTxPowerX;
        private ListViewItem itemVfo2TxPowerX;
        private ListViewItem itemDisDigitalMute;
        private ListViewItem itemSignalingEccEn;
        private ListViewItem itemChDataLock;
        private ListViewItem itemVfo1ModFreqX;
        private ListViewItem itemVfo2ModFreqX;

        // ListViewItem references for updating BSS settings values
        private ListViewItem itemAllowPositionCheck;
        private ListViewItem itemAprsCallsign;
        private ListViewItem itemAprsSymbol;
        private ListViewItem itemBeaconMessage;
        private ListViewItem itemBssUserIdLower;
        private ListViewItem itemLocationShareInterval;
        private ListViewItem itemMaxFwdTimes;
        private ListViewItem itemPacketFormat;
        private ListViewItem itemPttReleaseIdInfo;
        private ListViewItem itemPttReleaseSendBssUserId;
        private ListViewItem itemPttReleaseSendIdInfo;
        private ListViewItem itemPttReleaseSendLocation;
        private ListViewItem itemSendPwrVoltage;
        private ListViewItem itemShouldShareLocation;
        private ListViewItem itemTimeToLive;

        // ListViewItem references for updating position values
        private ListViewItem itemPositionStatus;
        private ListViewItem itemLatitude;
        private ListViewItem itemLongitude;
        private ListViewItem itemAccuracy;
        private ListViewItem itemAltitude;
        private ListViewItem itemSpeed;
        private ListViewItem itemHeading;
        private ListViewItem itemReceivedTime;
        private ListViewItem itemGpsTimeLocal;
        private ListViewItem itemGpsTimeUtc;

        public RadioInfoForm()
        {
            InitializeComponent();
            this.deviceId = -1; // No device selected initially

            // Enable double buffering on the ListView to prevent flickering
            EnableDoubleBuffering(mainListView);

            // Create ListViewItems once
            CreateListViewItems();

            // Create the broker and subscribe to connected radios list
            broker = new DataBrokerClient();
            broker.Subscribe(1, "ConnectedRadios", OnConnectedRadiosChanged);

            // Subscribe to FriendlyName changes for all devices to update the combobox
            broker.Subscribe(DataBroker.AllDevices, "FriendlyName", OnFriendlyNameChanged);

            // Populate the combobox with current connected radios and subscribe to first if available
            PopulateRadioComboBox();

            // Wire up combobox selection change
            radioSelectionComboBox.SelectedIndexChanged += RadioSelectionComboBox_SelectedIndexChanged;

            this.FormClosed += (s, e) => broker?.Dispose();
        }

        private void PopulateRadioComboBox()
        {
            var connectedRadios = DataBroker.GetValue(1, "ConnectedRadios") as IList;
            UpdateRadioComboBox(connectedRadios);
        }

        private void OnConnectedRadiosChanged(int deviceId, string name, object data)
        {
            var connectedRadios = data as IList;
            UpdateRadioComboBox(connectedRadios);
        }

        private void OnFriendlyNameChanged(int deviceId, string name, object data)
        {
            // When a radio's friendly name changes, update the combobox item
            string newFriendlyName = data as string;
            
            isUpdatingComboBox = true;
            try
            {
                for (int i = 0; i < radioSelectionComboBox.Items.Count; i++)
                {
                    var item = radioSelectionComboBox.Items[i] as RadioComboBoxItem;
                    if (item != null && item.DeviceId == deviceId)
                    {
                        item.FriendlyName = newFriendlyName;
                        // Force refresh of the combobox display
                        radioSelectionComboBox.Items[i] = item;
                        break;
                    }
                }
            }
            finally
            {
                isUpdatingComboBox = false;
            }
        }

        private void UpdateRadioComboBox(IList connectedRadios)
        {
            isUpdatingComboBox = true;
            try
            {
                // Remember current selection
                int currentDeviceId = this.deviceId;

                radioSelectionComboBox.Items.Clear();

                if (connectedRadios != null)
                {
                    foreach (var radio in connectedRadios)
                    {
                        // Use reflection to get properties from anonymous type
                        var radioType = radio.GetType();
                        int radioDeviceId = (int)radioType.GetProperty("DeviceId").GetValue(radio);
                        string macAddress = (string)radioType.GetProperty("MacAddress").GetValue(radio);
                        string friendlyName = (string)radioType.GetProperty("FriendlyName").GetValue(radio);

                        var item = new RadioComboBoxItem
                        {
                            DeviceId = radioDeviceId,
                            MacAddress = macAddress,
                            FriendlyName = friendlyName
                        };
                        radioSelectionComboBox.Items.Add(item);
                    }
                }

                // If no radios available, unsubscribe from current and clear display
                if (radioSelectionComboBox.Items.Count == 0)
                {
                    if (this.deviceId != -1)
                    {
                        UnsubscribeFromDevice(this.deviceId);
                        this.deviceId = -1;
                        ClearAllData();
                    }
                    return;
                }

                // Try to restore selection to current device
                bool found = false;
                for (int i = 0; i < radioSelectionComboBox.Items.Count; i++)
                {
                    var item = radioSelectionComboBox.Items[i] as RadioComboBoxItem;
                    if (item != null && item.DeviceId == currentDeviceId)
                    {
                        radioSelectionComboBox.SelectedIndex = i;
                        found = true;
                        break;
                    }
                }

                // If current device not found, select first available and switch to it
                if (!found && radioSelectionComboBox.Items.Count > 0)
                {
                    radioSelectionComboBox.SelectedIndex = 0;
                    var firstItem = radioSelectionComboBox.Items[0] as RadioComboBoxItem;
                    if (firstItem != null)
                    {
                        SwitchToDevice(firstItem.DeviceId);
                    }
                }
            }
            finally
            {
                isUpdatingComboBox = false;
            }
        }

        private void ClearAllData()
        {
            Info = null;
            HtStatus = null;
            Settings = null;
            BssSettings = null;
            Position = null;
            
            // Clear the listview completely
            mainListView.Items.Clear();
            mainListView.Groups.Clear();
        }

        private void RebuildListView()
        {
            // Clear and rebuild the listview structure
            mainListView.Items.Clear();
            mainListView.Groups.Clear();
            CreateListViewItems();
            
            // Update with current data
            UpdateListView();
            UpdateHtStatusListView();
            UpdateSettingsListView();
            UpdateBssSettingsListView();
            UpdatePositionListView();
        }

        private void RadioSelectionComboBox_SelectedIndexChanged(object sender, EventArgs e)
        {
            if (isUpdatingComboBox) return;

            var selectedItem = radioSelectionComboBox.SelectedItem as RadioComboBoxItem;
            if (selectedItem != null && selectedItem.DeviceId != this.deviceId)
            {
                SwitchToDevice(selectedItem.DeviceId);
            }
        }

        private void SwitchToDevice(int newDeviceId)
        {
            // Unsubscribe from current device if we have one
            if (this.deviceId != -1)
            {
                UnsubscribeFromDevice(this.deviceId);
            }

            // Clear current data
            Info = null;
            HtStatus = null;
            Settings = null;
            BssSettings = null;
            Position = null;

            // Update device ID and subscribe to new device
            this.deviceId = newDeviceId;
            if (newDeviceId != -1)
            {
                SubscribeToDevice(newDeviceId);
                // Rebuild listview with data from new device
                RebuildListView();
            }
            else
            {
                // No device - clear the listview
                ClearAllData();
            }
        }

        private void SubscribeToDevice(int deviceId)
        {
            Info = (RadioDevInfo)DataBroker.GetValue(deviceId, "Info");
            HtStatus = (RadioHtStatus)DataBroker.GetValue(deviceId, "HtStatus");
            Settings = (RadioSettings)DataBroker.GetValue(deviceId, "Settings");
            BssSettings = (RadioBssSettings)DataBroker.GetValue(deviceId, "BssSettings");
            Position = (RadioPosition)DataBroker.GetValue(deviceId, "Position");

            broker.Subscribe(deviceId, "Info", OnDeviceInfoChanged);
            broker.Subscribe(deviceId, "HtStatus", OnHtStatusChanged);
            broker.Subscribe(deviceId, "Settings", OnSettingsChanged);
            broker.Subscribe(deviceId, "BssSettings", OnBssSettingsChanged);
            broker.Subscribe(deviceId, "Position", OnPositionChanged);
        }

        private void UnsubscribeFromDevice(int deviceId)
        {
            broker.Unsubscribe(deviceId, "Info");
            broker.Unsubscribe(deviceId, "HtStatus");
            broker.Unsubscribe(deviceId, "Settings");
            broker.Unsubscribe(deviceId, "BssSettings");
            broker.Unsubscribe(deviceId, "Position");
        }

        private void CreateListViewItems()
        {
            // Create the group for device information
            groupDeviceInfo = new ListViewGroup("Device Information", HorizontalAlignment.Left);
            mainListView.Groups.Add(groupDeviceInfo);

            itemProductId = new ListViewItem(new[] { "Product ID", "" }, groupDeviceInfo);
            itemVendorId = new ListViewItem(new[] { "Vendor ID", "" }, groupDeviceInfo);
            itemDmrSupport = new ListViewItem(new[] { "DMR Support", "" }, groupDeviceInfo);
            itemGmrsSupport = new ListViewItem(new[] { "GMRS Support", "" }, groupDeviceInfo);
            itemHwSpeaker = new ListViewItem(new[] { "Hardware Speaker", "" }, groupDeviceInfo);
            itemHwVersion = new ListViewItem(new[] { "Hardware Version", "" }, groupDeviceInfo);
            itemSwVersion = new ListViewItem(new[] { "Software Version", "" }, groupDeviceInfo);
            itemRegionCount = new ListViewItem(new[] { "Region Count", "" }, groupDeviceInfo);
            itemMediumPower = new ListViewItem(new[] { "Medium Power", "" }, groupDeviceInfo);
            itemChannelCount = new ListViewItem(new[] { "Channel Count", "" }, groupDeviceInfo);
            itemNoaa = new ListViewItem(new[] { "NOAA", "" }, groupDeviceInfo);
            itemRadio = new ListViewItem(new[] { "Radio", "" }, groupDeviceInfo);
            itemVfo = new ListViewItem(new[] { "VFO", "" }, groupDeviceInfo);
            itemFreqRangeCount = new ListViewItem(new[] { "Freq Range Count", "" }, groupDeviceInfo);

            mainListView.Items.AddRange(new ListViewItem[]
            {
                itemProductId,
                itemVendorId,
                itemDmrSupport,
                itemGmrsSupport,
                itemHwSpeaker,
                itemHwVersion,
                itemSwVersion,
                itemRegionCount,
                itemMediumPower,
                itemChannelCount,
                itemNoaa,
                itemRadio,
                itemVfo,
                itemFreqRangeCount
            });

            // Create the group for device status
            groupDeviceStatus = new ListViewGroup("Device Status", HorizontalAlignment.Left);
            mainListView.Groups.Add(groupDeviceStatus);

            itemPowerOn = new ListViewItem(new[] { "Power On", "" }, groupDeviceStatus);
            itemInTx = new ListViewItem(new[] { "In TX", "" }, groupDeviceStatus);
            itemIsSq = new ListViewItem(new[] { "is_sq", "" }, groupDeviceStatus);
            itemInRx = new ListViewItem(new[] { "In RX", "" }, groupDeviceStatus);
            itemDoubleChannel = new ListViewItem(new[] { "Double Channel", "" }, groupDeviceStatus);
            itemScanning = new ListViewItem(new[] { "Scanning", "" }, groupDeviceStatus);
            itemRadioStatus = new ListViewItem(new[] { "Radio", "" }, groupDeviceStatus);
            itemCurrentChannelId = new ListViewItem(new[] { "Current Channel ID", "" }, groupDeviceStatus);
            itemGpsLocked = new ListViewItem(new[] { "GPS Locked", "" }, groupDeviceStatus);
            itemHfpConnected = new ListViewItem(new[] { "HFP Connected", "" }, groupDeviceStatus);
            itemAocConnected = new ListViewItem(new[] { "AOC Connected", "" }, groupDeviceStatus);
            itemRssi = new ListViewItem(new[] { "RSSI", "" }, groupDeviceStatus);
            itemCurrentRegion = new ListViewItem(new[] { "Current Region", "" }, groupDeviceStatus);

            mainListView.Items.AddRange(new ListViewItem[]
            {
                itemPowerOn,
                itemInTx,
                itemIsSq,
                itemInRx,
                itemDoubleChannel,
                itemScanning,
                itemRadioStatus,
                itemCurrentChannelId,
                itemGpsLocked,
                itemHfpConnected,
                itemAocConnected,
                itemRssi,
                itemCurrentRegion
            });

            // Create the group for device settings
            groupDeviceSettings = new ListViewGroup("Device Settings", HorizontalAlignment.Left);
            mainListView.Groups.Add(groupDeviceSettings);

            itemVfoA = new ListViewItem(new[] { "VFO A", "" }, groupDeviceSettings);
            itemVfoB = new ListViewItem(new[] { "VFO B", "" }, groupDeviceSettings);
            itemScan = new ListViewItem(new[] { "Scan", "" }, groupDeviceSettings);
            itemAghfpCallMode = new ListViewItem(new[] { "AGHFP Call Mode", "" }, groupDeviceSettings);
            itemDoubleChannelSetting = new ListViewItem(new[] { "Double Channel", "" }, groupDeviceSettings);
            itemSquelchLevel = new ListViewItem(new[] { "Squelch Level", "" }, groupDeviceSettings);
            itemTailElim = new ListViewItem(new[] { "Tail elim", "" }, groupDeviceSettings);
            itemAutoRelayEn = new ListViewItem(new[] { "Auto relay en", "" }, groupDeviceSettings);
            itemAutoPowerOn = new ListViewItem(new[] { "Auto power on", "" }, groupDeviceSettings);
            itemKeepAghfpLink = new ListViewItem(new[] { "Keep AGHFP link", "" }, groupDeviceSettings);
            itemMicGain = new ListViewItem(new[] { "Mic gain", "" }, groupDeviceSettings);
            itemTxHoldTime = new ListViewItem(new[] { "TX hold time", "" }, groupDeviceSettings);
            itemTxTimeLimit = new ListViewItem(new[] { "TX time limit", "" }, groupDeviceSettings);
            itemLocalSpeaker = new ListViewItem(new[] { "Local Speaker", "" }, groupDeviceSettings);
            itemBtMicGain = new ListViewItem(new[] { "BT mic gain", "" }, groupDeviceSettings);
            itemAdaptiveResponse = new ListViewItem(new[] { "Adaptive Response", "" }, groupDeviceSettings);
            itemDisTone = new ListViewItem(new[] { "DIS Tone", "" }, groupDeviceSettings);
            itemPowerSavingMode = new ListViewItem(new[] { "Power saving mode", "" }, groupDeviceSettings);
            itemAutoPowerOff = new ListViewItem(new[] { "Auto power off", "" }, groupDeviceSettings);
            itemAutoShareLocCh = new ListViewItem(new[] { "Auto share location ch", "" }, groupDeviceSettings);
            itemHmSpeaker = new ListViewItem(new[] { "HW speaker", "" }, groupDeviceSettings);
            itemPositioningSystem = new ListViewItem(new[] { "Positioning system", "" }, groupDeviceSettings);
            itemTimeOffset = new ListViewItem(new[] { "Time offset", "" }, groupDeviceSettings);
            itemUseFreqRange2 = new ListViewItem(new[] { "Use freq range 2", "" }, groupDeviceSettings);
            itemPttLock = new ListViewItem(new[] { "PTT lock", "" }, groupDeviceSettings);
            itemLeadingSyncBitEn = new ListViewItem(new[] { "Leading sync bit en", "" }, groupDeviceSettings);
            itemPairingAtPowerOn = new ListViewItem(new[] { "Pairing at power on", "" }, groupDeviceSettings);
            itemScreenTimeout = new ListViewItem(new[] { "Screen Timeout", "" }, groupDeviceSettings);
            itemVfoX = new ListViewItem(new[] { "VFO x", "" }, groupDeviceSettings);
            itemImperialUnit = new ListViewItem(new[] { "Imperial Units", "" }, groupDeviceSettings);
            itemWxMode = new ListViewItem(new[] { "Weather Mode", "" }, groupDeviceSettings);
            itemNoaaCh = new ListViewItem(new[] { "NOAA Channel", "" }, groupDeviceSettings);
            itemVfolTxPowerX = new ListViewItem(new[] { "VFOl tx power", "" }, groupDeviceSettings);
            itemVfo2TxPowerX = new ListViewItem(new[] { "VFO2 tx power", "" }, groupDeviceSettings);
            itemDisDigitalMute = new ListViewItem(new[] { "Dis digital mute", "" }, groupDeviceSettings);
            itemSignalingEccEn = new ListViewItem(new[] { "Signaling ecc en", "" }, groupDeviceSettings);
            itemChDataLock = new ListViewItem(new[] { "Ch data lock", "" }, groupDeviceSettings);
            itemVfo1ModFreqX = new ListViewItem(new[] { "VFO1 mod freq", "" }, groupDeviceSettings);
            itemVfo2ModFreqX = new ListViewItem(new[] { "VFO2 mod freq", "" }, groupDeviceSettings);

            mainListView.Items.AddRange(new ListViewItem[]
            {
                itemVfoA,
                itemVfoB,
                itemScan,
                itemAghfpCallMode,
                itemDoubleChannelSetting,
                itemSquelchLevel,
                itemTailElim,
                itemAutoRelayEn,
                itemAutoPowerOn,
                itemKeepAghfpLink,
                itemMicGain,
                itemTxHoldTime,
                itemTxTimeLimit,
                itemLocalSpeaker,
                itemBtMicGain,
                itemAdaptiveResponse,
                itemDisTone,
                itemPowerSavingMode,
                itemAutoPowerOff,
                itemAutoShareLocCh,
                itemHmSpeaker,
                itemPositioningSystem,
                itemTimeOffset,
                itemUseFreqRange2,
                itemPttLock,
                itemLeadingSyncBitEn,
                itemPairingAtPowerOn,
                itemScreenTimeout,
                itemVfoX,
                itemImperialUnit,
                itemWxMode,
                itemNoaaCh,
                itemVfolTxPowerX,
                itemVfo2TxPowerX,
                itemDisDigitalMute,
                itemSignalingEccEn,
                itemChDataLock,
                itemVfo1ModFreqX,
                itemVfo2ModFreqX
            });

            // Create the group for BSS settings
            groupBssSettings = new ListViewGroup("BSS Settings", HorizontalAlignment.Left);
            mainListView.Groups.Add(groupBssSettings);

            itemAllowPositionCheck = new ListViewItem(new[] { "Allow Position Check", "" }, groupBssSettings);
            itemAprsCallsign = new ListViewItem(new[] { "APRS Callsign", "" }, groupBssSettings);
            itemAprsSymbol = new ListViewItem(new[] { "APRS Symbol", "" }, groupBssSettings);
            itemBeaconMessage = new ListViewItem(new[] { "Beacon Message", "" }, groupBssSettings);
            itemBssUserIdLower = new ListViewItem(new[] { "BSS User Id Lower", "" }, groupBssSettings);
            itemLocationShareInterval = new ListViewItem(new[] { "Location Share Interval", "" }, groupBssSettings);
            itemMaxFwdTimes = new ListViewItem(new[] { "Max Fwd Times", "" }, groupBssSettings);
            itemPacketFormat = new ListViewItem(new[] { "Packet Format", "" }, groupBssSettings);
            itemPttReleaseIdInfo = new ListViewItem(new[] { "PTT Release ID Info", "" }, groupBssSettings);
            itemPttReleaseSendBssUserId = new ListViewItem(new[] { "PTT Release Send BSS User Id", "" }, groupBssSettings);
            itemPttReleaseSendIdInfo = new ListViewItem(new[] { "PTT Release Send Id Info", "" }, groupBssSettings);
            itemPttReleaseSendLocation = new ListViewItem(new[] { "PTT Release Send Location", "" }, groupBssSettings);
            itemSendPwrVoltage = new ListViewItem(new[] { "Send Pwr Voltage", "" }, groupBssSettings);
            itemShouldShareLocation = new ListViewItem(new[] { "Should Share Location", "" }, groupBssSettings);
            itemTimeToLive = new ListViewItem(new[] { "Time To Live", "" }, groupBssSettings);

            mainListView.Items.AddRange(new ListViewItem[]
            {
                itemAllowPositionCheck,
                itemAprsCallsign,
                itemAprsSymbol,
                itemBeaconMessage,
                itemBssUserIdLower,
                itemLocationShareInterval,
                itemMaxFwdTimes,
                itemPacketFormat,
                itemPttReleaseIdInfo,
                itemPttReleaseSendBssUserId,
                itemPttReleaseSendIdInfo,
                itemPttReleaseSendLocation,
                itemSendPwrVoltage,
                itemShouldShareLocation,
                itemTimeToLive
            });

            // Create the group for position
            groupPosition = new ListViewGroup("Position", HorizontalAlignment.Left);
            mainListView.Groups.Add(groupPosition);

            itemPositionStatus = new ListViewItem(new[] { "Status", "" }, groupPosition);
            itemLatitude = new ListViewItem(new[] { "Latitude", "" }, groupPosition);
            itemLongitude = new ListViewItem(new[] { "Longitude", "" }, groupPosition);
            itemAccuracy = new ListViewItem(new[] { "Accuracy", "" }, groupPosition);
            itemAltitude = new ListViewItem(new[] { "Altitude", "" }, groupPosition);
            itemSpeed = new ListViewItem(new[] { "Speed", "" }, groupPosition);
            itemHeading = new ListViewItem(new[] { "Heading", "" }, groupPosition);
            itemReceivedTime = new ListViewItem(new[] { "Received Time", "" }, groupPosition);
            itemGpsTimeLocal = new ListViewItem(new[] { "GPS Time Local", "" }, groupPosition);
            itemGpsTimeUtc = new ListViewItem(new[] { "GPS Time UTC", "" }, groupPosition);

            mainListView.Items.AddRange(new ListViewItem[]
            {
                itemPositionStatus,
                itemLatitude,
                itemLongitude,
                itemAccuracy,
                itemAltitude,
                itemSpeed,
                itemHeading,
                itemReceivedTime,
                itemGpsTimeLocal,
                itemGpsTimeUtc
            });
        }

        private void OnDeviceInfoChanged(int deviceId, string name, object data)
        {
            Info = data as RadioDevInfo;
            UpdateListView();
        }

        private void OnHtStatusChanged(int deviceId, string name, object data)
        {
            HtStatus = data as RadioHtStatus;
            UpdateHtStatusListView();
        }

        private void OnSettingsChanged(int deviceId, string name, object data)
        {
            Settings = data as RadioSettings;
            UpdateSettingsListView();
        }

        private void OnBssSettingsChanged(int deviceId, string name, object data)
        {
            BssSettings = data as RadioBssSettings;
            UpdateBssSettingsListView();
        }

        private void OnPositionChanged(int deviceId, string name, object data)
        {
            Position = data as RadioPosition;
            UpdatePositionListView();
        }

        private void RadioInfoForm_Load(object sender, EventArgs e)
        {
            UpdateListView();
            UpdateHtStatusListView();
            UpdateSettingsListView();
            UpdateBssSettingsListView();
            UpdatePositionListView();
            mainListView.Columns[mainListView.Columns.Count - 1].Width = -2; // Auto-fill remaining width
        }

        private void UpdateListView()
        {
            if (Info == null) return;

            mainListView.BeginUpdate();
            itemProductId.SubItems[1].Text = Info.product_id.ToString();
            itemVendorId.SubItems[1].Text = Info.vendor_id.ToString();
            if (Info.vendor_id == 1) { itemVendorId.SubItems[1].Text += " - Vero"; }
            if (Info.vendor_id == 6) { itemVendorId.SubItems[1].Text += " - BTech"; }
            if (Info.vendor_id == 255) { itemVendorId.SubItems[1].Text += " - RadioOddity"; }
            itemDmrSupport.SubItems[1].Text = Info.support_dmr ? "Present" : "Not-Present";
            itemGmrsSupport.SubItems[1].Text = Info.gmrs ? "Present" : "Not-Present";
            itemHwSpeaker.SubItems[1].Text = Info.have_hm_speaker ? "Present" : "Not-Present";
            itemHwVersion.SubItems[1].Text = Info.hw_ver.ToString();
            itemSwVersion.SubItems[1].Text = $"{(Info.soft_ver >> 8) & 0xF}.{(Info.soft_ver >> 4) & 0xF}.{Info.soft_ver & 0xF}";
            itemRegionCount.SubItems[1].Text = Info.region_count.ToString();
            itemMediumPower.SubItems[1].Text = Info.support_medium_power ? "Supported" : "Not-Supported";
            itemChannelCount.SubItems[1].Text = Info.channel_count.ToString();
            itemNoaa.SubItems[1].Text = Info.support_noaa ? "Supported" : "Not-Supported";
            itemRadio.SubItems[1].Text = Info.support_radio ? "Supported" : "Not-Supported";
            itemVfo.SubItems[1].Text = Info.support_vfo ? "Supported" : "Not-Supported";
            itemFreqRangeCount.SubItems[1].Text = Info.freq_range_count.ToString();
            mainListView.EndUpdate();
        }

        private void UpdateHtStatusListView()
        {
            if (HtStatus == null) return;

            mainListView.BeginUpdate();
            itemPowerOn.SubItems[1].Text = HtStatus.is_power_on.ToString();
            itemInTx.SubItems[1].Text = HtStatus.is_in_tx.ToString();
            itemIsSq.SubItems[1].Text = HtStatus.is_sq.ToString();
            itemInRx.SubItems[1].Text = HtStatus.is_in_rx.ToString();
            itemDoubleChannel.SubItems[1].Text = HtStatus.double_channel.ToString();
            itemScanning.SubItems[1].Text = HtStatus.is_scan.ToString();
            itemRadioStatus.SubItems[1].Text = HtStatus.is_radio.ToString();
            itemCurrentChannelId.SubItems[1].Text = (HtStatus.curr_ch_id + 1).ToString();
            itemGpsLocked.SubItems[1].Text = HtStatus.is_gps_locked.ToString();
            itemHfpConnected.SubItems[1].Text = HtStatus.is_hfp_connected.ToString();
            itemAocConnected.SubItems[1].Text = HtStatus.is_aoc_connected.ToString();
            itemRssi.SubItems[1].Text = HtStatus.rssi.ToString();
            itemCurrentRegion.SubItems[1].Text = HtStatus.curr_region.ToString();
            mainListView.EndUpdate();
        }

        private void UpdateSettingsListView()
        {
            if (Settings == null) return;

            mainListView.BeginUpdate();
            itemVfoA.SubItems[1].Text = "Channel " + (Settings.channel_a + 1);
            itemVfoB.SubItems[1].Text = "Channel " + (Settings.channel_b + 1);
            itemScan.SubItems[1].Text = Settings.scan.ToString();
            itemAghfpCallMode.SubItems[1].Text = Settings.aghfp_call_mode.ToString();
            itemDoubleChannelSetting.SubItems[1].Text = Settings.double_channel.ToString();
            itemSquelchLevel.SubItems[1].Text = Settings.squelch_level.ToString();
            itemTailElim.SubItems[1].Text = Settings.tail_elim.ToString();
            itemAutoRelayEn.SubItems[1].Text = Settings.auto_relay_en.ToString();
            itemAutoPowerOn.SubItems[1].Text = Settings.auto_power_on.ToString();
            itemKeepAghfpLink.SubItems[1].Text = Settings.keep_aghfp_link.ToString();
            itemMicGain.SubItems[1].Text = Settings.mic_gain.ToString();
            itemTxHoldTime.SubItems[1].Text = Settings.tx_hold_time.ToString();
            itemTxTimeLimit.SubItems[1].Text = Settings.tx_time_limit.ToString();
            itemLocalSpeaker.SubItems[1].Text = Settings.local_speaker.ToString();
            itemBtMicGain.SubItems[1].Text = Settings.bt_mic_gain.ToString();
            itemAdaptiveResponse.SubItems[1].Text = Settings.adaptive_response.ToString();
            itemDisTone.SubItems[1].Text = Settings.dis_tone.ToString();
            itemPowerSavingMode.SubItems[1].Text = Settings.power_saving_mode.ToString();
            itemAutoPowerOff.SubItems[1].Text = Settings.auto_power_off.ToString();
            string autoShareLocCh = Settings.auto_share_loc_ch == 0 ? "Current" : "Channel " + Settings.auto_share_loc_ch;
            itemAutoShareLocCh.SubItems[1].Text = autoShareLocCh;
            itemHmSpeaker.SubItems[1].Text = Settings.hm_speaker.ToString();
            itemPositioningSystem.SubItems[1].Text = Settings.positioning_system.ToString();
            itemTimeOffset.SubItems[1].Text = Settings.time_offset.ToString();
            itemUseFreqRange2.SubItems[1].Text = Settings.use_freq_range_2.ToString();
            itemPttLock.SubItems[1].Text = Settings.ptt_lock.ToString();
            itemLeadingSyncBitEn.SubItems[1].Text = Settings.leading_sync_bit_en.ToString();
            itemPairingAtPowerOn.SubItems[1].Text = Settings.pairing_at_power_on.ToString();
            itemScreenTimeout.SubItems[1].Text = Settings.screen_timeout.ToString();
            itemVfoX.SubItems[1].Text = Settings.vfo_x.ToString();
            itemImperialUnit.SubItems[1].Text = Settings.imperial_unit.ToString();
            itemWxMode.SubItems[1].Text = Settings.wx_mode.ToString();
            itemNoaaCh.SubItems[1].Text = Settings.noaa_ch.ToString();
            itemVfolTxPowerX.SubItems[1].Text = Settings.vfol_tx_power_x.ToString();
            itemVfo2TxPowerX.SubItems[1].Text = Settings.vfo2_tx_power_x.ToString();
            itemDisDigitalMute.SubItems[1].Text = Settings.dis_digital_mute.ToString();
            itemSignalingEccEn.SubItems[1].Text = Settings.signaling_ecc_en.ToString();
            itemChDataLock.SubItems[1].Text = Settings.ch_data_lock.ToString();
            itemVfo1ModFreqX.SubItems[1].Text = Settings.vfo1_mod_freq_x.ToString();
            itemVfo2ModFreqX.SubItems[1].Text = Settings.vfo2_mod_freq_x.ToString();
            mainListView.EndUpdate();
        }

        private void UpdateBssSettingsListView()
        {
            if (BssSettings == null) return;

            mainListView.BeginUpdate();
            itemAllowPositionCheck.SubItems[1].Text = BssSettings.AllowPositionCheck.ToString();
            itemAprsCallsign.SubItems[1].Text = BssSettings.AprsCallsign + "-" + BssSettings.AprsSsid.ToString();
            itemAprsSymbol.SubItems[1].Text = BssSettings.AprsSymbol;
            itemBeaconMessage.SubItems[1].Text = BssSettings.BeaconMessage;
            itemBssUserIdLower.SubItems[1].Text = BssSettings.BssUserIdLower.ToString();
            itemLocationShareInterval.SubItems[1].Text = BssSettings.LocationShareInterval == 0 ? "Off" : BssSettings.LocationShareInterval.ToString() + " second(s)";
            itemMaxFwdTimes.SubItems[1].Text = BssSettings.MaxFwdTimes.ToString();
            itemPacketFormat.SubItems[1].Text = BssSettings.PacketFormat.ToString();
            itemPttReleaseIdInfo.SubItems[1].Text = BssSettings.PttReleaseIdInfo.ToString();
            itemPttReleaseSendBssUserId.SubItems[1].Text = BssSettings.PttReleaseSendBssUserId.ToString();
            itemPttReleaseSendIdInfo.SubItems[1].Text = BssSettings.PttReleaseSendIdInfo.ToString();
            itemPttReleaseSendLocation.SubItems[1].Text = BssSettings.PttReleaseSendLocation.ToString();
            itemSendPwrVoltage.SubItems[1].Text = BssSettings.SendPwrVoltage.ToString();
            itemShouldShareLocation.SubItems[1].Text = BssSettings.ShouldShareLocation.ToString();
            itemTimeToLive.SubItems[1].Text = BssSettings.TimeToLive.ToString();
            mainListView.EndUpdate();
        }

        private void UpdatePositionListView()
        {
            if (Position == null)
            {
                itemPositionStatus.SubItems[1].Text = "No GPS data";
                itemLatitude.SubItems[1].Text = "";
                itemLongitude.SubItems[1].Text = "";
                itemAccuracy.SubItems[1].Text = "";
                itemAltitude.SubItems[1].Text = "";
                itemSpeed.SubItems[1].Text = "";
                itemHeading.SubItems[1].Text = "";
                itemReceivedTime.SubItems[1].Text = "";
                itemGpsTimeLocal.SubItems[1].Text = "";
                itemGpsTimeUtc.SubItems[1].Text = "";
                return;
            }

            mainListView.BeginUpdate();
            if (Position.Status == Radio.RadioCommandState.SUCCESS)
            {
                itemPositionStatus.SubItems[1].Text = "GPS locked";
                itemLatitude.SubItems[1].Text = Position.LatitudeStr;
                itemLongitude.SubItems[1].Text = Position.LongitudeStr;
                if (Position.Time != DateTime.MinValue)
                {
                    itemAccuracy.SubItems[1].Text = Position.Accuracy.ToString() + " meters";
                    itemAltitude.SubItems[1].Text = Position.Altitude.ToString() + " meters";
                    itemSpeed.SubItems[1].Text = Position.Speed.ToString();
                    itemHeading.SubItems[1].Text = Position.Heading.ToString() + " degrees";
                    itemReceivedTime.SubItems[1].Text = Position.ReceivedTime.ToString("yyyy-MM-dd HH:mm:ss");
                    itemGpsTimeLocal.SubItems[1].Text = Position.Time.ToString("yyyy-MM-dd HH:mm:ss");
                    itemGpsTimeUtc.SubItems[1].Text = Position.TimeUTC.ToString("yyyy-MM-dd HH:mm:ss");
                }
                else
                {
                    itemAccuracy.SubItems[1].Text = "";
                    itemAltitude.SubItems[1].Text = "";
                    itemSpeed.SubItems[1].Text = "";
                    itemHeading.SubItems[1].Text = "";
                    itemReceivedTime.SubItems[1].Text = "";
                    itemGpsTimeLocal.SubItems[1].Text = "";
                    itemGpsTimeUtc.SubItems[1].Text = "";
                }
            }
            else
            {
                itemPositionStatus.SubItems[1].Text = "No GPS lock";
                itemLatitude.SubItems[1].Text = "";
                itemLongitude.SubItems[1].Text = "";
                itemAccuracy.SubItems[1].Text = "";
                itemAltitude.SubItems[1].Text = "";
                itemSpeed.SubItems[1].Text = "";
                itemHeading.SubItems[1].Text = "";
                itemReceivedTime.SubItems[1].Text = "";
                itemGpsTimeLocal.SubItems[1].Text = "";
                itemGpsTimeUtc.SubItems[1].Text = "";
            }
            mainListView.EndUpdate();
        }

        private void okButton_Click(object sender, EventArgs e)
        {
            Close();
        }

        private static void EnableDoubleBuffering(Control control)
        {
            typeof(Control).GetProperty("DoubleBuffered", BindingFlags.NonPublic | BindingFlags.Instance)
                ?.SetValue(control, true, null);
        }
    }
}
