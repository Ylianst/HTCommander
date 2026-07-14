import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('hi'),
    Locale('ja'),
    Locale('zh'),
  ];

  /// The application product name. Do not translate.
  ///
  /// In en, this message translates to:
  /// **'Handi-Talkie Commander'**
  String get appTitle;

  /// Top-level File menu label (labeled 'Radio' on macOS).
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get menuFile;

  /// Menu item to connect to a radio.
  ///
  /// In en, this message translates to:
  /// **'Connect...'**
  String get menuConnect;

  /// Menu item to disconnect from a radio.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get menuDisconnect;

  /// Menu item that opens the settings dialog.
  ///
  /// In en, this message translates to:
  /// **'Settings...'**
  String get menuSettings;

  /// Menu item that quits the application.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get menuExit;

  /// No description provided for @menuDualWatch.
  ///
  /// In en, this message translates to:
  /// **'Dual-Watch'**
  String get menuDualWatch;

  /// No description provided for @menuScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get menuScan;

  /// No description provided for @menuRegions.
  ///
  /// In en, this message translates to:
  /// **'Regions'**
  String get menuRegions;

  /// No description provided for @menuTrustedDevices.
  ///
  /// In en, this message translates to:
  /// **'Trusted Devices...'**
  String get menuTrustedDevices;

  /// No description provided for @menuButtons.
  ///
  /// In en, this message translates to:
  /// **'Buttons...'**
  String get menuButtons;

  /// No description provided for @menuExportChannels.
  ///
  /// In en, this message translates to:
  /// **'Export Channels...'**
  String get menuExportChannels;

  /// No description provided for @menuImportChannels.
  ///
  /// In en, this message translates to:
  /// **'Import Channels...'**
  String get menuImportChannels;

  /// No description provided for @menuMacRadio.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get menuMacRadio;

  /// No description provided for @menuMacDisplay.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get menuMacDisplay;

  /// Generic Close button.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Generic Cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Generic confirm/OK button.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// Button in the About dialog to check for application updates.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get aboutCheckForUpdates;

  /// Version and author block in the About dialog.
  ///
  /// In en, this message translates to:
  /// **'Version {version}\nYlian Saint-Hilaire, KK7VZT\nOpen Source, Apache 2.0 License'**
  String aboutVersionAuthor(String version);

  /// Label for the application language selector in Settings.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Helper text under the language selector.
  ///
  /// In en, this message translates to:
  /// **'Choose the language used by the application. \'System default\' follows your device language.'**
  String get settingsLanguageHint;

  /// Label for the application theme (light/dark) selector in Settings.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsThemeMode;

  /// Helper text under the theme selector.
  ///
  /// In en, this message translates to:
  /// **'Choose the light or dark appearance. \'System default\' follows your device setting.'**
  String get settingsThemeModeHint;

  /// Theme option that follows the operating system light/dark setting.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsThemeModeSystem;

  /// Light theme option.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeModeLight;

  /// Dark theme option.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeModeDark;

  /// Language option that follows the operating system locale.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// English language option.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// French language option.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get languageFrench;

  /// Spanish language option.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get languageSpanish;

  /// Chinese language option.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get languageChinese;

  /// Japanese language option.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get languageJapanese;

  /// Hindi language option.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get languageHindi;

  /// German language option.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get languageGerman;

  /// Top-level Audio menu label.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get menuAudio;

  /// Toggle that enables radio audio.
  ///
  /// In en, this message translates to:
  /// **'Audio Enabled'**
  String get menuAudioEnabled;

  /// Submenu selecting the software modem mode.
  ///
  /// In en, this message translates to:
  /// **'Software Modem'**
  String get menuSoftwareModem;

  /// Menu option that turns a modem off.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get menuModemDisabled;

  /// Submenu selecting the DART modem transmit level.
  ///
  /// In en, this message translates to:
  /// **'DART Transmit Level'**
  String get menuDartTransmitLevel;

  /// No description provided for @menuDartLevel0.
  ///
  /// In en, this message translates to:
  /// **'Level 0 (BPSK, LDPC 1/2)'**
  String get menuDartLevel0;

  /// No description provided for @menuDartLevel1.
  ///
  /// In en, this message translates to:
  /// **'Level 1 (QPSK, LDPC 1/2)'**
  String get menuDartLevel1;

  /// No description provided for @menuDartLevel2.
  ///
  /// In en, this message translates to:
  /// **'Level 2 (QPSK, LDPC 2/3)'**
  String get menuDartLevel2;

  /// No description provided for @menuDartLevel3.
  ///
  /// In en, this message translates to:
  /// **'Level 3 (8PSK, LDPC 2/3)'**
  String get menuDartLevel3;

  /// No description provided for @menuDartLevel4.
  ///
  /// In en, this message translates to:
  /// **'Level 4 (16QAM, LDPC 3/4)'**
  String get menuDartLevel4;

  /// No description provided for @menuDartLevel5.
  ///
  /// In en, this message translates to:
  /// **'Level 5 (16QAM, LDPC 5/6)'**
  String get menuDartLevel5;

  /// DART transmit levels. Only 'Level'/'Niveau' is translated; the modulation and coding descriptors are technical and kept as-is.
  ///
  /// In en, this message translates to:
  /// **'Level F (4-FSK, LDPC 1/2)'**
  String get menuDartLevelF;

  /// Submenu selecting the APRS modem mode.
  ///
  /// In en, this message translates to:
  /// **'APRS Modem'**
  String get menuAprsModem;

  /// Top-level View menu label (labeled 'Display' on macOS).
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get menuView;

  /// Radio label, used for the File menu on macOS and the View menu radio-panel toggle.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get menuRadio;

  /// Toggle that shows or hides the tab strip in compact mode.
  ///
  /// In en, this message translates to:
  /// **'Tabs'**
  String get menuTabs;

  /// Toggle that shows or hides the text names under tab icons.
  ///
  /// In en, this message translates to:
  /// **'Tab Names'**
  String get menuTabNames;

  /// Toggle that reveals every tab, including hidden ones.
  ///
  /// In en, this message translates to:
  /// **'Show All Tabs'**
  String get menuShowAllTabs;

  /// Toggle that shows all radio channels.
  ///
  /// In en, this message translates to:
  /// **'All Channels'**
  String get menuAllChannels;

  /// Top-level Help menu label.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get menuHelp;

  /// Menu item that opens the radio information dialog.
  ///
  /// In en, this message translates to:
  /// **'Radio Information...'**
  String get menuRadioInformation;

  /// Menu item that opens the GPS information dialog.
  ///
  /// In en, this message translates to:
  /// **'GPS Information...'**
  String get menuGpsInformation;

  /// Help menu item that checks for application updates.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates...'**
  String get menuCheckForUpdatesEllipsis;

  /// Menu item that opens the About dialog.
  ///
  /// In en, this message translates to:
  /// **'About...'**
  String get menuAbout;

  /// No description provided for @tabComms.
  ///
  /// In en, this message translates to:
  /// **'Comms'**
  String get tabComms;

  /// No description provided for @tabAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get tabAudio;

  /// No description provided for @tabAprs.
  ///
  /// In en, this message translates to:
  /// **'APRS'**
  String get tabAprs;

  /// No description provided for @tabMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get tabMap;

  /// No description provided for @tabMail.
  ///
  /// In en, this message translates to:
  /// **'Mail'**
  String get tabMail;

  /// No description provided for @tabTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get tabTerminal;

  /// No description provided for @tabContacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get tabContacts;

  /// No description provided for @tabBbs.
  ///
  /// In en, this message translates to:
  /// **'BBS'**
  String get tabBbs;

  /// No description provided for @tabTorrent.
  ///
  /// In en, this message translates to:
  /// **'Torrent'**
  String get tabTorrent;

  /// No description provided for @tabPackets.
  ///
  /// In en, this message translates to:
  /// **'Packets'**
  String get tabPackets;

  /// No description provided for @tabDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get tabDebug;

  /// Display names for the main navigation tabs.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get tabRadio;

  /// Radio connection state: not connected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get stateDisconnected;

  /// Radio connection state: connection in progress.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get stateConnecting;

  /// Radio connection state: connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get stateConnected;

  /// Radio connection state: connection attempt failed.
  ///
  /// In en, this message translates to:
  /// **'Unable to Connect'**
  String get stateUnableToConnect;

  /// Radio connection state: Bluetooth access was denied.
  ///
  /// In en, this message translates to:
  /// **'Access Denied'**
  String get stateAccessDenied;

  /// Radio connection state: prompt to pick one of several radios.
  ///
  /// In en, this message translates to:
  /// **'Select Radio'**
  String get stateSelectRadio;

  /// Status bar battery indicator.
  ///
  /// In en, this message translates to:
  /// **'Battery: {percent}%'**
  String statusBattery(int percent);

  /// Status message shown while verifying Bluetooth availability.
  ///
  /// In en, this message translates to:
  /// **'Checking Bluetooth...'**
  String get statusCheckingBluetooth;

  /// Status message when Bluetooth is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth not available'**
  String get statusBluetoothNotAvailable;

  /// Status message shown while scanning for radios.
  ///
  /// In en, this message translates to:
  /// **'Scanning for radios...'**
  String get statusScanningForRadios;

  /// Status message when a scan for radios fails.
  ///
  /// In en, this message translates to:
  /// **'Error scanning for radios'**
  String get statusErrorScanning;

  /// Status message when no compatible radios are found.
  ///
  /// In en, this message translates to:
  /// **'No compatible radios found'**
  String get statusNoCompatibleRadios;

  /// Status message when every detected radio is already connected.
  ///
  /// In en, this message translates to:
  /// **'All radios already connected'**
  String get statusAllRadiosConnected;

  /// Status message while connecting to a specific radio.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {name}...'**
  String statusConnectingTo(String name);

  /// Status message after connecting to a specific radio.
  ///
  /// In en, this message translates to:
  /// **'Connected to {name}'**
  String statusConnectedTo(String name);

  /// Status message when connecting to a radio fails.
  ///
  /// In en, this message translates to:
  /// **'Failed to connect to {name}'**
  String statusFailedToConnect(String name);

  /// Status message while disconnecting from a radio.
  ///
  /// In en, this message translates to:
  /// **'Disconnecting...'**
  String get statusDisconnecting;

  /// No description provided for @settingsTabLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get settingsTabLicense;

  /// No description provided for @settingsTabAprs.
  ///
  /// In en, this message translates to:
  /// **'APRS'**
  String get settingsTabAprs;

  /// No description provided for @settingsTabComms.
  ///
  /// In en, this message translates to:
  /// **'Comms'**
  String get settingsTabComms;

  /// No description provided for @settingsTabWinlink.
  ///
  /// In en, this message translates to:
  /// **'Winlink'**
  String get settingsTabWinlink;

  /// No description provided for @settingsTabServers.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get settingsTabServers;

  /// No description provided for @settingsTabMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get settingsTabMap;

  /// Settings dialog tab titles.
  ///
  /// In en, this message translates to:
  /// **'Limits'**
  String get settingsTabLimits;

  /// No description provided for @settingsTabApplication.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get settingsTabApplication;

  /// No description provided for @settingsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get settingsAdd;

  /// No description provided for @settingsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get settingsRemove;

  /// No description provided for @settingsDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get settingsDownload;

  /// No description provided for @settingsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get settingsRetry;

  /// No description provided for @settingsPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get settingsPreview;

  /// Generic 'None' option, e.g. for the station ID selector.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get settingsNone;

  /// No description provided for @settingsLicenseInfo.
  ///
  /// In en, this message translates to:
  /// **'In the United States, you need an amateur radio license to transmit. Visit the ARRL website for more information on getting licensed.'**
  String get settingsLicenseInfo;

  /// No description provided for @settingsCallSignStationId.
  ///
  /// In en, this message translates to:
  /// **'Call Sign & Station ID'**
  String get settingsCallSignStationId;

  /// No description provided for @settingsCallSign.
  ///
  /// In en, this message translates to:
  /// **'Call Sign'**
  String get settingsCallSign;

  /// No description provided for @settingsCallSignHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. W1AW'**
  String get settingsCallSignHint;

  /// No description provided for @settingsStationId.
  ///
  /// In en, this message translates to:
  /// **'Station ID'**
  String get settingsStationId;

  /// No description provided for @settingsAllowTransmit.
  ///
  /// In en, this message translates to:
  /// **'Allow this application to transmit'**
  String get settingsAllowTransmit;

  /// No description provided for @settingsCallSignHelp.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid call sign (at least 3 characters) to enable transmit'**
  String get settingsCallSignHelp;

  /// No description provided for @settingsAprsIntro.
  ///
  /// In en, this message translates to:
  /// **'Configure APRS routing paths for packet transmission.'**
  String get settingsAprsIntro;

  /// No description provided for @settingsAprsRoutes.
  ///
  /// In en, this message translates to:
  /// **'APRS Routes'**
  String get settingsAprsRoutes;

  /// No description provided for @settingsEditRoute.
  ///
  /// In en, this message translates to:
  /// **'Edit route'**
  String get settingsEditRoute;

  /// No description provided for @settingsEditRouteProtected.
  ///
  /// In en, this message translates to:
  /// **'Built-in route cannot be edited'**
  String get settingsEditRouteProtected;

  /// No description provided for @settingsDeleteRoute.
  ///
  /// In en, this message translates to:
  /// **'Delete route'**
  String get settingsDeleteRoute;

  /// No description provided for @settingsDeleteRouteProtected.
  ///
  /// In en, this message translates to:
  /// **'Built-in route cannot be removed'**
  String get settingsDeleteRouteProtected;

  /// No description provided for @settingsCommsIntro.
  ///
  /// In en, this message translates to:
  /// **'Configure speech recognition and text-to-speech settings.'**
  String get settingsCommsIntro;

  /// No description provided for @settingsSpeechToText.
  ///
  /// In en, this message translates to:
  /// **'Speech-to-Text'**
  String get settingsSpeechToText;

  /// No description provided for @settingsSpeechToTextInfo.
  ///
  /// In en, this message translates to:
  /// **'Transcribes received radio audio to text. Runs fully offline on this device; audio is never written to disk.'**
  String get settingsSpeechToTextInfo;

  /// No description provided for @settingsModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get settingsModel;

  /// No description provided for @settingsRecognitionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Recognition Language'**
  String get settingsRecognitionLanguage;

  /// No description provided for @settingsRecognitionLanguageHelp.
  ///
  /// In en, this message translates to:
  /// **'Language changes take effect the next time the engine starts.'**
  String get settingsRecognitionLanguageHelp;

  /// No description provided for @settingsStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get settingsStatus;

  /// No description provided for @settingsModelInstalled.
  ///
  /// In en, this message translates to:
  /// **'Model installed{suffix}'**
  String settingsModelInstalled(String suffix);

  /// No description provided for @settingsDownloadingModelPct.
  ///
  /// In en, this message translates to:
  /// **'Downloading model… {percent}%'**
  String settingsDownloadingModelPct(String percent);

  /// No description provided for @settingsDownloadingModel.
  ///
  /// In en, this message translates to:
  /// **'Downloading model…'**
  String get settingsDownloadingModel;

  /// No description provided for @settingsInstallingModelPct.
  ///
  /// In en, this message translates to:
  /// **'Installing model… {percent}%'**
  String settingsInstallingModelPct(String percent);

  /// No description provided for @settingsInstallingModel.
  ///
  /// In en, this message translates to:
  /// **'Installing model…'**
  String get settingsInstallingModel;

  /// No description provided for @settingsModelInstallError.
  ///
  /// In en, this message translates to:
  /// **'Model could not be installed.'**
  String get settingsModelInstallError;

  /// No description provided for @settingsModelNotDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Model not downloaded. {downloadLabel} happens once and is cached on this device.'**
  String settingsModelNotDownloaded(String downloadLabel);

  /// No description provided for @settingsBytesOf.
  ///
  /// In en, this message translates to:
  /// **'{received} of {total}'**
  String settingsBytesOf(String received, String total);

  /// No description provided for @settingsRemoveSttModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove speech-to-text model?'**
  String get settingsRemoveSttModelTitle;

  /// No description provided for @settingsRemoveSttModelBody.
  ///
  /// In en, this message translates to:
  /// **'The downloaded \"{name}\" model will be deleted to reclaim disk space. It will be downloaded again the next time it is used.'**
  String settingsRemoveSttModelBody(String name);

  /// No description provided for @settingsTextToSpeech.
  ///
  /// In en, this message translates to:
  /// **'Text-to-Speech'**
  String get settingsTextToSpeech;

  /// No description provided for @settingsTextToSpeechInfo.
  ///
  /// In en, this message translates to:
  /// **'Used when sending text in \"Speech\" mode from the Comms tab.'**
  String get settingsTextToSpeechInfo;

  /// No description provided for @settingsTtsUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Text-to-speech is unavailable'**
  String get settingsTtsUnavailableTitle;

  /// No description provided for @settingsVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get settingsVoice;

  /// No description provided for @settingsSpeechRate.
  ///
  /// In en, this message translates to:
  /// **'Speech Rate'**
  String get settingsSpeechRate;

  /// No description provided for @settingsPitch.
  ///
  /// In en, this message translates to:
  /// **'Pitch'**
  String get settingsPitch;

  /// No description provided for @settingsLoadingVoices.
  ///
  /// In en, this message translates to:
  /// **'Loading voices…'**
  String get settingsLoadingVoices;

  /// No description provided for @settingsSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get settingsSystemDefault;

  /// No description provided for @settingsLangAutoDetect.
  ///
  /// In en, this message translates to:
  /// **'Auto-detect'**
  String get settingsLangAutoDetect;

  /// No description provided for @settingsLangChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get settingsLangChinese;

  /// No description provided for @settingsLangJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get settingsLangJapanese;

  /// No description provided for @settingsLangKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get settingsLangKorean;

  /// No description provided for @settingsLangCantonese.
  ///
  /// In en, this message translates to:
  /// **'Cantonese'**
  String get settingsLangCantonese;

  /// No description provided for @settingsWinlinkIntro.
  ///
  /// In en, this message translates to:
  /// **'Configure Winlink email settings for radio email.'**
  String get settingsWinlinkIntro;

  /// No description provided for @settingsWinlinkAccount.
  ///
  /// In en, this message translates to:
  /// **'Winlink Account'**
  String get settingsWinlinkAccount;

  /// No description provided for @settingsAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsAccount;

  /// No description provided for @settingsWinlinkAccountHelp.
  ///
  /// In en, this message translates to:
  /// **'Based on your call sign from the License tab'**
  String get settingsWinlinkAccountHelp;

  /// No description provided for @settingsPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get settingsPassword;

  /// No description provided for @settingsUseStationIdWinlink.
  ///
  /// In en, this message translates to:
  /// **'Use Station ID for Winlink'**
  String get settingsUseStationIdWinlink;

  /// No description provided for @settingsServersIntro.
  ///
  /// In en, this message translates to:
  /// **'Configure local server settings.'**
  String get settingsServersIntro;

  /// No description provided for @settingsLocalServers.
  ///
  /// In en, this message translates to:
  /// **'Local Servers'**
  String get settingsLocalServers;

  /// No description provided for @settingsEnableWebServer.
  ///
  /// In en, this message translates to:
  /// **'Enable Web Server'**
  String get settingsEnableWebServer;

  /// No description provided for @settingsPort.
  ///
  /// In en, this message translates to:
  /// **'Port:'**
  String get settingsPort;

  /// No description provided for @settingsEnableAgwpeServer.
  ///
  /// In en, this message translates to:
  /// **'Enable AGWPE Server'**
  String get settingsEnableAgwpeServer;

  /// No description provided for @settingsMapIntroGps.
  ///
  /// In en, this message translates to:
  /// **'Configure GPS and airplane tracking data sources.'**
  String get settingsMapIntroGps;

  /// No description provided for @settingsMapIntroNoGps.
  ///
  /// In en, this message translates to:
  /// **'Configure airplane tracking data sources.'**
  String get settingsMapIntroNoGps;

  /// No description provided for @settingsGpsSerialPort.
  ///
  /// In en, this message translates to:
  /// **'GPS Serial Port'**
  String get settingsGpsSerialPort;

  /// No description provided for @settingsSerialPort.
  ///
  /// In en, this message translates to:
  /// **'Serial Port'**
  String get settingsSerialPort;

  /// No description provided for @settingsBaudRate.
  ///
  /// In en, this message translates to:
  /// **'Baud Rate'**
  String get settingsBaudRate;

  /// No description provided for @settingsShareGpsLocation.
  ///
  /// In en, this message translates to:
  /// **'Share serial GPS location'**
  String get settingsShareGpsLocation;

  /// No description provided for @settingsShareGpsLocationHelp.
  ///
  /// In en, this message translates to:
  /// **'Send the serial GPS position to the connected radio so it beacons your current location.'**
  String get settingsShareGpsLocationHelp;

  /// No description provided for @settingsAirplaneTracking.
  ///
  /// In en, this message translates to:
  /// **'Airplane Tracking (dump1090)'**
  String get settingsAirplaneTracking;

  /// No description provided for @settingsServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get settingsServerUrl;

  /// No description provided for @settingsTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get settingsTestConnection;

  /// No description provided for @settingsTest.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get settingsTest;

  /// No description provided for @settingsTestTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing...'**
  String get settingsTestTesting;

  /// No description provided for @settingsTestEmptyAddress.
  ///
  /// In en, this message translates to:
  /// **'Failed: empty server address'**
  String get settingsTestEmptyAddress;

  /// No description provided for @settingsTestFailedHttp.
  ///
  /// In en, this message translates to:
  /// **'Failed: HTTP {code}'**
  String settingsTestFailedHttp(int code);

  /// No description provided for @settingsTestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success, {count} aircraft found.'**
  String settingsTestSuccess(int count);

  /// No description provided for @settingsTestUnexpectedJson.
  ///
  /// In en, this message translates to:
  /// **'Failed: unexpected JSON format'**
  String get settingsTestUnexpectedJson;

  /// No description provided for @settingsTestTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Failed: request timed out'**
  String get settingsTestTimedOut;

  /// No description provided for @settingsTestInvalidJson.
  ///
  /// In en, this message translates to:
  /// **'Failed: invalid JSON response'**
  String get settingsTestInvalidJson;

  /// No description provided for @settingsTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get settingsTestFailed;

  /// No description provided for @settingsTestConnectionFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Test Connection Failed'**
  String get settingsTestConnectionFailedTitle;

  /// No description provided for @settingsLimitsIntro.
  ///
  /// In en, this message translates to:
  /// **'Limit how many historical items are kept across app restarts. Set to \"Unlimited\" to keep everything.'**
  String get settingsLimitsIntro;

  /// No description provided for @settingsHistoryLimits.
  ///
  /// In en, this message translates to:
  /// **'History Limits'**
  String get settingsHistoryLimits;

  /// No description provided for @settingsUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get settingsUnlimited;

  /// No description provided for @settingsLimitAprsMessages.
  ///
  /// In en, this message translates to:
  /// **'APRS Messages'**
  String get settingsLimitAprsMessages;

  /// No description provided for @settingsLimitPackets.
  ///
  /// In en, this message translates to:
  /// **'Packets'**
  String get settingsLimitPackets;

  /// No description provided for @settingsLimitSstvImages.
  ///
  /// In en, this message translates to:
  /// **'SSTV Images'**
  String get settingsLimitSstvImages;

  /// No description provided for @settingsLimitCommEvents.
  ///
  /// In en, this message translates to:
  /// **'Communication Events'**
  String get settingsLimitCommEvents;

  /// No description provided for @settingsLimitCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current: {count}'**
  String settingsLimitCurrent(int count);

  /// No description provided for @settingsLimitItemsDeleted.
  ///
  /// In en, this message translates to:
  /// **'{count} items will be deleted'**
  String settingsLimitItemsDeleted(int count);

  /// No description provided for @settingsDeleteHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete History Items?'**
  String get settingsDeleteHistoryTitle;

  /// No description provided for @settingsDeleteHistoryBody.
  ///
  /// In en, this message translates to:
  /// **'These limits will permanently delete the oldest:\n\n{items}\n\nThis cannot be undone.'**
  String settingsDeleteHistoryBody(String items);

  /// No description provided for @settingsDeleteAprsMessages.
  ///
  /// In en, this message translates to:
  /// **'{count} APRS messages'**
  String settingsDeleteAprsMessages(int count);

  /// No description provided for @settingsDeletePackets.
  ///
  /// In en, this message translates to:
  /// **'{count} packets'**
  String settingsDeletePackets(int count);

  /// No description provided for @settingsDeleteSstvImages.
  ///
  /// In en, this message translates to:
  /// **'{count} SSTV images'**
  String settingsDeleteSstvImages(int count);

  /// No description provided for @settingsDeleteCommEvents.
  ///
  /// In en, this message translates to:
  /// **'{count} communication events'**
  String settingsDeleteCommEvents(int count);

  /// No description provided for @settingsAddAprsRoute.
  ///
  /// In en, this message translates to:
  /// **'Add APRS Route'**
  String get settingsAddAprsRoute;

  /// No description provided for @settingsEditAprsRoute.
  ///
  /// In en, this message translates to:
  /// **'Edit APRS Route'**
  String get settingsEditAprsRoute;

  /// No description provided for @settingsName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get settingsName;

  /// No description provided for @settingsNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Standard'**
  String get settingsNameHint;

  /// No description provided for @settingsDuplicateRoute.
  ///
  /// In en, this message translates to:
  /// **'A route with this name already exists.'**
  String get settingsDuplicateRoute;

  /// No description provided for @settingsPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get settingsPath;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get commonError;

  /// No description provided for @commonConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get commonConnect;

  /// No description provided for @commonDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get commonDisconnect;

  /// No description provided for @commonRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get commonRename;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @connectScanError.
  ///
  /// In en, this message translates to:
  /// **'Failed to scan for Bluetooth devices: {error}'**
  String connectScanError(String error);

  /// No description provided for @connectNoRadiosTitle.
  ///
  /// In en, this message translates to:
  /// **'No Radios Found'**
  String get connectNoRadiosTitle;

  /// No description provided for @connectNoRadiosBody.
  ///
  /// In en, this message translates to:
  /// **'No compatible radio devices were found.\n\nMake sure your radio is powered on and Bluetooth is enabled.'**
  String get connectNoRadiosBody;

  /// No description provided for @connectAllConnectedTitle.
  ///
  /// In en, this message translates to:
  /// **'All Connected'**
  String get connectAllConnectedTitle;

  /// No description provided for @connectAllConnectedBody.
  ///
  /// In en, this message translates to:
  /// **'All detected radio devices are already connected.'**
  String get connectAllConnectedBody;

  /// No description provided for @connectBluetoothOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth Not Available'**
  String get connectBluetoothOffTitle;

  /// No description provided for @connectBluetoothOffBody.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is not available or is turned off.\n\nPlease enable Bluetooth in your device settings and try again.'**
  String get connectBluetoothOffBody;

  /// No description provided for @radioConnectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Radio Connection'**
  String get radioConnectionTitle;

  /// No description provided for @radioConnectionEmpty.
  ///
  /// In en, this message translates to:
  /// **'No compatible radios found.\nMake sure your radio is powered on and Bluetooth is enabled.'**
  String get radioConnectionEmpty;

  /// No description provided for @radioRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename Radio'**
  String get radioRenameTitle;

  /// No description provided for @radioRenamePrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter a custom name for this radio:'**
  String get radioRenamePrompt;

  /// No description provided for @radioRenameHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to use the default name'**
  String get radioRenameHint;

  /// No description provided for @updateTitle.
  ///
  /// In en, this message translates to:
  /// **'Software Update'**
  String get updateTitle;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates...'**
  String get updateChecking;

  /// No description provided for @updateVersionAvailable.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available.'**
  String updateVersionAvailable(String version);

  /// No description provided for @updateFreshDownload.
  ///
  /// In en, this message translates to:
  /// **'Version {version} requires a fresh download.'**
  String updateFreshDownload(String version);

  /// No description provided for @updateUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This version is no longer supported. Update to {version}.'**
  String updateUnsupported(String version);

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You are running the latest version.'**
  String get updateUpToDate;

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Update check failed: {error}'**
  String updateCheckFailed(String error);

  /// No description provided for @updateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading update...'**
  String get updateDownloading;

  /// No description provided for @updateDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Update downloaded. Ready to install.'**
  String get updateDownloaded;

  /// No description provided for @updateDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String updateDownloadFailed(String error);

  /// No description provided for @updateInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Install failed: {error}'**
  String updateInstallFailed(String error);

  /// No description provided for @updateDiagnosticsLog.
  ///
  /// In en, this message translates to:
  /// **'If the update does not complete, see the diagnostics log:\n{path}'**
  String updateDiagnosticsLog(String path);

  /// No description provided for @updateInstallRestart.
  ///
  /// In en, this message translates to:
  /// **'Install & Restart'**
  String get updateInstallRestart;

  /// No description provided for @updateCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check Again'**
  String get updateCheckAgain;

  /// No description provided for @regionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename Regions'**
  String get regionsTitle;

  /// No description provided for @regionsMaxChars.
  ///
  /// In en, this message translates to:
  /// **'Region names can be up to {count} characters.'**
  String regionsMaxChars(int count);

  /// No description provided for @regionLabel.
  ///
  /// In en, this message translates to:
  /// **'Region {number}'**
  String regionLabel(int number);

  /// No description provided for @gpsInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'GPS Information'**
  String get gpsInfoTitle;

  /// No description provided for @gpsSectionConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get gpsSectionConnection;

  /// No description provided for @gpsSectionFix.
  ///
  /// In en, this message translates to:
  /// **'GPS Fix'**
  String get gpsSectionFix;

  /// No description provided for @gpsSectionPosition.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get gpsSectionPosition;

  /// No description provided for @gpsSectionMotion.
  ///
  /// In en, this message translates to:
  /// **'Motion'**
  String get gpsSectionMotion;

  /// No description provided for @gpsSectionTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get gpsSectionTime;

  /// No description provided for @gpsPortStatus.
  ///
  /// In en, this message translates to:
  /// **'Port Status'**
  String get gpsPortStatus;

  /// No description provided for @gpsNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not Configured'**
  String get gpsNotConfigured;

  /// No description provided for @gpsOpenReceiving.
  ///
  /// In en, this message translates to:
  /// **'Open — Receiving Data'**
  String get gpsOpenReceiving;

  /// No description provided for @gpsPermDeniedLinux.
  ///
  /// In en, this message translates to:
  /// **'Permission denied — add your user to the \'dialout\' group (sudo usermod -aG dialout \$USER), then log out and back in.'**
  String get gpsPermDeniedLinux;

  /// No description provided for @gpsPermDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied — the app cannot access this port.'**
  String get gpsPermDenied;

  /// No description provided for @gpsPortError.
  ///
  /// In en, this message translates to:
  /// **'Port error — could not open the serial port.'**
  String get gpsPortError;

  /// No description provided for @gpsFix.
  ///
  /// In en, this message translates to:
  /// **'Fix'**
  String get gpsFix;

  /// No description provided for @gpsFixQuality.
  ///
  /// In en, this message translates to:
  /// **'Fix Quality'**
  String get gpsFixQuality;

  /// No description provided for @gpsSatellites.
  ///
  /// In en, this message translates to:
  /// **'Satellites'**
  String get gpsSatellites;

  /// No description provided for @gpsNoData.
  ///
  /// In en, this message translates to:
  /// **'No Data'**
  String get gpsNoData;

  /// No description provided for @gpsActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get gpsActive;

  /// No description provided for @gpsNoFix.
  ///
  /// In en, this message translates to:
  /// **'No Fix'**
  String get gpsNoFix;

  /// No description provided for @gpsQualGps.
  ///
  /// In en, this message translates to:
  /// **'GPS Fix (1)'**
  String get gpsQualGps;

  /// No description provided for @gpsQualDgps.
  ///
  /// In en, this message translates to:
  /// **'DGPS Fix (2)'**
  String get gpsQualDgps;

  /// No description provided for @gpsQualInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid (0)'**
  String get gpsQualInvalid;

  /// No description provided for @gpsQualUnknown.
  ///
  /// In en, this message translates to:
  /// **'{quality} (unknown)'**
  String gpsQualUnknown(int quality);

  /// No description provided for @gpsLatitude.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get gpsLatitude;

  /// No description provided for @gpsLatitudeDms.
  ///
  /// In en, this message translates to:
  /// **'Latitude (DMS)'**
  String get gpsLatitudeDms;

  /// No description provided for @gpsLongitude.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get gpsLongitude;

  /// No description provided for @gpsLongitudeDms.
  ///
  /// In en, this message translates to:
  /// **'Longitude (DMS)'**
  String get gpsLongitudeDms;

  /// No description provided for @gpsAltitude.
  ///
  /// In en, this message translates to:
  /// **'Altitude'**
  String get gpsAltitude;

  /// No description provided for @gpsSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get gpsSpeed;

  /// No description provided for @gpsHeading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get gpsHeading;

  /// No description provided for @gpsTimeUtc.
  ///
  /// In en, this message translates to:
  /// **'GPS Time (UTC)'**
  String get gpsTimeUtc;

  /// No description provided for @gpsDate.
  ///
  /// In en, this message translates to:
  /// **'GPS Date'**
  String get gpsDate;

  /// No description provided for @gpsLastUpdate.
  ///
  /// In en, this message translates to:
  /// **'Last Update'**
  String get gpsLastUpdate;

  /// No description provided for @trustedDevicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Trusted Devices'**
  String get trustedDevicesTitle;

  /// No description provided for @trustedRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove Trusted Device'**
  String get trustedRemoveTitle;

  /// No description provided for @trustedRemoveMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from the radio\'s trusted device list?'**
  String trustedRemoveMessage(String name);

  /// No description provided for @trustedNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No trusted devices found.'**
  String get trustedNoDevices;

  /// No description provided for @pfConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Configure Buttons'**
  String get pfConfigTitle;

  /// No description provided for @pfSaveToRadio.
  ///
  /// In en, this message translates to:
  /// **'Save to Radio'**
  String get pfSaveToRadio;

  /// No description provided for @pfNoRadio.
  ///
  /// In en, this message translates to:
  /// **'No radio connected.'**
  String get pfNoRadio;

  /// No description provided for @pfNoButtons.
  ///
  /// In en, this message translates to:
  /// **'This radio reported no programmable buttons.'**
  String get pfNoButtons;

  /// No description provided for @pfIntro.
  ///
  /// In en, this message translates to:
  /// **'Choose what each programmable button does for every press type. Changes are written to the radio when you save.'**
  String get pfIntro;

  /// No description provided for @pfButtonLabel.
  ///
  /// In en, this message translates to:
  /// **'Button {number}'**
  String pfButtonLabel(int number);

  /// No description provided for @pfActionShort.
  ///
  /// In en, this message translates to:
  /// **'Short press'**
  String get pfActionShort;

  /// No description provided for @pfActionLong.
  ///
  /// In en, this message translates to:
  /// **'Long press'**
  String get pfActionLong;

  /// No description provided for @pfActionVeryLong.
  ///
  /// In en, this message translates to:
  /// **'Very long press'**
  String get pfActionVeryLong;

  /// No description provided for @pfActionVeryVeryLong.
  ///
  /// In en, this message translates to:
  /// **'Very-very long press'**
  String get pfActionVeryVeryLong;

  /// No description provided for @pfActionDouble.
  ///
  /// In en, this message translates to:
  /// **'Double press'**
  String get pfActionDouble;

  /// No description provided for @pfActionTriple.
  ///
  /// In en, this message translates to:
  /// **'Triple press'**
  String get pfActionTriple;

  /// No description provided for @pfActionRepeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get pfActionRepeat;

  /// No description provided for @pfActionPressDown.
  ///
  /// In en, this message translates to:
  /// **'Press down'**
  String get pfActionPressDown;

  /// No description provided for @pfActionRelease.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get pfActionRelease;

  /// No description provided for @pfActionLongRelease.
  ///
  /// In en, this message translates to:
  /// **'Long release'**
  String get pfActionLongRelease;

  /// No description provided for @pfActionVeryLongRelease.
  ///
  /// In en, this message translates to:
  /// **'Very long release'**
  String get pfActionVeryLongRelease;

  /// No description provided for @pfActionVeryVeryLongRelease.
  ///
  /// In en, this message translates to:
  /// **'Very-very long release'**
  String get pfActionVeryVeryLongRelease;

  /// No description provided for @pfActionUnknown.
  ///
  /// In en, this message translates to:
  /// **'Action {action}'**
  String pfActionUnknown(int action);

  /// No description provided for @pfEffectDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get pfEffectDisabled;

  /// No description provided for @pfEffectAlarm.
  ///
  /// In en, this message translates to:
  /// **'Alarm'**
  String get pfEffectAlarm;

  /// No description provided for @pfEffectAlarmAndMute.
  ///
  /// In en, this message translates to:
  /// **'Alarm and Mute'**
  String get pfEffectAlarmAndMute;

  /// No description provided for @pfEffectToggleOffline.
  ///
  /// In en, this message translates to:
  /// **'Toggle Offline'**
  String get pfEffectToggleOffline;

  /// No description provided for @pfEffectToggleRadioTx.
  ///
  /// In en, this message translates to:
  /// **'Toggle Radio TX'**
  String get pfEffectToggleRadioTx;

  /// No description provided for @pfEffectToggleTxPower.
  ///
  /// In en, this message translates to:
  /// **'Toggle TX Power'**
  String get pfEffectToggleTxPower;

  /// No description provided for @pfEffectToggleFm.
  ///
  /// In en, this message translates to:
  /// **'Toggle FM Radio'**
  String get pfEffectToggleFm;

  /// No description provided for @pfEffectPrevChannel.
  ///
  /// In en, this message translates to:
  /// **'Previous Channel'**
  String get pfEffectPrevChannel;

  /// No description provided for @pfEffectNextChannel.
  ///
  /// In en, this message translates to:
  /// **'Next Channel'**
  String get pfEffectNextChannel;

  /// No description provided for @pfEffectTCall.
  ///
  /// In en, this message translates to:
  /// **'T-Call (1750 Hz)'**
  String get pfEffectTCall;

  /// No description provided for @pfEffectPrevRegion.
  ///
  /// In en, this message translates to:
  /// **'Previous Region'**
  String get pfEffectPrevRegion;

  /// No description provided for @pfEffectNextRegion.
  ///
  /// In en, this message translates to:
  /// **'Next Region'**
  String get pfEffectNextRegion;

  /// No description provided for @pfEffectToggleChScan.
  ///
  /// In en, this message translates to:
  /// **'Toggle Channel Scan'**
  String get pfEffectToggleChScan;

  /// No description provided for @pfEffectMainPtt.
  ///
  /// In en, this message translates to:
  /// **'Main PTT'**
  String get pfEffectMainPtt;

  /// No description provided for @pfEffectSubPtt.
  ///
  /// In en, this message translates to:
  /// **'Sub PTT'**
  String get pfEffectSubPtt;

  /// No description provided for @pfEffectToggleMonitor.
  ///
  /// In en, this message translates to:
  /// **'Toggle Monitor'**
  String get pfEffectToggleMonitor;

  /// No description provided for @pfEffectBtPairing.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth Pairing'**
  String get pfEffectBtPairing;

  /// No description provided for @pfEffectToggleDoubleCh.
  ///
  /// In en, this message translates to:
  /// **'Toggle Dual Channel'**
  String get pfEffectToggleDoubleCh;

  /// No description provided for @pfEffectToggleAbCh.
  ///
  /// In en, this message translates to:
  /// **'Toggle A/B Channel'**
  String get pfEffectToggleAbCh;

  /// No description provided for @pfEffectSendLocation.
  ///
  /// In en, this message translates to:
  /// **'Send Location'**
  String get pfEffectSendLocation;

  /// No description provided for @pfEffectOneClickLink.
  ///
  /// In en, this message translates to:
  /// **'One-Click Link'**
  String get pfEffectOneClickLink;

  /// No description provided for @pfEffectVolDown.
  ///
  /// In en, this message translates to:
  /// **'Volume Down'**
  String get pfEffectVolDown;

  /// No description provided for @pfEffectVolUp.
  ///
  /// In en, this message translates to:
  /// **'Volume Up'**
  String get pfEffectVolUp;

  /// No description provided for @pfEffectToggleMute.
  ///
  /// In en, this message translates to:
  /// **'Toggle Mute'**
  String get pfEffectToggleMute;

  /// No description provided for @pfEffectUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown ({effect})'**
  String pfEffectUnknown(int effect);

  /// No description provided for @importChannelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Channels'**
  String get importChannelsTitle;

  /// No description provided for @importChannelsTitleWith.
  ///
  /// In en, this message translates to:
  /// **'Import Channels — {name}'**
  String importChannelsTitleWith(String name);

  /// No description provided for @importIntro.
  ///
  /// In en, this message translates to:
  /// **'Drag a channel from the left onto a radio slot, or select a channel and a slot and press the arrow. Tap the info icon for details. Channels are written to the radio only when you press OK.'**
  String get importIntro;

  /// No description provided for @importOkCount.
  ///
  /// In en, this message translates to:
  /// **'OK ({count})'**
  String importOkCount(int count);

  /// No description provided for @importImportedHeader.
  ///
  /// In en, this message translates to:
  /// **'Imported ({count})'**
  String importImportedHeader(int count);

  /// No description provided for @importNoChannels.
  ///
  /// In en, this message translates to:
  /// **'No channels imported.'**
  String get importNoChannels;

  /// No description provided for @importRadioChannelsHeader.
  ///
  /// In en, this message translates to:
  /// **'Radio Channels ({count})'**
  String importRadioChannelsHeader(int count);

  /// No description provided for @importNoRadioChannels.
  ///
  /// In en, this message translates to:
  /// **'No radio channels.'**
  String get importNoRadioChannels;

  /// No description provided for @importMoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Move selected channel to selected slot'**
  String get importMoveTooltip;

  /// No description provided for @importCopyAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy all imported channels to radio slots 1:1'**
  String get importCopyAllTooltip;

  /// No description provided for @importChannelShort.
  ///
  /// In en, this message translates to:
  /// **'Ch {number}'**
  String importChannelShort(int number);

  /// No description provided for @importClearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear pending assignment'**
  String get importClearTooltip;

  /// No description provided for @importChannelDetails.
  ///
  /// In en, this message translates to:
  /// **'Channel details'**
  String get importChannelDetails;

  /// No description provided for @riTitle.
  ///
  /// In en, this message translates to:
  /// **'Radio Information'**
  String get riTitle;

  /// No description provided for @riNoRadioConnected.
  ///
  /// In en, this message translates to:
  /// **'No radio connected'**
  String get riNoRadioConnected;

  /// No description provided for @riConnectPrompt.
  ///
  /// In en, this message translates to:
  /// **'Connect a radio to view its information.'**
  String get riConnectPrompt;

  /// No description provided for @riRadioFallback.
  ///
  /// In en, this message translates to:
  /// **'Radio {id}'**
  String riRadioFallback(int id);

  /// No description provided for @riSectionRadio.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get riSectionRadio;

  /// No description provided for @riSectionDeviceInfo.
  ///
  /// In en, this message translates to:
  /// **'Device Information'**
  String get riSectionDeviceInfo;

  /// No description provided for @riSectionDeviceStatus.
  ///
  /// In en, this message translates to:
  /// **'Device Status'**
  String get riSectionDeviceStatus;

  /// No description provided for @riSectionDeviceSettings.
  ///
  /// In en, this message translates to:
  /// **'Device Settings'**
  String get riSectionDeviceSettings;

  /// No description provided for @riSectionBss.
  ///
  /// In en, this message translates to:
  /// **'BSS Settings'**
  String get riSectionBss;

  /// No description provided for @riSectionPosition.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get riSectionPosition;

  /// No description provided for @riName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get riName;

  /// No description provided for @riStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get riStatus;

  /// No description provided for @riSettingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get riSettingsLabel;

  /// No description provided for @riNoData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get riNoData;

  /// No description provided for @riNoGpsData.
  ///
  /// In en, this message translates to:
  /// **'No GPS data'**
  String get riNoGpsData;

  /// No description provided for @riNoGpsLock.
  ///
  /// In en, this message translates to:
  /// **'No GPS lock'**
  String get riNoGpsLock;

  /// No description provided for @riGpsLocked.
  ///
  /// In en, this message translates to:
  /// **'GPS locked'**
  String get riGpsLocked;

  /// No description provided for @riTrue.
  ///
  /// In en, this message translates to:
  /// **'True'**
  String get riTrue;

  /// No description provided for @riFalse.
  ///
  /// In en, this message translates to:
  /// **'False'**
  String get riFalse;

  /// No description provided for @riPresent.
  ///
  /// In en, this message translates to:
  /// **'Present'**
  String get riPresent;

  /// No description provided for @riNotPresent.
  ///
  /// In en, this message translates to:
  /// **'Not-Present'**
  String get riNotPresent;

  /// No description provided for @riSupported.
  ///
  /// In en, this message translates to:
  /// **'Supported'**
  String get riSupported;

  /// No description provided for @riNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Not-Supported'**
  String get riNotSupported;

  /// No description provided for @riCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get riCurrent;

  /// No description provided for @riOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get riOff;

  /// No description provided for @riChannelValue.
  ///
  /// In en, this message translates to:
  /// **'Channel {number}'**
  String riChannelValue(int number);

  /// No description provided for @riSeconds.
  ///
  /// In en, this message translates to:
  /// **'{count} second(s)'**
  String riSeconds(int count);

  /// No description provided for @riMeters.
  ///
  /// In en, this message translates to:
  /// **'{value} meters'**
  String riMeters(String value);

  /// No description provided for @riDegrees.
  ///
  /// In en, this message translates to:
  /// **'{value} degrees'**
  String riDegrees(String value);

  /// No description provided for @riProductId.
  ///
  /// In en, this message translates to:
  /// **'Product ID'**
  String get riProductId;

  /// No description provided for @riVendorId.
  ///
  /// In en, this message translates to:
  /// **'Vendor ID'**
  String get riVendorId;

  /// No description provided for @riDmrSupport.
  ///
  /// In en, this message translates to:
  /// **'DMR Support'**
  String get riDmrSupport;

  /// No description provided for @riGmrsSupport.
  ///
  /// In en, this message translates to:
  /// **'GMRS Support'**
  String get riGmrsSupport;

  /// No description provided for @riHardwareSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Hardware Speaker'**
  String get riHardwareSpeaker;

  /// No description provided for @riHardwareVersion.
  ///
  /// In en, this message translates to:
  /// **'Hardware Version'**
  String get riHardwareVersion;

  /// No description provided for @riSoftwareVersion.
  ///
  /// In en, this message translates to:
  /// **'Software Version'**
  String get riSoftwareVersion;

  /// No description provided for @riRegionCount.
  ///
  /// In en, this message translates to:
  /// **'Region Count'**
  String get riRegionCount;

  /// No description provided for @riMediumPower.
  ///
  /// In en, this message translates to:
  /// **'Medium Power'**
  String get riMediumPower;

  /// No description provided for @riChannelCount.
  ///
  /// In en, this message translates to:
  /// **'Channel Count'**
  String get riChannelCount;

  /// No description provided for @riNoaa.
  ///
  /// In en, this message translates to:
  /// **'NOAA'**
  String get riNoaa;

  /// No description provided for @riRadioLabel.
  ///
  /// In en, this message translates to:
  /// **'Radio'**
  String get riRadioLabel;

  /// No description provided for @riVfo.
  ///
  /// In en, this message translates to:
  /// **'VFO'**
  String get riVfo;

  /// No description provided for @riFreqRangeCount.
  ///
  /// In en, this message translates to:
  /// **'Freq Range Count'**
  String get riFreqRangeCount;

  /// No description provided for @riPowerOn.
  ///
  /// In en, this message translates to:
  /// **'Power On'**
  String get riPowerOn;

  /// No description provided for @riInTx.
  ///
  /// In en, this message translates to:
  /// **'In TX'**
  String get riInTx;

  /// No description provided for @riInRx.
  ///
  /// In en, this message translates to:
  /// **'In RX'**
  String get riInRx;

  /// No description provided for @riDoubleChannelLabel.
  ///
  /// In en, this message translates to:
  /// **'Double Channel'**
  String get riDoubleChannelLabel;

  /// No description provided for @riScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning'**
  String get riScanning;

  /// No description provided for @riCurrentChannelId.
  ///
  /// In en, this message translates to:
  /// **'Current Channel ID'**
  String get riCurrentChannelId;

  /// No description provided for @riGpsLockedLabel.
  ///
  /// In en, this message translates to:
  /// **'GPS Locked'**
  String get riGpsLockedLabel;

  /// No description provided for @riHfpConnected.
  ///
  /// In en, this message translates to:
  /// **'HFP Connected'**
  String get riHfpConnected;

  /// No description provided for @riAocConnected.
  ///
  /// In en, this message translates to:
  /// **'AOC Connected'**
  String get riAocConnected;

  /// No description provided for @riRssi.
  ///
  /// In en, this message translates to:
  /// **'RSSI'**
  String get riRssi;

  /// No description provided for @riCurrentRegion.
  ///
  /// In en, this message translates to:
  /// **'Current Region'**
  String get riCurrentRegion;

  /// No description provided for @riAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Accuracy'**
  String get riAccuracy;

  /// No description provided for @riReceivedTime.
  ///
  /// In en, this message translates to:
  /// **'Received Time'**
  String get riReceivedTime;

  /// No description provided for @riGpsTimeLocal.
  ///
  /// In en, this message translates to:
  /// **'GPS Time Local'**
  String get riGpsTimeLocal;

  /// No description provided for @riGpsTimeUtcLabel.
  ///
  /// In en, this message translates to:
  /// **'GPS Time UTC'**
  String get riGpsTimeUtcLabel;

  /// No description provided for @tabDetach.
  ///
  /// In en, this message translates to:
  /// **'Detach...'**
  String get tabDetach;

  /// No description provided for @tabClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get tabClear;

  /// No description provided for @tabSaveToFile.
  ///
  /// In en, this message translates to:
  /// **'Save to File...'**
  String get tabSaveToFile;

  /// No description provided for @commonNoRadioConnected.
  ///
  /// In en, this message translates to:
  /// **'No radio connected.'**
  String get commonNoRadioConnected;

  /// No description provided for @errorOpeningFileDialog.
  ///
  /// In en, this message translates to:
  /// **'Error opening file dialog: {error}'**
  String errorOpeningFileDialog(String error);

  /// No description provided for @errorSavingFile.
  ///
  /// In en, this message translates to:
  /// **'Error saving file: {error}'**
  String errorSavingFile(String error);

  /// No description provided for @debugSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Debug Log'**
  String get debugSaveTitle;

  /// No description provided for @debugLogSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Debug log saved to {path}'**
  String debugLogSavedTo(String path);

  /// No description provided for @debugShowBluetoothFrames.
  ///
  /// In en, this message translates to:
  /// **'Show Bluetooth Frames'**
  String get debugShowBluetoothFrames;

  /// No description provided for @debugLoopbackMode.
  ///
  /// In en, this message translates to:
  /// **'Loopback Mode'**
  String get debugLoopbackMode;

  /// No description provided for @debugQueryDeviceNames.
  ///
  /// In en, this message translates to:
  /// **'Query Device Names'**
  String get debugQueryDeviceNames;

  /// No description provided for @debugRawCommand.
  ///
  /// In en, this message translates to:
  /// **'Raw Command...'**
  String get debugRawCommand;

  /// No description provided for @debugAutoScroll.
  ///
  /// In en, this message translates to:
  /// **'Auto Scroll'**
  String get debugAutoScroll;

  /// No description provided for @debugFirmwareUpdate.
  ///
  /// In en, this message translates to:
  /// **'Firmware Update...'**
  String get debugFirmwareUpdate;

  /// No description provided for @debugShowBuiltInMenus.
  ///
  /// In en, this message translates to:
  /// **'Show Built-in Menus'**
  String get debugShowBuiltInMenus;

  /// No description provided for @packetsCopyHex.
  ///
  /// In en, this message translates to:
  /// **'Copy HEX packet'**
  String get packetsCopyHex;

  /// No description provided for @packetsHexCopied.
  ///
  /// In en, this message translates to:
  /// **'HEX packet copied to clipboard'**
  String get packetsHexCopied;

  /// No description provided for @packetsSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Packet Capture'**
  String get packetsSaveTitle;

  /// No description provided for @packetsSaved.
  ///
  /// In en, this message translates to:
  /// **'Packet capture saved'**
  String get packetsSaved;

  /// No description provided for @packetsSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Packet capture saved to {path}'**
  String packetsSavedTo(String path);

  /// No description provided for @packetsShowDecode.
  ///
  /// In en, this message translates to:
  /// **'Show Packet Decode'**
  String get packetsShowDecode;

  /// No description provided for @packetsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No packets captured'**
  String get packetsEmpty;

  /// No description provided for @packetsColTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get packetsColTime;

  /// No description provided for @packetsColChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get packetsColChannel;

  /// No description provided for @packetsColData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get packetsColData;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonEditEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Edit...'**
  String get commonEditEllipsis;

  /// No description provided for @commonAddEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Add...'**
  String get commonAddEllipsis;

  /// No description provided for @commonExportEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Export...'**
  String get commonExportEllipsis;

  /// No description provided for @commonImportEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Import...'**
  String get commonImportEllipsis;

  /// No description provided for @contactsTypeGeneric.
  ///
  /// In en, this message translates to:
  /// **'Generic Stations'**
  String get contactsTypeGeneric;

  /// No description provided for @contactsTypeAprs.
  ///
  /// In en, this message translates to:
  /// **'APRS Stations'**
  String get contactsTypeAprs;

  /// No description provided for @contactsTypeTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal Stations'**
  String get contactsTypeTerminal;

  /// No description provided for @contactsTypeBbs.
  ///
  /// In en, this message translates to:
  /// **'BBS Stations'**
  String get contactsTypeBbs;

  /// No description provided for @contactsTypeWinlink.
  ///
  /// In en, this message translates to:
  /// **'Winlink Stations'**
  String get contactsTypeWinlink;

  /// No description provided for @contactsTypeTorrent.
  ///
  /// In en, this message translates to:
  /// **'Torrent Stations'**
  String get contactsTypeTorrent;

  /// No description provided for @contactsTypeAgwpe.
  ///
  /// In en, this message translates to:
  /// **'AGWPE Stations'**
  String get contactsTypeAgwpe;

  /// No description provided for @contactsExists.
  ///
  /// In en, this message translates to:
  /// **'A station with this callsign and type already exists'**
  String get contactsExists;

  /// No description provided for @contactsRemovePrompt.
  ///
  /// In en, this message translates to:
  /// **'Remove selected station?'**
  String get contactsRemovePrompt;

  /// No description provided for @contactsNoExport.
  ///
  /// In en, this message translates to:
  /// **'There are no stations to export'**
  String get contactsNoExport;

  /// No description provided for @contactsExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Stations'**
  String get contactsExportTitle;

  /// No description provided for @contactsImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Stations'**
  String get contactsImportTitle;

  /// No description provided for @contactsExported.
  ///
  /// In en, this message translates to:
  /// **'Exported {count} stations'**
  String contactsExported(int count);

  /// No description provided for @contactsImported.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} stations'**
  String contactsImported(int count);

  /// No description provided for @contactsUnableOpen.
  ///
  /// In en, this message translates to:
  /// **'Unable to open address book'**
  String get contactsUnableOpen;

  /// No description provided for @contactsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid address book'**
  String get contactsInvalid;

  /// No description provided for @contactsColCallsign.
  ///
  /// In en, this message translates to:
  /// **'Callsign'**
  String get contactsColCallsign;

  /// No description provided for @contactsColName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get contactsColName;

  /// No description provided for @contactsColDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get contactsColDescription;

  /// No description provided for @terminalHeaderWith.
  ///
  /// In en, this message translates to:
  /// **'Terminal - {callsign}'**
  String terminalHeaderWith(String callsign);

  /// No description provided for @terminalNoRadio.
  ///
  /// In en, this message translates to:
  /// **'No available radio to connect.'**
  String get terminalNoRadio;

  /// No description provided for @terminalShowCallsign.
  ///
  /// In en, this message translates to:
  /// **'Show Callsign'**
  String get terminalShowCallsign;

  /// No description provided for @terminalWordWrap.
  ///
  /// In en, this message translates to:
  /// **'Word Wrap'**
  String get terminalWordWrap;

  /// No description provided for @terminalWaitForConnection.
  ///
  /// In en, this message translates to:
  /// **'Wait for Connection...'**
  String get terminalWaitForConnection;

  /// No description provided for @terminalSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get terminalSend;

  /// No description provided for @terminalConnectedTo.
  ///
  /// In en, this message translates to:
  /// **'Connected to {callsign}'**
  String terminalConnectedTo(String callsign);

  /// No description provided for @terminalConnectingTo.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {callsign}...'**
  String terminalConnectingTo(String callsign);

  /// No description provided for @terminalInvalidCallsignDest.
  ///
  /// In en, this message translates to:
  /// **'Invalid callsign/destination'**
  String get terminalInvalidCallsignDest;

  /// No description provided for @terminalInvalidCallsign.
  ///
  /// In en, this message translates to:
  /// **'Invalid callsign'**
  String get terminalInvalidCallsign;

  /// No description provided for @terminalNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get terminalNotConnected;

  /// No description provided for @terminalError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String terminalError(String error);

  /// No description provided for @terminalBrotli.
  ///
  /// In en, this message translates to:
  /// **'Received a Brotli-compressed packet (not supported)'**
  String get terminalBrotli;

  /// No description provided for @audioSectionDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get audioSectionDevices;

  /// No description provided for @audioRefreshDevices.
  ///
  /// In en, this message translates to:
  /// **'Refresh device list'**
  String get audioRefreshDevices;

  /// No description provided for @audioOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get audioOutput;

  /// No description provided for @audioInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get audioInput;

  /// No description provided for @audioVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get audioVolume;

  /// No description provided for @audioSquelch.
  ///
  /// In en, this message translates to:
  /// **'Squelch'**
  String get audioSquelch;

  /// No description provided for @audioSectionComputer.
  ///
  /// In en, this message translates to:
  /// **'Computer'**
  String get audioSectionComputer;

  /// No description provided for @audioApplication.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get audioApplication;

  /// No description provided for @audioMaster.
  ///
  /// In en, this message translates to:
  /// **'Master'**
  String get audioMaster;

  /// No description provided for @audioMicGain.
  ///
  /// In en, this message translates to:
  /// **'Mic Gain'**
  String get audioMicGain;

  /// No description provided for @audioMicNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Microphone capture is not available on this platform.'**
  String get audioMicNotAvailable;

  /// No description provided for @audioMicNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Microphone capture is not supported here.'**
  String get audioMicNotSupported;

  /// No description provided for @audioSpectRadio.
  ///
  /// In en, this message translates to:
  /// **'Radio Spectrograph'**
  String get audioSpectRadio;

  /// No description provided for @audioSpectMic.
  ///
  /// In en, this message translates to:
  /// **'Microphone Spectrograph'**
  String get audioSpectMic;

  /// No description provided for @audioSpectNone.
  ///
  /// In en, this message translates to:
  /// **'Spectrograph'**
  String get audioSpectNone;

  /// No description provided for @audioSpectMenuNone.
  ///
  /// In en, this message translates to:
  /// **'No Spectrograph'**
  String get audioSpectMenuNone;

  /// No description provided for @audioDartQuality.
  ///
  /// In en, this message translates to:
  /// **'DART Reception Quality'**
  String get audioDartQuality;

  /// No description provided for @audioDartSignalAnalysis.
  ///
  /// In en, this message translates to:
  /// **'DART Signal Analysis'**
  String get audioDartSignalAnalysis;

  /// No description provided for @audioDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get audioDefault;

  /// No description provided for @audioMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get audioMute;

  /// No description provided for @audioUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get audioUnmute;

  /// No description provided for @audioEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get audioEnable;

  /// No description provided for @audioDisable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get audioDisable;

  /// No description provided for @audioNa.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get audioNa;

  /// No description provided for @bbsHeaderActive.
  ///
  /// In en, this message translates to:
  /// **'BBS - Active'**
  String get bbsHeaderActive;

  /// No description provided for @bbsActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get bbsActivate;

  /// No description provided for @bbsDeactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get bbsDeactivate;

  /// No description provided for @bbsViewTraffic.
  ///
  /// In en, this message translates to:
  /// **'View Traffic'**
  String get bbsViewTraffic;

  /// No description provided for @bbsClearTraffic.
  ///
  /// In en, this message translates to:
  /// **'Clear Traffic'**
  String get bbsClearTraffic;

  /// No description provided for @bbsClearStats.
  ///
  /// In en, this message translates to:
  /// **'Clear Stats'**
  String get bbsClearStats;

  /// No description provided for @bbsColCallSign.
  ///
  /// In en, this message translates to:
  /// **'Call Sign'**
  String get bbsColCallSign;

  /// No description provided for @bbsColLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last Seen'**
  String get bbsColLastSeen;

  /// No description provided for @bbsColStats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get bbsColStats;

  /// No description provided for @bbsTraffic.
  ///
  /// In en, this message translates to:
  /// **'Traffic'**
  String get bbsTraffic;

  /// No description provided for @bbsJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get bbsJustNow;

  /// No description provided for @bbsMinAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}m ago'**
  String bbsMinAgo(int n);

  /// No description provided for @bbsHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}h ago'**
  String bbsHoursAgo(int n);

  /// No description provided for @bbsDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}d ago'**
  String bbsDaysAgo(int n);

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @torrentAddFile.
  ///
  /// In en, this message translates to:
  /// **'Add File'**
  String get torrentAddFile;

  /// No description provided for @torrentShowDetails.
  ///
  /// In en, this message translates to:
  /// **'Show Details'**
  String get torrentShowDetails;

  /// No description provided for @torrentFileSaved.
  ///
  /// In en, this message translates to:
  /// **'File saved.'**
  String get torrentFileSaved;

  /// No description provided for @torrentFileDataUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Error saving file: file data not available'**
  String get torrentFileDataUnavailable;

  /// No description provided for @torrentUnknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get torrentUnknownError;

  /// No description provided for @torrentSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Torrent File'**
  String get torrentSaveTitle;

  /// No description provided for @torrentNoRadios.
  ///
  /// In en, this message translates to:
  /// **'No radios connected. Connect a radio first.'**
  String get torrentNoRadios;

  /// No description provided for @torrentMultiRadio.
  ///
  /// In en, this message translates to:
  /// **'Multi-radio torrent mode is not yet supported.'**
  String get torrentMultiRadio;

  /// No description provided for @torrentDropSingle.
  ///
  /// In en, this message translates to:
  /// **'Please drop a single file.'**
  String get torrentDropSingle;

  /// No description provided for @torrentDeletePrompt.
  ///
  /// In en, this message translates to:
  /// **'Delete selected torrent file?'**
  String get torrentDeletePrompt;

  /// No description provided for @torrentPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get torrentPause;

  /// No description provided for @torrentShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get torrentShare;

  /// No description provided for @torrentRequest.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get torrentRequest;

  /// No description provided for @torrentSaveAs.
  ///
  /// In en, this message translates to:
  /// **'Save As...'**
  String get torrentSaveAs;

  /// No description provided for @torrentDropToShare.
  ///
  /// In en, this message translates to:
  /// **'Drop a file to share'**
  String get torrentDropToShare;

  /// No description provided for @torrentNoFiles.
  ///
  /// In en, this message translates to:
  /// **'No torrent files. Add or drop a file to share.'**
  String get torrentNoFiles;

  /// No description provided for @torrentUnknownSource.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get torrentUnknownSource;

  /// No description provided for @torrentColFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get torrentColFile;

  /// No description provided for @torrentColMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get torrentColMode;

  /// No description provided for @torrentDetailFileName.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get torrentDetailFileName;

  /// No description provided for @torrentDetailSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get torrentDetailSource;

  /// No description provided for @torrentDetailFileSize.
  ///
  /// In en, this message translates to:
  /// **'File size'**
  String get torrentDetailFileSize;

  /// No description provided for @torrentBytes.
  ///
  /// In en, this message translates to:
  /// **'{count} bytes'**
  String torrentBytes(int count);

  /// No description provided for @torrentDetailCompression.
  ///
  /// In en, this message translates to:
  /// **'Compression'**
  String get torrentDetailCompression;

  /// No description provided for @torrentDetailBlocks.
  ///
  /// In en, this message translates to:
  /// **'Blocks'**
  String get torrentDetailBlocks;

  /// No description provided for @torrentDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Torrent Details'**
  String get torrentDetailsTitle;

  /// No description provided for @torrentSelectPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select a torrent to view details'**
  String get torrentSelectPrompt;

  /// No description provided for @torrentModePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get torrentModePaused;

  /// No description provided for @torrentModeSharing.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get torrentModeSharing;

  /// No description provided for @torrentModeRequesting.
  ///
  /// In en, this message translates to:
  /// **'Requesting'**
  String get torrentModeRequesting;

  /// No description provided for @torrentModeError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get torrentModeError;

  /// No description provided for @torrentCompUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get torrentCompUnknown;

  /// No description provided for @mailInbox.
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get mailInbox;

  /// No description provided for @mailOutbox.
  ///
  /// In en, this message translates to:
  /// **'Outbox'**
  String get mailOutbox;

  /// No description provided for @mailDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get mailDraft;

  /// No description provided for @mailSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get mailSent;

  /// No description provided for @mailArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get mailArchive;

  /// No description provided for @mailTrash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get mailTrash;

  /// No description provided for @mailInternet.
  ///
  /// In en, this message translates to:
  /// **'Internet'**
  String get mailInternet;

  /// No description provided for @mailDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Mail'**
  String get mailDeleteTitle;

  /// No description provided for @mailMoveToTrashTitle.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get mailMoveToTrashTitle;

  /// No description provided for @mailDeletePermanent.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete the selected mail? This cannot be undone.'**
  String get mailDeletePermanent;

  /// No description provided for @mailMoveToTrashPrompt.
  ///
  /// In en, this message translates to:
  /// **'Move the selected mail to Trash?'**
  String get mailMoveToTrashPrompt;

  /// No description provided for @mailMove.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get mailMove;

  /// No description provided for @mailOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get mailOpen;

  /// No description provided for @mailReply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get mailReply;

  /// No description provided for @mailReplyAll.
  ///
  /// In en, this message translates to:
  /// **'Reply All'**
  String get mailReplyAll;

  /// No description provided for @mailForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get mailForward;

  /// No description provided for @mailShowPreview.
  ///
  /// In en, this message translates to:
  /// **'Show Preview'**
  String get mailShowPreview;

  /// No description provided for @mailBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup Mail...'**
  String get mailBackup;

  /// No description provided for @mailRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore Mail...'**
  String get mailRestore;

  /// No description provided for @mailShowTraffic.
  ///
  /// In en, this message translates to:
  /// **'Show Traffic...'**
  String get mailShowTraffic;

  /// No description provided for @mailBackupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String mailBackupFailed(String error);

  /// No description provided for @mailBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup Mail'**
  String get mailBackupTitle;

  /// No description provided for @mailBackupSuccess.
  ///
  /// In en, this message translates to:
  /// **'Backup completed successfully.'**
  String get mailBackupSuccess;

  /// No description provided for @mailRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore Mail'**
  String get mailRestoreTitle;

  /// No description provided for @mailRestoreUnableOpen.
  ///
  /// In en, this message translates to:
  /// **'Unable to open backup file'**
  String get mailRestoreUnableOpen;

  /// No description provided for @mailRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String mailRestoreFailed(String error);

  /// No description provided for @mailNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get mailNew;

  /// No description provided for @mailNewMail.
  ///
  /// In en, this message translates to:
  /// **'New Mail'**
  String get mailNewMail;

  /// No description provided for @mailColTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get mailColTime;

  /// No description provided for @mailColTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get mailColTo;

  /// No description provided for @mailColFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get mailColFrom;

  /// No description provided for @mailColSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get mailColSubject;

  /// No description provided for @mailSelectPreview.
  ///
  /// In en, this message translates to:
  /// **'Select a message to preview'**
  String get mailSelectPreview;

  /// No description provided for @commonUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get commonUnknown;

  /// No description provided for @mapOfflineMode.
  ///
  /// In en, this message translates to:
  /// **'Offline Mode'**
  String get mapOfflineMode;

  /// No description provided for @mapOfflineMap.
  ///
  /// In en, this message translates to:
  /// **'Offline Map'**
  String get mapOfflineMap;

  /// No description provided for @mapCacheArea.
  ///
  /// In en, this message translates to:
  /// **'Cache Area...'**
  String get mapCacheArea;

  /// No description provided for @mapCenterGps.
  ///
  /// In en, this message translates to:
  /// **'Center to GPS'**
  String get mapCenterGps;

  /// No description provided for @mapShowTracks.
  ///
  /// In en, this message translates to:
  /// **'Show Tracks'**
  String get mapShowTracks;

  /// No description provided for @mapShowMarkers.
  ///
  /// In en, this message translates to:
  /// **'Show Markers'**
  String get mapShowMarkers;

  /// No description provided for @mapShowAirplanes.
  ///
  /// In en, this message translates to:
  /// **'Show Airplanes'**
  String get mapShowAirplanes;

  /// No description provided for @mapLargeMarkers.
  ///
  /// In en, this message translates to:
  /// **'Large Markers'**
  String get mapLargeMarkers;

  /// No description provided for @mapShowContactsOnly.
  ///
  /// In en, this message translates to:
  /// **'Show Contacts Only'**
  String get mapShowContactsOnly;

  /// No description provided for @mapFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get mapFilterAll;

  /// No description provided for @mapFilterLast30.
  ///
  /// In en, this message translates to:
  /// **'Last 30 Minutes'**
  String get mapFilterLast30;

  /// No description provided for @mapFilterLastHour.
  ///
  /// In en, this message translates to:
  /// **'Last Hour'**
  String get mapFilterLastHour;

  /// No description provided for @mapFilterLast6.
  ///
  /// In en, this message translates to:
  /// **'Last 6 Hours'**
  String get mapFilterLast6;

  /// No description provided for @mapFilterLast12.
  ///
  /// In en, this message translates to:
  /// **'Last 12 Hours'**
  String get mapFilterLast12;

  /// No description provided for @mapFilterLast24.
  ///
  /// In en, this message translates to:
  /// **'Last 24 Hours'**
  String get mapFilterLast24;

  /// No description provided for @mapCacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Cache Map Area'**
  String get mapCacheTitle;

  /// No description provided for @mapCachePrompt.
  ///
  /// In en, this message translates to:
  /// **'Download {count} tiles for zoom levels {minZoom}–{maxZoom}?\n\nThis will cache the selected area for offline use.'**
  String mapCachePrompt(int count, int minZoom, int maxZoom);

  /// No description provided for @mapDownloadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloading Tiles'**
  String get mapDownloadingTitle;

  /// No description provided for @mapTilesProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total} tiles'**
  String mapTilesProgress(int done, int total);

  /// No description provided for @mapDragToSelect.
  ///
  /// In en, this message translates to:
  /// **'Drag to select area to cache'**
  String get mapDragToSelect;

  /// No description provided for @aprsNoChannel.
  ///
  /// In en, this message translates to:
  /// **'No radio with an APRS channel is available'**
  String get aprsNoChannel;

  /// No description provided for @aprsNoLoadedChannels.
  ///
  /// In en, this message translates to:
  /// **'No radio with loaded channels is available'**
  String get aprsNoLoadedChannels;

  /// No description provided for @aprsDetails.
  ///
  /// In en, this message translates to:
  /// **'Details...'**
  String get aprsDetails;

  /// No description provided for @aprsShowLocation.
  ///
  /// In en, this message translates to:
  /// **'Show Location...'**
  String get aprsShowLocation;

  /// No description provided for @aprsSetReceiver.
  ///
  /// In en, this message translates to:
  /// **'Set as receiver'**
  String get aprsSetReceiver;

  /// No description provided for @aprsCopyMessage.
  ///
  /// In en, this message translates to:
  /// **'Copy Message'**
  String get aprsCopyMessage;

  /// No description provided for @aprsCopyCallsign.
  ///
  /// In en, this message translates to:
  /// **'Copy Callsign'**
  String get aprsCopyCallsign;

  /// No description provided for @aprsClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear APRS Messages'**
  String get aprsClearTitle;

  /// No description provided for @aprsClearPrompt.
  ///
  /// In en, this message translates to:
  /// **'Clear all APRS messages? This also removes all APRS markers from the map. This cannot be undone.'**
  String get aprsClearPrompt;

  /// No description provided for @aprsShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show All Messages'**
  String get aprsShowAll;

  /// No description provided for @aprsSendSms.
  ///
  /// In en, this message translates to:
  /// **'Send SMS Message...'**
  String get aprsSendSms;

  /// No description provided for @aprsWeatherReport.
  ///
  /// In en, this message translates to:
  /// **'Weather Report...'**
  String get aprsWeatherReport;

  /// No description provided for @aprsBeaconSettingsMenu.
  ///
  /// In en, this message translates to:
  /// **'Beacon Settings...'**
  String get aprsBeaconSettingsMenu;

  /// No description provided for @aprsDropShare.
  ///
  /// In en, this message translates to:
  /// **'Drop to share this channel'**
  String get aprsDropShare;

  /// No description provided for @aprsBeaconWarning.
  ///
  /// In en, this message translates to:
  /// **'Beaconing is enabled on the current channel which is not recommended.'**
  String get aprsBeaconWarning;

  /// No description provided for @aprsBeaconActive.
  ///
  /// In en, this message translates to:
  /// **'Radio beacon is active, interval: {interval}.'**
  String aprsBeaconActive(String interval);

  /// No description provided for @aprsBeaconSettings.
  ///
  /// In en, this message translates to:
  /// **'Beacon Settings'**
  String get aprsBeaconSettings;

  /// No description provided for @aprsIntervalSeconds.
  ///
  /// In en, this message translates to:
  /// **'{count} seconds'**
  String aprsIntervalSeconds(int count);

  /// No description provided for @aprsIntervalMinute.
  ///
  /// In en, this message translates to:
  /// **'1 minute'**
  String get aprsIntervalMinute;

  /// No description provided for @aprsIntervalMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes'**
  String aprsIntervalMinutes(int count);

  /// No description provided for @aprsMissingChannel.
  ///
  /// In en, this message translates to:
  /// **'No \"APRS\" channel is configured on the connected radio. Add an APRS channel to send and receive APRS messages.'**
  String get aprsMissingChannel;

  /// No description provided for @aprsSetup.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get aprsSetup;

  /// No description provided for @aprsTypeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get aprsTypeMessage;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// No description provided for @commonSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get commonSend;

  /// No description provided for @commonSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String commonSavedTo(String path);

  /// No description provided for @commsFailedLoadImage.
  ///
  /// In en, this message translates to:
  /// **'Failed to load image: {error}'**
  String commsFailedLoadImage(String error);

  /// No description provided for @commsFailedSaveImage.
  ///
  /// In en, this message translates to:
  /// **'Failed to save image: {error}'**
  String commsFailedSaveImage(String error);

  /// No description provided for @commsFailedEncodeSstv.
  ///
  /// In en, this message translates to:
  /// **'Failed to encode SSTV audio: {error}'**
  String commsFailedEncodeSstv(String error);

  /// No description provided for @commsFailedLoadAudio.
  ///
  /// In en, this message translates to:
  /// **'Failed to load audio: {error}'**
  String commsFailedLoadAudio(String error);

  /// No description provided for @commsUnsupportedWav.
  ///
  /// In en, this message translates to:
  /// **'Unsupported or empty WAV file.'**
  String get commsUnsupportedWav;

  /// No description provided for @commsSstvWebUnavailable.
  ///
  /// In en, this message translates to:
  /// **'SSTV image save/transmit is not available on web.'**
  String get commsSstvWebUnavailable;

  /// No description provided for @commsNoRadioVoice.
  ///
  /// In en, this message translates to:
  /// **'No radio is connected for voice transmission.'**
  String get commsNoRadioVoice;

  /// No description provided for @commsSelectImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Image for SSTV'**
  String get commsSelectImageTitle;

  /// No description provided for @commsSelectWavTitle.
  ///
  /// In en, this message translates to:
  /// **'Select WAV Audio'**
  String get commsSelectWavTitle;

  /// No description provided for @commsRecordingWebUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Recording playback from files is unavailable on web.'**
  String get commsRecordingWebUnavailable;

  /// No description provided for @commsFileNoLongerExists.
  ///
  /// In en, this message translates to:
  /// **'The file no longer exists.'**
  String get commsFileNoLongerExists;

  /// No description provided for @commsSaveAsTitle.
  ///
  /// In en, this message translates to:
  /// **'Save As'**
  String get commsSaveAsTitle;

  /// No description provided for @commsTransmitDisabledAprs.
  ///
  /// In en, this message translates to:
  /// **'Transmit is disabled while VFO A is set to the APRS channel.'**
  String get commsTransmitDisabledAprs;

  /// No description provided for @commsWaitTransmission.
  ///
  /// In en, this message translates to:
  /// **'Please wait for the current transmission to finish.'**
  String get commsWaitTransmission;

  /// No description provided for @commsConnectRadioChat.
  ///
  /// In en, this message translates to:
  /// **'Connect a radio before sending a chat message.'**
  String get commsConnectRadioChat;

  /// No description provided for @commsEnableAudioMode.
  ///
  /// In en, this message translates to:
  /// **'Enable audio (the Enable button) before sending in this mode.'**
  String get commsEnableAudioMode;

  /// No description provided for @commsMicNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Microphone capture is not supported on this platform.'**
  String get commsMicNotSupported;

  /// No description provided for @commsConnectRadioPtt.
  ///
  /// In en, this message translates to:
  /// **'Connect a radio before using push-to-talk.'**
  String get commsConnectRadioPtt;

  /// No description provided for @commsEnableAudioPtt.
  ///
  /// In en, this message translates to:
  /// **'Enable audio (the Enable button) before using push-to-talk.'**
  String get commsEnableAudioPtt;

  /// No description provided for @commsSwitchChatShare.
  ///
  /// In en, this message translates to:
  /// **'Switch to Chat mode to share a channel.'**
  String get commsSwitchChatShare;

  /// No description provided for @commsModePtt.
  ///
  /// In en, this message translates to:
  /// **'PTT'**
  String get commsModePtt;

  /// No description provided for @commsModeChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get commsModeChat;

  /// No description provided for @commsModeSpeak.
  ///
  /// In en, this message translates to:
  /// **'Speak'**
  String get commsModeSpeak;

  /// No description provided for @commsModeMorse.
  ///
  /// In en, this message translates to:
  /// **'Morse'**
  String get commsModeMorse;

  /// No description provided for @commsModeDtmf.
  ///
  /// In en, this message translates to:
  /// **'DTMF'**
  String get commsModeDtmf;

  /// No description provided for @commsRecordAudio.
  ///
  /// In en, this message translates to:
  /// **'Record Audio'**
  String get commsRecordAudio;

  /// No description provided for @commsSendImage.
  ///
  /// In en, this message translates to:
  /// **'Send Image...'**
  String get commsSendImage;

  /// No description provided for @commsSendAudio.
  ///
  /// In en, this message translates to:
  /// **'Send Audio...'**
  String get commsSendAudio;

  /// No description provided for @commsPttReleaseSettings.
  ///
  /// In en, this message translates to:
  /// **'PTT Release Settings...'**
  String get commsPttReleaseSettings;

  /// No description provided for @commsClearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get commsClearHistory;

  /// No description provided for @commsShowImage.
  ///
  /// In en, this message translates to:
  /// **'Show Image...'**
  String get commsShowImage;

  /// No description provided for @commsPlayRecording.
  ///
  /// In en, this message translates to:
  /// **'Play Recording...'**
  String get commsPlayRecording;

  /// No description provided for @commsSaveAsMenu.
  ///
  /// In en, this message translates to:
  /// **'Save as...'**
  String get commsSaveAsMenu;

  /// No description provided for @commsShowLocation.
  ///
  /// In en, this message translates to:
  /// **'Show Location'**
  String get commsShowLocation;

  /// No description provided for @commsClearHistoryPrompt.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear the voice history?'**
  String get commsClearHistoryPrompt;

  /// No description provided for @commsAudioMuted.
  ///
  /// In en, this message translates to:
  /// **'Audio is muted.'**
  String get commsAudioMuted;

  /// No description provided for @commsUnmute.
  ///
  /// In en, this message translates to:
  /// **'Un-mute'**
  String get commsUnmute;

  /// No description provided for @commsPttTransmitting.
  ///
  /// In en, this message translates to:
  /// **'Transmitting...'**
  String get commsPttTransmitting;

  /// No description provided for @commsPttHold.
  ///
  /// In en, this message translates to:
  /// **'PTT - Hold to Transmit'**
  String get commsPttHold;

  /// No description provided for @commsDtmfHint.
  ///
  /// In en, this message translates to:
  /// **'Enter DTMF digits (0-9, *, #)...'**
  String get commsDtmfHint;

  /// No description provided for @mailComposeNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New Message'**
  String get mailComposeNewTitle;

  /// No description provided for @mailComposeEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Message'**
  String get mailComposeEditTitle;

  /// No description provided for @mailDiscardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard changes to this message?'**
  String get mailDiscardChanges;

  /// No description provided for @mailDiscardMessage.
  ///
  /// In en, this message translates to:
  /// **'Discard this message?'**
  String get mailDiscardMessage;

  /// No description provided for @mailDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get mailDiscard;

  /// No description provided for @mailAddCc.
  ///
  /// In en, this message translates to:
  /// **'Add Cc'**
  String get mailAddCc;

  /// No description provided for @mailCc.
  ///
  /// In en, this message translates to:
  /// **'Cc'**
  String get mailCc;

  /// No description provided for @mailRemoveCc.
  ///
  /// In en, this message translates to:
  /// **'Remove Cc'**
  String get mailRemoveCc;

  /// No description provided for @mailMessageLabel.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get mailMessageLabel;

  /// No description provided for @mailSaveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save Draft'**
  String get mailSaveDraft;

  /// No description provided for @smsTitle.
  ///
  /// In en, this message translates to:
  /// **'Send SMS Message'**
  String get smsTitle;

  /// No description provided for @smsPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get smsPhoneNumber;

  /// No description provided for @smsIntro.
  ///
  /// In en, this message translates to:
  /// **'You can send SMS messages to phones in the USA, Puerto Rico, Canada, Australia & UK as long as the phone number has already opted in to the service. You can opt-in at: '**
  String get smsIntro;

  /// No description provided for @locationTitle.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationTitle;

  /// No description provided for @beaconIntro.
  ///
  /// In en, this message translates to:
  /// **'Change how the radio will beacon information about itself including position, voltage and a custom message. Other stations around will be able to see this information.'**
  String get beaconIntro;

  /// No description provided for @beaconRadio.
  ///
  /// In en, this message translates to:
  /// **'Radio: {name}'**
  String beaconRadio(String name);

  /// No description provided for @beaconSection.
  ///
  /// In en, this message translates to:
  /// **'Beacon'**
  String get beaconSection;

  /// No description provided for @beaconPacketFormat.
  ///
  /// In en, this message translates to:
  /// **'Packet Format'**
  String get beaconPacketFormat;

  /// No description provided for @beaconInterval.
  ///
  /// In en, this message translates to:
  /// **'Beacon Interval'**
  String get beaconInterval;

  /// No description provided for @beaconAprsCallsign.
  ///
  /// In en, this message translates to:
  /// **'APRS Callsign'**
  String get beaconAprsCallsign;

  /// No description provided for @beaconCallsignHint.
  ///
  /// In en, this message translates to:
  /// **'Callsign - Station ID'**
  String get beaconCallsignHint;

  /// No description provided for @beaconCallsignInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid callsign and station ID (e.g. W1AW-5)'**
  String get beaconCallsignInvalid;

  /// No description provided for @beaconAprsMessage.
  ///
  /// In en, this message translates to:
  /// **'APRS Message'**
  String get beaconAprsMessage;

  /// No description provided for @beaconShareLocation.
  ///
  /// In en, this message translates to:
  /// **'Should Share Location'**
  String get beaconShareLocation;

  /// No description provided for @beaconSendVoltage.
  ///
  /// In en, this message translates to:
  /// **'Send Voltage'**
  String get beaconSendVoltage;

  /// No description provided for @beaconAllowPositionCheck.
  ///
  /// In en, this message translates to:
  /// **'Allow Position Check'**
  String get beaconAllowPositionCheck;

  /// No description provided for @beaconChannelCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current (Not Recommended)'**
  String get beaconChannelCurrent;

  /// No description provided for @beaconEverySeconds.
  ///
  /// In en, this message translates to:
  /// **'Every {n} seconds'**
  String beaconEverySeconds(int n);

  /// No description provided for @beaconEveryMinutes.
  ///
  /// In en, this message translates to:
  /// **'Every {n} minutes'**
  String beaconEveryMinutes(int n);

  /// No description provided for @assConnectTerminal.
  ///
  /// In en, this message translates to:
  /// **'Connect to Terminal Station'**
  String get assConnectTerminal;

  /// No description provided for @assConnectBbs.
  ///
  /// In en, this message translates to:
  /// **'Connect to BBS Station'**
  String get assConnectBbs;

  /// No description provided for @assConnectWinlink.
  ///
  /// In en, this message translates to:
  /// **'Connect to Winlink Gateway'**
  String get assConnectWinlink;

  /// No description provided for @assConnectStation.
  ///
  /// In en, this message translates to:
  /// **'Connect to Station'**
  String get assConnectStation;

  /// No description provided for @assNew.
  ///
  /// In en, this message translates to:
  /// **'New…'**
  String get assNew;

  /// No description provided for @attSelectFile.
  ///
  /// In en, this message translates to:
  /// **'Select File to Share'**
  String get attSelectFile;

  /// No description provided for @attCompressing.
  ///
  /// In en, this message translates to:
  /// **'Compressing...'**
  String get attCompressing;

  /// No description provided for @attTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Torrent File'**
  String get attTitle;

  /// No description provided for @attSelect.
  ///
  /// In en, this message translates to:
  /// **'Select...'**
  String get attSelect;

  /// No description provided for @attDescriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get attDescriptionOptional;

  /// No description provided for @stationTitleVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice Station'**
  String get stationTitleVoice;

  /// No description provided for @stationTitleAprs.
  ///
  /// In en, this message translates to:
  /// **'APRS Station'**
  String get stationTitleAprs;

  /// No description provided for @stationTitleTerminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal Station'**
  String get stationTitleTerminal;

  /// No description provided for @stationTitleWinlink.
  ///
  /// In en, this message translates to:
  /// **'Winlink Gateway'**
  String get stationTitleWinlink;

  /// No description provided for @stationTitleGeneric.
  ///
  /// In en, this message translates to:
  /// **'Station'**
  String get stationTitleGeneric;

  /// No description provided for @stationTypeOptionVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice / Generic Station'**
  String get stationTypeOptionVoice;

  /// No description provided for @stationTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Station Type'**
  String get stationTypeLabel;

  /// No description provided for @stationAprsRoute.
  ///
  /// In en, this message translates to:
  /// **'APRS Route'**
  String get stationAprsRoute;

  /// No description provided for @stationUseAuth.
  ///
  /// In en, this message translates to:
  /// **'Use message authentication'**
  String get stationUseAuth;

  /// No description provided for @stationAuthPassword.
  ///
  /// In en, this message translates to:
  /// **'Auth Password'**
  String get stationAuthPassword;

  /// No description provided for @stationPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password required'**
  String get stationPasswordRequired;

  /// No description provided for @stationTerminalProtocol.
  ///
  /// In en, this message translates to:
  /// **'Terminal Protocol'**
  String get stationTerminalProtocol;

  /// No description provided for @stationAx25Destination.
  ///
  /// In en, this message translates to:
  /// **'AX.25 Destination (e.g. CALL-1)'**
  String get stationAx25Destination;

  /// No description provided for @stationAx25Invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid AX.25 address'**
  String get stationAx25Invalid;

  /// No description provided for @stationModem.
  ///
  /// In en, this message translates to:
  /// **'Modem'**
  String get stationModem;

  /// No description provided for @apdTitle.
  ///
  /// In en, this message translates to:
  /// **'APRS Packet Details'**
  String get apdTitle;

  /// No description provided for @apdCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy All'**
  String get apdCopyAll;

  /// No description provided for @apdCopyValue.
  ///
  /// In en, this message translates to:
  /// **'Copy Value'**
  String get apdCopyValue;

  /// No description provided for @apdValueCopied.
  ///
  /// In en, this message translates to:
  /// **'Value copied'**
  String get apdValueCopied;

  /// No description provided for @apdAllValuesCopied.
  ///
  /// In en, this message translates to:
  /// **'All values copied'**
  String get apdAllValuesCopied;

  /// No description provided for @apdNoDetails.
  ///
  /// In en, this message translates to:
  /// **'No details available.'**
  String get apdNoDetails;

  /// No description provided for @apdShowLocation.
  ///
  /// In en, this message translates to:
  /// **'Show Location...'**
  String get apdShowLocation;

  /// No description provided for @acfgTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up APRS Channel'**
  String get acfgTitle;

  /// No description provided for @acfgIntro.
  ///
  /// In en, this message translates to:
  /// **'The APRS frequency changes depending on the region of the world. Use this site to find the right frequency to configure the APRS channel.'**
  String get acfgIntro;

  /// No description provided for @acfgConfiguration.
  ///
  /// In en, this message translates to:
  /// **'APRS Configuration'**
  String get acfgConfiguration;

  /// No description provided for @acfgFrequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get acfgFrequency;

  /// No description provided for @acfgFrequencyHint.
  ///
  /// In en, this message translates to:
  /// **'144.39 in North America\n144.80 in Europe'**
  String get acfgFrequencyHint;

  /// No description provided for @acfgChannelOverwritten.
  ///
  /// In en, this message translates to:
  /// **'The selected channel will be overwritten'**
  String get acfgChannelOverwritten;

  /// No description provided for @sstvSendTitle.
  ///
  /// In en, this message translates to:
  /// **'Send SSTV Image'**
  String get sstvSendTitle;

  /// No description provided for @sstvSendTitleNamed.
  ///
  /// In en, this message translates to:
  /// **'Send SSTV Image - {name}'**
  String sstvSendTitleNamed(String name);

  /// No description provided for @sstvMode.
  ///
  /// In en, this message translates to:
  /// **'Mode:'**
  String get sstvMode;

  /// No description provided for @sstvTransmitTime.
  ///
  /// In en, this message translates to:
  /// **'Transmit time: ~{time}'**
  String sstvTransmitTime(String time);

  /// No description provided for @msgdTitle.
  ///
  /// In en, this message translates to:
  /// **'Message Details'**
  String get msgdTitle;

  /// No description provided for @msgdFieldType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get msgdFieldType;

  /// No description provided for @msgdFieldDirection.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get msgdFieldDirection;

  /// No description provided for @msgdFieldTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get msgdFieldTime;

  /// No description provided for @msgdFieldSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get msgdFieldSource;

  /// No description provided for @msgdFieldReceiver.
  ///
  /// In en, this message translates to:
  /// **'Receiver'**
  String get msgdFieldReceiver;

  /// No description provided for @msgdFieldDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get msgdFieldDuration;

  /// No description provided for @msgdFieldLatitude.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get msgdFieldLatitude;

  /// No description provided for @msgdFieldLongitude.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get msgdFieldLongitude;

  /// No description provided for @msgdFieldMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get msgdFieldMessage;

  /// No description provided for @msgdFieldFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get msgdFieldFile;

  /// No description provided for @msgdDirReceived.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get msgdDirReceived;

  /// No description provided for @msgdDirSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get msgdDirSent;

  /// No description provided for @msgdTypeVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get msgdTypeVoice;

  /// No description provided for @msgdTypeVoiceClip.
  ///
  /// In en, this message translates to:
  /// **'Voice Clip'**
  String get msgdTypeVoiceClip;

  /// No description provided for @msgdTypeRecording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get msgdTypeRecording;

  /// No description provided for @msgdTypeSstvPicture.
  ///
  /// In en, this message translates to:
  /// **'SSTV Picture'**
  String get msgdTypeSstvPicture;

  /// No description provided for @msgdTypeIdentification.
  ///
  /// In en, this message translates to:
  /// **'Identification'**
  String get msgdTypeIdentification;

  /// No description provided for @msgdTypeChatMessage.
  ///
  /// In en, this message translates to:
  /// **'Chat Message'**
  String get msgdTypeChatMessage;

  /// No description provided for @msgdTypeAx25Packet.
  ///
  /// In en, this message translates to:
  /// **'AX.25 Packet'**
  String get msgdTypeAx25Packet;

  /// No description provided for @rpbFailedToLoad.
  ///
  /// In en, this message translates to:
  /// **'Failed to load recording.'**
  String get rpbFailedToLoad;

  /// No description provided for @ivwFailedToLoad.
  ///
  /// In en, this message translates to:
  /// **'Failed to load image.'**
  String get ivwFailedToLoad;

  /// No description provided for @rawTitle.
  ///
  /// In en, this message translates to:
  /// **'Raw Radio Command'**
  String get rawTitle;

  /// No description provided for @rawCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get rawCommand;

  /// No description provided for @rawHexPayload.
  ///
  /// In en, this message translates to:
  /// **'HEX Payload (optional)'**
  String get rawHexPayload;

  /// No description provided for @rawResponse.
  ///
  /// In en, this message translates to:
  /// **'Response'**
  String get rawResponse;

  /// No description provided for @identTitle.
  ///
  /// In en, this message translates to:
  /// **'PTT Release Settings'**
  String get identTitle;

  /// No description provided for @identDescription.
  ///
  /// In en, this message translates to:
  /// **'If enabled, sends your callsign and/or location information each time you release the PTT on the channel you are transmitting on.'**
  String get identDescription;

  /// No description provided for @identCallsignHint.
  ///
  /// In en, this message translates to:
  /// **'Enter Callsign - Station ID'**
  String get identCallsignHint;

  /// No description provided for @identSendCallsign.
  ///
  /// In en, this message translates to:
  /// **'Send Callsign'**
  String get identSendCallsign;

  /// No description provided for @identSendPosition.
  ///
  /// In en, this message translates to:
  /// **'Send Position'**
  String get identSendPosition;

  /// No description provided for @commonOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get commonOn;

  /// No description provided for @commonOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get commonOff;

  /// No description provided for @commonNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get commonNone;

  /// No description provided for @chChannelNumber.
  ///
  /// In en, this message translates to:
  /// **'Channel {n}'**
  String chChannelNumber(int n);

  /// No description provided for @chChShort.
  ///
  /// In en, this message translates to:
  /// **'Ch {n}'**
  String chChShort(int n);

  /// No description provided for @chMoreSettings.
  ///
  /// In en, this message translates to:
  /// **'More settings'**
  String get chMoreSettings;

  /// No description provided for @chChannelNameHint.
  ///
  /// In en, this message translates to:
  /// **'Channel name'**
  String get chChannelNameHint;

  /// No description provided for @chFrequencyMhz.
  ///
  /// In en, this message translates to:
  /// **'Frequency (MHz)'**
  String get chFrequencyMhz;

  /// No description provided for @chReceiveMhz.
  ///
  /// In en, this message translates to:
  /// **'Receive (MHz)'**
  String get chReceiveMhz;

  /// No description provided for @chTransmitMhz.
  ///
  /// In en, this message translates to:
  /// **'Transmit (MHz)'**
  String get chTransmitMhz;

  /// No description provided for @chMode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get chMode;

  /// No description provided for @chPower.
  ///
  /// In en, this message translates to:
  /// **'Power'**
  String get chPower;

  /// No description provided for @chBandwidth.
  ///
  /// In en, this message translates to:
  /// **'Bandwidth'**
  String get chBandwidth;

  /// No description provided for @chReceiveTone.
  ///
  /// In en, this message translates to:
  /// **'Receive tone (CTCSS / DCS)'**
  String get chReceiveTone;

  /// No description provided for @chTransmitTone.
  ///
  /// In en, this message translates to:
  /// **'Transmit tone (CTCSS / DCS)'**
  String get chTransmitTone;

  /// No description provided for @chDisableTransmit.
  ///
  /// In en, this message translates to:
  /// **'Disable transmit'**
  String get chDisableTransmit;

  /// No description provided for @chMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get chMute;

  /// No description provided for @chScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get chScan;

  /// No description provided for @chTalkAround.
  ///
  /// In en, this message translates to:
  /// **'Talk around'**
  String get chTalkAround;

  /// No description provided for @chDeemphasis.
  ///
  /// In en, this message translates to:
  /// **'De-emphasis'**
  String get chDeemphasis;

  /// No description provided for @chPowerHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get chPowerHigh;

  /// No description provided for @chPowerMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get chPowerMedium;

  /// No description provided for @chPowerLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get chPowerLow;

  /// No description provided for @chBandwidthWide.
  ///
  /// In en, this message translates to:
  /// **'25 KHz Wide'**
  String get chBandwidthWide;

  /// No description provided for @chBandwidthNarrow.
  ///
  /// In en, this message translates to:
  /// **'12.5 KHz Narrow'**
  String get chBandwidthNarrow;

  /// No description provided for @chClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear channel'**
  String get chClearTitle;

  /// No description provided for @chClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear channel {n}?\n\nThis removes the frequency, name and settings from this slot on the radio.'**
  String chClearConfirm(int n);

  /// No description provided for @cdRxFrequency.
  ///
  /// In en, this message translates to:
  /// **'RX Frequency'**
  String get cdRxFrequency;

  /// No description provided for @cdTxFrequency.
  ///
  /// In en, this message translates to:
  /// **'TX Frequency'**
  String get cdTxFrequency;

  /// No description provided for @cdRxModulation.
  ///
  /// In en, this message translates to:
  /// **'RX Modulation'**
  String get cdRxModulation;

  /// No description provided for @cdTxModulation.
  ///
  /// In en, this message translates to:
  /// **'TX Modulation'**
  String get cdTxModulation;

  /// No description provided for @cdRxTone.
  ///
  /// In en, this message translates to:
  /// **'RX Tone'**
  String get cdRxTone;

  /// No description provided for @cdTxTone.
  ///
  /// In en, this message translates to:
  /// **'TX Tone'**
  String get cdTxTone;

  /// No description provided for @cdTxDisabled.
  ///
  /// In en, this message translates to:
  /// **'TX Disabled'**
  String get cdTxDisabled;

  /// No description provided for @cdTalkAround.
  ///
  /// In en, this message translates to:
  /// **'Talk Around'**
  String get cdTalkAround;

  /// No description provided for @cdEmpty.
  ///
  /// In en, this message translates to:
  /// **'(empty)'**
  String get cdEmpty;

  /// No description provided for @cdBandwidthWide.
  ///
  /// In en, this message translates to:
  /// **'25 kHz (Wide)'**
  String get cdBandwidthWide;

  /// No description provided for @cdBandwidthNarrow.
  ///
  /// In en, this message translates to:
  /// **'12.5 kHz (Narrow)'**
  String get cdBandwidthNarrow;

  /// No description provided for @gpsDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'GPS Details'**
  String get gpsDetailsTitle;

  /// No description provided for @gpsDisabled.
  ///
  /// In en, this message translates to:
  /// **'GPS Disabled'**
  String get gpsDisabled;

  /// No description provided for @gpsLock.
  ///
  /// In en, this message translates to:
  /// **'GPS Lock'**
  String get gpsLock;

  /// No description provided for @gpsNoLock.
  ///
  /// In en, this message translates to:
  /// **'No GPS Lock'**
  String get gpsNoLock;

  /// No description provided for @mdbgTitle.
  ///
  /// In en, this message translates to:
  /// **'Winlink Traffic'**
  String get mdbgTitle;

  /// No description provided for @mdbgNoTraffic.
  ///
  /// In en, this message translates to:
  /// **'No traffic yet.'**
  String get mdbgNoTraffic;

  /// No description provided for @fwTitle.
  ///
  /// In en, this message translates to:
  /// **'Radio Firmware Update'**
  String get fwTitle;

  /// No description provided for @fwStatusInitial.
  ///
  /// In en, this message translates to:
  /// **'Check online for a firmware update, or load a firmware file from disk.'**
  String get fwStatusInitial;

  /// No description provided for @fwErrNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Radio is not connected.'**
  String get fwErrNotConnected;

  /// No description provided for @fwErrNoDeviceInfo.
  ///
  /// In en, this message translates to:
  /// **'Radio device information is not available yet.'**
  String get fwErrNoDeviceInfo;

  /// No description provided for @fwStatusChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for a firmware update…'**
  String get fwStatusChecking;

  /// No description provided for @fwErrNoServerInfo.
  ///
  /// In en, this message translates to:
  /// **'The vendor server did not return firmware information.'**
  String get fwErrNoServerInfo;

  /// No description provided for @fwUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'A firmware update is available {version}. Review the release notes below, then download to update.'**
  String fwUpdateAvailable(String version);

  /// No description provided for @fwErrCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Update check failed: {error}'**
  String fwErrCheckFailed(String error);

  /// No description provided for @fwPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Firmware File'**
  String get fwPickTitle;

  /// No description provided for @fwLoaded.
  ///
  /// In en, this message translates to:
  /// **'Loaded {name}: {size} (MD5 {md5}…).'**
  String fwLoaded(String name, String size, String md5);

  /// No description provided for @fwErrLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load firmware file: {error}'**
  String fwErrLoadFailed(String error);

  /// No description provided for @fwSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Firmware File'**
  String get fwSaveTitle;

  /// No description provided for @fwSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Firmware saved to {path}'**
  String fwSavedTo(String path);

  /// No description provided for @fwErrSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save firmware file: {error}'**
  String fwErrSaveFailed(String error);

  /// No description provided for @fwStatusDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading and assembling firmware…'**
  String get fwStatusDownloading;

  /// No description provided for @fwProgressStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get fwProgressStarting;

  /// No description provided for @fwReady.
  ///
  /// In en, this message translates to:
  /// **'Firmware ready: {size} (MD5 {md5}…).'**
  String fwReady(String size, String md5);

  /// No description provided for @fwErrDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String fwErrDownloadFailed(String error);

  /// No description provided for @fwStatusWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing firmware to the radio. Do not power it off.'**
  String get fwStatusWriting;

  /// No description provided for @fwProgressTransferring.
  ///
  /// In en, this message translates to:
  /// **'Transferring…'**
  String get fwProgressTransferring;

  /// No description provided for @fwErrTransferFailed.
  ///
  /// In en, this message translates to:
  /// **'Firmware transfer failed: {error}'**
  String fwErrTransferFailed(String error);

  /// No description provided for @fwStatusRebooting.
  ///
  /// In en, this message translates to:
  /// **'Radio is rebooting. Reconnecting…'**
  String get fwStatusRebooting;

  /// No description provided for @fwProgressWaitingRestart.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the radio to restart…'**
  String get fwProgressWaitingRestart;

  /// No description provided for @fwErrReconnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Reconnect failed after reboot: {error}'**
  String fwErrReconnectFailed(String error);

  /// No description provided for @fwErrReconnectNull.
  ///
  /// In en, this message translates to:
  /// **'Could not reconnect to the radio after it rebooted. The firmware was transferred but not confirmed. Reconnect manually and retry.'**
  String get fwErrReconnectNull;

  /// No description provided for @fwStatusFinalising.
  ///
  /// In en, this message translates to:
  /// **'Finalising the update…'**
  String get fwStatusFinalising;

  /// No description provided for @fwProgressConfirming.
  ///
  /// In en, this message translates to:
  /// **'Confirming…'**
  String get fwProgressConfirming;

  /// No description provided for @fwErrConfirmFailed.
  ///
  /// In en, this message translates to:
  /// **'Update confirmation failed: {error}'**
  String fwErrConfirmFailed(String error);

  /// No description provided for @fwStatusComplete.
  ///
  /// In en, this message translates to:
  /// **'Firmware update complete! The radio is now running the new firmware.'**
  String get fwStatusComplete;

  /// No description provided for @fwProgressDownloadPatch.
  ///
  /// In en, this message translates to:
  /// **'Downloading patch'**
  String get fwProgressDownloadPatch;

  /// No description provided for @fwProgressDownloadBase.
  ///
  /// In en, this message translates to:
  /// **'Downloading base image'**
  String get fwProgressDownloadBase;

  /// No description provided for @fwProgressAssemble.
  ///
  /// In en, this message translates to:
  /// **'Assembling firmware'**
  String get fwProgressAssemble;

  /// No description provided for @fwProgressBytes.
  ///
  /// In en, this message translates to:
  /// **'{label} ({done} / {total})'**
  String fwProgressBytes(String label, String done, String total);

  /// No description provided for @fwProgressTransferringBytes.
  ///
  /// In en, this message translates to:
  /// **'Transferring ({done} / {total})'**
  String fwProgressTransferringBytes(String done, String total);

  /// No description provided for @fwCurrentFirmware.
  ///
  /// In en, this message translates to:
  /// **'Current firmware: {version}'**
  String fwCurrentFirmware(String version);

  /// No description provided for @fwErrGeneric.
  ///
  /// In en, this message translates to:
  /// **'An error occurred.'**
  String get fwErrGeneric;

  /// No description provided for @fwIdleDisclosure.
  ///
  /// In en, this message translates to:
  /// **'Checking online contacts the radio vendor\'s server (rpc.benshikj.com) and sends only your radio\'s product ID. Nothing is sent until you press Check for Update.'**
  String get fwIdleDisclosure;

  /// No description provided for @fwWhatsNew.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get fwWhatsNew;

  /// No description provided for @fwConfirmWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning: keep the radio powered on, charged, and within Bluetooth range for the entire process. The radio will reboot partway through. Interrupting the update may require a manual recovery.'**
  String get fwConfirmWarning;

  /// No description provided for @fwFromFile.
  ///
  /// In en, this message translates to:
  /// **'From File…'**
  String get fwFromFile;

  /// No description provided for @fwCheckForUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check for Update'**
  String get fwCheckForUpdate;

  /// No description provided for @fwDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get fwDownload;

  /// No description provided for @fwSave.
  ///
  /// In en, this message translates to:
  /// **'Save…'**
  String get fwSave;

  /// No description provided for @fwFlashNow.
  ///
  /// In en, this message translates to:
  /// **'Flash Now'**
  String get fwFlashNow;

  /// No description provided for @fwRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get fwRetry;

  /// No description provided for @wxTitle.
  ///
  /// In en, this message translates to:
  /// **'Request Weather Report'**
  String get wxTitle;

  /// No description provided for @wxIntro.
  ///
  /// In en, this message translates to:
  /// **'Request a weather report using APRS. '**
  String get wxIntro;

  /// No description provided for @wxLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get wxLocation;

  /// No description provided for @wxLocationHelper.
  ///
  /// In en, this message translates to:
  /// **'US city/state or US zipcode, or coordinates 41.123/-121.334'**
  String get wxLocationHelper;

  /// No description provided for @wxTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get wxTime;

  /// No description provided for @wxReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get wxReport;

  /// No description provided for @wxToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get wxToday;

  /// No description provided for @wxTonight.
  ///
  /// In en, this message translates to:
  /// **'Tonight'**
  String get wxTonight;

  /// No description provided for @wxTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get wxTomorrow;

  /// No description provided for @wxTomorrowNight.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow night'**
  String get wxTomorrowNight;

  /// No description provided for @wxMonday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get wxMonday;

  /// No description provided for @wxMondayNight.
  ///
  /// In en, this message translates to:
  /// **'Monday night'**
  String get wxMondayNight;

  /// No description provided for @wxTuesday.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get wxTuesday;

  /// No description provided for @wxTuesdayNight.
  ///
  /// In en, this message translates to:
  /// **'Tuesday night'**
  String get wxTuesdayNight;

  /// No description provided for @wxWednesday.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get wxWednesday;

  /// No description provided for @wxWednesdayNight.
  ///
  /// In en, this message translates to:
  /// **'Wednesday night'**
  String get wxWednesdayNight;

  /// No description provided for @wxThursday.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get wxThursday;

  /// No description provided for @wxThursdayNight.
  ///
  /// In en, this message translates to:
  /// **'Thursday night'**
  String get wxThursdayNight;

  /// No description provided for @wxFriday.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get wxFriday;

  /// No description provided for @wxFridayNight.
  ///
  /// In en, this message translates to:
  /// **'Friday night'**
  String get wxFridayNight;

  /// No description provided for @wxSaturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get wxSaturday;

  /// No description provided for @wxSaturdayNight.
  ///
  /// In en, this message translates to:
  /// **'Saturday night'**
  String get wxSaturdayNight;

  /// No description provided for @wxSunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get wxSunday;

  /// No description provided for @wxSundayNight.
  ///
  /// In en, this message translates to:
  /// **'Sunday night'**
  String get wxSundayNight;

  /// No description provided for @wxReportBrief.
  ///
  /// In en, this message translates to:
  /// **'Brief, Short forecast, US only'**
  String get wxReportBrief;

  /// No description provided for @wxReportFull.
  ///
  /// In en, this message translates to:
  /// **'Full, More complete forecast, US only'**
  String get wxReportFull;

  /// No description provided for @wxReportCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current, Nearest NWS station, US only'**
  String get wxReportCurrent;

  /// No description provided for @wxReportMetar.
  ///
  /// In en, this message translates to:
  /// **'METAR, ICAO station in METAR form'**
  String get wxReportMetar;

  /// No description provided for @wxReportCwop.
  ///
  /// In en, this message translates to:
  /// **'CWOP, Nearest CWOP station'**
  String get wxReportCwop;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'hi',
    'ja',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'hi':
      return AppLocalizationsHi();
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
