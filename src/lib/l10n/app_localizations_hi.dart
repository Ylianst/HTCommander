// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'Handi-Talkie Commander';

  @override
  String get menuFile => 'फ़ाइल';

  @override
  String get menuConnect => 'कनेक्ट करें...';

  @override
  String get menuDisconnect => 'डिस्कनेक्ट करें';

  @override
  String get menuSettings => 'सेटिंग्स...';

  @override
  String get menuExit => 'बाहर निकलें';

  @override
  String get menuDualWatch => 'डुअल-वॉच';

  @override
  String get menuScan => 'स्कैन';

  @override
  String get menuRegions => 'क्षेत्र';

  @override
  String get menuTrustedDevices => 'विश्वसनीय डिवाइस...';

  @override
  String get menuButtons => 'बटन...';

  @override
  String get menuExportChannels => 'चैनल निर्यात करें...';

  @override
  String get menuImportChannels => 'चैनल आयात करें...';

  @override
  String get menuMacRadio => 'रेडियो';

  @override
  String get menuMacDisplay => 'डिस्प्ले';

  @override
  String get commonClose => 'बंद करें';

  @override
  String get commonCancel => 'रद्द करें';

  @override
  String get commonOk => 'ठीक है';

  @override
  String get aboutCheckForUpdates => 'अपडेट के लिए जाँचें';

  @override
  String aboutVersionAuthor(String version) {
    return 'संस्करण $version\nYlian Saint-Hilaire, KK7VZT\nओपन सोर्स, Apache 2.0 लाइसेंस';
  }

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get settingsLanguageHint =>
      'एप्लिकेशन द्वारा उपयोग की जाने वाली भाषा चुनें। \'सिस्टम डिफ़ॉल्ट\' आपके डिवाइस की भाषा का अनुसरण करता है।';

  @override
  String get settingsThemeMode => 'थीम';

  @override
  String get settingsThemeModeHint =>
      'हल्का या गहरा रूप चुनें। \'सिस्टम डिफ़ॉल्ट\' आपके डिवाइस की सेटिंग का अनुसरण करता है।';

  @override
  String get settingsThemeModeSystem => 'सिस्टम डिफ़ॉल्ट';

  @override
  String get settingsThemeModeLight => 'हल्का';

  @override
  String get settingsThemeModeDark => 'गहरा';

  @override
  String get languageSystem => 'सिस्टम डिफ़ॉल्ट';

  @override
  String get languageEnglish => 'अंग्रेज़ी';

  @override
  String get languageFrench => 'फ़्रेंच';

  @override
  String get languageSpanish => 'स्पेनिश';

  @override
  String get languageChinese => 'चीनी';

  @override
  String get languageJapanese => 'जापानी';

  @override
  String get languageHindi => 'हिन्दी';

  @override
  String get languageGerman => 'जर्मन';

  @override
  String get menuAudio => 'ऑडियो';

  @override
  String get menuAudioEnabled => 'ऑडियो सक्षम';

  @override
  String get menuSoftwareModem => 'सॉफ़्टवेयर मॉडेम';

  @override
  String get menuModemDisabled => 'अक्षम';

  @override
  String get menuDartTransmitLevel => 'DART ट्रांसमिट स्तर';

  @override
  String get menuDartLevel0 => 'स्तर 0 (BPSK, LDPC 1/2)';

  @override
  String get menuDartLevel1 => 'स्तर 1 (QPSK, LDPC 1/2)';

  @override
  String get menuDartLevel2 => 'स्तर 2 (QPSK, LDPC 2/3)';

  @override
  String get menuDartLevel3 => 'स्तर 3 (8PSK, LDPC 2/3)';

  @override
  String get menuDartLevel4 => 'स्तर 4 (16QAM, LDPC 3/4)';

  @override
  String get menuDartLevel5 => 'स्तर 5 (16QAM, LDPC 5/6)';

  @override
  String get menuDartLevelF => 'स्तर F (4-FSK, LDPC 1/2)';

  @override
  String get menuAprsModem => 'APRS मॉडेम';

  @override
  String get menuView => 'देखें';

  @override
  String get menuRadio => 'रेडियो';

  @override
  String get menuTabs => 'टैब';

  @override
  String get menuTabNames => 'टैब नाम';

  @override
  String get menuShowAllTabs => 'सभी टैब दिखाएँ';

  @override
  String get menuAllChannels => 'सभी चैनल';

  @override
  String get menuHelp => 'सहायता';

  @override
  String get menuRadioInformation => 'रेडियो जानकारी...';

  @override
  String get menuGpsInformation => 'GPS जानकारी...';

  @override
  String get menuCheckForUpdatesEllipsis => 'अपडेट के लिए जाँचें...';

  @override
  String get menuAbout => 'बारे में...';

  @override
  String get tabComms => 'संचार';

  @override
  String get tabAudio => 'ऑडियो';

  @override
  String get tabAprs => 'APRS';

  @override
  String get tabMap => 'मानचित्र';

  @override
  String get tabMail => 'मेल';

  @override
  String get tabTerminal => 'टर्मिनल';

  @override
  String get tabContacts => 'संपर्क';

  @override
  String get tabBbs => 'BBS';

  @override
  String get tabTorrent => 'टोरेंट';

  @override
  String get tabPackets => 'पैकेट';

  @override
  String get tabDebug => 'डिबग';

  @override
  String get tabRadio => 'रेडियो';

  @override
  String get stateDisconnected => 'डिस्कनेक्ट किया गया';

  @override
  String get stateConnecting => 'कनेक्ट हो रहा है...';

  @override
  String get stateConnected => 'कनेक्ट किया गया';

  @override
  String get stateUnableToConnect => 'कनेक्ट करने में असमर्थ';

  @override
  String get stateAccessDenied => 'एक्सेस अस्वीकृत';

  @override
  String get stateSelectRadio => 'रेडियो चुनें';

  @override
  String statusBattery(int percent) {
    return 'बैटरी: $percent %';
  }

  @override
  String get statusCheckingBluetooth => 'ब्लूटूथ जाँच रहा है...';

  @override
  String get statusBluetoothNotAvailable => 'ब्लूटूथ उपलब्ध नहीं है';

  @override
  String get statusScanningForRadios => 'रेडियो खोज रहा है...';

  @override
  String get statusErrorScanning => 'रेडियो खोजने में त्रुटि';

  @override
  String get statusNoCompatibleRadios => 'कोई संगत रेडियो नहीं मिला';

  @override
  String get statusAllRadiosConnected => 'सभी रेडियो पहले से कनेक्ट हैं';

  @override
  String statusConnectingTo(String name) {
    return '$name से कनेक्ट हो रहा है...';
  }

  @override
  String statusConnectedTo(String name) {
    return '$name से कनेक्ट किया गया';
  }

  @override
  String statusFailedToConnect(String name) {
    return '$name से कनेक्ट करने में विफल';
  }

  @override
  String get statusDisconnecting => 'डिस्कनेक्ट हो रहा है...';

  @override
  String get settingsTabLicense => 'लाइसेंस';

  @override
  String get settingsTabAprs => 'APRS';

  @override
  String get settingsTabComms => 'संचार';

  @override
  String get settingsTabWinlink => 'Winlink';

  @override
  String get settingsTabServers => 'सर्वर';

  @override
  String get settingsTabMap => 'मानचित्र';

  @override
  String get settingsTabLimits => 'सीमाएँ';

  @override
  String get settingsTabApplication => 'एप्लिकेशन';

  @override
  String get settingsAdd => 'जोड़ें';

  @override
  String get settingsRemove => 'हटाएँ';

  @override
  String get settingsDownload => 'डाउनलोड करें';

  @override
  String get settingsRetry => 'पुनः प्रयास करें';

  @override
  String get settingsPreview => 'पूर्वावलोकन';

  @override
  String get settingsNone => 'कोई नहीं';

  @override
  String get settingsLicenseInfo =>
      'संयुक्त राज्य अमेरिका में, ट्रांसमिट करने के लिए आपको एक शौकिया रेडियो लाइसेंस की आवश्यकता होती है। लाइसेंस प्राप्त करने के बारे में अधिक जानकारी के लिए ARRL वेबसाइट देखें।';

  @override
  String get settingsCallSignStationId => 'कॉल साइन और स्टेशन ID';

  @override
  String get settingsCallSign => 'कॉल साइन';

  @override
  String get settingsCallSignHint => 'उदा. W1AW';

  @override
  String get settingsStationId => 'स्टेशन ID';

  @override
  String get settingsAllowTransmit =>
      'इस एप्लिकेशन को ट्रांसमिट करने की अनुमति दें';

  @override
  String get settingsCallSignHelp =>
      'ट्रांसमिट सक्षम करने के लिए एक मान्य कॉल साइन (कम से कम 3 अक्षर) दर्ज करें';

  @override
  String get settingsAprsIntro =>
      'पैकेट ट्रांसमिशन के लिए APRS रूटिंग पथ कॉन्फ़िगर करें।';

  @override
  String get settingsAprsRoutes => 'APRS रूट';

  @override
  String get settingsEditRoute => 'रूट संपादित करें';

  @override
  String get settingsEditRouteProtected =>
      'अंतर्निहित रूट संपादित नहीं किया जा सकता';

  @override
  String get settingsDeleteRoute => 'रूट हटाएँ';

  @override
  String get settingsDeleteRouteProtected =>
      'अंतर्निहित रूट हटाया नहीं जा सकता';

  @override
  String get settingsCommsIntro =>
      'वाक् पहचान और वाक् संश्लेषण सेटिंग्स कॉन्फ़िगर करें।';

  @override
  String get settingsSpeechToText => 'वाक् पहचान';

  @override
  String get settingsSpeechToTextInfo =>
      'प्राप्त रेडियो ऑडियो को टेक्स्ट में लिखता है। इस डिवाइस पर पूरी तरह ऑफ़लाइन काम करता है; ऑडियो कभी डिस्क पर सहेजा नहीं जाता।';

  @override
  String get settingsModel => 'मॉडल';

  @override
  String get settingsRecognitionLanguage => 'पहचान भाषा';

  @override
  String get settingsRecognitionLanguageHelp =>
      'भाषा परिवर्तन इंजन के अगली बार शुरू होने पर प्रभावी होते हैं।';

  @override
  String get settingsStatus => 'स्थिति';

  @override
  String settingsModelInstalled(String suffix) {
    return 'मॉडल इंस्टॉल किया गया$suffix';
  }

  @override
  String settingsDownloadingModelPct(String percent) {
    return 'मॉडल डाउनलोड हो रहा है… $percent %';
  }

  @override
  String get settingsDownloadingModel => 'मॉडल डाउनलोड हो रहा है…';

  @override
  String settingsInstallingModelPct(String percent) {
    return 'मॉडल इंस्टॉल हो रहा है… $percent %';
  }

  @override
  String get settingsInstallingModel => 'मॉडल इंस्टॉल हो रहा है…';

  @override
  String get settingsModelInstallError => 'मॉडल इंस्टॉल नहीं किया जा सका।';

  @override
  String settingsModelNotDownloaded(String downloadLabel) {
    return 'मॉडल डाउनलोड नहीं किया गया। $downloadLabel केवल एक बार होता है और इस डिवाइस पर कैश किया जाता है।';
  }

  @override
  String settingsBytesOf(String received, String total) {
    return '$total में से $received';
  }

  @override
  String get settingsRemoveSttModelTitle => 'वाक् पहचान मॉडल हटाएँ?';

  @override
  String settingsRemoveSttModelBody(String name) {
    return 'डिस्क स्थान खाली करने के लिए डाउनलोड किया गया मॉडल \"$name\" हटा दिया जाएगा। अगली बार उपयोग करने पर इसे फिर से डाउनलोड किया जाएगा।';
  }

  @override
  String get settingsTextToSpeech => 'वाक् संश्लेषण';

  @override
  String get settingsTextToSpeechInfo =>
      'संचार टैब से \'आवाज़\' मोड में टेक्स्ट भेजते समय उपयोग किया जाता है।';

  @override
  String get settingsTtsUnavailableTitle => 'वाक् संश्लेषण उपलब्ध नहीं है';

  @override
  String get settingsVoice => 'आवाज़';

  @override
  String get settingsSpeechRate => 'वाक् गति';

  @override
  String get settingsPitch => 'पिच';

  @override
  String get settingsLoadingVoices => 'आवाज़ें लोड हो रही हैं…';

  @override
  String get settingsSystemDefault => 'सिस्टम डिफ़ॉल्ट';

  @override
  String get settingsLangAutoDetect => 'स्वतः पता लगाएँ';

  @override
  String get settingsLangChinese => 'चीनी';

  @override
  String get settingsLangJapanese => 'जापानी';

  @override
  String get settingsLangKorean => 'कोरियाई';

  @override
  String get settingsLangCantonese => 'कैंटोनीज़';

  @override
  String get settingsWinlinkIntro =>
      'रेडियो के माध्यम से ईमेल के लिए Winlink संदेश सेटिंग्स कॉन्फ़िगर करें।';

  @override
  String get settingsWinlinkAccount => 'Winlink खाता';

  @override
  String get settingsAccount => 'खाता';

  @override
  String get settingsWinlinkAccountHelp =>
      'लाइसेंस टैब में आपके कॉल साइन पर आधारित';

  @override
  String get settingsPassword => 'पासवर्ड';

  @override
  String get settingsUseStationIdWinlink =>
      'Winlink के लिए स्टेशन ID का उपयोग करें';

  @override
  String get settingsServersIntro => 'स्थानीय सर्वर सेटिंग्स कॉन्फ़िगर करें।';

  @override
  String get settingsLocalServers => 'स्थानीय सर्वर';

  @override
  String get settingsEnableWebServer => 'वेब सर्वर सक्षम करें';

  @override
  String get settingsPort => 'पोर्ट:';

  @override
  String get settingsEnableAgwpeServer => 'AGWPE सर्वर सक्षम करें';

  @override
  String get settingsMapIntroGps =>
      'GPS और विमान ट्रैकिंग डेटा स्रोत कॉन्फ़िगर करें।';

  @override
  String get settingsMapIntroNoGps =>
      'विमान ट्रैकिंग डेटा स्रोत कॉन्फ़िगर करें।';

  @override
  String get settingsGpsSerialPort => 'GPS सीरियल पोर्ट';

  @override
  String get settingsSerialPort => 'सीरियल पोर्ट';

  @override
  String get settingsBaudRate => 'बॉड दर';

  @override
  String get settingsShareGpsLocation => 'सीरियल GPS स्थान साझा करें';

  @override
  String get settingsShareGpsLocationHelp =>
      'कनेक्टेड रेडियो को सीरियल GPS स्थान भेजता है ताकि वह आपकी वर्तमान स्थिति प्रसारित करे।';

  @override
  String get settingsAirplaneTracking => 'विमान ट्रैकिंग (dump1090)';

  @override
  String get settingsServerUrl => 'सर्वर URL';

  @override
  String get settingsTestConnection => 'कनेक्शन परीक्षण करें';

  @override
  String get settingsTest => 'परीक्षण';

  @override
  String get settingsTestTesting => 'परीक्षण हो रहा है...';

  @override
  String get settingsTestEmptyAddress => 'विफल: सर्वर पता खाली है';

  @override
  String settingsTestFailedHttp(int code) {
    return 'विफल: HTTP $code';
  }

  @override
  String settingsTestSuccess(int count) {
    return 'सफल, $count विमान मिले।';
  }

  @override
  String get settingsTestUnexpectedJson => 'विफल: अप्रत्याशित JSON प्रारूप';

  @override
  String get settingsTestTimedOut => 'विफल: समय समाप्त';

  @override
  String get settingsTestInvalidJson => 'विफल: अमान्य JSON प्रतिक्रिया';

  @override
  String get settingsTestFailed => 'विफल';

  @override
  String get settingsTestConnectionFailedTitle => 'कनेक्शन परीक्षण विफल';

  @override
  String get settingsLimitsIntro =>
      'स्टार्टअप के बीच रखे जाने वाले इतिहास आइटम की संख्या सीमित करें। सब कुछ रखने के लिए \'असीमित\' पर सेट करें।';

  @override
  String get settingsHistoryLimits => 'इतिहास सीमाएँ';

  @override
  String get settingsUnlimited => 'असीमित';

  @override
  String get settingsLimitAprsMessages => 'APRS संदेश';

  @override
  String get settingsLimitPackets => 'पैकेट';

  @override
  String get settingsLimitSstvImages => 'SSTV छवियाँ';

  @override
  String get settingsLimitCommEvents => 'संचार घटनाएँ';

  @override
  String settingsLimitCurrent(int count) {
    return 'वर्तमान: $count';
  }

  @override
  String settingsLimitItemsDeleted(int count) {
    return '$count आइटम हटा दिए जाएँगे';
  }

  @override
  String get settingsDeleteHistoryTitle => 'इतिहास आइटम हटाएँ?';

  @override
  String settingsDeleteHistoryBody(String items) {
    return 'ये सीमाएँ सबसे पुराने को स्थायी रूप से हटा देंगी:\n\n$items\n\nयह क्रिया पूर्ववत नहीं की जा सकती।';
  }

  @override
  String settingsDeleteAprsMessages(int count) {
    return '$count APRS संदेश';
  }

  @override
  String settingsDeletePackets(int count) {
    return '$count पैकेट';
  }

  @override
  String settingsDeleteSstvImages(int count) {
    return '$count SSTV छवियाँ';
  }

  @override
  String settingsDeleteCommEvents(int count) {
    return '$count संचार घटनाएँ';
  }

  @override
  String get settingsAddAprsRoute => 'APRS रूट जोड़ें';

  @override
  String get settingsEditAprsRoute => 'APRS रूट संपादित करें';

  @override
  String get settingsName => 'नाम';

  @override
  String get settingsNameHint => 'उदा. मानक';

  @override
  String get settingsDuplicateRoute => 'उस नाम का एक रूट पहले से मौजूद है।';

  @override
  String get settingsPath => 'पथ';

  @override
  String get commonError => 'त्रुटि';

  @override
  String get commonConnect => 'कनेक्ट करें';

  @override
  String get commonDisconnect => 'डिस्कनेक्ट करें';

  @override
  String get commonRename => 'नाम बदलें';

  @override
  String get commonRemove => 'हटाएँ';

  @override
  String connectScanError(String error) {
    return 'ब्लूटूथ डिवाइस खोजने में विफल: $error';
  }

  @override
  String get connectNoRadiosTitle => 'कोई रेडियो नहीं मिला';

  @override
  String get connectNoRadiosBody =>
      'कोई संगत रेडियो डिवाइस नहीं मिला।\n\nसुनिश्चित करें कि आपका रेडियो चालू है और ब्लूटूथ सक्षम है।';

  @override
  String get connectAllConnectedTitle => 'सभी कनेक्ट हैं';

  @override
  String get connectAllConnectedBody =>
      'सभी पहचाने गए रेडियो डिवाइस पहले से कनेक्ट हैं।';

  @override
  String get connectBluetoothOffTitle => 'ब्लूटूथ उपलब्ध नहीं है';

  @override
  String get connectBluetoothOffBody =>
      'ब्लूटूथ उपलब्ध नहीं है या अक्षम है।\n\nकृपया अपने डिवाइस की सेटिंग्स में ब्लूटूथ सक्षम करें और पुनः प्रयास करें।';

  @override
  String get radioConnectionTitle => 'रेडियो कनेक्शन';

  @override
  String get radioConnectionEmpty =>
      'कोई संगत रेडियो नहीं मिला।\nसुनिश्चित करें कि आपका रेडियो चालू है और ब्लूटूथ सक्षम है।';

  @override
  String get radioRenameTitle => 'रेडियो का नाम बदलें';

  @override
  String get radioRenamePrompt => 'इस रेडियो के लिए एक कस्टम नाम दर्ज करें:';

  @override
  String get radioRenameHint => 'डिफ़ॉल्ट नाम उपयोग करने के लिए खाली छोड़ें';

  @override
  String get updateTitle => 'सॉफ़्टवेयर अपडेट';

  @override
  String get updateChecking => 'अपडेट के लिए जाँच रहा है...';

  @override
  String updateVersionAvailable(String version) {
    return 'संस्करण $version उपलब्ध है।';
  }

  @override
  String updateFreshDownload(String version) {
    return 'संस्करण $version के लिए नई डाउनलोड आवश्यक है।';
  }

  @override
  String updateUnsupported(String version) {
    return 'यह संस्करण अब समर्थित नहीं है। $version पर अपडेट करें।';
  }

  @override
  String get updateUpToDate => 'आप नवीनतम संस्करण का उपयोग कर रहे हैं।';

  @override
  String updateCheckFailed(String error) {
    return 'अपडेट की जाँच विफल: $error';
  }

  @override
  String get updateDownloading => 'अपडेट डाउनलोड हो रहा है...';

  @override
  String get updateDownloaded =>
      'अपडेट डाउनलोड किया गया। इंस्टॉल करने के लिए तैयार।';

  @override
  String updateDownloadFailed(String error) {
    return 'डाउनलोड विफल: $error';
  }

  @override
  String updateInstallFailed(String error) {
    return 'इंस्टॉल विफल: $error';
  }

  @override
  String updateDiagnosticsLog(String path) {
    return 'यदि अपडेट पूरा नहीं होता है, तो डायग्नोस्टिक लॉग देखें:\n$path';
  }

  @override
  String get updateInstallRestart => 'इंस्टॉल करें और पुनः आरंभ करें';

  @override
  String get updateCheckAgain => 'फिर से जाँचें';

  @override
  String get regionsTitle => 'क्षेत्रों का नाम बदलें';

  @override
  String regionsMaxChars(int count) {
    return 'क्षेत्र नाम अधिकतम $count अक्षरों तक हो सकते हैं।';
  }

  @override
  String regionLabel(int number) {
    return 'क्षेत्र $number';
  }

  @override
  String get gpsInfoTitle => 'GPS जानकारी';

  @override
  String get gpsSectionConnection => 'कनेक्शन';

  @override
  String get gpsSectionFix => 'GPS फ़िक्स';

  @override
  String get gpsSectionPosition => 'स्थिति';

  @override
  String get gpsSectionMotion => 'गति';

  @override
  String get gpsSectionTime => 'समय';

  @override
  String get gpsPortStatus => 'पोर्ट स्थिति';

  @override
  String get gpsNotConfigured => 'कॉन्फ़िगर नहीं किया गया';

  @override
  String get gpsOpenReceiving => 'खुला — डेटा प्राप्त हो रहा है';

  @override
  String get gpsPermDeniedLinux =>
      'अनुमति अस्वीकृत — अपने उपयोगकर्ता को \'dialout\' समूह में जोड़ें (sudo usermod -aG dialout \$USER), फिर लॉग आउट करें और फिर से लॉग इन करें।';

  @override
  String get gpsPermDenied =>
      'अनुमति अस्वीकृत — एप्लिकेशन इस पोर्ट तक पहुँच नहीं सकता।';

  @override
  String get gpsPortError => 'पोर्ट त्रुटि — सीरियल पोर्ट नहीं खोला जा सका।';

  @override
  String get gpsFix => 'फ़िक्स';

  @override
  String get gpsFixQuality => 'फ़िक्स गुणवत्ता';

  @override
  String get gpsSatellites => 'उपग्रह';

  @override
  String get gpsNoData => 'कोई डेटा नहीं';

  @override
  String get gpsActive => 'सक्रिय';

  @override
  String get gpsNoFix => 'कोई फ़िक्स नहीं';

  @override
  String get gpsQualGps => 'GPS फ़िक्स (1)';

  @override
  String get gpsQualDgps => 'DGPS फ़िक्स (2)';

  @override
  String get gpsQualInvalid => 'अमान्य (0)';

  @override
  String gpsQualUnknown(int quality) {
    return '$quality (अज्ञात)';
  }

  @override
  String get gpsLatitude => 'अक्षांश';

  @override
  String get gpsLatitudeDms => 'अक्षांश (DMS)';

  @override
  String get gpsLongitude => 'देशांतर';

  @override
  String get gpsLongitudeDms => 'देशांतर (DMS)';

  @override
  String get gpsAltitude => 'ऊँचाई';

  @override
  String get gpsSpeed => 'गति';

  @override
  String get gpsHeading => 'दिशा';

  @override
  String get gpsTimeUtc => 'GPS समय (UTC)';

  @override
  String get gpsDate => 'GPS तिथि';

  @override
  String get gpsLastUpdate => 'अंतिम अपडेट';

  @override
  String get trustedDevicesTitle => 'विश्वसनीय डिवाइस';

  @override
  String get trustedRemoveTitle => 'विश्वसनीय डिवाइस हटाएँ';

  @override
  String trustedRemoveMessage(String name) {
    return 'रेडियो की विश्वसनीय डिवाइस सूची से \"$name\" हटाएँ?';
  }

  @override
  String get trustedNoDevices => 'कोई विश्वसनीय डिवाइस नहीं मिला।';

  @override
  String get pfConfigTitle => 'बटन कॉन्फ़िगर करें';

  @override
  String get pfSaveToRadio => 'रेडियो में सहेजें';

  @override
  String get pfNoRadio => 'कोई रेडियो कनेक्ट नहीं है।';

  @override
  String get pfNoButtons =>
      'यह रेडियो किसी प्रोग्राम करने योग्य बटन की रिपोर्ट नहीं करता।';

  @override
  String get pfIntro =>
      'प्रत्येक प्रोग्राम करने योग्य बटन के लिए प्रत्येक प्रेस प्रकार की क्रिया चुनें। सहेजने पर परिवर्तन रेडियो में लिखे जाते हैं।';

  @override
  String pfButtonLabel(int number) {
    return 'बटन $number';
  }

  @override
  String get pfActionShort => 'छोटा प्रेस';

  @override
  String get pfActionLong => 'लंबा प्रेस';

  @override
  String get pfActionVeryLong => 'बहुत लंबा प्रेस';

  @override
  String get pfActionVeryVeryLong => 'बहुत बहुत लंबा प्रेस';

  @override
  String get pfActionDouble => 'डबल प्रेस';

  @override
  String get pfActionTriple => 'ट्रिपल प्रेस';

  @override
  String get pfActionRepeat => 'दोहराएँ';

  @override
  String get pfActionPressDown => 'दबाकर रखना';

  @override
  String get pfActionRelease => 'छोड़ना';

  @override
  String get pfActionLongRelease => 'लंबा छोड़ना';

  @override
  String get pfActionVeryLongRelease => 'बहुत लंबा छोड़ना';

  @override
  String get pfActionVeryVeryLongRelease => 'बहुत बहुत लंबा छोड़ना';

  @override
  String pfActionUnknown(int action) {
    return 'क्रिया $action';
  }

  @override
  String get pfEffectDisabled => 'अक्षम';

  @override
  String get pfEffectAlarm => 'अलार्म';

  @override
  String get pfEffectAlarmAndMute => 'अलार्म और म्यूट';

  @override
  String get pfEffectToggleOffline => 'ऑफ़लाइन टॉगल करें';

  @override
  String get pfEffectToggleRadioTx => 'रेडियो ट्रांसमिट टॉगल करें';

  @override
  String get pfEffectToggleTxPower => 'ट्रांसमिट पावर टॉगल करें';

  @override
  String get pfEffectToggleFm => 'FM रेडियो टॉगल करें';

  @override
  String get pfEffectPrevChannel => 'पिछला चैनल';

  @override
  String get pfEffectNextChannel => 'अगला चैनल';

  @override
  String get pfEffectTCall => 'T टोन (1750 Hz)';

  @override
  String get pfEffectPrevRegion => 'पिछला क्षेत्र';

  @override
  String get pfEffectNextRegion => 'अगला क्षेत्र';

  @override
  String get pfEffectToggleChScan => 'चैनल स्कैन टॉगल करें';

  @override
  String get pfEffectMainPtt => 'मुख्य PTT';

  @override
  String get pfEffectSubPtt => 'सब PTT';

  @override
  String get pfEffectToggleMonitor => 'मॉनिटर टॉगल करें';

  @override
  String get pfEffectBtPairing => 'ब्लूटूथ पेयरिंग';

  @override
  String get pfEffectToggleDoubleCh => 'डुअल चैनल टॉगल करें';

  @override
  String get pfEffectToggleAbCh => 'A/B चैनल टॉगल करें';

  @override
  String get pfEffectSendLocation => 'स्थान भेजें';

  @override
  String get pfEffectOneClickLink => 'वन-क्लिक लिंक';

  @override
  String get pfEffectVolDown => 'वॉल्यूम कम करें';

  @override
  String get pfEffectVolUp => 'वॉल्यूम बढ़ाएँ';

  @override
  String get pfEffectToggleMute => 'म्यूट टॉगल करें';

  @override
  String pfEffectUnknown(int effect) {
    return 'अज्ञात ($effect)';
  }

  @override
  String get importChannelsTitle => 'चैनल आयात करें';

  @override
  String importChannelsTitleWith(String name) {
    return 'चैनल आयात करें — $name';
  }

  @override
  String get importIntro =>
      'बाईं ओर से किसी चैनल को रेडियो के स्लॉट पर खींचें, या एक चैनल और एक स्लॉट चुनें और फिर तीर पर टैप करें। विवरण के लिए जानकारी आइकन पर टैप करें। चैनल केवल तभी रेडियो में लिखे जाते हैं जब आप ठीक है पर टैप करते हैं।';

  @override
  String importOkCount(int count) {
    return 'ठीक है ($count)';
  }

  @override
  String importImportedHeader(int count) {
    return 'आयातित ($count)';
  }

  @override
  String get importNoChannels => 'कोई आयातित चैनल नहीं।';

  @override
  String importRadioChannelsHeader(int count) {
    return 'रेडियो चैनल ($count)';
  }

  @override
  String get importNoRadioChannels => 'कोई रेडियो चैनल नहीं।';

  @override
  String get importMoveTooltip => 'चयनित चैनल को चयनित स्लॉट में ले जाएँ';

  @override
  String get importCopyAllTooltip =>
      'सभी आयातित चैनलों को रेडियो स्लॉट में 1:1 कॉपी करें';

  @override
  String importChannelShort(int number) {
    return 'चैनल $number';
  }

  @override
  String get importClearTooltip => 'लंबित असाइनमेंट साफ़ करें';

  @override
  String get importChannelDetails => 'चैनल विवरण';

  @override
  String get riTitle => 'रेडियो जानकारी';

  @override
  String get riNoRadioConnected => 'कोई रेडियो कनेक्ट नहीं है';

  @override
  String get riConnectPrompt =>
      'इसकी जानकारी देखने के लिए एक रेडियो कनेक्ट करें।';

  @override
  String riRadioFallback(int id) {
    return 'रेडियो $id';
  }

  @override
  String get riSectionRadio => 'रेडियो';

  @override
  String get riSectionDeviceInfo => 'डिवाइस जानकारी';

  @override
  String get riSectionDeviceStatus => 'डिवाइस स्थिति';

  @override
  String get riSectionDeviceSettings => 'डिवाइस सेटिंग्स';

  @override
  String get riSectionBss => 'BSS सेटिंग्स';

  @override
  String get riSectionPosition => 'स्थिति';

  @override
  String get riName => 'नाम';

  @override
  String get riStatus => 'स्थिति';

  @override
  String get riSettingsLabel => 'सेटिंग्स';

  @override
  String get riNoData => 'कोई डेटा नहीं';

  @override
  String get riNoGpsData => 'कोई GPS डेटा नहीं';

  @override
  String get riNoGpsLock => 'कोई GPS फ़िक्स नहीं';

  @override
  String get riGpsLocked => 'GPS फ़िक्स प्राप्त हुआ';

  @override
  String get riTrue => 'हाँ';

  @override
  String get riFalse => 'नहीं';

  @override
  String get riPresent => 'मौजूद';

  @override
  String get riNotPresent => 'अनुपस्थित';

  @override
  String get riSupported => 'समर्थित';

  @override
  String get riNotSupported => 'असमर्थित';

  @override
  String get riCurrent => 'वर्तमान';

  @override
  String get riOff => 'बंद';

  @override
  String riChannelValue(int number) {
    return 'चैनल $number';
  }

  @override
  String riSeconds(int count) {
    return '$count सेकंड';
  }

  @override
  String riMeters(String value) {
    return '$value मीटर';
  }

  @override
  String riDegrees(String value) {
    return '$value डिग्री';
  }

  @override
  String get riProductId => 'उत्पाद ID';

  @override
  String get riVendorId => 'विक्रेता ID';

  @override
  String get riDmrSupport => 'DMR समर्थन';

  @override
  String get riGmrsSupport => 'GMRS समर्थन';

  @override
  String get riHardwareSpeaker => 'हार्डवेयर स्पीकर';

  @override
  String get riHardwareVersion => 'हार्डवेयर संस्करण';

  @override
  String get riSoftwareVersion => 'सॉफ़्टवेयर संस्करण';

  @override
  String get riRegionCount => 'क्षेत्रों की संख्या';

  @override
  String get riMediumPower => 'मध्यम पावर';

  @override
  String get riChannelCount => 'चैनलों की संख्या';

  @override
  String get riNoaa => 'NOAA';

  @override
  String get riRadioLabel => 'रेडियो';

  @override
  String get riVfo => 'VFO';

  @override
  String get riFreqRangeCount => 'आवृत्ति रेंज की संख्या';

  @override
  String get riPowerOn => 'चालू';

  @override
  String get riInTx => 'ट्रांसमिट में';

  @override
  String get riInRx => 'रिसीव में';

  @override
  String get riDoubleChannelLabel => 'डुअल चैनल';

  @override
  String get riScanning => 'स्कैन हो रहा है';

  @override
  String get riCurrentChannelId => 'वर्तमान चैनल ID';

  @override
  String get riGpsLockedLabel => 'GPS लॉक';

  @override
  String get riHfpConnected => 'HFP कनेक्ट किया गया';

  @override
  String get riAocConnected => 'AOC कनेक्ट किया गया';

  @override
  String get riRssi => 'RSSI';

  @override
  String get riCurrentRegion => 'वर्तमान क्षेत्र';

  @override
  String get riAccuracy => 'सटीकता';

  @override
  String get riReceivedTime => 'प्राप्ति समय';

  @override
  String get riGpsTimeLocal => 'GPS स्थानीय समय';

  @override
  String get riGpsTimeUtcLabel => 'GPS UTC समय';

  @override
  String get tabDetach => 'अलग करें...';

  @override
  String get tabClear => 'साफ़ करें';

  @override
  String get tabSaveToFile => 'फ़ाइल में सहेजें...';

  @override
  String get commonNoRadioConnected => 'कोई रेडियो कनेक्ट नहीं है।';

  @override
  String errorOpeningFileDialog(String error) {
    return 'फ़ाइल डायलॉग खोलने में त्रुटि: $error';
  }

  @override
  String errorSavingFile(String error) {
    return 'फ़ाइल सहेजने में त्रुटि: $error';
  }

  @override
  String get debugSaveTitle => 'डिबग लॉग सहेजें';

  @override
  String debugLogSavedTo(String path) {
    return 'डिबग लॉग $path में सहेजा गया';
  }

  @override
  String get debugShowBluetoothFrames => 'ब्लूटूथ फ़्रेम दिखाएँ';

  @override
  String get debugLoopbackMode => 'लूपबैक मोड';

  @override
  String get debugQueryDeviceNames => 'डिवाइस नाम पूछें';

  @override
  String get debugRawCommand => 'रॉ कमांड...';

  @override
  String get debugAutoScroll => 'स्वतः स्क्रॉल';

  @override
  String get debugFirmwareUpdate => 'फ़र्मवेयर अपडेट...';

  @override
  String get debugShowBuiltInMenus => 'अंतर्निहित मेनू दिखाएँ';

  @override
  String get packetsCopyHex => 'HEX पैकेट कॉपी करें';

  @override
  String get packetsHexCopied => 'HEX पैकेट क्लिपबोर्ड में कॉपी किया गया';

  @override
  String get packetsSaveTitle => 'पैकेट कैप्चर सहेजें';

  @override
  String get packetsSaved => 'पैकेट कैप्चर सहेजा गया';

  @override
  String packetsSavedTo(String path) {
    return 'पैकेट कैप्चर $path में सहेजा गया';
  }

  @override
  String get packetsShowDecode => 'पैकेट डिकोड दिखाएँ';

  @override
  String get packetsEmpty => 'कोई पैकेट कैप्चर नहीं किया गया';

  @override
  String get packetsColTime => 'समय';

  @override
  String get packetsColChannel => 'चैनल';

  @override
  String get packetsColData => 'डेटा';

  @override
  String get commonAdd => 'जोड़ें';

  @override
  String get commonEdit => 'संपादित करें';

  @override
  String get commonEditEllipsis => 'संपादित करें...';

  @override
  String get commonAddEllipsis => 'जोड़ें...';

  @override
  String get commonExportEllipsis => 'निर्यात करें...';

  @override
  String get commonImportEllipsis => 'आयात करें...';

  @override
  String get contactsTypeGeneric => 'सामान्य स्टेशन';

  @override
  String get contactsTypeAprs => 'APRS स्टेशन';

  @override
  String get contactsTypeTerminal => 'टर्मिनल स्टेशन';

  @override
  String get contactsTypeBbs => 'BBS स्टेशन';

  @override
  String get contactsTypeWinlink => 'Winlink स्टेशन';

  @override
  String get contactsTypeTorrent => 'टोरेंट स्टेशन';

  @override
  String get contactsTypeAgwpe => 'AGWPE स्टेशन';

  @override
  String get contactsExists =>
      'इस कॉल साइन और प्रकार वाला स्टेशन पहले से मौजूद है';

  @override
  String get contactsRemovePrompt => 'चयनित स्टेशन हटाएँ?';

  @override
  String get contactsNoExport => 'निर्यात करने के लिए कोई स्टेशन नहीं';

  @override
  String get contactsExportTitle => 'स्टेशन निर्यात करें';

  @override
  String get contactsImportTitle => 'स्टेशन आयात करें';

  @override
  String contactsExported(int count) {
    return '$count स्टेशन निर्यात किए गए';
  }

  @override
  String contactsImported(int count) {
    return '$count स्टेशन आयात किए गए';
  }

  @override
  String get contactsUnableOpen => 'पता पुस्तिका नहीं खोली जा सकी';

  @override
  String get contactsInvalid => 'अमान्य पता पुस्तिका';

  @override
  String get contactsColCallsign => 'कॉल साइन';

  @override
  String get contactsColName => 'नाम';

  @override
  String get contactsColDescription => 'विवरण';

  @override
  String terminalHeaderWith(String callsign) {
    return 'टर्मिनल - $callsign';
  }

  @override
  String get terminalNoRadio => 'कनेक्शन के लिए कोई रेडियो उपलब्ध नहीं है।';

  @override
  String get terminalShowCallsign => 'कॉल साइन दिखाएँ';

  @override
  String get terminalWordWrap => 'शब्द रैप';

  @override
  String get terminalWaitForConnection => 'कनेक्शन की प्रतीक्षा करें...';

  @override
  String get terminalSend => 'भेजें';

  @override
  String terminalConnectedTo(String callsign) {
    return '$callsign से कनेक्ट किया गया';
  }

  @override
  String terminalConnectingTo(String callsign) {
    return '$callsign से कनेक्ट हो रहा है...';
  }

  @override
  String get terminalInvalidCallsignDest => 'अमान्य कॉल साइन/गंतव्य';

  @override
  String get terminalInvalidCallsign => 'अमान्य कॉल साइन';

  @override
  String get terminalNotConnected => 'कनेक्ट नहीं है';

  @override
  String terminalError(String error) {
    return 'त्रुटि: $error';
  }

  @override
  String get terminalBrotli => 'Brotli संपीड़ित पैकेट प्राप्त हुआ (असमर्थित)';

  @override
  String get audioSectionDevices => 'डिवाइस';

  @override
  String get audioRefreshDevices => 'डिवाइस सूची रीफ़्रेश करें';

  @override
  String get audioOutput => 'आउटपुट';

  @override
  String get audioInput => 'इनपुट';

  @override
  String get audioVolume => 'वॉल्यूम';

  @override
  String get audioSquelch => 'स्क्वेल्च';

  @override
  String get audioSectionComputer => 'कंप्यूटर';

  @override
  String get audioApplication => 'एप्लिकेशन';

  @override
  String get audioMaster => 'मास्टर';

  @override
  String get audioMicGain => 'माइक गेन';

  @override
  String get audioMicNotAvailable =>
      'इस प्लेटफ़ॉर्म पर माइक्रोफ़ोन कैप्चर उपलब्ध नहीं है।';

  @override
  String get audioMicNotSupported => 'यहाँ माइक्रोफ़ोन कैप्चर समर्थित नहीं है।';

  @override
  String get audioSpectRadio => 'रेडियो स्पेक्ट्रोग्राफ';

  @override
  String get audioSpectMic => 'माइक्रोफ़ोन स्पेक्ट्रोग्राफ';

  @override
  String get audioSpectNone => 'स्पेक्ट्रोग्राफ';

  @override
  String get audioSpectMenuNone => 'कोई स्पेक्ट्रोग्राफ नहीं';

  @override
  String get audioDartQuality => 'DART रिसीव गुणवत्ता';

  @override
  String get audioDartSignalAnalysis => 'DART सिग्नल विश्लेषण';

  @override
  String get audioDefault => 'डिफ़ॉल्ट';

  @override
  String get audioMute => 'म्यूट';

  @override
  String get audioUnmute => 'अनम्यूट';

  @override
  String get audioEnable => 'सक्षम करें';

  @override
  String get audioDisable => 'अक्षम करें';

  @override
  String get audioNa => 'लागू नहीं';

  @override
  String get bbsHeaderActive => 'BBS - सक्रिय';

  @override
  String get bbsActivate => 'सक्रिय करें';

  @override
  String get bbsDeactivate => 'निष्क्रिय करें';

  @override
  String get bbsViewTraffic => 'ट्रैफ़िक देखें';

  @override
  String get bbsClearTraffic => 'ट्रैफ़िक साफ़ करें';

  @override
  String get bbsClearStats => 'आँकड़े साफ़ करें';

  @override
  String get bbsColCallSign => 'कॉल साइन';

  @override
  String get bbsColLastSeen => 'अंतिम बार देखा गया';

  @override
  String get bbsColStats => 'आँकड़े';

  @override
  String get bbsTraffic => 'ट्रैफ़िक';

  @override
  String get bbsJustNow => 'अभी-अभी';

  @override
  String bbsMinAgo(int n) {
    return '$n मिनट पहले';
  }

  @override
  String bbsHoursAgo(int n) {
    return '$n घंटे पहले';
  }

  @override
  String bbsDaysAgo(int n) {
    return '$n दिन पहले';
  }

  @override
  String get commonDelete => 'हटाएँ';

  @override
  String get torrentAddFile => 'फ़ाइल जोड़ें';

  @override
  String get torrentShowDetails => 'विवरण दिखाएँ';

  @override
  String get torrentFileSaved => 'फ़ाइल सहेजी गई।';

  @override
  String get torrentFileDataUnavailable =>
      'सहेजने में त्रुटि: फ़ाइल डेटा उपलब्ध नहीं है';

  @override
  String get torrentUnknownError => 'अज्ञात त्रुटि';

  @override
  String get torrentSaveTitle => 'टोरेंट फ़ाइल सहेजें';

  @override
  String get torrentNoRadios =>
      'कोई रेडियो कनेक्ट नहीं है। पहले एक रेडियो कनेक्ट करें।';

  @override
  String get torrentMultiRadio =>
      'मल्टी-रेडियो टोरेंट मोड अभी समर्थित नहीं है।';

  @override
  String get torrentDropSingle => 'कृपया केवल एक फ़ाइल ड्रॉप करें।';

  @override
  String get torrentDeletePrompt => 'चयनित टोरेंट फ़ाइल हटाएँ?';

  @override
  String get torrentPause => 'रोकें';

  @override
  String get torrentShare => 'साझा करें';

  @override
  String get torrentRequest => 'अनुरोध करें';

  @override
  String get torrentSaveAs => 'इस रूप में सहेजें...';

  @override
  String get torrentDropToShare => 'साझा करने के लिए एक फ़ाइल ड्रॉप करें';

  @override
  String get torrentNoFiles =>
      'कोई टोरेंट फ़ाइल नहीं। साझा करने के लिए एक फ़ाइल जोड़ें या ड्रॉप करें।';

  @override
  String get torrentUnknownSource => 'अज्ञात';

  @override
  String get torrentColFile => 'फ़ाइल';

  @override
  String get torrentColMode => 'मोड';

  @override
  String get torrentDetailFileName => 'फ़ाइल नाम';

  @override
  String get torrentDetailSource => 'स्रोत';

  @override
  String get torrentDetailFileSize => 'फ़ाइल आकार';

  @override
  String torrentBytes(int count) {
    return '$count बाइट्स';
  }

  @override
  String get torrentDetailCompression => 'संपीड़न';

  @override
  String get torrentDetailBlocks => 'ब्लॉक';

  @override
  String get torrentDetailsTitle => 'टोरेंट विवरण';

  @override
  String get torrentSelectPrompt => 'विवरण देखने के लिए एक टोरेंट चुनें';

  @override
  String get torrentModePaused => 'रोका गया';

  @override
  String get torrentModeSharing => 'साझा हो रहा है';

  @override
  String get torrentModeRequesting => 'अनुरोध हो रहा है';

  @override
  String get torrentModeError => 'त्रुटि';

  @override
  String get torrentCompUnknown => 'अज्ञात';

  @override
  String get mailInbox => 'इनबॉक्स';

  @override
  String get mailOutbox => 'आउटबॉक्स';

  @override
  String get mailDraft => 'ड्राफ़्ट';

  @override
  String get mailSent => 'भेजे गए';

  @override
  String get mailArchive => 'संग्रह';

  @override
  String get mailTrash => 'कचरा';

  @override
  String get mailInternet => 'इंटरनेट';

  @override
  String get mailDeleteTitle => 'मेल हटाएँ';

  @override
  String get mailMoveToTrashTitle => 'कचरे में ले जाएँ';

  @override
  String get mailDeletePermanent =>
      'चयनित मेल स्थायी रूप से हटाएँ? यह क्रिया पूर्ववत नहीं की जा सकती।';

  @override
  String get mailMoveToTrashPrompt => 'चयनित मेल को कचरे में ले जाएँ?';

  @override
  String get mailMove => 'ले जाएँ';

  @override
  String get mailOpen => 'खोलें';

  @override
  String get mailReply => 'उत्तर दें';

  @override
  String get mailReplyAll => 'सभी को उत्तर दें';

  @override
  String get mailForward => 'अग्रेषित करें';

  @override
  String get mailShowPreview => 'पूर्वावलोकन दिखाएँ';

  @override
  String get mailBackup => 'मेल का बैकअप लें...';

  @override
  String get mailRestore => 'मेल पुनर्स्थापित करें...';

  @override
  String get mailShowTraffic => 'ट्रैफ़िक दिखाएँ...';

  @override
  String mailBackupFailed(String error) {
    return 'बैकअप विफल: $error';
  }

  @override
  String get mailBackupTitle => 'मेल का बैकअप लें';

  @override
  String get mailBackupSuccess => 'बैकअप सफलतापूर्वक पूरा हुआ।';

  @override
  String get mailRestoreTitle => 'मेल पुनर्स्थापित करें';

  @override
  String get mailRestoreUnableOpen => 'बैकअप फ़ाइल नहीं खोली जा सकी';

  @override
  String mailRestoreFailed(String error) {
    return 'पुनर्स्थापना विफल: $error';
  }

  @override
  String get mailNew => 'नया';

  @override
  String get mailNewMail => 'नया मेल';

  @override
  String get mailColTime => 'समय';

  @override
  String get mailColTo => 'प्रति';

  @override
  String get mailColFrom => 'से';

  @override
  String get mailColSubject => 'विषय';

  @override
  String get mailSelectPreview => 'पूर्वावलोकन के लिए एक संदेश चुनें';

  @override
  String get commonUnknown => 'अज्ञात';

  @override
  String get mapOfflineMode => 'ऑफ़लाइन मोड';

  @override
  String get mapOfflineMap => 'ऑफ़लाइन मानचित्र';

  @override
  String get mapCacheArea => 'क्षेत्र कैश करें...';

  @override
  String get mapCenterGps => 'GPS पर केंद्रित करें';

  @override
  String get mapShowTracks => 'ट्रैक दिखाएँ';

  @override
  String get mapShowMarkers => 'मार्कर दिखाएँ';

  @override
  String get mapShowAirplanes => 'विमान दिखाएँ';

  @override
  String get mapLargeMarkers => 'बड़े मार्कर';

  @override
  String get mapShowContactsOnly => 'केवल संपर्क दिखाएँ';

  @override
  String get mapFilterAll => 'सभी';

  @override
  String get mapFilterLast30 => 'पिछले 30 मिनट';

  @override
  String get mapFilterLastHour => 'पिछला एक घंटा';

  @override
  String get mapFilterLast6 => 'पिछले 6 घंटे';

  @override
  String get mapFilterLast12 => 'पिछले 12 घंटे';

  @override
  String get mapFilterLast24 => 'पिछले 24 घंटे';

  @override
  String get mapCacheTitle => 'मानचित्र क्षेत्र कैश करें';

  @override
  String mapCachePrompt(int count, int minZoom, int maxZoom) {
    return 'ज़ूम स्तर $minZoom–$maxZoom के लिए $count टाइलें डाउनलोड करें?\n\nयह चयनित क्षेत्र को ऑफ़लाइन उपयोग के लिए कैश कर देगा।';
  }

  @override
  String get mapDownloadingTitle => 'टाइलें डाउनलोड हो रही हैं';

  @override
  String mapTilesProgress(int done, int total) {
    return '$done / $total टाइलें';
  }

  @override
  String get mapDragToSelect => 'कैश करने के लिए क्षेत्र चुनने हेतु खींचें';

  @override
  String get aprsNoChannel => 'APRS चैनल वाला कोई रेडियो उपलब्ध नहीं है';

  @override
  String get aprsNoLoadedChannels =>
      'लोड किए गए चैनलों वाला कोई रेडियो उपलब्ध नहीं है';

  @override
  String get aprsDetails => 'विवरण...';

  @override
  String get aprsShowLocation => 'स्थान दिखाएँ...';

  @override
  String get aprsSetReceiver => 'प्राप्तकर्ता के रूप में सेट करें';

  @override
  String get aprsCopyMessage => 'संदेश कॉपी करें';

  @override
  String get aprsCopyCallsign => 'कॉल साइन कॉपी करें';

  @override
  String get aprsClearTitle => 'APRS संदेश साफ़ करें';

  @override
  String get aprsClearPrompt =>
      'सभी APRS संदेश साफ़ करें? यह मानचित्र से सभी APRS मार्कर भी हटा देता है। यह क्रिया पूर्ववत नहीं की जा सकती।';

  @override
  String get aprsShowAll => 'सभी संदेश दिखाएँ';

  @override
  String get aprsSendSms => 'SMS संदेश भेजें...';

  @override
  String get aprsWeatherReport => 'मौसम रिपोर्ट...';

  @override
  String get aprsBeaconSettingsMenu => 'बीकन सेटिंग्स...';

  @override
  String get aprsDropShare => 'इस चैनल को साझा करने के लिए ड्रॉप करें';

  @override
  String get aprsBeaconWarning =>
      'वर्तमान चैनल पर बीकन प्रसारण सक्षम है, जो अनुशंसित नहीं है।';

  @override
  String aprsBeaconActive(String interval) {
    return 'रेडियो बीकन सक्रिय है, अंतराल: $interval।';
  }

  @override
  String get aprsBeaconSettings => 'बीकन सेटिंग्स';

  @override
  String aprsIntervalSeconds(int count) {
    return '$count सेकंड';
  }

  @override
  String get aprsIntervalMinute => '1 मिनट';

  @override
  String aprsIntervalMinutes(int count) {
    return '$count मिनट';
  }

  @override
  String get aprsMissingChannel =>
      'कनेक्टेड रेडियो पर कोई \'APRS\' चैनल कॉन्फ़िगर नहीं है। APRS संदेश भेजने और प्राप्त करने के लिए एक APRS चैनल जोड़ें।';

  @override
  String get aprsSetup => 'सेटअप';

  @override
  String get aprsTypeMessage => 'एक संदेश लिखें...';

  @override
  String get commonYes => 'हाँ';

  @override
  String get commonNo => 'नहीं';

  @override
  String get commonSend => 'भेजें';

  @override
  String commonSavedTo(String path) {
    return '$path में सहेजा गया';
  }

  @override
  String commsFailedLoadImage(String error) {
    return 'छवि लोड करने में विफल: $error';
  }

  @override
  String commsFailedSaveImage(String error) {
    return 'छवि सहेजने में विफल: $error';
  }

  @override
  String commsFailedEncodeSstv(String error) {
    return 'SSTV ऑडियो एन्कोड करने में विफल: $error';
  }

  @override
  String commsFailedLoadAudio(String error) {
    return 'ऑडियो लोड करने में विफल: $error';
  }

  @override
  String get commsUnsupportedWav => 'असमर्थित या खाली WAV फ़ाइल।';

  @override
  String get commsSstvWebUnavailable =>
      'वेब पर SSTV छवि रिकॉर्डिंग/ट्रांसमिशन उपलब्ध नहीं है।';

  @override
  String get commsNoRadioVoice =>
      'आवाज़ ट्रांसमिशन के लिए कोई रेडियो कनेक्ट नहीं है।';

  @override
  String get commsSelectImageTitle => 'SSTV के लिए एक छवि चुनें';

  @override
  String get commsSelectWavTitle => 'एक WAV ऑडियो फ़ाइल चुनें';

  @override
  String get commsRecordingWebUnavailable =>
      'वेब पर फ़ाइलों से रिकॉर्डिंग चलाना उपलब्ध नहीं है।';

  @override
  String get commsFileNoLongerExists => 'फ़ाइल अब मौजूद नहीं है।';

  @override
  String get commsSaveAsTitle => 'इस रूप में सहेजें';

  @override
  String get commsTransmitDisabledAprs =>
      'जब VFO A APRS चैनल पर सेट होता है तो ट्रांसमिशन अक्षम रहता है।';

  @override
  String get commsWaitTransmission =>
      'कृपया वर्तमान ट्रांसमिशन पूरा होने की प्रतीक्षा करें।';

  @override
  String get commsConnectRadioChat =>
      'चैट संदेश भेजने से पहले एक रेडियो कनेक्ट करें।';

  @override
  String get commsEnableAudioMode =>
      'इस मोड में भेजने से पहले ऑडियो सक्षम करें (\'सक्षम करें\' बटन)।';

  @override
  String get commsMicNotSupported =>
      'इस प्लेटफ़ॉर्म पर माइक्रोफ़ोन कैप्चर समर्थित नहीं है।';

  @override
  String get commsConnectRadioPtt =>
      'पुश-टू-टॉक का उपयोग करने से पहले एक रेडियो कनेक्ट करें।';

  @override
  String get commsEnableAudioPtt =>
      'पुश-टू-टॉक का उपयोग करने से पहले ऑडियो सक्षम करें (\'सक्षम करें\' बटन)।';

  @override
  String get commsSwitchChatShare =>
      'चैनल साझा करने के लिए चैट मोड पर स्विच करें।';

  @override
  String get commsModePtt => 'PTT';

  @override
  String get commsModeChat => 'चैट';

  @override
  String get commsModeSpeak => 'बोलें';

  @override
  String get commsModeMorse => 'मोर्स';

  @override
  String get commsModeDtmf => 'DTMF';

  @override
  String get commsRecordAudio => 'ऑडियो रिकॉर्ड करें';

  @override
  String get commsSendImage => 'छवि भेजें...';

  @override
  String get commsSendAudio => 'ऑडियो भेजें...';

  @override
  String get commsPttReleaseSettings => 'PTT रिलीज़ सेटिंग्स...';

  @override
  String get commsClearHistory => 'इतिहास साफ़ करें';

  @override
  String get commsShowImage => 'छवि दिखाएँ...';

  @override
  String get commsPlayRecording => 'रिकॉर्डिंग चलाएँ...';

  @override
  String get commsSaveAsMenu => 'इस रूप में सहेजें...';

  @override
  String get commsShowLocation => 'स्थान दिखाएँ';

  @override
  String get commsClearHistoryPrompt =>
      'क्या आप वाकई आवाज़ इतिहास साफ़ करना चाहते हैं?';

  @override
  String get commsAudioMuted => 'ऑडियो म्यूट है।';

  @override
  String get commsUnmute => 'अनम्यूट';

  @override
  String get commsPttTransmitting => 'ट्रांसमिट हो रहा है...';

  @override
  String get commsPttHold => 'PTT - ट्रांसमिट करने के लिए दबाए रखें';

  @override
  String get commsDtmfHint => 'DTMF अंक दर्ज करें (0-9, *, #)...';

  @override
  String get mailComposeNewTitle => 'नया संदेश';

  @override
  String get mailComposeEditTitle => 'संदेश संपादित करें';

  @override
  String get mailDiscardChanges => 'इस संदेश के परिवर्तन खारिज करें?';

  @override
  String get mailDiscardMessage => 'इस संदेश को खारिज करें?';

  @override
  String get mailDiscard => 'खारिज करें';

  @override
  String get mailAddCc => 'Cc जोड़ें';

  @override
  String get mailCc => 'Cc';

  @override
  String get mailRemoveCc => 'Cc हटाएँ';

  @override
  String get mailMessageLabel => 'संदेश';

  @override
  String get mailSaveDraft => 'ड्राफ़्ट सहेजें';

  @override
  String get smsTitle => 'SMS संदेश भेजें';

  @override
  String get smsPhoneNumber => 'फ़ोन नंबर';

  @override
  String get smsIntro =>
      'आप संयुक्त राज्य अमेरिका, प्यूर्टो रिको, कनाडा, ऑस्ट्रेलिया और यूनाइटेड किंगडम में फ़ोन पर SMS संदेश भेज सकते हैं, बशर्ते कि नंबर ने पहले ही सेवा स्वीकार कर ली हो। आप यहाँ पंजीकरण कर सकते हैं: ';

  @override
  String get locationTitle => 'स्थान';

  @override
  String get beaconIntro =>
      'रेडियो अपने बारे में जानकारी कैसे प्रसारित करता है, इसे संशोधित करें, जिसमें स्थान, वोल्टेज और एक कस्टम संदेश शामिल है। आस-पास के अन्य स्टेशन यह जानकारी देख सकेंगे।';

  @override
  String beaconRadio(String name) {
    return 'रेडियो: $name';
  }

  @override
  String get beaconSection => 'बीकन';

  @override
  String get beaconPacketFormat => 'पैकेट प्रारूप';

  @override
  String get beaconInterval => 'बीकन अंतराल';

  @override
  String get beaconAprsCallsign => 'APRS कॉल साइन';

  @override
  String get beaconCallsignHint => 'कॉल साइन - स्टेशन ID';

  @override
  String get beaconCallsignInvalid =>
      'एक मान्य कॉल साइन और स्टेशन ID दर्ज करें (उदा. W1AW-5)';

  @override
  String get beaconAprsMessage => 'APRS संदेश';

  @override
  String get beaconShareLocation => 'स्थान साझा करें';

  @override
  String get beaconSendVoltage => 'वोल्टेज भेजें';

  @override
  String get beaconAllowPositionCheck => 'स्थिति जाँच की अनुमति दें';

  @override
  String get beaconChannelCurrent => 'वर्तमान (अनुशंसित नहीं)';

  @override
  String beaconEverySeconds(int n) {
    return 'हर $n सेकंड';
  }

  @override
  String beaconEveryMinutes(int n) {
    return 'हर $n मिनट';
  }

  @override
  String get assConnectTerminal => 'टर्मिनल स्टेशन से कनेक्ट करें';

  @override
  String get assConnectBbs => 'BBS स्टेशन से कनेक्ट करें';

  @override
  String get assConnectWinlink => 'Winlink गेटवे से कनेक्ट करें';

  @override
  String get assConnectStation => 'स्टेशन से कनेक्ट करें';

  @override
  String get assNew => 'नया…';

  @override
  String get attSelectFile => 'साझा करने के लिए एक फ़ाइल चुनें';

  @override
  String get attCompressing => 'संपीड़न हो रहा है...';

  @override
  String get attTitle => 'टोरेंट फ़ाइल जोड़ें';

  @override
  String get attSelect => 'चुनें...';

  @override
  String get attDescriptionOptional => 'विवरण (वैकल्पिक)';

  @override
  String get stationTitleVoice => 'आवाज़ स्टेशन';

  @override
  String get stationTitleAprs => 'APRS स्टेशन';

  @override
  String get stationTitleTerminal => 'टर्मिनल स्टेशन';

  @override
  String get stationTitleWinlink => 'Winlink गेटवे';

  @override
  String get stationTitleGeneric => 'स्टेशन';

  @override
  String get stationTypeOptionVoice => 'आवाज़ / सामान्य स्टेशन';

  @override
  String get stationTypeLabel => 'स्टेशन प्रकार';

  @override
  String get stationAprsRoute => 'APRS रूट';

  @override
  String get stationUseAuth => 'संदेश प्रमाणीकरण का उपयोग करें';

  @override
  String get stationAuthPassword => 'प्रमाणीकरण पासवर्ड';

  @override
  String get stationPasswordRequired => 'पासवर्ड आवश्यक है';

  @override
  String get stationTerminalProtocol => 'टर्मिनल प्रोटोकॉल';

  @override
  String get stationAx25Destination => 'AX.25 गंतव्य (उदा. CALL-1)';

  @override
  String get stationAx25Invalid => 'अमान्य AX.25 पता';

  @override
  String get stationModem => 'मॉडेम';

  @override
  String get apdTitle => 'APRS पैकेट विवरण';

  @override
  String get apdCopyAll => 'सभी कॉपी करें';

  @override
  String get apdCopyValue => 'मान कॉपी करें';

  @override
  String get apdValueCopied => 'मान कॉपी किया गया';

  @override
  String get apdAllValuesCopied => 'सभी मान कॉपी किए गए';

  @override
  String get apdNoDetails => 'कोई विवरण उपलब्ध नहीं है।';

  @override
  String get apdShowLocation => 'स्थान दिखाएँ...';

  @override
  String get acfgTitle => 'APRS चैनल कॉन्फ़िगर करें';

  @override
  String get acfgIntro =>
      'APRS आवृत्ति दुनिया के क्षेत्र के अनुसार भिन्न होती है। APRS चैनल कॉन्फ़िगर करने के लिए उपयुक्त आवृत्ति खोजने हेतु इस साइट का उपयोग करें।';

  @override
  String get acfgConfiguration => 'APRS कॉन्फ़िगरेशन';

  @override
  String get acfgFrequency => 'आवृत्ति';

  @override
  String get acfgFrequencyHint => 'उत्तरी अमेरिका में 144.39\nयूरोप में 144.80';

  @override
  String get acfgChannelOverwritten => 'चयनित चैनल अधिलेखित हो जाएगा';

  @override
  String get sstvSendTitle => 'SSTV छवि भेजें';

  @override
  String sstvSendTitleNamed(String name) {
    return 'SSTV छवि भेजें - $name';
  }

  @override
  String get sstvMode => 'मोड:';

  @override
  String sstvTransmitTime(String time) {
    return 'ट्रांसमिट समय: ~$time';
  }

  @override
  String get msgdTitle => 'संदेश विवरण';

  @override
  String get msgdFieldType => 'प्रकार';

  @override
  String get msgdFieldDirection => 'दिशा';

  @override
  String get msgdFieldTime => 'समय';

  @override
  String get msgdFieldSource => 'स्रोत';

  @override
  String get msgdFieldReceiver => 'प्राप्तकर्ता';

  @override
  String get msgdFieldDuration => 'अवधि';

  @override
  String get msgdFieldLatitude => 'अक्षांश';

  @override
  String get msgdFieldLongitude => 'देशांतर';

  @override
  String get msgdFieldMessage => 'संदेश';

  @override
  String get msgdFieldFile => 'फ़ाइल';

  @override
  String get msgdDirReceived => 'प्राप्त';

  @override
  String get msgdDirSent => 'भेजा गया';

  @override
  String get msgdTypeVoice => 'आवाज़';

  @override
  String get msgdTypeVoiceClip => 'आवाज़ क्लिप';

  @override
  String get msgdTypeRecording => 'रिकॉर्डिंग';

  @override
  String get msgdTypeSstvPicture => 'SSTV छवि';

  @override
  String get msgdTypeIdentification => 'पहचान';

  @override
  String get msgdTypeChatMessage => 'चैट संदेश';

  @override
  String get msgdTypeAx25Packet => 'AX.25 पैकेट';

  @override
  String get rpbFailedToLoad => 'रिकॉर्डिंग लोड करने में विफल।';

  @override
  String get ivwFailedToLoad => 'छवि लोड करने में विफल।';

  @override
  String get rawTitle => 'रॉ रेडियो कमांड';

  @override
  String get rawCommand => 'कमांड';

  @override
  String get rawHexPayload => 'HEX पेलोड (वैकल्पिक)';

  @override
  String get rawResponse => 'प्रतिक्रिया';

  @override
  String get identTitle => 'PTT रिलीज़ सेटिंग्स';

  @override
  String get identDescription =>
      'यदि सक्षम है, तो हर बार जब आप उस चैनल पर PTT छोड़ते हैं जिस पर आप ट्रांसमिट कर रहे हैं, तो यह आपका कॉल साइन और/या स्थान जानकारी भेजता है।';

  @override
  String get identCallsignHint => 'कॉल साइन - स्टेशन ID दर्ज करें';

  @override
  String get identSendCallsign => 'कॉल साइन भेजें';

  @override
  String get identSendPosition => 'स्थिति भेजें';

  @override
  String get commonOn => 'चालू';

  @override
  String get commonOff => 'बंद';

  @override
  String get commonNone => 'कोई नहीं';

  @override
  String chChannelNumber(int n) {
    return 'चैनल $n';
  }

  @override
  String chChShort(int n) {
    return 'चैनल $n';
  }

  @override
  String get chMoreSettings => 'अधिक सेटिंग्स';

  @override
  String get chChannelNameHint => 'चैनल नाम';

  @override
  String get chFrequencyMhz => 'आवृत्ति (MHz)';

  @override
  String get chReceiveMhz => 'रिसीव (MHz)';

  @override
  String get chTransmitMhz => 'ट्रांसमिट (MHz)';

  @override
  String get chMode => 'मोड';

  @override
  String get chPower => 'पावर';

  @override
  String get chBandwidth => 'बैंडविड्थ';

  @override
  String get chReceiveTone => 'रिसीव टोन (CTCSS / DCS)';

  @override
  String get chTransmitTone => 'ट्रांसमिट टोन (CTCSS / DCS)';

  @override
  String get chDisableTransmit => 'ट्रांसमिट अक्षम करें';

  @override
  String get chMute => 'म्यूट';

  @override
  String get chScan => 'स्कैन';

  @override
  String get chTalkAround => 'टॉक अराउंड';

  @override
  String get chDeemphasis => 'डीएम्फ़ेसिस';

  @override
  String get chPowerHigh => 'उच्च';

  @override
  String get chPowerMedium => 'मध्यम';

  @override
  String get chPowerLow => 'निम्न';

  @override
  String get chBandwidthWide => '25 KHz वाइड';

  @override
  String get chBandwidthNarrow => '12.5 KHz नैरो';

  @override
  String get chClearTitle => 'चैनल साफ़ करें';

  @override
  String chClearConfirm(int n) {
    return 'चैनल $n साफ़ करें?\n\nयह रेडियो पर इस स्लॉट की आवृत्ति, नाम और सेटिंग्स हटा देता है।';
  }

  @override
  String get cdRxFrequency => 'RX आवृत्ति';

  @override
  String get cdTxFrequency => 'TX आवृत्ति';

  @override
  String get cdRxModulation => 'RX मॉड्यूलेशन';

  @override
  String get cdTxModulation => 'TX मॉड्यूलेशन';

  @override
  String get cdRxTone => 'RX टोन';

  @override
  String get cdTxTone => 'TX टोन';

  @override
  String get cdTxDisabled => 'ट्रांसमिट अक्षम';

  @override
  String get cdTalkAround => 'टॉक अराउंड';

  @override
  String get cdEmpty => '(खाली)';

  @override
  String get cdBandwidthWide => '25 kHz (वाइड)';

  @override
  String get cdBandwidthNarrow => '12.5 kHz (नैरो)';

  @override
  String get gpsDetailsTitle => 'GPS विवरण';

  @override
  String get gpsDisabled => 'GPS अक्षम';

  @override
  String get gpsLock => 'GPS लॉक';

  @override
  String get gpsNoLock => 'कोई GPS लॉक नहीं';

  @override
  String get mdbgTitle => 'Winlink ट्रैफ़िक';

  @override
  String get mdbgNoTraffic => 'अभी कोई ट्रैफ़िक नहीं।';

  @override
  String get fwTitle => 'रेडियो फ़र्मवेयर अपडेट';

  @override
  String get fwStatusInitial =>
      'ऑनलाइन फ़र्मवेयर अपडेट के लिए जाँचें, या डिस्क से एक फ़र्मवेयर फ़ाइल लोड करें।';

  @override
  String get fwErrNotConnected => 'रेडियो कनेक्ट नहीं है।';

  @override
  String get fwErrNoDeviceInfo => 'रेडियो डिवाइस जानकारी अभी उपलब्ध नहीं है।';

  @override
  String get fwStatusChecking => 'फ़र्मवेयर अपडेट की जाँच हो रही है…';

  @override
  String get fwErrNoServerInfo =>
      'विक्रेता सर्वर ने फ़र्मवेयर जानकारी नहीं लौटाई।';

  @override
  String fwUpdateAvailable(String version) {
    return 'एक फ़र्मवेयर अपडेट उपलब्ध है $version। नीचे रिलीज़ नोट्स देखें, फिर अपडेट करने के लिए डाउनलोड करें।';
  }

  @override
  String fwErrCheckFailed(String error) {
    return 'अपडेट की जाँच विफल: $error';
  }

  @override
  String get fwPickTitle => 'एक फ़र्मवेयर फ़ाइल चुनें';

  @override
  String fwLoaded(String name, String size, String md5) {
    return '$name लोड किया गया: $size (MD5 $md5…)।';
  }

  @override
  String fwErrLoadFailed(String error) {
    return 'फ़र्मवेयर फ़ाइल लोड नहीं की जा सकी: $error';
  }

  @override
  String get fwSaveTitle => 'फ़र्मवेयर फ़ाइल सहेजें';

  @override
  String fwSavedTo(String path) {
    return 'फ़र्मवेयर $path में सहेजा गया';
  }

  @override
  String fwErrSaveFailed(String error) {
    return 'फ़र्मवेयर फ़ाइल सहेजी नहीं जा सकी: $error';
  }

  @override
  String get fwStatusDownloading => 'फ़र्मवेयर डाउनलोड और असेंबल हो रहा है…';

  @override
  String get fwProgressStarting => 'आरंभ हो रहा है…';

  @override
  String fwReady(String size, String md5) {
    return 'फ़र्मवेयर तैयार: $size (MD5 $md5…)।';
  }

  @override
  String fwErrDownloadFailed(String error) {
    return 'डाउनलोड विफल: $error';
  }

  @override
  String get fwStatusWriting =>
      'फ़र्मवेयर रेडियो पर लिखा जा रहा है। इसे बंद न करें।';

  @override
  String get fwProgressTransferring => 'स्थानांतरित हो रहा है…';

  @override
  String fwErrTransferFailed(String error) {
    return 'फ़र्मवेयर स्थानांतरण विफल: $error';
  }

  @override
  String get fwStatusRebooting =>
      'रेडियो पुनः आरंभ हो रहा है। पुनः कनेक्ट हो रहा है…';

  @override
  String get fwProgressWaitingRestart =>
      'रेडियो के पुनः आरंभ होने की प्रतीक्षा हो रही है…';

  @override
  String fwErrReconnectFailed(String error) {
    return 'पुनः आरंभ के बाद पुनः कनेक्ट करने में विफल: $error';
  }

  @override
  String get fwErrReconnectNull =>
      'रेडियो के पुनः आरंभ होने के बाद उससे पुनः कनेक्ट नहीं किया जा सका। फ़र्मवेयर स्थानांतरित हो गया लेकिन पुष्टि नहीं हुई। मैन्युअल रूप से पुनः कनेक्ट करें और पुनः प्रयास करें।';

  @override
  String get fwStatusFinalising => 'अपडेट को अंतिम रूप दिया जा रहा है…';

  @override
  String get fwProgressConfirming => 'पुष्टि हो रही है…';

  @override
  String fwErrConfirmFailed(String error) {
    return 'अपडेट की पुष्टि विफल: $error';
  }

  @override
  String get fwStatusComplete =>
      'फ़र्मवेयर अपडेट पूरा हुआ! रेडियो अब नया फ़र्मवेयर चला रहा है।';

  @override
  String get fwProgressDownloadPatch => 'पैच डाउनलोड हो रहा है';

  @override
  String get fwProgressDownloadBase => 'बेस इमेज डाउनलोड हो रही है';

  @override
  String get fwProgressAssemble => 'फ़र्मवेयर असेंबल हो रहा है';

  @override
  String fwProgressBytes(String label, String done, String total) {
    return '$label ($done / $total)';
  }

  @override
  String fwProgressTransferringBytes(String done, String total) {
    return 'स्थानांतरित हो रहा है ($done / $total)';
  }

  @override
  String fwCurrentFirmware(String version) {
    return 'वर्तमान फ़र्मवेयर: $version';
  }

  @override
  String get fwErrGeneric => 'एक त्रुटि हुई।';

  @override
  String get fwIdleDisclosure =>
      'ऑनलाइन जाँच रेडियो विक्रेता के सर्वर (rpc.benshikj.com) से संपर्क करती है और केवल आपके रेडियो का उत्पाद पहचानकर्ता भेजती है। जब तक आप अपडेट के लिए जाँचें पर टैप नहीं करते, तब तक कुछ नहीं भेजा जाता।';

  @override
  String get fwWhatsNew => 'नया क्या है';

  @override
  String get fwConfirmWarning =>
      'चेतावनी: पूरी प्रक्रिया के दौरान रेडियो को चालू, चार्ज और ब्लूटूथ रेंज में रखें। रेडियो बीच में पुनः आरंभ होगा। अपडेट को बाधित करने पर मैन्युअल पुनर्प्राप्ति की आवश्यकता हो सकती है।';

  @override
  String get fwFromFile => 'फ़ाइल से…';

  @override
  String get fwCheckForUpdate => 'अपडेट के लिए जाँचें';

  @override
  String get fwDownload => 'डाउनलोड करें';

  @override
  String get fwSave => 'सहेजें…';

  @override
  String get fwFlashNow => 'अभी फ़्लैश करें';

  @override
  String get fwRetry => 'पुनः प्रयास करें';

  @override
  String get wxTitle => 'मौसम रिपोर्ट का अनुरोध करें';

  @override
  String get wxIntro => 'APRS के माध्यम से मौसम रिपोर्ट का अनुरोध करें। ';

  @override
  String get wxLocation => 'स्थान';

  @override
  String get wxLocationHelper =>
      'US शहर/राज्य या US ज़िप कोड, या निर्देशांक 41.123/-121.334';

  @override
  String get wxTime => 'समय';

  @override
  String get wxReport => 'रिपोर्ट';

  @override
  String get wxToday => 'आज';

  @override
  String get wxTonight => 'आज रात';

  @override
  String get wxTomorrow => 'कल';

  @override
  String get wxTomorrowNight => 'कल रात';

  @override
  String get wxMonday => 'सोमवार';

  @override
  String get wxMondayNight => 'सोमवार रात';

  @override
  String get wxTuesday => 'मंगलवार';

  @override
  String get wxTuesdayNight => 'मंगलवार रात';

  @override
  String get wxWednesday => 'बुधवार';

  @override
  String get wxWednesdayNight => 'बुधवार रात';

  @override
  String get wxThursday => 'गुरुवार';

  @override
  String get wxThursdayNight => 'गुरुवार रात';

  @override
  String get wxFriday => 'शुक्रवार';

  @override
  String get wxFridayNight => 'शुक्रवार रात';

  @override
  String get wxSaturday => 'शनिवार';

  @override
  String get wxSaturdayNight => 'शनिवार रात';

  @override
  String get wxSunday => 'रविवार';

  @override
  String get wxSundayNight => 'रविवार रात';

  @override
  String get wxReportBrief => 'संक्षिप्त, लघु पूर्वानुमान, केवल US';

  @override
  String get wxReportFull => 'पूर्ण, अधिक विस्तृत पूर्वानुमान, केवल US';

  @override
  String get wxReportCurrent => 'वर्तमान, निकटतम NWS स्टेशन, केवल US';

  @override
  String get wxReportMetar => 'METAR, ICAO स्टेशन METAR प्रारूप में';

  @override
  String get wxReportCwop => 'CWOP, निकटतम CWOP स्टेशन';
}
