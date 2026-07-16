// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Handi-Talkie Commander';

  @override
  String get menuFile => 'Datei';

  @override
  String get menuConnect => 'Verbinden...';

  @override
  String get menuDisconnect => 'Trennen';

  @override
  String get menuSettings => 'Einstellungen...';

  @override
  String get menuExit => 'Beenden';

  @override
  String get menuDualWatch => 'Dual-Watch';

  @override
  String get menuScan => 'Suchlauf';

  @override
  String get menuRegions => 'Regionen';

  @override
  String get menuTrustedDevices => 'Vertrauenswürdige Geräte...';

  @override
  String get menuButtons => 'Tasten...';

  @override
  String get menuFmRadio => 'UKW-Radio...';

  @override
  String get menuExportChannels => 'Kanäle exportieren...';

  @override
  String get menuImportChannels => 'Kanäle importieren...';

  @override
  String get menuMacRadio => 'Funkgerät';

  @override
  String get menuMacDisplay => 'Anzeige';

  @override
  String get fmRadioTitle => 'UKW-Radio';

  @override
  String fmRadioMhz(String value) {
    return '${value}MHz';
  }

  @override
  String get fmRadioOff => 'Aus';

  @override
  String get fmRadioPowerTooltip => 'UKW-Radio ein-/ausschalten';

  @override
  String get fmRadioSeekDownTooltip => 'Abwärts suchen';

  @override
  String get fmRadioStepDownTooltip => 'Frequenz verringern';

  @override
  String get fmRadioStopTooltip => 'Ausschalten';

  @override
  String get fmRadioStepUpTooltip => 'Frequenz erhöhen';

  @override
  String get fmRadioSeekUpTooltip => 'Aufwärts suchen';

  @override
  String get fmRadioStationsHeader => 'Bevorzugte Sender';

  @override
  String get fmRadioAddStationTooltip => 'Aktuelle Frequenz hinzufügen';

  @override
  String get fmRadioNoStations => 'Keine bevorzugten Sender';

  @override
  String get fmRadioStationNameLabel => 'Sendername';

  @override
  String get fmRadioRenameTitle => 'Sendername';

  @override
  String get fmRadioDeleteTitle => 'Sender löschen';

  @override
  String fmRadioDeleteMessage(String name) {
    return '„$name“ aus Ihren bevorzugten Sendern entfernen?';
  }

  @override
  String get commonClose => 'Schließen';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonOk => 'OK';

  @override
  String get aboutCheckForUpdates => 'Nach Updates suchen';

  @override
  String aboutVersionAuthor(String version) {
    return 'Version $version\nYlian Saint-Hilaire, KK7VZT\nOpen Source, Apache 2.0-Lizenz';
  }

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsLanguageHint =>
      'Wählen Sie die von der Anwendung verwendete Sprache. „Systemstandard“ folgt der Sprache Ihres Geräts.';

  @override
  String get settingsThemeMode => 'Design';

  @override
  String get settingsThemeModeHint =>
      'Wählen Sie das helle oder dunkle Erscheinungsbild. „Systemstandard“ folgt der Einstellung Ihres Geräts.';

  @override
  String get settingsThemeModeSystem => 'Systemstandard';

  @override
  String get settingsThemeModeLight => 'Hell';

  @override
  String get settingsThemeModeDark => 'Dunkel';

  @override
  String get languageSystem => 'Systemstandard';

  @override
  String get languageEnglish => 'Englisch';

  @override
  String get languageFrench => 'Französisch';

  @override
  String get languageSpanish => 'Spanisch';

  @override
  String get languageChinese => 'Chinesisch';

  @override
  String get languageJapanese => 'Japanisch';

  @override
  String get languageHindi => 'Hindi';

  @override
  String get languageGerman => 'Deutsch';

  @override
  String get menuAudio => 'Audio';

  @override
  String get menuAudioEnabled => 'Audio aktiviert';

  @override
  String get menuSoftwareModem => 'Software-Modem';

  @override
  String get menuModemDisabled => 'Deaktiviert';

  @override
  String get menuDartTransmitLevel => 'DART-Sendestufe';

  @override
  String get menuDartLevel0 => 'Stufe 0 (BPSK, LDPC 1/2)';

  @override
  String get menuDartLevel1 => 'Stufe 1 (QPSK, LDPC 1/2)';

  @override
  String get menuDartLevel2 => 'Stufe 2 (QPSK, LDPC 2/3)';

  @override
  String get menuDartLevel3 => 'Stufe 3 (8PSK, LDPC 2/3)';

  @override
  String get menuDartLevel4 => 'Stufe 4 (16QAM, LDPC 3/4)';

  @override
  String get menuDartLevel5 => 'Stufe 5 (16QAM, LDPC 5/6)';

  @override
  String get menuDartLevelF => 'Stufe F (4-FSK, LDPC 1/2)';

  @override
  String get menuAprsModem => 'APRS-Modem';

  @override
  String get menuView => 'Ansicht';

  @override
  String get menuRadio => 'Funkgerät';

  @override
  String get menuTabs => 'Tabs';

  @override
  String get menuTabNames => 'Tab-Namen';

  @override
  String get menuShowAllTabs => 'Alle Tabs anzeigen';

  @override
  String get menuAllChannels => 'Alle Kanäle';

  @override
  String get menuChannelFrequency => 'Kanalfrequenz';

  @override
  String get menuHelp => 'Hilfe';

  @override
  String get menuRadioInformation => 'Funkgerät-Informationen...';

  @override
  String get menuGpsInformation => 'GPS-Informationen...';

  @override
  String get menuCheckForUpdatesEllipsis => 'Nach Updates suchen...';

  @override
  String get menuAbout => 'Über...';

  @override
  String get tabComms => 'Kommunikation';

  @override
  String get tabAudio => 'Audio';

  @override
  String get tabAprs => 'APRS';

  @override
  String get tabMap => 'Karte';

  @override
  String get tabMail => 'E-Mail';

  @override
  String get tabTerminal => 'Terminal';

  @override
  String get tabContacts => 'Kontakte';

  @override
  String get tabBbs => 'BBS';

  @override
  String get tabTorrent => 'Torrent';

  @override
  String get tabPackets => 'Pakete';

  @override
  String get tabDebug => 'Debug';

  @override
  String get tabRadio => 'Funkgerät';

  @override
  String get stateDisconnected => 'Getrennt';

  @override
  String get stateConnecting => 'Verbinde...';

  @override
  String get stateConnected => 'Verbunden';

  @override
  String get stateUnableToConnect => 'Verbindung nicht möglich';

  @override
  String get stateAccessDenied => 'Zugriff verweigert';

  @override
  String get stateSelectRadio => 'Funkgerät auswählen';

  @override
  String statusBattery(int percent) {
    return 'Akku: $percent %';
  }

  @override
  String get statusCheckingBluetooth => 'Bluetooth wird geprüft...';

  @override
  String get statusBluetoothNotAvailable => 'Bluetooth nicht verfügbar';

  @override
  String get statusScanningForRadios => 'Suche nach Funkgeräten...';

  @override
  String get statusErrorScanning => 'Fehler bei der Suche nach Funkgeräten';

  @override
  String get statusNoCompatibleRadios =>
      'Keine kompatiblen Funkgeräte gefunden';

  @override
  String get statusAllRadiosConnected =>
      'Alle Funkgeräte sind bereits verbunden';

  @override
  String statusConnectingTo(String name) {
    return 'Verbinde mit $name...';
  }

  @override
  String statusConnectedTo(String name) {
    return 'Mit $name verbunden';
  }

  @override
  String statusFailedToConnect(String name) {
    return 'Verbindung mit $name fehlgeschlagen';
  }

  @override
  String get statusDisconnecting => 'Trenne Verbindung...';

  @override
  String get settingsTabLicense => 'Lizenz';

  @override
  String get settingsTabAprs => 'APRS';

  @override
  String get settingsTabComms => 'Kommunikation';

  @override
  String get settingsTabWinlink => 'Winlink';

  @override
  String get settingsTabServers => 'Server';

  @override
  String get settingsTabMap => 'Karte';

  @override
  String get settingsTabLimits => 'Limits';

  @override
  String get settingsTabApplication => 'Anwendung';

  @override
  String get settingsAdd => 'Hinzufügen';

  @override
  String get settingsRemove => 'Entfernen';

  @override
  String get settingsDownload => 'Herunterladen';

  @override
  String get settingsRetry => 'Wiederholen';

  @override
  String get settingsPreview => 'Vorschau';

  @override
  String get settingsNone => 'Keine';

  @override
  String get settingsLicenseInfo =>
      'In den USA benötigen Sie eine Amateurfunklizenz, um zu senden. Weitere Informationen zum Erwerb einer Lizenz finden Sie auf der ARRL-Website.';

  @override
  String get settingsCallSignStationId => 'Rufzeichen und Stations-ID';

  @override
  String get settingsCallSign => 'Rufzeichen';

  @override
  String get settingsCallSignHint => 'z. B. W1AW';

  @override
  String get settingsStationId => 'Stations-ID';

  @override
  String get settingsAllowTransmit => 'Dieser Anwendung das Senden erlauben';

  @override
  String get settingsCallSignHelp =>
      'Geben Sie ein gültiges Rufzeichen (mindestens 3 Zeichen) ein, um das Senden zu aktivieren';

  @override
  String get settingsAprsIntro =>
      'Konfigurieren Sie die APRS-Routing-Pfade für die Paketübertragung.';

  @override
  String get settingsAprsRoutes => 'APRS-Routen';

  @override
  String get settingsEditRoute => 'Route bearbeiten';

  @override
  String get settingsEditRouteProtected =>
      'Die integrierte Route kann nicht bearbeitet werden';

  @override
  String get settingsDeleteRoute => 'Route löschen';

  @override
  String get settingsDeleteRouteProtected =>
      'Die integrierte Route kann nicht gelöscht werden';

  @override
  String get settingsCommsIntro =>
      'Konfigurieren Sie die Einstellungen für Spracherkennung und Sprachsynthese.';

  @override
  String get settingsSpeechToText => 'Spracherkennung';

  @override
  String get settingsSpeechToTextInfo =>
      'Transkribiert empfangenes Funk-Audio in Text. Funktioniert vollständig offline auf diesem Gerät; Audio wird niemals auf der Festplatte gespeichert.';

  @override
  String get settingsModel => 'Modell';

  @override
  String get settingsRecognitionLanguage => 'Erkennungssprache';

  @override
  String get settingsRecognitionLanguageHelp =>
      'Sprachänderungen werden beim nächsten Start der Engine wirksam.';

  @override
  String get settingsStatus => 'Status';

  @override
  String settingsModelInstalled(String suffix) {
    return 'Modell installiert$suffix';
  }

  @override
  String settingsDownloadingModelPct(String percent) {
    return 'Modell wird heruntergeladen… $percent %';
  }

  @override
  String get settingsDownloadingModel => 'Modell wird heruntergeladen…';

  @override
  String settingsInstallingModelPct(String percent) {
    return 'Modell wird installiert… $percent %';
  }

  @override
  String get settingsInstallingModel => 'Modell wird installiert…';

  @override
  String get settingsModelInstallError =>
      'Das Modell konnte nicht installiert werden.';

  @override
  String settingsModelNotDownloaded(String downloadLabel) {
    return 'Modell nicht heruntergeladen. $downloadLabel erfolgt nur einmal und wird auf diesem Gerät zwischengespeichert.';
  }

  @override
  String settingsBytesOf(String received, String total) {
    return '$received von $total';
  }

  @override
  String get settingsRemoveSttModelTitle => 'Spracherkennungsmodell entfernen?';

  @override
  String settingsRemoveSttModelBody(String name) {
    return 'Das heruntergeladene Modell „$name“ wird entfernt, um Speicherplatz freizugeben. Es wird beim nächsten Gebrauch erneut heruntergeladen.';
  }

  @override
  String get settingsTextToSpeech => 'Sprachsynthese';

  @override
  String get settingsTextToSpeechInfo =>
      'Wird beim Senden von Text im Modus „Sprache“ auf der Registerkarte Kommunikation verwendet.';

  @override
  String get settingsTtsUnavailableTitle =>
      'Sprachsynthese ist nicht verfügbar';

  @override
  String get settingsVoice => 'Stimme';

  @override
  String get settingsSpeechRate => 'Sprechgeschwindigkeit';

  @override
  String get settingsPitch => 'Tonhöhe';

  @override
  String get settingsLoadingVoices => 'Stimmen werden geladen…';

  @override
  String get settingsSystemDefault => 'Systemstandard';

  @override
  String get settingsLangAutoDetect => 'Automatische Erkennung';

  @override
  String get settingsLangChinese => 'Chinesisch';

  @override
  String get settingsLangJapanese => 'Japanisch';

  @override
  String get settingsLangKorean => 'Koreanisch';

  @override
  String get settingsLangCantonese => 'Kantonesisch';

  @override
  String get settingsWinlinkIntro =>
      'Konfigurieren Sie die Winlink-Nachrichteneinstellungen für E-Mail über Funk.';

  @override
  String get settingsWinlinkAccount => 'Winlink-Konto';

  @override
  String get settingsAccount => 'Konto';

  @override
  String get settingsWinlinkAccountHelp =>
      'Basierend auf Ihrem Rufzeichen auf der Registerkarte Lizenz';

  @override
  String get settingsPassword => 'Passwort';

  @override
  String get settingsUseStationIdWinlink => 'Stations-ID für Winlink verwenden';

  @override
  String get settingsServersIntro =>
      'Konfigurieren Sie die Einstellungen für lokale Server.';

  @override
  String get settingsLocalServers => 'Lokale Server';

  @override
  String get settingsEnableWebServer => 'Webserver aktivieren';

  @override
  String get settingsPort => 'Port:';

  @override
  String get settingsEnableAgwpeServer => 'AGWPE-Server aktivieren';

  @override
  String get settingsMapIntroGps =>
      'Konfigurieren Sie die Datenquellen für GPS und Flugzeugverfolgung.';

  @override
  String get settingsMapIntroNoGps =>
      'Konfigurieren Sie die Datenquellen für die Flugzeugverfolgung.';

  @override
  String get settingsGpsSerialPort => 'GPS-Seriellport';

  @override
  String get settingsSerialPort => 'Serieller Port';

  @override
  String get settingsBaudRate => 'Baudrate';

  @override
  String get settingsShareGpsLocation => 'Serielle GPS-Position teilen';

  @override
  String get settingsShareGpsLocationHelp =>
      'Sendet die serielle GPS-Position an das verbundene Funkgerät, damit es Ihre aktuelle Position sendet.';

  @override
  String get settingsAirplaneTracking => 'Flugzeugverfolgung (dump1090)';

  @override
  String get settingsServerUrl => 'Server-URL';

  @override
  String get settingsTestConnection => 'Verbindung testen';

  @override
  String get settingsTest => 'Testen';

  @override
  String get settingsTestTesting => 'Test läuft...';

  @override
  String get settingsTestEmptyAddress =>
      'Fehlgeschlagen: Serveradresse ist leer';

  @override
  String settingsTestFailedHttp(int code) {
    return 'Fehlgeschlagen: HTTP $code';
  }

  @override
  String settingsTestSuccess(int count) {
    return 'Erfolgreich, $count Flugzeug(e) gefunden.';
  }

  @override
  String get settingsTestUnexpectedJson =>
      'Fehlgeschlagen: unerwartetes JSON-Format';

  @override
  String get settingsTestTimedOut => 'Fehlgeschlagen: Zeitüberschreitung';

  @override
  String get settingsTestInvalidJson =>
      'Fehlgeschlagen: ungültige JSON-Antwort';

  @override
  String get settingsTestFailed => 'Fehlgeschlagen';

  @override
  String get settingsTestConnectionFailedTitle =>
      'Verbindungstest fehlgeschlagen';

  @override
  String get settingsLimitsIntro =>
      'Begrenzen Sie die Anzahl der zwischen den Starts beibehaltenen Verlaufseinträge. Auf „Unbegrenzt“ setzen, um alles zu behalten.';

  @override
  String get settingsHistoryLimits => 'Verlaufslimits';

  @override
  String get settingsUnlimited => 'Unbegrenzt';

  @override
  String get settingsLimitAprsMessages => 'APRS-Nachrichten';

  @override
  String get settingsLimitPackets => 'Pakete';

  @override
  String get settingsLimitSstvImages => 'SSTV-Bilder';

  @override
  String get settingsLimitCommEvents => 'Kommunikationsereignisse';

  @override
  String settingsLimitCurrent(int count) {
    return 'Aktuell: $count';
  }

  @override
  String settingsLimitItemsDeleted(int count) {
    return '$count Einträge werden gelöscht';
  }

  @override
  String get settingsDeleteHistoryTitle => 'Verlaufseinträge löschen?';

  @override
  String settingsDeleteHistoryBody(String items) {
    return 'Diese Limits löschen dauerhaft die ältesten Einträge:\n\n$items\n\nDiese Aktion kann nicht rückgängig gemacht werden.';
  }

  @override
  String settingsDeleteAprsMessages(int count) {
    return '$count APRS-Nachrichten';
  }

  @override
  String settingsDeletePackets(int count) {
    return '$count Pakete';
  }

  @override
  String settingsDeleteSstvImages(int count) {
    return '$count SSTV-Bilder';
  }

  @override
  String settingsDeleteCommEvents(int count) {
    return '$count Kommunikationsereignisse';
  }

  @override
  String get settingsAddAprsRoute => 'APRS-Route hinzufügen';

  @override
  String get settingsEditAprsRoute => 'APRS-Route bearbeiten';

  @override
  String get settingsName => 'Name';

  @override
  String get settingsNameHint => 'z. B. Standard';

  @override
  String get settingsDuplicateRoute =>
      'Eine Route mit diesem Namen existiert bereits.';

  @override
  String get settingsPath => 'Pfad';

  @override
  String get commonError => 'Fehler';

  @override
  String get commonConnect => 'Verbinden';

  @override
  String get commonDisconnect => 'Trennen';

  @override
  String get commonRename => 'Umbenennen';

  @override
  String get commonRemove => 'Entfernen';

  @override
  String connectScanError(String error) {
    return 'Suche nach Bluetooth-Geräten fehlgeschlagen: $error';
  }

  @override
  String get connectNoRadiosTitle => 'Keine Funkgeräte gefunden';

  @override
  String get connectNoRadiosBody =>
      'Es wurde kein kompatibles Funkgerät gefunden.\n\nStellen Sie sicher, dass Ihr Funkgerät eingeschaltet und Bluetooth aktiviert ist.';

  @override
  String get connectAllConnectedTitle => 'Alle verbunden';

  @override
  String get connectAllConnectedBody =>
      'Alle erkannten Funkgeräte sind bereits verbunden.';

  @override
  String get connectBluetoothOffTitle => 'Bluetooth nicht verfügbar';

  @override
  String get connectBluetoothOffBody =>
      'Bluetooth ist nicht verfügbar oder deaktiviert.\n\nBitte aktivieren Sie Bluetooth in den Einstellungen Ihres Geräts und versuchen Sie es erneut.';

  @override
  String get radioConnectionTitle => 'Funkgerät-Verbindung';

  @override
  String get radioConnectionEmpty =>
      'Keine kompatiblen Funkgeräte gefunden.\nStellen Sie sicher, dass Ihr Funkgerät eingeschaltet und Bluetooth aktiviert ist.';

  @override
  String get radioRenameTitle => 'Funkgerät umbenennen';

  @override
  String get radioRenamePrompt =>
      'Geben Sie einen benutzerdefinierten Namen für dieses Funkgerät ein:';

  @override
  String get radioRenameHint =>
      'Leer lassen, um den Standardnamen zu verwenden';

  @override
  String get updateTitle => 'Software-Update';

  @override
  String get updateChecking => 'Suche nach Updates...';

  @override
  String updateVersionAvailable(String version) {
    return 'Version $version ist verfügbar.';
  }

  @override
  String updateFreshDownload(String version) {
    return 'Version $version erfordert einen erneuten Download.';
  }

  @override
  String updateUnsupported(String version) {
    return 'Diese Version wird nicht mehr unterstützt. Aktualisieren Sie auf $version.';
  }

  @override
  String get updateUpToDate => 'Sie verwenden die neueste Version.';

  @override
  String updateCheckFailed(String error) {
    return 'Suche nach Updates fehlgeschlagen: $error';
  }

  @override
  String get updateDownloading => 'Update wird heruntergeladen...';

  @override
  String get updateDownloaded =>
      'Update heruntergeladen. Bereit zur Installation.';

  @override
  String updateDownloadFailed(String error) {
    return 'Download fehlgeschlagen: $error';
  }

  @override
  String updateInstallFailed(String error) {
    return 'Installation fehlgeschlagen: $error';
  }

  @override
  String updateDiagnosticsLog(String path) {
    return 'Wenn das Update nicht abgeschlossen wird, sehen Sie im Diagnoseprotokoll nach:\n$path';
  }

  @override
  String get updateInstallRestart => 'Installieren und neu starten';

  @override
  String get updateCheckAgain => 'Erneut prüfen';

  @override
  String get regionsTitle => 'Regionen umbenennen';

  @override
  String regionsMaxChars(int count) {
    return 'Regionsnamen können bis zu $count Zeichen lang sein.';
  }

  @override
  String regionLabel(int number) {
    return 'Region $number';
  }

  @override
  String get gpsInfoTitle => 'GPS-Informationen';

  @override
  String get gpsSectionConnection => 'Verbindung';

  @override
  String get gpsSectionFix => 'GPS-Fix';

  @override
  String get gpsSectionPosition => 'Position';

  @override
  String get gpsSectionMotion => 'Bewegung';

  @override
  String get gpsSectionTime => 'Zeit';

  @override
  String get gpsPortStatus => 'Portstatus';

  @override
  String get gpsNotConfigured => 'Nicht konfiguriert';

  @override
  String get gpsOpenReceiving => 'Geöffnet — Daten werden empfangen';

  @override
  String get gpsPermDeniedLinux =>
      'Zugriff verweigert — fügen Sie Ihren Benutzer zur Gruppe „dialout“ hinzu (sudo usermod -aG dialout \$USER), melden Sie sich dann ab und wieder an.';

  @override
  String get gpsPermDenied =>
      'Zugriff verweigert — die Anwendung kann nicht auf diesen Port zugreifen.';

  @override
  String get gpsPortError =>
      'Portfehler — der serielle Port konnte nicht geöffnet werden.';

  @override
  String get gpsFix => 'Fix';

  @override
  String get gpsFixQuality => 'Fix-Qualität';

  @override
  String get gpsSatellites => 'Satelliten';

  @override
  String get gpsNoData => 'Keine Daten';

  @override
  String get gpsActive => 'Aktiv';

  @override
  String get gpsNoFix => 'Kein Fix';

  @override
  String get gpsQualGps => 'GPS-Fix (1)';

  @override
  String get gpsQualDgps => 'DGPS-Fix (2)';

  @override
  String get gpsQualInvalid => 'Ungültig (0)';

  @override
  String gpsQualUnknown(int quality) {
    return '$quality (unbekannt)';
  }

  @override
  String get gpsLatitude => 'Breitengrad';

  @override
  String get gpsLatitudeDms => 'Breitengrad (DMS)';

  @override
  String get gpsLongitude => 'Längengrad';

  @override
  String get gpsLongitudeDms => 'Längengrad (DMS)';

  @override
  String get gpsAltitude => 'Höhe';

  @override
  String get gpsSpeed => 'Geschwindigkeit';

  @override
  String get gpsHeading => 'Kurs';

  @override
  String get gpsTimeUtc => 'GPS-Zeit (UTC)';

  @override
  String get gpsDate => 'GPS-Datum';

  @override
  String get gpsLastUpdate => 'Letzte Aktualisierung';

  @override
  String get trustedDevicesTitle => 'Vertrauenswürdige Geräte';

  @override
  String get trustedRemoveTitle => 'Vertrauenswürdiges Gerät entfernen';

  @override
  String trustedRemoveMessage(String name) {
    return '„$name“ aus der Liste der vertrauenswürdigen Geräte des Funkgeräts entfernen?';
  }

  @override
  String get trustedNoDevices => 'Keine vertrauenswürdigen Geräte gefunden.';

  @override
  String get pfConfigTitle => 'Tasten konfigurieren';

  @override
  String get pfSaveToRadio => 'Auf Funkgerät speichern';

  @override
  String get pfNoRadio => 'Kein Funkgerät verbunden.';

  @override
  String get pfNoButtons =>
      'Dieses Funkgerät meldet keine programmierbaren Tasten.';

  @override
  String get pfIntro =>
      'Wählen Sie für jede programmierbare Taste die Aktion für jeden Tastendruck-Typ. Änderungen werden beim Speichern auf das Funkgerät geschrieben.';

  @override
  String pfButtonLabel(int number) {
    return 'Taste $number';
  }

  @override
  String get pfActionShort => 'Kurzer Druck';

  @override
  String get pfActionLong => 'Langer Druck';

  @override
  String get pfActionVeryLong => 'Sehr langer Druck';

  @override
  String get pfActionVeryVeryLong => 'Sehr sehr langer Druck';

  @override
  String get pfActionDouble => 'Doppelter Druck';

  @override
  String get pfActionTriple => 'Dreifacher Druck';

  @override
  String get pfActionRepeat => 'Wiederholung';

  @override
  String get pfActionPressDown => 'Gedrückt halten';

  @override
  String get pfActionRelease => 'Loslassen';

  @override
  String get pfActionLongRelease => 'Langes Loslassen';

  @override
  String get pfActionVeryLongRelease => 'Sehr langes Loslassen';

  @override
  String get pfActionVeryVeryLongRelease => 'Sehr sehr langes Loslassen';

  @override
  String pfActionUnknown(int action) {
    return 'Aktion $action';
  }

  @override
  String get pfEffectDisabled => 'Deaktiviert';

  @override
  String get pfEffectAlarm => 'Alarm';

  @override
  String get pfEffectAlarmAndMute => 'Alarm und Stummschaltung';

  @override
  String get pfEffectToggleOffline => 'Offline umschalten';

  @override
  String get pfEffectToggleRadioTx => 'Funksenden umschalten';

  @override
  String get pfEffectToggleTxPower => 'Sendeleistung umschalten';

  @override
  String get pfEffectToggleFm => 'FM-Radio umschalten';

  @override
  String get pfEffectPrevChannel => 'Vorheriger Kanal';

  @override
  String get pfEffectNextChannel => 'Nächster Kanal';

  @override
  String get pfEffectTCall => 'T-Ton (1750 Hz)';

  @override
  String get pfEffectPrevRegion => 'Vorherige Region';

  @override
  String get pfEffectNextRegion => 'Nächste Region';

  @override
  String get pfEffectToggleChScan => 'Kanalsuchlauf umschalten';

  @override
  String get pfEffectMainPtt => 'Haupt-PTT';

  @override
  String get pfEffectSubPtt => 'Neben-PTT';

  @override
  String get pfEffectToggleMonitor => 'Monitor umschalten';

  @override
  String get pfEffectBtPairing => 'Bluetooth-Kopplung';

  @override
  String get pfEffectToggleDoubleCh => 'Doppelkanal umschalten';

  @override
  String get pfEffectToggleAbCh => 'A/B-Kanal umschalten';

  @override
  String get pfEffectSendLocation => 'Position senden';

  @override
  String get pfEffectOneClickLink => 'Ein-Klick-Verbindung';

  @override
  String get pfEffectVolDown => 'Lautstärke verringern';

  @override
  String get pfEffectVolUp => 'Lautstärke erhöhen';

  @override
  String get pfEffectToggleMute => 'Stummschaltung umschalten';

  @override
  String pfEffectUnknown(int effect) {
    return 'Unbekannt ($effect)';
  }

  @override
  String get importChannelsTitle => 'Kanäle importieren';

  @override
  String importChannelsTitleWith(String name) {
    return 'Kanäle importieren — $name';
  }

  @override
  String get importIntro =>
      'Ziehen Sie einen Kanal von links auf einen Steckplatz des Funkgeräts oder wählen Sie einen Kanal und einen Steckplatz aus und tippen Sie dann auf den Pfeil. Tippen Sie auf das Info-Symbol für Details. Kanäle werden nur dann auf das Funkgerät geschrieben, wenn Sie auf OK tippen.';

  @override
  String importOkCount(int count) {
    return 'OK ($count)';
  }

  @override
  String importImportedHeader(int count) {
    return 'Importiert ($count)';
  }

  @override
  String get importNoChannels => 'Keine importierten Kanäle.';

  @override
  String importRadioChannelsHeader(int count) {
    return 'Funkgerät-Kanäle ($count)';
  }

  @override
  String get importNoRadioChannels => 'Keine Funkgerät-Kanäle.';

  @override
  String get importMoveTooltip =>
      'Ausgewählten Kanal auf ausgewählten Steckplatz verschieben';

  @override
  String get importCopyAllTooltip =>
      'Alle importierten Kanäle 1:1 auf die Funkgerät-Steckplätze kopieren';

  @override
  String importChannelShort(int number) {
    return 'Kanal $number';
  }

  @override
  String get importClearTooltip => 'Ausstehende Zuweisung löschen';

  @override
  String get importChannelDetails => 'Kanaldetails';

  @override
  String get riTitle => 'Funkgerät-Informationen';

  @override
  String get riNoRadioConnected => 'Kein Funkgerät verbunden';

  @override
  String get riConnectPrompt =>
      'Verbinden Sie ein Funkgerät, um dessen Informationen anzuzeigen.';

  @override
  String riRadioFallback(int id) {
    return 'Funkgerät $id';
  }

  @override
  String get riSectionRadio => 'Funkgerät';

  @override
  String get riSectionDeviceInfo => 'Geräteinformationen';

  @override
  String get riSectionDeviceStatus => 'Gerätestatus';

  @override
  String get riSectionDeviceSettings => 'Geräteeinstellungen';

  @override
  String get riSectionBss => 'BSS-Einstellungen';

  @override
  String get riSectionPosition => 'Position';

  @override
  String get riName => 'Name';

  @override
  String get riStatus => 'Status';

  @override
  String get riSettingsLabel => 'Einstellungen';

  @override
  String get riNoData => 'Keine Daten';

  @override
  String get riNoGpsData => 'Keine GPS-Daten';

  @override
  String get riNoGpsLock => 'Kein GPS-Fix';

  @override
  String get riGpsLocked => 'GPS-Fix erhalten';

  @override
  String get riTrue => 'Ja';

  @override
  String get riFalse => 'Nein';

  @override
  String get riPresent => 'Vorhanden';

  @override
  String get riNotPresent => 'Nicht vorhanden';

  @override
  String get riSupported => 'Unterstützt';

  @override
  String get riNotSupported => 'Nicht unterstützt';

  @override
  String get riCurrent => 'Aktuell';

  @override
  String get riOff => 'Aus';

  @override
  String riChannelValue(int number) {
    return 'Kanal $number';
  }

  @override
  String riSeconds(int count) {
    return '$count Sekunde(n)';
  }

  @override
  String riMeters(String value) {
    return '$value Meter';
  }

  @override
  String riDegrees(String value) {
    return '$value Grad';
  }

  @override
  String get riProductId => 'Produkt-ID';

  @override
  String get riVendorId => 'Hersteller-ID';

  @override
  String get riDmrSupport => 'DMR-Unterstützung';

  @override
  String get riGmrsSupport => 'GMRS-Unterstützung';

  @override
  String get riHardwareSpeaker => 'Hardware-Lautsprecher';

  @override
  String get riHardwareVersion => 'Hardware-Version';

  @override
  String get riSoftwareVersion => 'Software-Version';

  @override
  String get riRegionCount => 'Anzahl der Regionen';

  @override
  String get riMediumPower => 'Mittlere Leistung';

  @override
  String get riChannelCount => 'Anzahl der Kanäle';

  @override
  String get riNoaa => 'NOAA';

  @override
  String get riWeather => 'Wetter';

  @override
  String riWeatherChannel(int number) {
    return 'Wetter $number';
  }

  @override
  String get riBroadcastFm => 'UKW-Radio';

  @override
  String get riRadioLabel => 'Funkgerät';

  @override
  String get riVfo => 'VFO';

  @override
  String get riFreqRangeCount => 'Anzahl der Frequenzbereiche';

  @override
  String get riPowerOn => 'Eingeschaltet';

  @override
  String get riInTx => 'Sendet';

  @override
  String get riInRx => 'Empfängt';

  @override
  String get riDoubleChannelLabel => 'Doppelkanal';

  @override
  String get riScanning => 'Suchlauf';

  @override
  String get riCurrentChannelId => 'Aktuelle Kanal-ID';

  @override
  String get riGpsLockedLabel => 'GPS gesperrt';

  @override
  String get riHfpConnected => 'HFP verbunden';

  @override
  String get riAocConnected => 'AOC verbunden';

  @override
  String get riRssi => 'RSSI';

  @override
  String get riCurrentRegion => 'Aktuelle Region';

  @override
  String get riAccuracy => 'Genauigkeit';

  @override
  String get riReceivedTime => 'Empfangszeit';

  @override
  String get riGpsTimeLocal => 'GPS-Ortszeit';

  @override
  String get riGpsTimeUtcLabel => 'GPS-UTC-Zeit';

  @override
  String get tabDetach => 'Ablösen...';

  @override
  String get tabClear => 'Löschen';

  @override
  String get tabSaveToFile => 'In Datei speichern...';

  @override
  String get commonNoRadioConnected => 'Kein Funkgerät verbunden.';

  @override
  String errorOpeningFileDialog(String error) {
    return 'Fehler beim Öffnen des Dateidialogs: $error';
  }

  @override
  String errorSavingFile(String error) {
    return 'Fehler beim Speichern der Datei: $error';
  }

  @override
  String get debugSaveTitle => 'Debug-Protokoll speichern';

  @override
  String debugLogSavedTo(String path) {
    return 'Debug-Protokoll gespeichert in $path';
  }

  @override
  String get debugShowBluetoothFrames => 'Bluetooth-Frames anzeigen';

  @override
  String get debugLoopbackMode => 'Loopback-Modus';

  @override
  String get debugQueryDeviceNames => 'Gerätenamen abfragen';

  @override
  String get debugRawCommand => 'Rohbefehl...';

  @override
  String get debugAutoScroll => 'Automatisches Scrollen';

  @override
  String get debugFirmwareUpdate => 'Firmware-Update...';

  @override
  String get debugShowBuiltInMenus => 'Integrierte Menüs anzeigen';

  @override
  String get packetsCopyHex => 'HEX-Paket kopieren';

  @override
  String get packetsHexCopied => 'HEX-Paket in die Zwischenablage kopiert';

  @override
  String get packetsSaveTitle => 'Paketaufzeichnung speichern';

  @override
  String get packetsSaved => 'Paketaufzeichnung gespeichert';

  @override
  String packetsSavedTo(String path) {
    return 'Paketaufzeichnung gespeichert in $path';
  }

  @override
  String get packetsShowDecode => 'Paketdekodierung anzeigen';

  @override
  String get packetsEmpty => 'Keine Pakete aufgezeichnet';

  @override
  String get packetsColTime => 'Zeit';

  @override
  String get packetsColChannel => 'Kanal';

  @override
  String get packetsColData => 'Daten';

  @override
  String get commonAdd => 'Hinzufügen';

  @override
  String get commonEdit => 'Bearbeiten';

  @override
  String get commonEditEllipsis => 'Bearbeiten...';

  @override
  String get commonAddEllipsis => 'Hinzufügen...';

  @override
  String get commonExportEllipsis => 'Exportieren...';

  @override
  String get commonImportEllipsis => 'Importieren...';

  @override
  String get contactsTypeGeneric => 'Generische Stationen';

  @override
  String get contactsTypeAprs => 'APRS-Stationen';

  @override
  String get contactsTypeTerminal => 'Terminal-Stationen';

  @override
  String get contactsTypeBbs => 'BBS-Stationen';

  @override
  String get contactsTypeWinlink => 'Winlink-Stationen';

  @override
  String get contactsTypeTorrent => 'Torrent-Stationen';

  @override
  String get contactsTypeAgwpe => 'AGWPE-Stationen';

  @override
  String get contactsExists =>
      'Eine Station mit diesem Rufzeichen und Typ existiert bereits';

  @override
  String get contactsRemovePrompt => 'Ausgewählte Station entfernen?';

  @override
  String get contactsNoExport => 'Keine Stationen zum Exportieren';

  @override
  String get contactsExportTitle => 'Stationen exportieren';

  @override
  String get contactsImportTitle => 'Stationen importieren';

  @override
  String contactsExported(int count) {
    return '$count Stationen exportiert';
  }

  @override
  String contactsImported(int count) {
    return '$count Stationen importiert';
  }

  @override
  String get contactsUnableOpen => 'Adressbuch kann nicht geöffnet werden';

  @override
  String get contactsInvalid => 'Ungültiges Adressbuch';

  @override
  String get contactsColCallsign => 'Rufzeichen';

  @override
  String get contactsColName => 'Name';

  @override
  String get contactsColDescription => 'Beschreibung';

  @override
  String terminalHeaderWith(String callsign) {
    return 'Terminal - $callsign';
  }

  @override
  String get terminalNoRadio => 'Kein Funkgerät für die Verbindung verfügbar.';

  @override
  String get terminalShowCallsign => 'Rufzeichen anzeigen';

  @override
  String get terminalWordWrap => 'Zeilenumbruch';

  @override
  String get terminalWaitForConnection => 'Auf Verbindung warten...';

  @override
  String get terminalSend => 'Senden';

  @override
  String terminalConnectedTo(String callsign) {
    return 'Mit $callsign verbunden';
  }

  @override
  String terminalConnectingTo(String callsign) {
    return 'Verbinde mit $callsign...';
  }

  @override
  String get terminalInvalidCallsignDest => 'Ungültiges Rufzeichen/Ziel';

  @override
  String get terminalInvalidCallsign => 'Ungültiges Rufzeichen';

  @override
  String get terminalNotConnected => 'Nicht verbunden';

  @override
  String terminalError(String error) {
    return 'Fehler: $error';
  }

  @override
  String get terminalBrotli =>
      'Brotli-komprimiertes Paket empfangen (nicht unterstützt)';

  @override
  String get audioSectionDevices => 'Geräte';

  @override
  String get audioRefreshDevices => 'Geräteliste aktualisieren';

  @override
  String get audioOutput => 'Ausgang';

  @override
  String get audioInput => 'Eingang';

  @override
  String get audioVolume => 'Lautstärke';

  @override
  String get audioSquelch => 'Rauschsperre';

  @override
  String get audioSectionComputer => 'Computer';

  @override
  String get audioApplication => 'Anwendung';

  @override
  String get audioMaster => 'Master';

  @override
  String get audioMicGain => 'Mikrofonverstärkung';

  @override
  String get audioMicNotAvailable =>
      'Mikrofonaufnahme ist auf dieser Plattform nicht verfügbar.';

  @override
  String get audioMicNotSupported =>
      'Mikrofonaufnahme wird hier nicht unterstützt.';

  @override
  String get audioSpectRadio => 'Funk-Spektrograf';

  @override
  String get audioSpectMic => 'Mikrofon-Spektrograf';

  @override
  String get audioSpectNone => 'Spektrograf';

  @override
  String get audioSpectMenuNone => 'Kein Spektrograf';

  @override
  String get audioDartQuality => 'DART-Empfangsqualität';

  @override
  String get audioDartSignalAnalysis => 'DART-Signalanalyse';

  @override
  String get audioDefault => 'Standard';

  @override
  String get audioMute => 'Stummschalten';

  @override
  String get audioUnmute => 'Stummschaltung aufheben';

  @override
  String get audioEnable => 'Aktivieren';

  @override
  String get audioDisable => 'Deaktivieren';

  @override
  String get audioNa => 'N/V';

  @override
  String get bbsHeaderActive => 'BBS - Aktiv';

  @override
  String get bbsActivate => 'Aktivieren';

  @override
  String get bbsDeactivate => 'Deaktivieren';

  @override
  String get bbsViewTraffic => 'Datenverkehr anzeigen';

  @override
  String get bbsClearTraffic => 'Datenverkehr löschen';

  @override
  String get bbsClearStats => 'Statistiken löschen';

  @override
  String get bbsColCallSign => 'Rufzeichen';

  @override
  String get bbsColLastSeen => 'Zuletzt gesehen';

  @override
  String get bbsColStats => 'Statistiken';

  @override
  String get bbsTraffic => 'Datenverkehr';

  @override
  String get bbsJustNow => 'Gerade eben';

  @override
  String bbsMinAgo(int n) {
    return 'vor $n Min.';
  }

  @override
  String bbsHoursAgo(int n) {
    return 'vor $n Std.';
  }

  @override
  String bbsDaysAgo(int n) {
    return 'vor $n Tg.';
  }

  @override
  String get commonDelete => 'Löschen';

  @override
  String get torrentAddFile => 'Datei hinzufügen';

  @override
  String get torrentShowDetails => 'Details anzeigen';

  @override
  String get torrentFileSaved => 'Datei gespeichert.';

  @override
  String get torrentFileDataUnavailable =>
      'Speicherfehler: Dateidaten nicht verfügbar';

  @override
  String get torrentUnknownError => 'Unbekannter Fehler';

  @override
  String get torrentSaveTitle => 'Torrent-Datei speichern';

  @override
  String get torrentNoRadios =>
      'Kein Funkgerät verbunden. Verbinden Sie zuerst ein Funkgerät.';

  @override
  String get torrentMultiRadio =>
      'Der Torrent-Modus mit mehreren Funkgeräten wird noch nicht unterstützt.';

  @override
  String get torrentDropSingle => 'Bitte legen Sie nur eine Datei ab.';

  @override
  String get torrentDeletePrompt => 'Ausgewählte Torrent-Datei löschen?';

  @override
  String get torrentPause => 'Pause';

  @override
  String get torrentShare => 'Teilen';

  @override
  String get torrentRequest => 'Anfordern';

  @override
  String get torrentSaveAs => 'Speichern unter...';

  @override
  String get torrentDropToShare => 'Legen Sie eine Datei zum Teilen ab';

  @override
  String get torrentNoFiles =>
      'Keine Torrent-Dateien. Fügen Sie eine Datei hinzu oder legen Sie eine zum Teilen ab.';

  @override
  String get torrentUnknownSource => 'Unbekannt';

  @override
  String get torrentColFile => 'Datei';

  @override
  String get torrentColMode => 'Modus';

  @override
  String get torrentDetailFileName => 'Dateiname';

  @override
  String get torrentDetailSource => 'Quelle';

  @override
  String get torrentDetailFileSize => 'Dateigröße';

  @override
  String torrentBytes(int count) {
    return '$count Bytes';
  }

  @override
  String get torrentDetailCompression => 'Komprimierung';

  @override
  String get torrentDetailBlocks => 'Blöcke';

  @override
  String get torrentDetailsTitle => 'Torrent-Details';

  @override
  String get torrentSelectPrompt =>
      'Wählen Sie einen Torrent, um Details anzuzeigen';

  @override
  String get torrentModePaused => 'Angehalten';

  @override
  String get torrentModeSharing => 'Wird geteilt';

  @override
  String get torrentModeRequesting => 'Wird angefordert';

  @override
  String get torrentModeError => 'Fehler';

  @override
  String get torrentCompUnknown => 'Unbekannt';

  @override
  String get mailInbox => 'Posteingang';

  @override
  String get mailOutbox => 'Postausgang';

  @override
  String get mailDraft => 'Entwurf';

  @override
  String get mailSent => 'Gesendet';

  @override
  String get mailArchive => 'Archiv';

  @override
  String get mailTrash => 'Papierkorb';

  @override
  String get mailInternet => 'Internet';

  @override
  String get mailDeleteTitle => 'E-Mail löschen';

  @override
  String get mailMoveToTrashTitle => 'In den Papierkorb verschieben';

  @override
  String get mailDeletePermanent =>
      'Ausgewählte E-Mail dauerhaft löschen? Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get mailMoveToTrashPrompt =>
      'Ausgewählte E-Mail in den Papierkorb verschieben?';

  @override
  String get mailMove => 'Verschieben';

  @override
  String get mailOpen => 'Öffnen';

  @override
  String get mailReply => 'Antworten';

  @override
  String get mailReplyAll => 'Allen antworten';

  @override
  String get mailForward => 'Weiterleiten';

  @override
  String get mailShowPreview => 'Vorschau anzeigen';

  @override
  String get mailBackup => 'E-Mail sichern...';

  @override
  String get mailRestore => 'E-Mail wiederherstellen...';

  @override
  String get mailShowTraffic => 'Datenverkehr anzeigen...';

  @override
  String mailBackupFailed(String error) {
    return 'Sicherung fehlgeschlagen: $error';
  }

  @override
  String get mailBackupTitle => 'E-Mail sichern';

  @override
  String get mailBackupSuccess => 'Sicherung erfolgreich abgeschlossen.';

  @override
  String get mailRestoreTitle => 'E-Mail wiederherstellen';

  @override
  String get mailRestoreUnableOpen =>
      'Sicherungsdatei kann nicht geöffnet werden';

  @override
  String mailRestoreFailed(String error) {
    return 'Wiederherstellung fehlgeschlagen: $error';
  }

  @override
  String get mailNew => 'Neu';

  @override
  String get mailNewMail => 'Neue E-Mail';

  @override
  String get mailColTime => 'Zeit';

  @override
  String get mailColTo => 'An';

  @override
  String get mailColFrom => 'Von';

  @override
  String get mailColSubject => 'Betreff';

  @override
  String get mailSelectPreview => 'Wählen Sie eine Nachricht für die Vorschau';

  @override
  String get commonUnknown => 'Unbekannt';

  @override
  String get mapOfflineMode => 'Offline-Modus';

  @override
  String get mapOfflineMap => 'Offline-Karte';

  @override
  String get mapCacheArea => 'Bereich zwischenspeichern...';

  @override
  String get mapCenterGps => 'Auf GPS zentrieren';

  @override
  String get mapShowTracks => 'Spuren anzeigen';

  @override
  String get mapShowMarkers => 'Markierungen anzeigen';

  @override
  String get mapShowAirplanes => 'Flugzeuge anzeigen';

  @override
  String get mapLargeMarkers => 'Große Markierungen';

  @override
  String get mapShowContactsOnly => 'Nur Kontakte anzeigen';

  @override
  String get mapFilterAll => 'Alle';

  @override
  String get mapFilterLast30 => 'Letzte 30 Minuten';

  @override
  String get mapFilterLastHour => 'Letzte Stunde';

  @override
  String get mapFilterLast6 => 'Letzte 6 Stunden';

  @override
  String get mapFilterLast12 => 'Letzte 12 Stunden';

  @override
  String get mapFilterLast24 => 'Letzte 24 Stunden';

  @override
  String get mapCacheTitle => 'Kartenbereich zwischenspeichern';

  @override
  String mapCachePrompt(int count, int minZoom, int maxZoom) {
    return '$count Kacheln für die Zoomstufen $minZoom–$maxZoom herunterladen?\n\nDadurch wird der ausgewählte Bereich für die Offline-Nutzung zwischengespeichert.';
  }

  @override
  String get mapDownloadingTitle => 'Kacheln werden heruntergeladen';

  @override
  String mapTilesProgress(int done, int total) {
    return '$done / $total Kacheln';
  }

  @override
  String get mapDragToSelect =>
      'Ziehen Sie, um den zwischenzuspeichernden Bereich auszuwählen';

  @override
  String get aprsNoChannel => 'Kein Funkgerät mit APRS-Kanal verfügbar';

  @override
  String get aprsNoLoadedChannels =>
      'Kein Funkgerät mit geladenen Kanälen verfügbar';

  @override
  String get aprsDetails => 'Details...';

  @override
  String get aprsShowLocation => 'Position anzeigen...';

  @override
  String get aprsSetReceiver => 'Als Empfänger festlegen';

  @override
  String get aprsCopyMessage => 'Nachricht kopieren';

  @override
  String get aprsCopyCallsign => 'Rufzeichen kopieren';

  @override
  String get aprsCopyChannel => 'Kanal kopieren';

  @override
  String get aprsClearTitle => 'APRS-Nachrichten löschen';

  @override
  String get aprsClearPrompt =>
      'Alle APRS-Nachrichten löschen? Dadurch werden auch alle APRS-Markierungen von der Karte entfernt. Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get aprsShowAll => 'Alle Nachrichten anzeigen';

  @override
  String get aprsSendSms => 'SMS-Nachricht senden...';

  @override
  String get aprsWeatherReport => 'Wetterbericht...';

  @override
  String get aprsBeaconSettingsMenu => 'Baken-Einstellungen...';

  @override
  String get aprsDropShare => 'Ablegen, um diesen Kanal zu teilen';

  @override
  String get aprsBeaconWarning =>
      'Die Baken-Aussendung ist auf dem aktuellen Kanal aktiviert, was nicht empfohlen wird.';

  @override
  String aprsBeaconActive(String interval) {
    return 'Die Funkbake ist aktiv, Intervall: $interval.';
  }

  @override
  String get aprsBeaconSettings => 'Baken-Einstellungen';

  @override
  String aprsIntervalSeconds(int count) {
    return '$count Sekunden';
  }

  @override
  String get aprsIntervalMinute => '1 Minute';

  @override
  String aprsIntervalMinutes(int count) {
    return '$count Minuten';
  }

  @override
  String get aprsMissingChannel =>
      'Auf dem verbundenen Funkgerät ist kein „APRS“-Kanal konfiguriert. Fügen Sie einen APRS-Kanal hinzu, um APRS-Nachrichten zu senden und zu empfangen.';

  @override
  String get aprsSetup => 'Einrichten';

  @override
  String get aprsTypeMessage => 'Nachricht eingeben...';

  @override
  String get commonYes => 'Ja';

  @override
  String get commonNo => 'Nein';

  @override
  String get commonSend => 'Senden';

  @override
  String commonSavedTo(String path) {
    return 'Gespeichert in $path';
  }

  @override
  String commsFailedLoadImage(String error) {
    return 'Bild konnte nicht geladen werden: $error';
  }

  @override
  String commsFailedSaveImage(String error) {
    return 'Bild konnte nicht gespeichert werden: $error';
  }

  @override
  String commsFailedEncodeSstv(String error) {
    return 'SSTV-Audio konnte nicht codiert werden: $error';
  }

  @override
  String commsFailedLoadAudio(String error) {
    return 'Audio konnte nicht geladen werden: $error';
  }

  @override
  String get commsUnsupportedWav => 'Nicht unterstützte oder leere WAV-Datei.';

  @override
  String get commsSstvWebUnavailable =>
      'SSTV-Bildaufnahme/-übertragung ist im Web nicht verfügbar.';

  @override
  String get commsNoRadioVoice =>
      'Kein Funkgerät für die Sprachübertragung verbunden.';

  @override
  String get commsSelectImageTitle => 'Bild für SSTV auswählen';

  @override
  String get commsSelectWavTitle => 'WAV-Audiodatei auswählen';

  @override
  String get commsRecordingWebUnavailable =>
      'Das Abspielen von Aufnahmen aus Dateien ist im Web nicht verfügbar.';

  @override
  String get commsFileNoLongerExists => 'Die Datei existiert nicht mehr.';

  @override
  String get commsSaveAsTitle => 'Speichern unter';

  @override
  String get commsTransmitDisabledAprs =>
      'Die Übertragung ist deaktiviert, wenn VFO A auf den APRS-Kanal eingestellt ist.';

  @override
  String get commsWaitTransmission =>
      'Bitte warten Sie, bis die aktuelle Übertragung abgeschlossen ist.';

  @override
  String get commsConnectRadioChat =>
      'Verbinden Sie ein Funkgerät, bevor Sie eine Chat-Nachricht senden.';

  @override
  String get commsEnableAudioMode =>
      'Aktivieren Sie Audio (die Schaltfläche Aktivieren), bevor Sie in diesem Modus senden.';

  @override
  String get commsMicNotSupported =>
      'Mikrofonaufnahme wird auf dieser Plattform nicht unterstützt.';

  @override
  String get commsConnectRadioPtt =>
      'Verbinden Sie ein Funkgerät, bevor Sie Push-to-Talk verwenden.';

  @override
  String get commsEnableAudioPtt =>
      'Aktivieren Sie Audio (die Schaltfläche Aktivieren), bevor Sie Push-to-Talk verwenden.';

  @override
  String get commsSwitchChatShare =>
      'Wechseln Sie in den Chat-Modus, um einen Kanal zu teilen.';

  @override
  String get commsModePtt => 'PTT';

  @override
  String get commsModeChat => 'Chat';

  @override
  String get commsModeSpeak => 'Sprechen';

  @override
  String get commsModeMorse => 'Morse';

  @override
  String get commsModeDtmf => 'DTMF';

  @override
  String get commsRecordAudio => 'Audio aufnehmen';

  @override
  String get commsSendImage => 'Bild senden...';

  @override
  String get commsSendAudio => 'Audio senden...';

  @override
  String get commsPttReleaseSettings => 'PTT-Loslass-Einstellungen...';

  @override
  String get commsClearHistory => 'Verlauf löschen';

  @override
  String get commsShowImage => 'Bild anzeigen...';

  @override
  String get commsPlayRecording => 'Aufnahme abspielen...';

  @override
  String get commsSaveAsMenu => 'Speichern unter...';

  @override
  String get commsShowLocation => 'Position anzeigen';

  @override
  String get commsClearHistoryPrompt =>
      'Möchten Sie den Sprachverlauf wirklich löschen?';

  @override
  String get commsAudioMuted => 'Audio ist stummgeschaltet.';

  @override
  String get commsUnmute => 'Stummschaltung aufheben';

  @override
  String get commsPttTransmitting => 'Übertragung läuft...';

  @override
  String get commsPttHold => 'PTT - Zum Senden gedrückt halten';

  @override
  String get commsDtmfHint => 'DTMF-Ziffern eingeben (0-9, *, #)...';

  @override
  String get mailComposeNewTitle => 'Neue Nachricht';

  @override
  String get mailComposeEditTitle => 'Nachricht bearbeiten';

  @override
  String get mailDiscardChanges => 'Änderungen an dieser Nachricht verwerfen?';

  @override
  String get mailDiscardMessage => 'Diese Nachricht verwerfen?';

  @override
  String get mailDiscard => 'Verwerfen';

  @override
  String get mailAddCc => 'Cc hinzufügen';

  @override
  String get mailCc => 'Cc';

  @override
  String get mailRemoveCc => 'Cc entfernen';

  @override
  String get mailMessageLabel => 'Nachricht';

  @override
  String get mailSaveDraft => 'Entwurf speichern';

  @override
  String get smsTitle => 'SMS-Nachricht senden';

  @override
  String get smsPhoneNumber => 'Telefonnummer';

  @override
  String get smsIntro =>
      'Sie können SMS-Nachrichten an Telefone in den USA, Puerto Rico, Kanada, Australien und dem Vereinigten Königreich senden, sofern die Nummer den Dienst bereits akzeptiert hat. Sie können sich hier registrieren: ';

  @override
  String get locationTitle => 'Position';

  @override
  String get beaconIntro =>
      'Ändern Sie, wie das Funkgerät Informationen über sich selbst aussendet, einschließlich Position, Spannung und einer benutzerdefinierten Nachricht. Andere Stationen in der Nähe können diese Informationen sehen.';

  @override
  String beaconRadio(String name) {
    return 'Funkgerät: $name';
  }

  @override
  String get beaconSection => 'Bake';

  @override
  String get beaconPacketFormat => 'Paketformat';

  @override
  String get beaconInterval => 'Baken-Intervall';

  @override
  String get beaconAprsCallsign => 'APRS-Rufzeichen';

  @override
  String get beaconCallsignHint => 'Rufzeichen - Stations-ID';

  @override
  String get beaconCallsignInvalid =>
      'Geben Sie ein gültiges Rufzeichen und eine gültige Stations-ID ein (z. B. W1AW-5)';

  @override
  String get beaconAprsMessage => 'APRS-Nachricht';

  @override
  String get beaconShareLocation => 'Position teilen';

  @override
  String get beaconSendVoltage => 'Spannung senden';

  @override
  String get beaconAllowPositionCheck => 'Positionsprüfung zulassen';

  @override
  String get beaconChannelCurrent => 'Aktuell (nicht empfohlen)';

  @override
  String beaconEverySeconds(int n) {
    return 'Alle $n Sekunden';
  }

  @override
  String beaconEveryMinutes(int n) {
    return 'Alle $n Minuten';
  }

  @override
  String get assConnectTerminal => 'Mit Terminal-Station verbinden';

  @override
  String get assConnectBbs => 'Mit BBS-Station verbinden';

  @override
  String get assConnectWinlink => 'Mit Winlink-Gateway verbinden';

  @override
  String get assConnectStation => 'Mit Station verbinden';

  @override
  String get assNew => 'Neu…';

  @override
  String get attSelectFile => 'Datei zum Teilen auswählen';

  @override
  String get attCompressing => 'Wird komprimiert...';

  @override
  String get attTitle => 'Torrent-Datei hinzufügen';

  @override
  String get attSelect => 'Auswählen...';

  @override
  String get attDescriptionOptional => 'Beschreibung (optional)';

  @override
  String get stationTitleVoice => 'Sprachstation';

  @override
  String get stationTitleAprs => 'APRS-Station';

  @override
  String get stationTitleTerminal => 'Terminal-Station';

  @override
  String get stationTitleWinlink => 'Winlink-Gateway';

  @override
  String get stationTitleGeneric => 'Station';

  @override
  String get stationTypeOptionVoice => 'Sprach- / generische Station';

  @override
  String get stationTypeLabel => 'Stationstyp';

  @override
  String get stationAprsRoute => 'APRS-Route';

  @override
  String get stationUseAuth => 'Nachrichtenauthentifizierung verwenden';

  @override
  String get stationAuthPassword => 'Authentifizierungspasswort';

  @override
  String get stationPasswordRequired => 'Passwort erforderlich';

  @override
  String get stationTerminalProtocol => 'Terminal-Protokoll';

  @override
  String get stationAx25Destination => 'AX.25-Ziel (z. B. CALL-1)';

  @override
  String get stationAx25Invalid => 'Ungültige AX.25-Adresse';

  @override
  String get stationModem => 'Modem';

  @override
  String get apdTitle => 'APRS-Paketdetails';

  @override
  String get apdCopyAll => 'Alles kopieren';

  @override
  String get apdCopyValue => 'Wert kopieren';

  @override
  String get apdValueCopied => 'Wert kopiert';

  @override
  String get apdAllValuesCopied => 'Alle Werte kopiert';

  @override
  String get apdNoDetails => 'Keine Details verfügbar.';

  @override
  String get apdShowLocation => 'Position anzeigen...';

  @override
  String get acfgTitle => 'APRS-Kanal konfigurieren';

  @override
  String get acfgIntro =>
      'Die APRS-Frequenz variiert je nach Weltregion. Verwenden Sie diese Website, um die passende Frequenz zur Konfiguration des APRS-Kanals zu finden.';

  @override
  String get acfgConfiguration => 'APRS-Konfiguration';

  @override
  String get acfgFrequency => 'Frequenz';

  @override
  String get acfgFrequencyHint => '144.39 in Nordamerika\n144.80 in Europa';

  @override
  String get acfgChannelOverwritten =>
      'Der ausgewählte Kanal wird überschrieben';

  @override
  String get sstvSendTitle => 'SSTV-Bild senden';

  @override
  String sstvSendTitleNamed(String name) {
    return 'SSTV-Bild senden - $name';
  }

  @override
  String get sstvMode => 'Modus:';

  @override
  String sstvTransmitTime(String time) {
    return 'Sendezeit: ~$time';
  }

  @override
  String get msgdTitle => 'Nachrichtendetails';

  @override
  String get msgdFieldType => 'Typ';

  @override
  String get msgdFieldDirection => 'Richtung';

  @override
  String get msgdFieldTime => 'Zeit';

  @override
  String get msgdFieldSource => 'Quelle';

  @override
  String get msgdFieldReceiver => 'Empfänger';

  @override
  String get msgdFieldDuration => 'Dauer';

  @override
  String get msgdFieldLatitude => 'Breitengrad';

  @override
  String get msgdFieldLongitude => 'Längengrad';

  @override
  String get msgdFieldMessage => 'Nachricht';

  @override
  String get msgdFieldFile => 'Datei';

  @override
  String get msgdDirReceived => 'Empfangen';

  @override
  String get msgdDirSent => 'Gesendet';

  @override
  String get msgdTypeVoice => 'Sprache';

  @override
  String get msgdTypeVoiceClip => 'Sprachclip';

  @override
  String get msgdTypeRecording => 'Aufnahme';

  @override
  String get msgdTypeSstvPicture => 'SSTV-Bild';

  @override
  String get msgdTypeIdentification => 'Identifikation';

  @override
  String get msgdTypeChatMessage => 'Chat-Nachricht';

  @override
  String get msgdTypeAx25Packet => 'AX.25-Paket';

  @override
  String get rpbFailedToLoad => 'Aufnahme konnte nicht geladen werden.';

  @override
  String get ivwFailedToLoad => 'Bild konnte nicht geladen werden.';

  @override
  String get rawTitle => 'Roher Funkbefehl';

  @override
  String get rawCommand => 'Befehl';

  @override
  String get rawHexPayload => 'HEX-Nutzdaten (optional)';

  @override
  String get rawResponse => 'Antwort';

  @override
  String get identTitle => 'PTT-Loslass-Einstellungen';

  @override
  String get identDescription =>
      'Wenn aktiviert, sendet es Ihr Rufzeichen und/oder Ihre Positionsinformationen jedes Mal, wenn Sie die PTT-Taste auf dem Kanal loslassen, auf dem Sie senden.';

  @override
  String get identCallsignHint => 'Rufzeichen - Stations-ID eingeben';

  @override
  String get identSendCallsign => 'Rufzeichen senden';

  @override
  String get identSendPosition => 'Position senden';

  @override
  String get commonOn => 'Ein';

  @override
  String get commonOff => 'Aus';

  @override
  String get commonNone => 'Keine';

  @override
  String chChannelNumber(int n) {
    return 'Kanal $n';
  }

  @override
  String chChShort(int n) {
    return 'Kanal $n';
  }

  @override
  String get chMoreSettings => 'Weitere Einstellungen';

  @override
  String get chChannelNameHint => 'Kanalname';

  @override
  String get chFrequencyMhz => 'Frequenz (MHz)';

  @override
  String get chReceiveMhz => 'Empfang (MHz)';

  @override
  String get chTransmitMhz => 'Senden (MHz)';

  @override
  String get chMode => 'Modus';

  @override
  String get chPower => 'Leistung';

  @override
  String get chBandwidth => 'Bandbreite';

  @override
  String get chReceiveTone => 'Empfangston (CTCSS / DCS)';

  @override
  String get chTransmitTone => 'Sendeton (CTCSS / DCS)';

  @override
  String get chDisableTransmit => 'Senden deaktivieren';

  @override
  String get chMute => 'Stummschalten';

  @override
  String get chScan => 'Suchlauf';

  @override
  String get chTalkAround => 'Talk around';

  @override
  String get chDeemphasis => 'Deemphasis';

  @override
  String get chPowerHigh => 'Hoch';

  @override
  String get chPowerMedium => 'Mittel';

  @override
  String get chPowerLow => 'Niedrig';

  @override
  String get chBandwidthWide => '25 KHz breit';

  @override
  String get chBandwidthNarrow => '12.5 KHz schmal';

  @override
  String get chClearTitle => 'Kanal löschen';

  @override
  String chClearConfirm(int n) {
    return 'Kanal $n löschen?\n\nDadurch werden Frequenz, Name und Einstellungen dieses Steckplatzes auf dem Funkgerät entfernt.';
  }

  @override
  String get cdRxFrequency => 'RX-Frequenz';

  @override
  String get cdTxFrequency => 'TX-Frequenz';

  @override
  String get cdRxModulation => 'RX-Modulation';

  @override
  String get cdTxModulation => 'TX-Modulation';

  @override
  String get cdRxTone => 'RX-Ton';

  @override
  String get cdTxTone => 'TX-Ton';

  @override
  String get cdTxDisabled => 'Senden deaktiviert';

  @override
  String get cdTalkAround => 'Talk around';

  @override
  String get cdEmpty => '(leer)';

  @override
  String get cdBandwidthWide => '25 kHz (breit)';

  @override
  String get cdBandwidthNarrow => '12.5 kHz (schmal)';

  @override
  String get gpsDetailsTitle => 'GPS-Details';

  @override
  String get gpsDisabled => 'GPS deaktiviert';

  @override
  String get gpsLock => 'GPS-Sperre';

  @override
  String get gpsNoLock => 'Keine GPS-Sperre';

  @override
  String get mdbgTitle => 'Winlink-Datenverkehr';

  @override
  String get mdbgNoTraffic => 'Derzeit kein Datenverkehr.';

  @override
  String get fwTitle => 'Funkgerät-Firmware-Update';

  @override
  String get fwStatusInitial =>
      'Suchen Sie online nach einem Firmware-Update oder laden Sie eine Firmware-Datei von der Festplatte.';

  @override
  String get fwErrNotConnected => 'Das Funkgerät ist nicht verbunden.';

  @override
  String get fwErrNoDeviceInfo =>
      'Die Funkgerät-Geräteinformationen sind noch nicht verfügbar.';

  @override
  String get fwStatusChecking => 'Suche nach einem Firmware-Update…';

  @override
  String get fwErrNoServerInfo =>
      'Der Herstellerserver hat keine Firmware-Informationen zurückgegeben.';

  @override
  String fwUpdateAvailable(String version) {
    return 'Ein Firmware-Update ist verfügbar $version. Sehen Sie sich die Versionshinweise unten an und laden Sie es dann herunter, um zu aktualisieren.';
  }

  @override
  String fwErrCheckFailed(String error) {
    return 'Suche nach Update fehlgeschlagen: $error';
  }

  @override
  String get fwPickTitle => 'Firmware-Datei auswählen';

  @override
  String fwLoaded(String name, String size, String md5) {
    return '$name geladen: $size (MD5 $md5…).';
  }

  @override
  String fwErrLoadFailed(String error) {
    return 'Firmware-Datei kann nicht geladen werden: $error';
  }

  @override
  String get fwSaveTitle => 'Firmware-Datei speichern';

  @override
  String fwSavedTo(String path) {
    return 'Firmware gespeichert in $path';
  }

  @override
  String fwErrSaveFailed(String error) {
    return 'Firmware-Datei kann nicht gespeichert werden: $error';
  }

  @override
  String get fwStatusDownloading =>
      'Firmware wird heruntergeladen und zusammengesetzt…';

  @override
  String get fwProgressStarting => 'Wird gestartet…';

  @override
  String fwReady(String size, String md5) {
    return 'Firmware bereit: $size (MD5 $md5…).';
  }

  @override
  String fwErrDownloadFailed(String error) {
    return 'Download fehlgeschlagen: $error';
  }

  @override
  String get fwStatusWriting =>
      'Firmware wird auf das Funkgerät geschrieben. Schalten Sie es nicht aus.';

  @override
  String get fwProgressTransferring => 'Wird übertragen…';

  @override
  String fwErrTransferFailed(String error) {
    return 'Firmware-Übertragung fehlgeschlagen: $error';
  }

  @override
  String get fwStatusRebooting =>
      'Das Funkgerät wird neu gestartet. Verbindung wird wiederhergestellt…';

  @override
  String get fwProgressWaitingRestart =>
      'Warten auf den Neustart des Funkgeräts…';

  @override
  String fwErrReconnectFailed(String error) {
    return 'Erneute Verbindung nach dem Neustart fehlgeschlagen: $error';
  }

  @override
  String get fwErrReconnectNull =>
      'Nach dem Neustart konnte keine erneute Verbindung mit dem Funkgerät hergestellt werden. Die Firmware wurde übertragen, aber nicht bestätigt. Stellen Sie die Verbindung manuell wieder her und versuchen Sie es erneut.';

  @override
  String get fwStatusFinalising => 'Update wird abgeschlossen…';

  @override
  String get fwProgressConfirming => 'Wird bestätigt…';

  @override
  String fwErrConfirmFailed(String error) {
    return 'Bestätigung des Updates fehlgeschlagen: $error';
  }

  @override
  String get fwStatusComplete =>
      'Firmware-Update abgeschlossen! Das Funkgerät führt jetzt die neue Firmware aus.';

  @override
  String get fwProgressDownloadPatch => 'Patch wird heruntergeladen';

  @override
  String get fwProgressDownloadBase => 'Basis-Image wird heruntergeladen';

  @override
  String get fwProgressAssemble => 'Firmware wird zusammengesetzt';

  @override
  String fwProgressBytes(String label, String done, String total) {
    return '$label ($done / $total)';
  }

  @override
  String fwProgressTransferringBytes(String done, String total) {
    return 'Wird übertragen ($done / $total)';
  }

  @override
  String fwCurrentFirmware(String version) {
    return 'Aktuelle Firmware: $version';
  }

  @override
  String get fwErrGeneric => 'Ein Fehler ist aufgetreten.';

  @override
  String get fwIdleDisclosure =>
      'Die Online-Prüfung kontaktiert den Server des Funkgerät-Herstellers (rpc.benshikj.com) und sendet nur die Produktkennung Ihres Funkgeräts. Es wird nichts gesendet, bis Sie auf Nach Update suchen tippen.';

  @override
  String get fwWhatsNew => 'Neuigkeiten';

  @override
  String get fwConfirmWarning =>
      'Warnung: Halten Sie das Funkgerät während des gesamten Vorgangs eingeschaltet, geladen und in Bluetooth-Reichweite. Das Funkgerät wird währenddessen neu gestartet. Ein Abbruch des Updates kann eine manuelle Wiederherstellung erfordern.';

  @override
  String get fwFromFile => 'Aus Datei…';

  @override
  String get fwCheckForUpdate => 'Nach Update suchen';

  @override
  String get fwDownload => 'Herunterladen';

  @override
  String get fwSave => 'Speichern…';

  @override
  String get fwFlashNow => 'Jetzt flashen';

  @override
  String get fwRetry => 'Wiederholen';

  @override
  String get wxTitle => 'Wetterbericht anfordern';

  @override
  String get wxIntro => 'Fordern Sie einen Wetterbericht über APRS an. ';

  @override
  String get wxLocation => 'Standort';

  @override
  String get wxLocationHelper =>
      'US-Stadt/Bundesstaat oder US-Postleitzahl oder Koordinaten 41.123/-121.334';

  @override
  String get wxTime => 'Zeitpunkt';

  @override
  String get wxReport => 'Bericht';

  @override
  String get wxToday => 'Heute';

  @override
  String get wxTonight => 'Heute Abend';

  @override
  String get wxTomorrow => 'Morgen';

  @override
  String get wxTomorrowNight => 'Morgen Abend';

  @override
  String get wxMonday => 'Montag';

  @override
  String get wxMondayNight => 'Montagabend';

  @override
  String get wxTuesday => 'Dienstag';

  @override
  String get wxTuesdayNight => 'Dienstagabend';

  @override
  String get wxWednesday => 'Mittwoch';

  @override
  String get wxWednesdayNight => 'Mittwochabend';

  @override
  String get wxThursday => 'Donnerstag';

  @override
  String get wxThursdayNight => 'Donnerstagabend';

  @override
  String get wxFriday => 'Freitag';

  @override
  String get wxFridayNight => 'Freitagabend';

  @override
  String get wxSaturday => 'Samstag';

  @override
  String get wxSaturdayNight => 'Samstagabend';

  @override
  String get wxSunday => 'Sonntag';

  @override
  String get wxSundayNight => 'Sonntagabend';

  @override
  String get wxReportBrief => 'Kurz, Kurzvorhersage, nur USA';

  @override
  String get wxReportFull => 'Vollständig, Detailliertere Vorhersage, nur USA';

  @override
  String get wxReportCurrent => 'Aktuell, Nächstgelegene NWS-Station, nur USA';

  @override
  String get wxReportMetar => 'METAR, ICAO-Station im METAR-Format';

  @override
  String get wxReportCwop => 'CWOP, Nächstgelegene CWOP-Station';
}
