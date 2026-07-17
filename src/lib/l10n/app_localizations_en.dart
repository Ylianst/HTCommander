// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Handi-Talkie Commander';

  @override
  String get menuFile => 'File';

  @override
  String get menuConnect => 'Connect...';

  @override
  String get menuDisconnect => 'Disconnect';

  @override
  String get menuSettings => 'Settings...';

  @override
  String get menuExit => 'Exit';

  @override
  String get menuRadios => 'Radios';

  @override
  String get menuDualWatch => 'Dual-Watch';

  @override
  String get menuScan => 'Scan';

  @override
  String get menuRegions => 'Regions';

  @override
  String get menuTrustedDevices => 'Trusted Devices...';

  @override
  String get menuButtons => 'Buttons...';

  @override
  String get menuFmRadio => 'FM Radio...';

  @override
  String get menuExportChannels => 'Export Channels...';

  @override
  String get menuImportChannels => 'Import Channels...';

  @override
  String get menuMacRadio => 'Radio';

  @override
  String get menuMacDisplay => 'Display';

  @override
  String get fmRadioTitle => 'FM Radio';

  @override
  String fmRadioMhz(String value) {
    return '${value}MHz';
  }

  @override
  String get fmRadioOff => 'Off';

  @override
  String get fmRadioPowerTooltip => 'Turn FM radio on or off';

  @override
  String get fmRadioSeekDownTooltip => 'Seek down';

  @override
  String get fmRadioStepDownTooltip => 'Tune down';

  @override
  String get fmRadioStopTooltip => 'Turn off';

  @override
  String get fmRadioStepUpTooltip => 'Tune up';

  @override
  String get fmRadioSeekUpTooltip => 'Seek up';

  @override
  String get fmRadioStationsHeader => 'Preferred Stations';

  @override
  String get fmRadioAddStationTooltip => 'Add current frequency';

  @override
  String get fmRadioNoStations => 'No preferred stations';

  @override
  String get fmRadioStationNameLabel => 'Station name';

  @override
  String get fmRadioRenameTitle => 'Station Name';

  @override
  String get fmRadioDeleteTitle => 'Delete Station';

  @override
  String fmRadioDeleteMessage(String name) {
    return 'Remove \"$name\" from your preferred stations?';
  }

  @override
  String get commonClose => 'Close';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonOk => 'OK';

  @override
  String get aboutCheckForUpdates => 'Check for Updates';

  @override
  String aboutVersionAuthor(String version) {
    return 'Version $version\nYlian Saint-Hilaire, KK7VZT\nOpen Source, Apache 2.0 License';
  }

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageHint =>
      'Choose the language used by the application. \'System default\' follows your device language.';

  @override
  String get settingsThemeMode => 'Theme';

  @override
  String get settingsThemeModeHint =>
      'Choose the light or dark appearance. \'System default\' follows your device setting.';

  @override
  String get settingsThemeModeSystem => 'System default';

  @override
  String get settingsThemeModeLight => 'Light';

  @override
  String get settingsThemeModeDark => 'Dark';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'French';

  @override
  String get languageSpanish => 'Spanish';

  @override
  String get languageChinese => 'Chinese';

  @override
  String get languageJapanese => 'Japanese';

  @override
  String get languageHindi => 'Hindi';

  @override
  String get languageGerman => 'German';

  @override
  String get menuAudio => 'Audio';

  @override
  String get menuAudioEnabled => 'Audio Enabled';

  @override
  String get menuSoftwareModem => 'Software Modem';

  @override
  String get menuModemDisabled => 'Disabled';

  @override
  String get menuDartTransmitLevel => 'DART Transmit Level';

  @override
  String get menuDartLevel0 => 'Level 0 (BPSK, LDPC 1/2)';

  @override
  String get menuDartLevel1 => 'Level 1 (QPSK, LDPC 1/2)';

  @override
  String get menuDartLevel2 => 'Level 2 (QPSK, LDPC 2/3)';

  @override
  String get menuDartLevel3 => 'Level 3 (8PSK, LDPC 2/3)';

  @override
  String get menuDartLevel4 => 'Level 4 (16QAM, LDPC 3/4)';

  @override
  String get menuDartLevel5 => 'Level 5 (16QAM, LDPC 5/6)';

  @override
  String get menuDartLevelF => 'Level F (4-FSK, LDPC 1/2)';

  @override
  String get menuAprsModem => 'APRS Modem';

  @override
  String get menuView => 'View';

  @override
  String get menuRadio => 'Radio';

  @override
  String get menuTabs => 'Tabs';

  @override
  String get menuTabNames => 'Tab Names';

  @override
  String get menuShowAllTabs => 'Show All Tabs';

  @override
  String get menuAllChannels => 'All Channels';

  @override
  String get menuChannelFrequency => 'Channel Frequency';

  @override
  String get menuHelp => 'Help';

  @override
  String get menuRadioInformation => 'Radio Information...';

  @override
  String get menuGpsInformation => 'GPS Information...';

  @override
  String get menuCheckForUpdatesEllipsis => 'Check for Updates...';

  @override
  String get menuAbout => 'About...';

  @override
  String get tabComms => 'Comms';

  @override
  String get tabAudio => 'Audio';

  @override
  String get tabAprs => 'APRS';

  @override
  String get tabMap => 'Map';

  @override
  String get tabMail => 'Mail';

  @override
  String get tabTerminal => 'Terminal';

  @override
  String get tabContacts => 'Contacts';

  @override
  String get tabBbs => 'BBS';

  @override
  String get tabTorrent => 'Torrent';

  @override
  String get tabPackets => 'Packets';

  @override
  String get tabDebug => 'Debug';

  @override
  String get tabRadio => 'Radio';

  @override
  String get stateDisconnected => 'Disconnected';

  @override
  String get stateConnecting => 'Connecting...';

  @override
  String get stateConnected => 'Connected';

  @override
  String get stateUnableToConnect => 'Unable to Connect';

  @override
  String get stateAccessDenied => 'Access Denied';

  @override
  String get stateSelectRadio => 'Select Radio';

  @override
  String statusBattery(int percent) {
    return 'Battery: $percent%';
  }

  @override
  String get statusCheckingBluetooth => 'Checking Bluetooth...';

  @override
  String get statusBluetoothNotAvailable => 'Bluetooth not available';

  @override
  String get statusScanningForRadios => 'Scanning for radios...';

  @override
  String get statusErrorScanning => 'Error scanning for radios';

  @override
  String get statusNoCompatibleRadios => 'No compatible radios found';

  @override
  String get statusAllRadiosConnected => 'All radios already connected';

  @override
  String statusConnectingTo(String name) {
    return 'Connecting to $name...';
  }

  @override
  String statusConnectedTo(String name) {
    return 'Connected to $name';
  }

  @override
  String statusFailedToConnect(String name) {
    return 'Failed to connect to $name';
  }

  @override
  String get statusDisconnecting => 'Disconnecting...';

  @override
  String get settingsTabLicense => 'License';

  @override
  String get settingsTabAprs => 'APRS';

  @override
  String get settingsTabComms => 'Comms';

  @override
  String get settingsTabWinlink => 'Winlink';

  @override
  String get settingsTabServers => 'Servers';

  @override
  String get settingsTabMap => 'Map';

  @override
  String get settingsTabLimits => 'Limits';

  @override
  String get settingsTabApplication => 'Application';

  @override
  String get settingsAdd => 'Add';

  @override
  String get settingsRemove => 'Remove';

  @override
  String get settingsDownload => 'Download';

  @override
  String get settingsRetry => 'Retry';

  @override
  String get settingsPreview => 'Preview';

  @override
  String get settingsNone => 'None';

  @override
  String get settingsLicenseInfo =>
      'In the United States, you need an amateur radio license to transmit. Visit the ARRL website for more information on getting licensed.';

  @override
  String get settingsCallSignStationId => 'Call Sign & Station ID';

  @override
  String get settingsCallSign => 'Call Sign';

  @override
  String get settingsCallSignHint => 'e.g. W1AW';

  @override
  String get settingsStationId => 'Station ID';

  @override
  String get settingsAllowTransmit => 'Allow this application to transmit';

  @override
  String get settingsCallSignHelp =>
      'Enter a valid call sign (at least 3 characters) to enable transmit';

  @override
  String get settingsAprsIntro =>
      'Configure APRS routing paths for packet transmission.';

  @override
  String get settingsAprsRoutes => 'APRS Routes';

  @override
  String get settingsEditRoute => 'Edit route';

  @override
  String get settingsEditRouteProtected => 'Built-in route cannot be edited';

  @override
  String get settingsDeleteRoute => 'Delete route';

  @override
  String get settingsDeleteRouteProtected => 'Built-in route cannot be removed';

  @override
  String get settingsCommsIntro =>
      'Configure speech recognition and text-to-speech settings.';

  @override
  String get settingsSpeechToText => 'Speech-to-Text';

  @override
  String get settingsSpeechToTextInfo =>
      'Transcribes received radio audio to text. Runs fully offline on this device; audio is never written to disk.';

  @override
  String get settingsModel => 'Model';

  @override
  String get settingsRecognitionLanguage => 'Recognition Language';

  @override
  String get settingsRecognitionLanguageHelp =>
      'Language changes take effect the next time the engine starts.';

  @override
  String get settingsStatus => 'Status';

  @override
  String settingsModelInstalled(String suffix) {
    return 'Model installed$suffix';
  }

  @override
  String settingsDownloadingModelPct(String percent) {
    return 'Downloading model… $percent%';
  }

  @override
  String get settingsDownloadingModel => 'Downloading model…';

  @override
  String settingsInstallingModelPct(String percent) {
    return 'Installing model… $percent%';
  }

  @override
  String get settingsInstallingModel => 'Installing model…';

  @override
  String get settingsModelInstallError => 'Model could not be installed.';

  @override
  String settingsModelNotDownloaded(String downloadLabel) {
    return 'Model not downloaded. $downloadLabel happens once and is cached on this device.';
  }

  @override
  String settingsBytesOf(String received, String total) {
    return '$received of $total';
  }

  @override
  String get settingsRemoveSttModelTitle => 'Remove speech-to-text model?';

  @override
  String settingsRemoveSttModelBody(String name) {
    return 'The downloaded \"$name\" model will be deleted to reclaim disk space. It will be downloaded again the next time it is used.';
  }

  @override
  String get settingsTextToSpeech => 'Text-to-Speech';

  @override
  String get settingsTextToSpeechInfo =>
      'Used when sending text in \"Speech\" mode from the Comms tab.';

  @override
  String get settingsTtsUnavailableTitle => 'Text-to-speech is unavailable';

  @override
  String get settingsVoice => 'Voice';

  @override
  String get settingsSpeechRate => 'Speech Rate';

  @override
  String get settingsPitch => 'Pitch';

  @override
  String get settingsLoadingVoices => 'Loading voices…';

  @override
  String get settingsSystemDefault => 'System Default';

  @override
  String get settingsLangAutoDetect => 'Auto-detect';

  @override
  String get settingsLangChinese => 'Chinese';

  @override
  String get settingsLangJapanese => 'Japanese';

  @override
  String get settingsLangKorean => 'Korean';

  @override
  String get settingsLangCantonese => 'Cantonese';

  @override
  String get settingsWinlinkIntro =>
      'Configure Winlink email settings for radio email.';

  @override
  String get settingsWinlinkAccount => 'Winlink Account';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsWinlinkAccountHelp =>
      'Based on your call sign from the License tab';

  @override
  String get settingsPassword => 'Password';

  @override
  String get settingsUseStationIdWinlink => 'Use Station ID for Winlink';

  @override
  String get settingsServersIntro => 'Configure local server settings.';

  @override
  String get settingsLocalServers => 'Local Servers';

  @override
  String get settingsEnableWebServer => 'Enable Web Server';

  @override
  String get settingsPort => 'Port:';

  @override
  String get settingsEnableAgwpeServer => 'Enable AGWPE Server';

  @override
  String get settingsHomeAssistant => 'Home Assistant';

  @override
  String get settingsHomeAssistantDescription =>
      'Expose each connected radio to Home Assistant over MQTT for monitoring and control.';

  @override
  String get settingsEnableHomeAssistant => 'Enable Home Assistant';

  @override
  String get settingsHomeAssistantMqttUrl => 'MQTT URL';

  @override
  String get settingsHomeAssistantUsername => 'Username';

  @override
  String get settingsHomeAssistantPassword => 'Password';

  @override
  String get settingsHomeAssistantTestSuccess =>
      'Success: connected to broker.';

  @override
  String get settingsMapIntroGps =>
      'Configure GPS and airplane tracking data sources.';

  @override
  String get settingsMapIntroNoGps =>
      'Configure airplane tracking data sources.';

  @override
  String get settingsGpsSerialPort => 'GPS Serial Port';

  @override
  String get settingsSerialPort => 'Serial Port';

  @override
  String get settingsBaudRate => 'Baud Rate';

  @override
  String get settingsShareGpsLocation => 'Share serial GPS location';

  @override
  String get settingsShareGpsLocationHelp =>
      'Send the serial GPS position to the connected radio so it beacons your current location.';

  @override
  String get settingsAirplaneTracking => 'Airplane Tracking (dump1090)';

  @override
  String get settingsServerUrl => 'Server URL';

  @override
  String get settingsTestConnection => 'Test Connection';

  @override
  String get settingsTest => 'Test';

  @override
  String get settingsTestTesting => 'Testing...';

  @override
  String get settingsTestEmptyAddress => 'Failed: empty server address';

  @override
  String settingsTestFailedHttp(int code) {
    return 'Failed: HTTP $code';
  }

  @override
  String settingsTestSuccess(int count) {
    return 'Success, $count aircraft found.';
  }

  @override
  String get settingsTestUnexpectedJson => 'Failed: unexpected JSON format';

  @override
  String get settingsTestTimedOut => 'Failed: request timed out';

  @override
  String get settingsTestInvalidJson => 'Failed: invalid JSON response';

  @override
  String get settingsTestFailed => 'Failed';

  @override
  String get settingsTestConnectionFailedTitle => 'Test Connection Failed';

  @override
  String get settingsLimitsIntro =>
      'Limit how many historical items are kept across app restarts. Set to \"Unlimited\" to keep everything.';

  @override
  String get settingsHistoryLimits => 'History Limits';

  @override
  String get settingsUnlimited => 'Unlimited';

  @override
  String get settingsLimitAprsMessages => 'APRS Messages';

  @override
  String get settingsLimitPackets => 'Packets';

  @override
  String get settingsLimitSstvImages => 'SSTV Images';

  @override
  String get settingsLimitCommEvents => 'Communication Events';

  @override
  String settingsLimitCurrent(int count) {
    return 'Current: $count';
  }

  @override
  String settingsLimitItemsDeleted(int count) {
    return '$count items will be deleted';
  }

  @override
  String get settingsDeleteHistoryTitle => 'Delete History Items?';

  @override
  String settingsDeleteHistoryBody(String items) {
    return 'These limits will permanently delete the oldest:\n\n$items\n\nThis cannot be undone.';
  }

  @override
  String settingsDeleteAprsMessages(int count) {
    return '$count APRS messages';
  }

  @override
  String settingsDeletePackets(int count) {
    return '$count packets';
  }

  @override
  String settingsDeleteSstvImages(int count) {
    return '$count SSTV images';
  }

  @override
  String settingsDeleteCommEvents(int count) {
    return '$count communication events';
  }

  @override
  String get settingsAddAprsRoute => 'Add APRS Route';

  @override
  String get settingsEditAprsRoute => 'Edit APRS Route';

  @override
  String get settingsName => 'Name';

  @override
  String get settingsNameHint => 'e.g. Standard';

  @override
  String get settingsDuplicateRoute => 'A route with this name already exists.';

  @override
  String get settingsPath => 'Path';

  @override
  String get commonError => 'Error';

  @override
  String get commonConnect => 'Connect';

  @override
  String get commonDisconnect => 'Disconnect';

  @override
  String get commonRename => 'Rename';

  @override
  String get commonRemove => 'Remove';

  @override
  String connectScanError(String error) {
    return 'Failed to scan for Bluetooth devices: $error';
  }

  @override
  String get connectNoRadiosTitle => 'No Radios Found';

  @override
  String get connectNoRadiosBody =>
      'No compatible radio devices were found.\n\nMake sure your radio is powered on and Bluetooth is enabled.';

  @override
  String get connectAllConnectedTitle => 'All Connected';

  @override
  String get connectAllConnectedBody =>
      'All detected radio devices are already connected.';

  @override
  String get connectBluetoothOffTitle => 'Bluetooth Not Available';

  @override
  String get connectBluetoothOffBody =>
      'Bluetooth is not available or is turned off.\n\nPlease enable Bluetooth in your device settings and try again.';

  @override
  String get radioConnectionTitle => 'Radio Connection';

  @override
  String get radioConnectionEmpty =>
      'No compatible radios found.\nMake sure your radio is powered on and Bluetooth is enabled.';

  @override
  String get radioRenameTitle => 'Rename Radio';

  @override
  String get radioRenamePrompt => 'Enter a custom name for this radio:';

  @override
  String get radioRenameHint => 'Leave blank to use the default name';

  @override
  String get updateTitle => 'Software Update';

  @override
  String get updateChecking => 'Checking for updates...';

  @override
  String updateVersionAvailable(String version) {
    return 'Version $version is available.';
  }

  @override
  String updateFreshDownload(String version) {
    return 'Version $version requires a fresh download.';
  }

  @override
  String updateUnsupported(String version) {
    return 'This version is no longer supported. Update to $version.';
  }

  @override
  String get updateUpToDate => 'You are running the latest version.';

  @override
  String updateCheckFailed(String error) {
    return 'Update check failed: $error';
  }

  @override
  String get updateDownloading => 'Downloading update...';

  @override
  String get updateDownloaded => 'Update downloaded. Ready to install.';

  @override
  String updateDownloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String updateInstallFailed(String error) {
    return 'Install failed: $error';
  }

  @override
  String updateDiagnosticsLog(String path) {
    return 'If the update does not complete, see the diagnostics log:\n$path';
  }

  @override
  String get updateInstallRestart => 'Install & Restart';

  @override
  String get updateCheckAgain => 'Check Again';

  @override
  String get regionsTitle => 'Rename Regions';

  @override
  String regionsMaxChars(int count) {
    return 'Region names can be up to $count characters.';
  }

  @override
  String regionLabel(int number) {
    return 'Region $number';
  }

  @override
  String get gpsInfoTitle => 'GPS Information';

  @override
  String get gpsSectionConnection => 'Connection';

  @override
  String get gpsSectionFix => 'GPS Fix';

  @override
  String get gpsSectionPosition => 'Position';

  @override
  String get gpsSectionMotion => 'Motion';

  @override
  String get gpsSectionTime => 'Time';

  @override
  String get gpsPortStatus => 'Port Status';

  @override
  String get gpsNotConfigured => 'Not Configured';

  @override
  String get gpsOpenReceiving => 'Open — Receiving Data';

  @override
  String get gpsPermDeniedLinux =>
      'Permission denied — add your user to the \'dialout\' group (sudo usermod -aG dialout \$USER), then log out and back in.';

  @override
  String get gpsPermDenied =>
      'Permission denied — the app cannot access this port.';

  @override
  String get gpsPortError => 'Port error — could not open the serial port.';

  @override
  String get gpsFix => 'Fix';

  @override
  String get gpsFixQuality => 'Fix Quality';

  @override
  String get gpsSatellites => 'Satellites';

  @override
  String get gpsNoData => 'No Data';

  @override
  String get gpsActive => 'Active';

  @override
  String get gpsNoFix => 'No Fix';

  @override
  String get gpsQualGps => 'GPS Fix (1)';

  @override
  String get gpsQualDgps => 'DGPS Fix (2)';

  @override
  String get gpsQualInvalid => 'Invalid (0)';

  @override
  String gpsQualUnknown(int quality) {
    return '$quality (unknown)';
  }

  @override
  String get gpsLatitude => 'Latitude';

  @override
  String get gpsLatitudeDms => 'Latitude (DMS)';

  @override
  String get gpsLongitude => 'Longitude';

  @override
  String get gpsLongitudeDms => 'Longitude (DMS)';

  @override
  String get gpsAltitude => 'Altitude';

  @override
  String get gpsSpeed => 'Speed';

  @override
  String get gpsHeading => 'Heading';

  @override
  String get gpsTimeUtc => 'GPS Time (UTC)';

  @override
  String get gpsDate => 'GPS Date';

  @override
  String get gpsLastUpdate => 'Last Update';

  @override
  String get trustedDevicesTitle => 'Trusted Devices';

  @override
  String get trustedRemoveTitle => 'Remove Trusted Device';

  @override
  String trustedRemoveMessage(String name) {
    return 'Remove \"$name\" from the radio\'s trusted device list?';
  }

  @override
  String get trustedNoDevices => 'No trusted devices found.';

  @override
  String get pfConfigTitle => 'Configure Buttons';

  @override
  String get pfSaveToRadio => 'Save to Radio';

  @override
  String get pfNoRadio => 'No radio connected.';

  @override
  String get pfNoButtons => 'This radio reported no programmable buttons.';

  @override
  String get pfIntro =>
      'Choose what each programmable button does for every press type. Changes are written to the radio when you save.';

  @override
  String pfButtonLabel(int number) {
    return 'Button $number';
  }

  @override
  String get pfActionShort => 'Short press';

  @override
  String get pfActionLong => 'Long press';

  @override
  String get pfActionVeryLong => 'Very long press';

  @override
  String get pfActionVeryVeryLong => 'Very-very long press';

  @override
  String get pfActionDouble => 'Double press';

  @override
  String get pfActionTriple => 'Triple press';

  @override
  String get pfActionRepeat => 'Repeat';

  @override
  String get pfActionPressDown => 'Press down';

  @override
  String get pfActionRelease => 'Release';

  @override
  String get pfActionLongRelease => 'Long release';

  @override
  String get pfActionVeryLongRelease => 'Very long release';

  @override
  String get pfActionVeryVeryLongRelease => 'Very-very long release';

  @override
  String pfActionUnknown(int action) {
    return 'Action $action';
  }

  @override
  String get pfEffectDisabled => 'Disabled';

  @override
  String get pfEffectAlarm => 'Alarm';

  @override
  String get pfEffectAlarmAndMute => 'Alarm and Mute';

  @override
  String get pfEffectToggleOffline => 'Toggle Offline';

  @override
  String get pfEffectToggleRadioTx => 'Toggle Radio TX';

  @override
  String get pfEffectToggleTxPower => 'Toggle TX Power';

  @override
  String get pfEffectToggleFm => 'Toggle FM Radio';

  @override
  String get pfEffectPrevChannel => 'Previous Channel';

  @override
  String get pfEffectNextChannel => 'Next Channel';

  @override
  String get pfEffectTCall => 'T-Call (1750 Hz)';

  @override
  String get pfEffectPrevRegion => 'Previous Region';

  @override
  String get pfEffectNextRegion => 'Next Region';

  @override
  String get pfEffectToggleChScan => 'Toggle Channel Scan';

  @override
  String get pfEffectMainPtt => 'Main PTT';

  @override
  String get pfEffectSubPtt => 'Sub PTT';

  @override
  String get pfEffectToggleMonitor => 'Toggle Monitor';

  @override
  String get pfEffectBtPairing => 'Bluetooth Pairing';

  @override
  String get pfEffectToggleDoubleCh => 'Toggle Dual Channel';

  @override
  String get pfEffectToggleAbCh => 'Toggle A/B Channel';

  @override
  String get pfEffectSendLocation => 'Send Location';

  @override
  String get pfEffectOneClickLink => 'One-Click Link';

  @override
  String get pfEffectVolDown => 'Volume Down';

  @override
  String get pfEffectVolUp => 'Volume Up';

  @override
  String get pfEffectToggleMute => 'Toggle Mute';

  @override
  String pfEffectUnknown(int effect) {
    return 'Unknown ($effect)';
  }

  @override
  String get importChannelsTitle => 'Import Channels';

  @override
  String importChannelsTitleWith(String name) {
    return 'Import Channels — $name';
  }

  @override
  String get importIntro =>
      'Drag a channel from the left onto a radio slot, or select a channel and a slot and press the arrow. Tap the info icon for details. Channels are written to the radio only when you press OK.';

  @override
  String importOkCount(int count) {
    return 'OK ($count)';
  }

  @override
  String importImportedHeader(int count) {
    return 'Imported ($count)';
  }

  @override
  String get importNoChannels => 'No channels imported.';

  @override
  String importRadioChannelsHeader(int count) {
    return 'Radio Channels ($count)';
  }

  @override
  String get importNoRadioChannels => 'No radio channels.';

  @override
  String get importMoveTooltip => 'Move selected channel to selected slot';

  @override
  String get importCopyAllTooltip =>
      'Copy all imported channels to radio slots 1:1';

  @override
  String importChannelShort(int number) {
    return 'Ch $number';
  }

  @override
  String get importClearTooltip => 'Clear pending assignment';

  @override
  String get importChannelDetails => 'Channel details';

  @override
  String get riTitle => 'Radio Information';

  @override
  String get riNoRadioConnected => 'No radio connected';

  @override
  String get riConnectPrompt => 'Connect a radio to view its information.';

  @override
  String riRadioFallback(int id) {
    return 'Radio $id';
  }

  @override
  String get riSectionRadio => 'Radio';

  @override
  String get riSectionDeviceInfo => 'Device Information';

  @override
  String get riSectionDeviceStatus => 'Device Status';

  @override
  String get riSectionDeviceSettings => 'Device Settings';

  @override
  String get riSectionBss => 'BSS Settings';

  @override
  String get riSectionPosition => 'Position';

  @override
  String get riName => 'Name';

  @override
  String get riStatus => 'Status';

  @override
  String get riSettingsLabel => 'Settings';

  @override
  String get riNoData => 'No data';

  @override
  String get riNoGpsData => 'No GPS data';

  @override
  String get riNoGpsLock => 'No GPS lock';

  @override
  String get riGpsLocked => 'GPS locked';

  @override
  String get riTrue => 'True';

  @override
  String get riFalse => 'False';

  @override
  String get riPresent => 'Present';

  @override
  String get riNotPresent => 'Not-Present';

  @override
  String get riSupported => 'Supported';

  @override
  String get riNotSupported => 'Not-Supported';

  @override
  String get riCurrent => 'Current';

  @override
  String get riOff => 'Off';

  @override
  String riChannelValue(int number) {
    return 'Channel $number';
  }

  @override
  String riSeconds(int count) {
    return '$count second(s)';
  }

  @override
  String riMeters(String value) {
    return '$value meters';
  }

  @override
  String riDegrees(String value) {
    return '$value degrees';
  }

  @override
  String get riProductId => 'Product ID';

  @override
  String get riVendorId => 'Vendor ID';

  @override
  String get riDmrSupport => 'DMR Support';

  @override
  String get riGmrsSupport => 'GMRS Support';

  @override
  String get riHardwareSpeaker => 'Hardware Speaker';

  @override
  String get riHardwareVersion => 'Hardware Version';

  @override
  String get riSoftwareVersion => 'Software Version';

  @override
  String get riRegionCount => 'Region Count';

  @override
  String get riMediumPower => 'Medium Power';

  @override
  String get riChannelCount => 'Channel Count';

  @override
  String get riNoaa => 'NOAA';

  @override
  String get riWeather => 'Weather';

  @override
  String riWeatherChannel(int number) {
    return 'Weather $number';
  }

  @override
  String get riBroadcastFm => 'Broadcast FM';

  @override
  String get riRadioLabel => 'Radio';

  @override
  String get riVfo => 'VFO';

  @override
  String get riFreqRangeCount => 'Freq Range Count';

  @override
  String get riPowerOn => 'Power On';

  @override
  String get riInTx => 'In TX';

  @override
  String get riInRx => 'In RX';

  @override
  String get riDoubleChannelLabel => 'Double Channel';

  @override
  String get riScanning => 'Scanning';

  @override
  String get riCurrentChannelId => 'Current Channel ID';

  @override
  String get riGpsLockedLabel => 'GPS Locked';

  @override
  String get riHfpConnected => 'HFP Connected';

  @override
  String get riAocConnected => 'AOC Connected';

  @override
  String get riRssi => 'RSSI';

  @override
  String get riCurrentRegion => 'Current Region';

  @override
  String get riAccuracy => 'Accuracy';

  @override
  String get riReceivedTime => 'Received Time';

  @override
  String get riGpsTimeLocal => 'GPS Time Local';

  @override
  String get riGpsTimeUtcLabel => 'GPS Time UTC';

  @override
  String get tabDetach => 'Detach...';

  @override
  String get tabClear => 'Clear';

  @override
  String get tabSaveToFile => 'Save to File...';

  @override
  String get commonNoRadioConnected => 'No radio connected.';

  @override
  String errorOpeningFileDialog(String error) {
    return 'Error opening file dialog: $error';
  }

  @override
  String errorSavingFile(String error) {
    return 'Error saving file: $error';
  }

  @override
  String get debugSaveTitle => 'Save Debug Log';

  @override
  String debugLogSavedTo(String path) {
    return 'Debug log saved to $path';
  }

  @override
  String get debugShowBluetoothFrames => 'Show Bluetooth Frames';

  @override
  String get debugLoopbackMode => 'Loopback Mode';

  @override
  String get debugQueryDeviceNames => 'Query Device Names';

  @override
  String get debugRawCommand => 'Raw Command...';

  @override
  String get debugAutoScroll => 'Auto Scroll';

  @override
  String get debugFirmwareUpdate => 'Firmware Update...';

  @override
  String get debugShowBuiltInMenus => 'Show Built-in Menus';

  @override
  String get packetsCopyHex => 'Copy HEX packet';

  @override
  String get packetsHexCopied => 'HEX packet copied to clipboard';

  @override
  String get packetsSaveTitle => 'Save Packet Capture';

  @override
  String get packetsSaved => 'Packet capture saved';

  @override
  String packetsSavedTo(String path) {
    return 'Packet capture saved to $path';
  }

  @override
  String get packetsShowDecode => 'Show Packet Decode';

  @override
  String get packetsEmpty => 'No packets captured';

  @override
  String get packetsColTime => 'Time';

  @override
  String get packetsColChannel => 'Channel';

  @override
  String get packetsColData => 'Data';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonEditEllipsis => 'Edit...';

  @override
  String get commonAddEllipsis => 'Add...';

  @override
  String get commonExportEllipsis => 'Export...';

  @override
  String get commonImportEllipsis => 'Import...';

  @override
  String get contactsTypeGeneric => 'Generic Stations';

  @override
  String get contactsTypeAprs => 'APRS Stations';

  @override
  String get contactsTypeTerminal => 'Terminal Stations';

  @override
  String get contactsTypeBbs => 'BBS Stations';

  @override
  String get contactsTypeWinlink => 'Winlink Stations';

  @override
  String get contactsTypeTorrent => 'Torrent Stations';

  @override
  String get contactsTypeAgwpe => 'AGWPE Stations';

  @override
  String get contactsExists =>
      'A station with this callsign and type already exists';

  @override
  String get contactsRemovePrompt => 'Remove selected station?';

  @override
  String get contactsNoExport => 'There are no stations to export';

  @override
  String get contactsExportTitle => 'Export Stations';

  @override
  String get contactsImportTitle => 'Import Stations';

  @override
  String contactsExported(int count) {
    return 'Exported $count stations';
  }

  @override
  String contactsImported(int count) {
    return 'Imported $count stations';
  }

  @override
  String get contactsUnableOpen => 'Unable to open address book';

  @override
  String get contactsInvalid => 'Invalid address book';

  @override
  String get contactsColCallsign => 'Callsign';

  @override
  String get contactsColName => 'Name';

  @override
  String get contactsColDescription => 'Description';

  @override
  String terminalHeaderWith(String callsign) {
    return 'Terminal - $callsign';
  }

  @override
  String get terminalNoRadio => 'No available radio to connect.';

  @override
  String get terminalShowCallsign => 'Show Callsign';

  @override
  String get terminalWordWrap => 'Word Wrap';

  @override
  String get terminalWaitForConnection => 'Wait for Connection...';

  @override
  String get terminalSend => 'Send';

  @override
  String terminalConnectedTo(String callsign) {
    return 'Connected to $callsign';
  }

  @override
  String terminalConnectingTo(String callsign) {
    return 'Connecting to $callsign...';
  }

  @override
  String get terminalInvalidCallsignDest => 'Invalid callsign/destination';

  @override
  String get terminalInvalidCallsign => 'Invalid callsign';

  @override
  String get terminalNotConnected => 'Not connected';

  @override
  String terminalError(String error) {
    return 'Error: $error';
  }

  @override
  String get terminalBrotli =>
      'Received a Brotli-compressed packet (not supported)';

  @override
  String get audioSectionDevices => 'Devices';

  @override
  String get audioRefreshDevices => 'Refresh device list';

  @override
  String get audioOutput => 'Output';

  @override
  String get audioInput => 'Input';

  @override
  String get audioVolume => 'Volume';

  @override
  String get audioSquelch => 'Squelch';

  @override
  String get audioSectionComputer => 'Computer';

  @override
  String get audioApplication => 'Application';

  @override
  String get audioMaster => 'Master';

  @override
  String get audioMicGain => 'Mic Gain';

  @override
  String get audioMicNotAvailable =>
      'Microphone capture is not available on this platform.';

  @override
  String get audioMicNotSupported =>
      'Microphone capture is not supported here.';

  @override
  String get audioSpectRadio => 'Radio Spectrograph';

  @override
  String get audioSpectMic => 'Microphone Spectrograph';

  @override
  String get audioSpectNone => 'Spectrograph';

  @override
  String get audioSpectMenuNone => 'No Spectrograph';

  @override
  String get audioDartQuality => 'DART Reception Quality';

  @override
  String get audioDartSignalAnalysis => 'DART Signal Analysis';

  @override
  String get audioDefault => 'Default';

  @override
  String get audioMute => 'Mute';

  @override
  String get audioUnmute => 'Unmute';

  @override
  String get audioEnable => 'Enable';

  @override
  String get audioDisable => 'Disable';

  @override
  String get audioNa => 'N/A';

  @override
  String get bbsHeaderActive => 'BBS - Active';

  @override
  String get bbsActivate => 'Activate';

  @override
  String get bbsDeactivate => 'Deactivate';

  @override
  String get bbsViewTraffic => 'View Traffic';

  @override
  String get bbsClearTraffic => 'Clear Traffic';

  @override
  String get bbsClearStats => 'Clear Stats';

  @override
  String get bbsColCallSign => 'Call Sign';

  @override
  String get bbsColLastSeen => 'Last Seen';

  @override
  String get bbsColStats => 'Stats';

  @override
  String get bbsTraffic => 'Traffic';

  @override
  String get bbsJustNow => 'Just now';

  @override
  String bbsMinAgo(int n) {
    return '${n}m ago';
  }

  @override
  String bbsHoursAgo(int n) {
    return '${n}h ago';
  }

  @override
  String bbsDaysAgo(int n) {
    return '${n}d ago';
  }

  @override
  String get commonDelete => 'Delete';

  @override
  String get torrentAddFile => 'Add File';

  @override
  String get torrentShowDetails => 'Show Details';

  @override
  String get torrentFileSaved => 'File saved.';

  @override
  String get torrentFileDataUnavailable =>
      'Error saving file: file data not available';

  @override
  String get torrentUnknownError => 'Unknown error';

  @override
  String get torrentSaveTitle => 'Save Torrent File';

  @override
  String get torrentNoRadios => 'No radios connected. Connect a radio first.';

  @override
  String get torrentMultiRadio =>
      'Multi-radio torrent mode is not yet supported.';

  @override
  String get torrentDropSingle => 'Please drop a single file.';

  @override
  String get torrentDeletePrompt => 'Delete selected torrent file?';

  @override
  String get torrentPause => 'Pause';

  @override
  String get torrentShare => 'Share';

  @override
  String get torrentRequest => 'Request';

  @override
  String get torrentSaveAs => 'Save As...';

  @override
  String get torrentDropToShare => 'Drop a file to share';

  @override
  String get torrentNoFiles => 'No torrent files. Add or drop a file to share.';

  @override
  String get torrentUnknownSource => 'Unknown';

  @override
  String get torrentColFile => 'File';

  @override
  String get torrentColMode => 'Mode';

  @override
  String get torrentDetailFileName => 'File name';

  @override
  String get torrentDetailSource => 'Source';

  @override
  String get torrentDetailFileSize => 'File size';

  @override
  String torrentBytes(int count) {
    return '$count bytes';
  }

  @override
  String get torrentDetailCompression => 'Compression';

  @override
  String get torrentDetailBlocks => 'Blocks';

  @override
  String get torrentDetailsTitle => 'Torrent Details';

  @override
  String get torrentSelectPrompt => 'Select a torrent to view details';

  @override
  String get torrentModePaused => 'Paused';

  @override
  String get torrentModeSharing => 'Sharing';

  @override
  String get torrentModeRequesting => 'Requesting';

  @override
  String get torrentModeError => 'Error';

  @override
  String get torrentCompUnknown => 'Unknown';

  @override
  String get mailInbox => 'Inbox';

  @override
  String get mailOutbox => 'Outbox';

  @override
  String get mailDraft => 'Draft';

  @override
  String get mailSent => 'Sent';

  @override
  String get mailArchive => 'Archive';

  @override
  String get mailTrash => 'Trash';

  @override
  String get mailInternet => 'Internet';

  @override
  String get mailDeleteTitle => 'Delete Mail';

  @override
  String get mailMoveToTrashTitle => 'Move to Trash';

  @override
  String get mailDeletePermanent =>
      'Permanently delete the selected mail? This cannot be undone.';

  @override
  String get mailMoveToTrashPrompt => 'Move the selected mail to Trash?';

  @override
  String get mailMove => 'Move';

  @override
  String get mailOpen => 'Open';

  @override
  String get mailReply => 'Reply';

  @override
  String get mailReplyAll => 'Reply All';

  @override
  String get mailForward => 'Forward';

  @override
  String get mailShowPreview => 'Show Preview';

  @override
  String get mailBackup => 'Backup Mail...';

  @override
  String get mailRestore => 'Restore Mail...';

  @override
  String get mailShowTraffic => 'Show Traffic...';

  @override
  String mailBackupFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String get mailBackupTitle => 'Backup Mail';

  @override
  String get mailBackupSuccess => 'Backup completed successfully.';

  @override
  String get mailRestoreTitle => 'Restore Mail';

  @override
  String get mailRestoreUnableOpen => 'Unable to open backup file';

  @override
  String mailRestoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get mailNew => 'New';

  @override
  String get mailNewMail => 'New Mail';

  @override
  String get mailColTime => 'Time';

  @override
  String get mailColTo => 'To';

  @override
  String get mailColFrom => 'From';

  @override
  String get mailColSubject => 'Subject';

  @override
  String get mailSelectPreview => 'Select a message to preview';

  @override
  String get commonUnknown => 'Unknown';

  @override
  String get mapOfflineMode => 'Offline Mode';

  @override
  String get mapOfflineMap => 'Offline Map';

  @override
  String get mapCacheArea => 'Cache Area...';

  @override
  String get mapCenterGps => 'Center to GPS';

  @override
  String get mapShowTracks => 'Show Tracks';

  @override
  String get mapShowMarkers => 'Show Markers';

  @override
  String get mapShowAirplanes => 'Show Airplanes';

  @override
  String get mapLargeMarkers => 'Large Markers';

  @override
  String get mapShowContactsOnly => 'Show Contacts Only';

  @override
  String get mapFilterAll => 'All';

  @override
  String get mapFilterLast30 => 'Last 30 Minutes';

  @override
  String get mapFilterLastHour => 'Last Hour';

  @override
  String get mapFilterLast6 => 'Last 6 Hours';

  @override
  String get mapFilterLast12 => 'Last 12 Hours';

  @override
  String get mapFilterLast24 => 'Last 24 Hours';

  @override
  String get mapCacheTitle => 'Cache Map Area';

  @override
  String mapCachePrompt(int count, int minZoom, int maxZoom) {
    return 'Download $count tiles for zoom levels $minZoom–$maxZoom?\n\nThis will cache the selected area for offline use.';
  }

  @override
  String get mapDownloadingTitle => 'Downloading Tiles';

  @override
  String mapTilesProgress(int done, int total) {
    return '$done / $total tiles';
  }

  @override
  String get mapDragToSelect => 'Drag to select area to cache';

  @override
  String get aprsNoChannel => 'No radio with an APRS channel is available';

  @override
  String get aprsNoLoadedChannels =>
      'No radio with loaded channels is available';

  @override
  String get aprsDetails => 'Details...';

  @override
  String get aprsShowLocation => 'Show Location...';

  @override
  String get aprsSetReceiver => 'Set as receiver';

  @override
  String get aprsCopyMessage => 'Copy Message';

  @override
  String get aprsCopyCallsign => 'Copy Callsign';

  @override
  String get aprsCopyChannel => 'Copy Channel';

  @override
  String get aprsClearTitle => 'Clear APRS Messages';

  @override
  String get aprsClearPrompt =>
      'Clear all APRS messages? This also removes all APRS markers from the map. This cannot be undone.';

  @override
  String get aprsShowAll => 'Show All Messages';

  @override
  String get aprsSendSms => 'Send SMS Message...';

  @override
  String get aprsWeatherReport => 'Weather Report...';

  @override
  String get aprsBeaconSettingsMenu => 'Beacon Settings...';

  @override
  String get aprsDropShare => 'Drop to share this channel';

  @override
  String get aprsBeaconWarning =>
      'Beaconing is enabled on the current channel which is not recommended.';

  @override
  String aprsBeaconActive(String interval) {
    return 'Radio beacon is active, interval: $interval.';
  }

  @override
  String get aprsBeaconSettings => 'Beacon Settings';

  @override
  String aprsIntervalSeconds(int count) {
    return '$count seconds';
  }

  @override
  String get aprsIntervalMinute => '1 minute';

  @override
  String aprsIntervalMinutes(int count) {
    return '$count minutes';
  }

  @override
  String get aprsMissingChannel =>
      'No \"APRS\" channel is configured on the connected radio. Add an APRS channel to send and receive APRS messages.';

  @override
  String get aprsSetup => 'Set up';

  @override
  String get aprsTypeMessage => 'Type a message...';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonSend => 'Send';

  @override
  String commonSavedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String commsFailedLoadImage(String error) {
    return 'Failed to load image: $error';
  }

  @override
  String commsFailedSaveImage(String error) {
    return 'Failed to save image: $error';
  }

  @override
  String commsFailedEncodeSstv(String error) {
    return 'Failed to encode SSTV audio: $error';
  }

  @override
  String commsFailedLoadAudio(String error) {
    return 'Failed to load audio: $error';
  }

  @override
  String get commsUnsupportedWav => 'Unsupported or empty WAV file.';

  @override
  String get commsSstvWebUnavailable =>
      'SSTV image save/transmit is not available on web.';

  @override
  String get commsNoRadioVoice =>
      'No radio is connected for voice transmission.';

  @override
  String get commsSelectImageTitle => 'Select Image for SSTV';

  @override
  String get commsSelectWavTitle => 'Select WAV Audio';

  @override
  String get commsRecordingWebUnavailable =>
      'Recording playback from files is unavailable on web.';

  @override
  String get commsFileNoLongerExists => 'The file no longer exists.';

  @override
  String get commsSaveAsTitle => 'Save As';

  @override
  String get commsTransmitDisabledAprs =>
      'Transmit is disabled while VFO A is set to the APRS channel.';

  @override
  String get commsWaitTransmission =>
      'Please wait for the current transmission to finish.';

  @override
  String get commsConnectRadioChat =>
      'Connect a radio before sending a chat message.';

  @override
  String get commsEnableAudioMode =>
      'Enable audio (the Enable button) before sending in this mode.';

  @override
  String get commsMicNotSupported =>
      'Microphone capture is not supported on this platform.';

  @override
  String get commsConnectRadioPtt =>
      'Connect a radio before using push-to-talk.';

  @override
  String get commsEnableAudioPtt =>
      'Enable audio (the Enable button) before using push-to-talk.';

  @override
  String get commsSwitchChatShare => 'Switch to Chat mode to share a channel.';

  @override
  String get commsModePtt => 'PTT';

  @override
  String get commsModeChat => 'Chat';

  @override
  String get commsModeSpeak => 'Speak';

  @override
  String get commsModeMorse => 'Morse';

  @override
  String get commsModeDtmf => 'DTMF';

  @override
  String get commsRecordAudio => 'Record Audio';

  @override
  String get commsSendImage => 'Send Image...';

  @override
  String get commsSendAudio => 'Send Audio...';

  @override
  String get commsPttReleaseSettings => 'PTT Release Settings...';

  @override
  String get commsClearHistory => 'Clear History';

  @override
  String get commsShowImage => 'Show Image...';

  @override
  String get commsPlayRecording => 'Play Recording...';

  @override
  String get commsSaveAsMenu => 'Save as...';

  @override
  String get commsShowLocation => 'Show Location';

  @override
  String get commsClearHistoryPrompt =>
      'Are you sure you want to clear the voice history?';

  @override
  String get commsAudioMuted => 'Audio is muted.';

  @override
  String get commsUnmute => 'Un-mute';

  @override
  String get commsPttTransmitting => 'Transmitting...';

  @override
  String get commsPttHold => 'PTT - Hold to Transmit';

  @override
  String get commsDtmfHint => 'Enter DTMF digits (0-9, *, #)...';

  @override
  String get mailComposeNewTitle => 'New Message';

  @override
  String get mailComposeEditTitle => 'Edit Message';

  @override
  String get mailDiscardChanges => 'Discard changes to this message?';

  @override
  String get mailDiscardMessage => 'Discard this message?';

  @override
  String get mailDiscard => 'Discard';

  @override
  String get mailAddCc => 'Add Cc';

  @override
  String get mailCc => 'Cc';

  @override
  String get mailRemoveCc => 'Remove Cc';

  @override
  String get mailMessageLabel => 'Message';

  @override
  String get mailSaveDraft => 'Save Draft';

  @override
  String get mailAttachmentsLabel => 'Attachments';

  @override
  String get mailAddAttachment => 'Add Attachment';

  @override
  String get mailRemoveAttachment => 'Remove attachment';

  @override
  String get mailSaveAttachment => 'Save Attachment';

  @override
  String get mailAttachmentDropHint => 'Drag & drop files here to attach';

  @override
  String mailAttachmentReadFailed(String name) {
    return 'Failed to read file: $name';
  }

  @override
  String mailAttachmentSaved(String name) {
    return 'Saved \"$name\"';
  }

  @override
  String mailAttachmentLargeWarning(String size) {
    return 'Large attachments ($size) may take a long time to send over radio.';
  }

  @override
  String get smsTitle => 'Send SMS Message';

  @override
  String get smsPhoneNumber => 'Phone Number';

  @override
  String get smsIntro =>
      'You can send SMS messages to phones in the USA, Puerto Rico, Canada, Australia & UK as long as the phone number has already opted in to the service. You can opt-in at: ';

  @override
  String get locationTitle => 'Location';

  @override
  String get beaconIntro =>
      'Change how the radio will beacon information about itself including position, voltage and a custom message. Other stations around will be able to see this information.';

  @override
  String beaconRadio(String name) {
    return 'Radio: $name';
  }

  @override
  String get beaconSection => 'Beacon';

  @override
  String get beaconPacketFormat => 'Packet Format';

  @override
  String get beaconInterval => 'Beacon Interval';

  @override
  String get beaconAprsCallsign => 'APRS Callsign';

  @override
  String get beaconCallsignHint => 'Callsign - Station ID';

  @override
  String get beaconCallsignInvalid =>
      'Enter a valid callsign and station ID (e.g. W1AW-5)';

  @override
  String get beaconAprsMessage => 'APRS Message';

  @override
  String get beaconShareLocation => 'Should Share Location';

  @override
  String get beaconSendVoltage => 'Send Voltage';

  @override
  String get beaconAllowPositionCheck => 'Allow Position Check';

  @override
  String get beaconChannelCurrent => 'Current (Not Recommended)';

  @override
  String beaconEverySeconds(int n) {
    return 'Every $n seconds';
  }

  @override
  String beaconEveryMinutes(int n) {
    return 'Every $n minutes';
  }

  @override
  String get assConnectTerminal => 'Connect to Terminal Station';

  @override
  String get assConnectBbs => 'Connect to BBS Station';

  @override
  String get assConnectWinlink => 'Connect to Winlink Gateway';

  @override
  String get assConnectStation => 'Connect to Station';

  @override
  String get assNew => 'New…';

  @override
  String get attSelectFile => 'Select File to Share';

  @override
  String get attCompressing => 'Compressing...';

  @override
  String get attTitle => 'Add Torrent File';

  @override
  String get attSelect => 'Select...';

  @override
  String get attDescriptionOptional => 'Description (optional)';

  @override
  String get stationTitleVoice => 'Voice Station';

  @override
  String get stationTitleAprs => 'APRS Station';

  @override
  String get stationTitleTerminal => 'Terminal Station';

  @override
  String get stationTitleWinlink => 'Winlink Gateway';

  @override
  String get stationTitleGeneric => 'Station';

  @override
  String get stationTypeOptionVoice => 'Voice / Generic Station';

  @override
  String get stationTypeLabel => 'Station Type';

  @override
  String get stationAprsRoute => 'APRS Route';

  @override
  String get stationUseAuth => 'Use message authentication';

  @override
  String get stationAuthPassword => 'Auth Password';

  @override
  String get stationPasswordRequired => 'Password required';

  @override
  String get stationTerminalProtocol => 'Terminal Protocol';

  @override
  String get stationAx25Destination => 'AX.25 Destination (e.g. CALL-1)';

  @override
  String get stationAx25Invalid => 'Invalid AX.25 address';

  @override
  String get stationModem => 'Modem';

  @override
  String get apdTitle => 'APRS Packet Details';

  @override
  String get apdCopyAll => 'Copy All';

  @override
  String get apdCopyValue => 'Copy Value';

  @override
  String get apdValueCopied => 'Value copied';

  @override
  String get apdAllValuesCopied => 'All values copied';

  @override
  String get apdNoDetails => 'No details available.';

  @override
  String get apdShowLocation => 'Show Location...';

  @override
  String get acfgTitle => 'Set up APRS Channel';

  @override
  String get acfgIntro =>
      'The APRS frequency changes depending on the region of the world. Use this site to find the right frequency to configure the APRS channel.';

  @override
  String get acfgConfiguration => 'APRS Configuration';

  @override
  String get acfgFrequency => 'Frequency';

  @override
  String get acfgFrequencyHint => '144.39 in North America\n144.80 in Europe';

  @override
  String get acfgChannelOverwritten =>
      'The selected channel will be overwritten';

  @override
  String get sstvSendTitle => 'Send SSTV Image';

  @override
  String sstvSendTitleNamed(String name) {
    return 'Send SSTV Image - $name';
  }

  @override
  String get sstvMode => 'Mode:';

  @override
  String sstvTransmitTime(String time) {
    return 'Transmit time: ~$time';
  }

  @override
  String get msgdTitle => 'Message Details';

  @override
  String get msgdFieldType => 'Type';

  @override
  String get msgdFieldDirection => 'Direction';

  @override
  String get msgdFieldTime => 'Time';

  @override
  String get msgdFieldSource => 'Source';

  @override
  String get msgdFieldReceiver => 'Receiver';

  @override
  String get msgdFieldDuration => 'Duration';

  @override
  String get msgdFieldLatitude => 'Latitude';

  @override
  String get msgdFieldLongitude => 'Longitude';

  @override
  String get msgdFieldMessage => 'Message';

  @override
  String get msgdFieldFile => 'File';

  @override
  String get msgdDirReceived => 'Received';

  @override
  String get msgdDirSent => 'Sent';

  @override
  String get msgdTypeVoice => 'Voice';

  @override
  String get msgdTypeVoiceClip => 'Voice Clip';

  @override
  String get msgdTypeRecording => 'Recording';

  @override
  String get msgdTypeSstvPicture => 'SSTV Picture';

  @override
  String get msgdTypeIdentification => 'Identification';

  @override
  String get msgdTypeChatMessage => 'Chat Message';

  @override
  String get msgdTypeAx25Packet => 'AX.25 Packet';

  @override
  String get rpbFailedToLoad => 'Failed to load recording.';

  @override
  String get ivwFailedToLoad => 'Failed to load image.';

  @override
  String get rawTitle => 'Raw Radio Command';

  @override
  String get rawCommand => 'Command';

  @override
  String get rawHexPayload => 'HEX Payload (optional)';

  @override
  String get rawResponse => 'Response';

  @override
  String get identTitle => 'PTT Release Settings';

  @override
  String get identDescription =>
      'If enabled, sends your callsign and/or location information each time you release the PTT on the channel you are transmitting on.';

  @override
  String get identCallsignHint => 'Enter Callsign - Station ID';

  @override
  String get identSendCallsign => 'Send Callsign';

  @override
  String get identSendPosition => 'Send Position';

  @override
  String get commonOn => 'On';

  @override
  String get commonOff => 'Off';

  @override
  String get commonNone => 'None';

  @override
  String chChannelNumber(int n) {
    return 'Channel $n';
  }

  @override
  String chChShort(int n) {
    return 'Ch $n';
  }

  @override
  String get chMoreSettings => 'More settings';

  @override
  String get chChannelNameHint => 'Channel name';

  @override
  String get chFrequencyMhz => 'Frequency (MHz)';

  @override
  String get chReceiveMhz => 'Receive (MHz)';

  @override
  String get chTransmitMhz => 'Transmit (MHz)';

  @override
  String get chMode => 'Mode';

  @override
  String get chPower => 'Power';

  @override
  String get chBandwidth => 'Bandwidth';

  @override
  String get chReceiveTone => 'Receive tone (CTCSS / DCS)';

  @override
  String get chTransmitTone => 'Transmit tone (CTCSS / DCS)';

  @override
  String get chDisableTransmit => 'Disable transmit';

  @override
  String get chMute => 'Mute';

  @override
  String get chScan => 'Scan';

  @override
  String get chTalkAround => 'Talk around';

  @override
  String get chDeemphasis => 'De-emphasis';

  @override
  String get chPowerHigh => 'High';

  @override
  String get chPowerMedium => 'Medium';

  @override
  String get chPowerLow => 'Low';

  @override
  String get chBandwidthWide => '25 KHz Wide';

  @override
  String get chBandwidthNarrow => '12.5 KHz Narrow';

  @override
  String get chClearTitle => 'Clear channel';

  @override
  String chClearConfirm(int n) {
    return 'Clear channel $n?\n\nThis removes the frequency, name and settings from this slot on the radio.';
  }

  @override
  String get cdRxFrequency => 'RX Frequency';

  @override
  String get cdTxFrequency => 'TX Frequency';

  @override
  String get cdRxModulation => 'RX Modulation';

  @override
  String get cdTxModulation => 'TX Modulation';

  @override
  String get cdRxTone => 'RX Tone';

  @override
  String get cdTxTone => 'TX Tone';

  @override
  String get cdTxDisabled => 'TX Disabled';

  @override
  String get cdTalkAround => 'Talk Around';

  @override
  String get cdEmpty => '(empty)';

  @override
  String get cdBandwidthWide => '25 kHz (Wide)';

  @override
  String get cdBandwidthNarrow => '12.5 kHz (Narrow)';

  @override
  String get gpsDetailsTitle => 'GPS Details';

  @override
  String get gpsDisabled => 'GPS Disabled';

  @override
  String get gpsLock => 'GPS Lock';

  @override
  String get gpsNoLock => 'No GPS Lock';

  @override
  String get mdbgTitle => 'Winlink Traffic';

  @override
  String get mdbgNoTraffic => 'No traffic yet.';

  @override
  String get fwTitle => 'Radio Firmware Update';

  @override
  String get fwStatusInitial =>
      'Check online for a firmware update, or load a firmware file from disk.';

  @override
  String get fwErrNotConnected => 'Radio is not connected.';

  @override
  String get fwErrNoDeviceInfo =>
      'Radio device information is not available yet.';

  @override
  String get fwStatusChecking => 'Checking for a firmware update…';

  @override
  String get fwErrNoServerInfo =>
      'The vendor server did not return firmware information.';

  @override
  String fwUpdateAvailable(String version) {
    return 'A firmware update is available $version. Review the release notes below, then download to update.';
  }

  @override
  String fwErrCheckFailed(String error) {
    return 'Update check failed: $error';
  }

  @override
  String get fwPickTitle => 'Select Firmware File';

  @override
  String fwLoaded(String name, String size, String md5) {
    return 'Loaded $name: $size (MD5 $md5…).';
  }

  @override
  String fwErrLoadFailed(String error) {
    return 'Could not load firmware file: $error';
  }

  @override
  String get fwSaveTitle => 'Save Firmware File';

  @override
  String fwSavedTo(String path) {
    return 'Firmware saved to $path';
  }

  @override
  String fwErrSaveFailed(String error) {
    return 'Could not save firmware file: $error';
  }

  @override
  String get fwStatusDownloading => 'Downloading and assembling firmware…';

  @override
  String get fwProgressStarting => 'Starting…';

  @override
  String fwReady(String size, String md5) {
    return 'Firmware ready: $size (MD5 $md5…).';
  }

  @override
  String fwErrDownloadFailed(String error) {
    return 'Download failed: $error';
  }

  @override
  String get fwStatusWriting =>
      'Writing firmware to the radio. Do not power it off.';

  @override
  String get fwProgressTransferring => 'Transferring…';

  @override
  String fwErrTransferFailed(String error) {
    return 'Firmware transfer failed: $error';
  }

  @override
  String get fwStatusRebooting => 'Radio is rebooting. Reconnecting…';

  @override
  String get fwProgressWaitingRestart => 'Waiting for the radio to restart…';

  @override
  String fwErrReconnectFailed(String error) {
    return 'Reconnect failed after reboot: $error';
  }

  @override
  String get fwErrReconnectNull =>
      'Could not reconnect to the radio after it rebooted. The firmware was transferred but not confirmed. Reconnect manually and retry.';

  @override
  String get fwStatusFinalising => 'Finalising the update…';

  @override
  String get fwProgressConfirming => 'Confirming…';

  @override
  String fwErrConfirmFailed(String error) {
    return 'Update confirmation failed: $error';
  }

  @override
  String get fwStatusComplete =>
      'Firmware update complete! The radio is now running the new firmware.';

  @override
  String get fwProgressDownloadPatch => 'Downloading patch';

  @override
  String get fwProgressDownloadBase => 'Downloading base image';

  @override
  String get fwProgressAssemble => 'Assembling firmware';

  @override
  String fwProgressBytes(String label, String done, String total) {
    return '$label ($done / $total)';
  }

  @override
  String fwProgressTransferringBytes(String done, String total) {
    return 'Transferring ($done / $total)';
  }

  @override
  String fwCurrentFirmware(String version) {
    return 'Current firmware: $version';
  }

  @override
  String get fwErrGeneric => 'An error occurred.';

  @override
  String get fwIdleDisclosure =>
      'Checking online contacts the radio vendor\'s server (rpc.benshikj.com) and sends only your radio\'s product ID. Nothing is sent until you press Check for Update.';

  @override
  String get fwWhatsNew => 'What\'s new';

  @override
  String get fwConfirmWarning =>
      'Warning: keep the radio powered on, charged, and within Bluetooth range for the entire process. The radio will reboot partway through. Interrupting the update may require a manual recovery.';

  @override
  String get fwFromFile => 'From File…';

  @override
  String get fwCheckForUpdate => 'Check for Update';

  @override
  String get fwDownload => 'Download';

  @override
  String get fwSave => 'Save…';

  @override
  String get fwFlashNow => 'Flash Now';

  @override
  String get fwRetry => 'Retry';

  @override
  String get wxTitle => 'Request Weather Report';

  @override
  String get wxIntro => 'Request a weather report using APRS. ';

  @override
  String get wxLocation => 'Location';

  @override
  String get wxLocationHelper =>
      'US city/state or US zipcode, or coordinates 41.123/-121.334';

  @override
  String get wxTime => 'Time';

  @override
  String get wxReport => 'Report';

  @override
  String get wxToday => 'Today';

  @override
  String get wxTonight => 'Tonight';

  @override
  String get wxTomorrow => 'Tomorrow';

  @override
  String get wxTomorrowNight => 'Tomorrow night';

  @override
  String get wxMonday => 'Monday';

  @override
  String get wxMondayNight => 'Monday night';

  @override
  String get wxTuesday => 'Tuesday';

  @override
  String get wxTuesdayNight => 'Tuesday night';

  @override
  String get wxWednesday => 'Wednesday';

  @override
  String get wxWednesdayNight => 'Wednesday night';

  @override
  String get wxThursday => 'Thursday';

  @override
  String get wxThursdayNight => 'Thursday night';

  @override
  String get wxFriday => 'Friday';

  @override
  String get wxFridayNight => 'Friday night';

  @override
  String get wxSaturday => 'Saturday';

  @override
  String get wxSaturdayNight => 'Saturday night';

  @override
  String get wxSunday => 'Sunday';

  @override
  String get wxSundayNight => 'Sunday night';

  @override
  String get wxReportBrief => 'Brief, Short forecast, US only';

  @override
  String get wxReportFull => 'Full, More complete forecast, US only';

  @override
  String get wxReportCurrent => 'Current, Nearest NWS station, US only';

  @override
  String get wxReportMetar => 'METAR, ICAO station in METAR form';

  @override
  String get wxReportCwop => 'CWOP, Nearest CWOP station';
}
