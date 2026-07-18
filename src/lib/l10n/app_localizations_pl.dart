// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get appTitle => 'Handi-Talkie Commander';

  @override
  String get menuFile => 'Plik';

  @override
  String get menuConnect => 'Połącz...';

  @override
  String get menuDisconnect => 'Rozłącz';

  @override
  String get menuSettings => 'Ustawienia...';

  @override
  String get menuExit => 'Zakończ';

  @override
  String get menuRadios => 'Radiotelefony';

  @override
  String get menuDualWatch => 'Podwójny nasłuch';

  @override
  String get menuScan => 'Skanowanie';

  @override
  String get menuRegions => 'Regiony';

  @override
  String get menuTrustedDevices => 'Zaufane urządzenia...';

  @override
  String get menuButtons => 'Przyciski...';

  @override
  String get menuFmRadio => 'Radio FM...';

  @override
  String get menuExportChannels => 'Eksportuj kanały...';

  @override
  String get menuImportChannels => 'Importuj kanały...';

  @override
  String get menuMacRadio => 'Radiotelefon';

  @override
  String get menuMacDisplay => 'Wyświetlanie';

  @override
  String get fmRadioTitle => 'Radio FM';

  @override
  String fmRadioMhz(String value) {
    return '${value}MHz';
  }

  @override
  String get fmRadioOff => 'Wył.';

  @override
  String get fmRadioPowerTooltip => 'Włącz/wyłącz radio FM';

  @override
  String get fmRadioSeekDownTooltip => 'Szukaj w dół';

  @override
  String get fmRadioStepDownTooltip => 'Zmniejsz częstotliwość';

  @override
  String get fmRadioStopTooltip => 'Wyłącz';

  @override
  String get fmRadioStepUpTooltip => 'Zwiększ częstotliwość';

  @override
  String get fmRadioSeekUpTooltip => 'Szukaj w górę';

  @override
  String get fmRadioStationsHeader => 'Ulubione stacje';

  @override
  String get fmRadioAddStationTooltip => 'Dodaj bieżącą częstotliwość';

  @override
  String get fmRadioNoStations => 'Brak ulubionych stacji';

  @override
  String get fmRadioStationNameLabel => 'Nazwa stacji';

  @override
  String get fmRadioRenameTitle => 'Nazwa stacji';

  @override
  String get fmRadioDeleteTitle => 'Usuń stację';

  @override
  String fmRadioDeleteMessage(String name) {
    return 'Usunąć „$name” z ulubionych stacji?';
  }

  @override
  String get commonClose => 'Zamknij';

  @override
  String get commonCancel => 'Anuluj';

  @override
  String get commonOk => 'OK';

  @override
  String get aboutCheckForUpdates => 'Sprawdź aktualizacje';

  @override
  String aboutVersionAuthor(String version) {
    return 'Wersja $version\nYlian Saint-Hilaire, KK7VZT\nOtwarte oprogramowanie, licencja Apache 2.0';
  }

  @override
  String get settingsLanguage => 'Język';

  @override
  String get settingsLanguageHint =>
      'Wybierz język używany przez aplikację. „Domyślny systemowy” podąża za językiem urządzenia.';

  @override
  String get settingsThemeMode => 'Motyw';

  @override
  String get settingsThemeModeHint =>
      'Wybierz jasny lub ciemny wygląd. „Domyślny systemowy” podąża za ustawieniem urządzenia.';

  @override
  String get settingsThemeModeSystem => 'Domyślny systemowy';

  @override
  String get settingsThemeModeLight => 'Jasny';

  @override
  String get settingsThemeModeDark => 'Ciemny';

  @override
  String get languageSystem => 'Domyślny systemowy';

  @override
  String get languageEnglish => 'Angielski';

  @override
  String get languageFrench => 'Francuski';

  @override
  String get languageSpanish => 'Hiszpański';

  @override
  String get languageChinese => 'Chiński';

  @override
  String get languageJapanese => 'Japoński';

  @override
  String get languageHindi => 'Hindi';

  @override
  String get languageGerman => 'Niemiecki';

  @override
  String get languagePolish => 'Polski';

  @override
  String get menuAudio => 'Dźwięk';

  @override
  String get menuAudioEnabled => 'Dźwięk włączony';

  @override
  String get menuSoftwareModem => 'Modem programowy';

  @override
  String get menuModemDisabled => 'Wyłączony';

  @override
  String get menuDartTransmitLevel => 'Poziom nadawania DART';

  @override
  String get menuDartLevel0 => 'Poziom 0 (BPSK, LDPC 1/2)';

  @override
  String get menuDartLevel1 => 'Poziom 1 (QPSK, LDPC 1/2)';

  @override
  String get menuDartLevel2 => 'Poziom 2 (QPSK, LDPC 2/3)';

  @override
  String get menuDartLevel3 => 'Poziom 3 (8PSK, LDPC 2/3)';

  @override
  String get menuDartLevel4 => 'Poziom 4 (16QAM, LDPC 3/4)';

  @override
  String get menuDartLevel5 => 'Poziom 5 (16QAM, LDPC 5/6)';

  @override
  String get menuDartLevelF => 'Poziom F (4-FSK, LDPC 1/2)';

  @override
  String get menuAprsModem => 'Modem APRS';

  @override
  String get menuView => 'Widok';

  @override
  String get menuRadio => 'Radiotelefon';

  @override
  String get menuTabs => 'Karty';

  @override
  String get menuTabNames => 'Nazwy kart';

  @override
  String get menuShowAllTabs => 'Pokaż wszystkie karty';

  @override
  String get menuAllChannels => 'Wszystkie kanały';

  @override
  String get menuChannelFrequency => 'Częstotliwość kanału';

  @override
  String get menuHelp => 'Pomoc';

  @override
  String get menuRadioInformation => 'Informacje o radiotelefonie...';

  @override
  String get menuGpsInformation => 'Informacje GPS...';

  @override
  String get menuCheckForUpdatesEllipsis => 'Sprawdź aktualizacje...';

  @override
  String get menuAbout => 'O programie...';

  @override
  String get tabComms => 'Komunikacja';

  @override
  String get tabAudio => 'Dźwięk';

  @override
  String get tabAprs => 'APRS';

  @override
  String get tabMap => 'Mapa';

  @override
  String get tabMail => 'Poczta';

  @override
  String get tabTerminal => 'Terminal';

  @override
  String get tabContacts => 'Kontakty';

  @override
  String get tabBbs => 'BBS';

  @override
  String get tabTorrent => 'Torrent';

  @override
  String get tabPackets => 'Pakiety';

  @override
  String get tabDebug => 'Debug';

  @override
  String get tabRadio => 'Radiotelefon';

  @override
  String get stateDisconnected => 'Rozłączono';

  @override
  String get stateConnecting => 'Łączenie...';

  @override
  String get stateConnected => 'Połączono';

  @override
  String get stateUnableToConnect => 'Nie można połączyć';

  @override
  String get stateAccessDenied => 'Odmowa dostępu';

  @override
  String get stateSelectRadio => 'Wybierz radiotelefon';

  @override
  String statusBattery(int percent) {
    return 'Bateria: $percent%';
  }

  @override
  String get statusCheckingBluetooth => 'Sprawdzanie Bluetooth...';

  @override
  String get statusBluetoothNotAvailable => 'Bluetooth niedostępny';

  @override
  String get statusScanningForRadios => 'Wyszukiwanie radiotelefonów...';

  @override
  String get statusErrorScanning => 'Błąd wyszukiwania radiotelefonów';

  @override
  String get statusNoCompatibleRadios =>
      'Nie znaleziono zgodnych radiotelefonów';

  @override
  String get statusAllRadiosConnected =>
      'Wszystkie radiotelefony są już połączone';

  @override
  String statusConnectingTo(String name) {
    return 'Łączenie z $name...';
  }

  @override
  String statusConnectedTo(String name) {
    return 'Połączono z $name';
  }

  @override
  String statusFailedToConnect(String name) {
    return 'Nie udało się połączyć z $name';
  }

  @override
  String get statusDisconnecting => 'Rozłączanie...';

  @override
  String get settingsTabLicense => 'Licencja';

  @override
  String get settingsTabAprs => 'APRS';

  @override
  String get settingsTabComms => 'Komunikacja';

  @override
  String get settingsTabWinlink => 'Winlink';

  @override
  String get settingsTabServers => 'Serwery';

  @override
  String get settingsTabMap => 'Mapa';

  @override
  String get settingsTabLimits => 'Limity';

  @override
  String get settingsTabApplication => 'Aplikacja';

  @override
  String get settingsAdd => 'Dodaj';

  @override
  String get settingsRemove => 'Usuń';

  @override
  String get settingsDownload => 'Pobierz';

  @override
  String get settingsRetry => 'Ponów';

  @override
  String get settingsPreview => 'Podgląd';

  @override
  String get settingsNone => 'Brak';

  @override
  String get settingsLicenseInfo =>
      'W USA do nadawania wymagana jest licencja krótkofalarska. Więcej informacji o uzyskaniu licencji znajdziesz na stronie ARRL.';

  @override
  String get settingsCallSignStationId => 'Znak wywoławczy i ID stacji';

  @override
  String get settingsCallSign => 'Znak wywoławczy';

  @override
  String get settingsCallSignHint => 'np. W1AW';

  @override
  String get settingsStationId => 'ID stacji';

  @override
  String get settingsAllowTransmit => 'Zezwól tej aplikacji na nadawanie';

  @override
  String get settingsCallSignHelp =>
      'Wprowadź prawidłowy znak wywoławczy (co najmniej 3 znaki), aby włączyć nadawanie';

  @override
  String get settingsAprsIntro =>
      'Skonfiguruj ścieżki routingu APRS do transmisji pakietów.';

  @override
  String get settingsAprsRoutes => 'Trasy APRS';

  @override
  String get settingsEditRoute => 'Edytuj trasę';

  @override
  String get settingsEditRouteProtected =>
      'Wbudowanej trasy nie można edytować';

  @override
  String get settingsDeleteRoute => 'Usuń trasę';

  @override
  String get settingsDeleteRouteProtected =>
      'Wbudowanej trasy nie można usunąć';

  @override
  String get settingsCommsIntro =>
      'Skonfiguruj ustawienia rozpoznawania i syntezy mowy.';

  @override
  String get settingsSpeechToText => 'Rozpoznawanie mowy';

  @override
  String get settingsSpeechToTextInfo =>
      'Transkrybuje odebrany dźwięk radiowy na tekst. Działa całkowicie offline na tym urządzeniu; dźwięk nigdy nie jest zapisywany na dysku.';

  @override
  String get settingsModel => 'Model';

  @override
  String get settingsRecognitionLanguage => 'Język rozpoznawania';

  @override
  String get settingsRecognitionLanguageHelp =>
      'Zmiany języka zaczną obowiązywać przy następnym uruchomieniu silnika.';

  @override
  String get settingsStatus => 'Stan';

  @override
  String settingsModelInstalled(String suffix) {
    return 'Model zainstalowany$suffix';
  }

  @override
  String settingsDownloadingModelPct(String percent) {
    return 'Pobieranie modelu… $percent%';
  }

  @override
  String get settingsDownloadingModel => 'Pobieranie modelu…';

  @override
  String settingsInstallingModelPct(String percent) {
    return 'Instalowanie modelu… $percent%';
  }

  @override
  String get settingsInstallingModel => 'Instalowanie modelu…';

  @override
  String get settingsModelInstallError => 'Nie udało się zainstalować modelu.';

  @override
  String settingsModelNotDownloaded(String downloadLabel) {
    return 'Model nie został pobrany. $downloadLabel następuje tylko raz i jest zapisywany w pamięci podręcznej tego urządzenia.';
  }

  @override
  String settingsBytesOf(String received, String total) {
    return '$received z $total';
  }

  @override
  String get settingsRemoveSttModelTitle => 'Usunąć model rozpoznawania mowy?';

  @override
  String settingsRemoveSttModelBody(String name) {
    return 'Pobrany model „$name” zostanie usunięty, aby zwolnić miejsce. Zostanie ponownie pobrany przy następnym użyciu.';
  }

  @override
  String get settingsTextToSpeech => 'Synteza mowy';

  @override
  String get settingsTextToSpeechInfo =>
      'Używane podczas wysyłania tekstu w trybie „Mowa” na karcie Komunikacja.';

  @override
  String get settingsTtsUnavailableTitle => 'Synteza mowy jest niedostępna';

  @override
  String get settingsVoice => 'Głos';

  @override
  String get settingsSpeechRate => 'Szybkość mowy';

  @override
  String get settingsPitch => 'Wysokość tonu';

  @override
  String get settingsLoadingVoices => 'Ładowanie głosów…';

  @override
  String get settingsSystemDefault => 'Domyślny systemowy';

  @override
  String get settingsLangAutoDetect => 'Wykrywanie automatyczne';

  @override
  String get settingsLangChinese => 'Chiński';

  @override
  String get settingsLangJapanese => 'Japoński';

  @override
  String get settingsLangKorean => 'Koreański';

  @override
  String get settingsLangCantonese => 'Kantoński';

  @override
  String get settingsWinlinkIntro =>
      'Skonfiguruj ustawienia wiadomości Winlink dla poczty e-mail przez radio.';

  @override
  String get settingsWinlinkAccount => 'Konto Winlink';

  @override
  String get settingsAccount => 'Konto';

  @override
  String get settingsWinlinkAccountHelp =>
      'Na podstawie znaku wywoławczego z karty Licencja';

  @override
  String get settingsPassword => 'Hasło';

  @override
  String get settingsUseStationIdWinlink => 'Użyj ID stacji dla Winlink';

  @override
  String get settingsServersIntro =>
      'Skonfiguruj ustawienia serwerów lokalnych.';

  @override
  String get settingsLocalServers => 'Serwery lokalne';

  @override
  String get settingsEnableWebServer => 'Włącz serwer WWW';

  @override
  String get settingsPort => 'Port:';

  @override
  String get settingsEnableAgwpeServer => 'Włącz serwer AGWPE';

  @override
  String get settingsHomeAssistant => 'Home Assistant';

  @override
  String get settingsHomeAssistantDescription =>
      'Udostępnij każdy połączony radiotelefon przez MQTT do monitorowania i sterowania w Home Assistant.';

  @override
  String get settingsEnableHomeAssistant => 'Włącz Home Assistant';

  @override
  String get settingsHomeAssistantMqttUrl => 'Adres URL MQTT';

  @override
  String get settingsHomeAssistantUsername => 'Nazwa użytkownika';

  @override
  String get settingsHomeAssistantPassword => 'Hasło';

  @override
  String get settingsHomeAssistantTestSuccess =>
      'Sukces: połączono z brokerem.';

  @override
  String get settingsMapIntroGps =>
      'Skonfiguruj źródła danych dla GPS i śledzenia samolotów.';

  @override
  String get settingsMapIntroNoGps =>
      'Skonfiguruj źródła danych dla śledzenia samolotów.';

  @override
  String get settingsGpsSerialPort => 'Port szeregowy GPS';

  @override
  String get settingsSerialPort => 'Port szeregowy';

  @override
  String get settingsBaudRate => 'Prędkość transmisji';

  @override
  String get settingsShareGpsLocation =>
      'Udostępniaj pozycję GPS z portu szeregowego';

  @override
  String get settingsShareGpsLocationHelp =>
      'Wysyła pozycję GPS z portu szeregowego do połączonego radiotelefonu, aby nadawał Twoją bieżącą lokalizację.';

  @override
  String get settingsAirplaneTracking => 'Śledzenie samolotów (dump1090)';

  @override
  String get settingsServerUrl => 'Adres URL serwera';

  @override
  String get settingsTestConnection => 'Testuj połączenie';

  @override
  String get settingsTest => 'Testuj';

  @override
  String get settingsTestTesting => 'Testowanie...';

  @override
  String get settingsTestEmptyAddress =>
      'Niepowodzenie: adres serwera jest pusty';

  @override
  String settingsTestFailedHttp(int code) {
    return 'Niepowodzenie: HTTP $code';
  }

  @override
  String settingsTestSuccess(int count) {
    return 'Sukces, znaleziono $count samolot(ów).';
  }

  @override
  String get settingsTestUnexpectedJson =>
      'Niepowodzenie: nieoczekiwany format JSON';

  @override
  String get settingsTestTimedOut => 'Niepowodzenie: przekroczono limit czasu';

  @override
  String get settingsTestInvalidJson =>
      'Niepowodzenie: nieprawidłowa odpowiedź JSON';

  @override
  String get settingsTestFailed => 'Niepowodzenie';

  @override
  String get settingsTestConnectionFailedTitle =>
      'Test połączenia nie powiódł się';

  @override
  String get settingsLimitsIntro =>
      'Ogranicz liczbę wpisów historii zachowywanych między uruchomieniami. Ustaw na „Bez ograniczeń”, aby zachować wszystko.';

  @override
  String get settingsHistoryLimits => 'Limity historii';

  @override
  String get settingsUnlimited => 'Bez ograniczeń';

  @override
  String get settingsLimitAprsMessages => 'Wiadomości APRS';

  @override
  String get settingsLimitPackets => 'Pakiety';

  @override
  String get settingsLimitSstvImages => 'Obrazy SSTV';

  @override
  String get settingsLimitCommEvents => 'Zdarzenia komunikacji';

  @override
  String settingsLimitCurrent(int count) {
    return 'Bieżąco: $count';
  }

  @override
  String settingsLimitItemsDeleted(int count) {
    return '$count wpisów zostanie usuniętych';
  }

  @override
  String get settingsDeleteHistoryTitle => 'Usunąć wpisy historii?';

  @override
  String settingsDeleteHistoryBody(String items) {
    return 'Te limity trwale usuną najstarsze wpisy:\n\n$items\n\nTej operacji nie można cofnąć.';
  }

  @override
  String settingsDeleteAprsMessages(int count) {
    return '$count wiadomości APRS';
  }

  @override
  String settingsDeletePackets(int count) {
    return '$count pakietów';
  }

  @override
  String settingsDeleteSstvImages(int count) {
    return '$count obrazów SSTV';
  }

  @override
  String settingsDeleteCommEvents(int count) {
    return '$count zdarzeń komunikacji';
  }

  @override
  String get settingsAddAprsRoute => 'Dodaj trasę APRS';

  @override
  String get settingsEditAprsRoute => 'Edytuj trasę APRS';

  @override
  String get settingsName => 'Nazwa';

  @override
  String get settingsNameHint => 'np. Domyślna';

  @override
  String get settingsDuplicateRoute => 'Trasa o tej nazwie już istnieje.';

  @override
  String get settingsPath => 'Ścieżka';

  @override
  String get commonError => 'Błąd';

  @override
  String get commonConnect => 'Połącz';

  @override
  String get commonDisconnect => 'Rozłącz';

  @override
  String get commonRename => 'Zmień nazwę';

  @override
  String get commonRemove => 'Usuń';

  @override
  String connectScanError(String error) {
    return 'Wyszukiwanie urządzeń Bluetooth nie powiodło się: $error';
  }

  @override
  String get connectNoRadiosTitle => 'Nie znaleziono radiotelefonów';

  @override
  String get connectNoRadiosBody =>
      'Nie znaleziono zgodnego radiotelefonu.\n\nUpewnij się, że radiotelefon jest włączony, a Bluetooth aktywny.';

  @override
  String get connectAllConnectedTitle => 'Wszystkie połączone';

  @override
  String get connectAllConnectedBody =>
      'Wszystkie wykryte radiotelefony są już połączone.';

  @override
  String get connectBluetoothOffTitle => 'Bluetooth niedostępny';

  @override
  String get connectBluetoothOffBody =>
      'Bluetooth jest niedostępny lub wyłączony.\n\nWłącz Bluetooth w ustawieniach urządzenia i spróbuj ponownie.';

  @override
  String get radioConnectionTitle => 'Połączenie radiotelefonu';

  @override
  String get radioConnectionEmpty =>
      'Nie znaleziono zgodnych radiotelefonów.\nUpewnij się, że radiotelefon jest włączony, a Bluetooth aktywny.';

  @override
  String get radioRenameTitle => 'Zmień nazwę radiotelefonu';

  @override
  String get radioRenamePrompt =>
      'Wprowadź niestandardową nazwę tego radiotelefonu:';

  @override
  String get radioRenameHint => 'Pozostaw puste, aby użyć nazwy domyślnej';

  @override
  String get updateTitle => 'Aktualizacja oprogramowania';

  @override
  String get updateChecking => 'Sprawdzanie aktualizacji...';

  @override
  String updateVersionAvailable(String version) {
    return 'Dostępna jest wersja $version.';
  }

  @override
  String updateFreshDownload(String version) {
    return 'Wersja $version wymaga ponownego pobrania.';
  }

  @override
  String updateUnsupported(String version) {
    return 'Ta wersja nie jest już obsługiwana. Zaktualizuj do $version.';
  }

  @override
  String get updateUpToDate => 'Używasz najnowszej wersji.';

  @override
  String updateCheckFailed(String error) {
    return 'Sprawdzanie aktualizacji nie powiodło się: $error';
  }

  @override
  String get updateDownloading => 'Pobieranie aktualizacji...';

  @override
  String get updateDownloaded => 'Aktualizacja pobrana. Gotowa do instalacji.';

  @override
  String updateDownloadFailed(String error) {
    return 'Pobieranie nie powiodło się: $error';
  }

  @override
  String updateInstallFailed(String error) {
    return 'Instalacja nie powiodła się: $error';
  }

  @override
  String updateDiagnosticsLog(String path) {
    return 'Jeśli aktualizacja się nie zakończy, sprawdź dziennik diagnostyczny:\n$path';
  }

  @override
  String get updateInstallRestart => 'Zainstaluj i uruchom ponownie';

  @override
  String get updateCheckAgain => 'Sprawdź ponownie';

  @override
  String get regionsTitle => 'Zmień nazwy regionów';

  @override
  String regionsMaxChars(int count) {
    return 'Nazwy regionów mogą mieć do $count znaków.';
  }

  @override
  String regionLabel(int number) {
    return 'Region $number';
  }

  @override
  String get gpsInfoTitle => 'Informacje GPS';

  @override
  String get gpsSectionConnection => 'Połączenie';

  @override
  String get gpsSectionFix => 'Ustalenie pozycji GPS';

  @override
  String get gpsSectionPosition => 'Pozycja';

  @override
  String get gpsSectionMotion => 'Ruch';

  @override
  String get gpsSectionTime => 'Czas';

  @override
  String get gpsPortStatus => 'Stan portu';

  @override
  String get gpsNotConfigured => 'Nie skonfigurowano';

  @override
  String get gpsOpenReceiving => 'Otwarty — odbieranie danych';

  @override
  String get gpsPermDeniedLinux =>
      'Odmowa dostępu — dodaj użytkownika do grupy „dialout” (sudo usermod -aG dialout \$USER), następnie wyloguj się i zaloguj ponownie.';

  @override
  String get gpsPermDenied =>
      'Odmowa dostępu — aplikacja nie może uzyskać dostępu do tego portu.';

  @override
  String get gpsPortError =>
      'Błąd portu — nie udało się otworzyć portu szeregowego.';

  @override
  String get gpsFix => 'Ustalenie pozycji';

  @override
  String get gpsFixQuality => 'Jakość ustalenia pozycji';

  @override
  String get gpsSatellites => 'Satelity';

  @override
  String get gpsNoData => 'Brak danych';

  @override
  String get gpsActive => 'Aktywny';

  @override
  String get gpsNoFix => 'Brak pozycji';

  @override
  String get gpsQualGps => 'Pozycja GPS (1)';

  @override
  String get gpsQualDgps => 'Pozycja DGPS (2)';

  @override
  String get gpsQualInvalid => 'Nieprawidłowa (0)';

  @override
  String gpsQualUnknown(int quality) {
    return '$quality (nieznana)';
  }

  @override
  String get gpsLatitude => 'Szerokość geograficzna';

  @override
  String get gpsLatitudeDms => 'Szerokość geograficzna (DMS)';

  @override
  String get gpsLongitude => 'Długość geograficzna';

  @override
  String get gpsLongitudeDms => 'Długość geograficzna (DMS)';

  @override
  String get gpsAltitude => 'Wysokość';

  @override
  String get gpsSpeed => 'Prędkość';

  @override
  String get gpsHeading => 'Kurs';

  @override
  String get gpsTimeUtc => 'Czas GPS (UTC)';

  @override
  String get gpsDate => 'Data GPS';

  @override
  String get gpsLastUpdate => 'Ostatnia aktualizacja';

  @override
  String get trustedDevicesTitle => 'Zaufane urządzenia';

  @override
  String get trustedRemoveTitle => 'Usuń zaufane urządzenie';

  @override
  String trustedRemoveMessage(String name) {
    return 'Usunąć „$name” z listy zaufanych urządzeń radiotelefonu?';
  }

  @override
  String get trustedNoDevices => 'Nie znaleziono zaufanych urządzeń.';

  @override
  String get pfConfigTitle => 'Konfiguruj przyciski';

  @override
  String get pfSaveToRadio => 'Zapisz w radiotelefonie';

  @override
  String get pfNoRadio => 'Brak połączonego radiotelefonu.';

  @override
  String get pfNoButtons =>
      'Ten radiotelefon nie zgłasza programowalnych przycisków.';

  @override
  String get pfIntro =>
      'Dla każdego programowalnego przycisku wybierz akcję dla każdego typu naciśnięcia. Zmiany zostaną zapisane w radiotelefonie po zapisaniu.';

  @override
  String pfButtonLabel(int number) {
    return 'Przycisk $number';
  }

  @override
  String get pfActionShort => 'Krótkie naciśnięcie';

  @override
  String get pfActionLong => 'Długie naciśnięcie';

  @override
  String get pfActionVeryLong => 'Bardzo długie naciśnięcie';

  @override
  String get pfActionVeryVeryLong => 'Bardzo bardzo długie naciśnięcie';

  @override
  String get pfActionDouble => 'Podwójne naciśnięcie';

  @override
  String get pfActionTriple => 'Potrójne naciśnięcie';

  @override
  String get pfActionRepeat => 'Powtórzenie';

  @override
  String get pfActionPressDown => 'Przytrzymanie';

  @override
  String get pfActionRelease => 'Zwolnienie';

  @override
  String get pfActionLongRelease => 'Długie zwolnienie';

  @override
  String get pfActionVeryLongRelease => 'Bardzo długie zwolnienie';

  @override
  String get pfActionVeryVeryLongRelease => 'Bardzo bardzo długie zwolnienie';

  @override
  String pfActionUnknown(int action) {
    return 'Akcja $action';
  }

  @override
  String get pfEffectDisabled => 'Wyłączone';

  @override
  String get pfEffectAlarm => 'Alarm';

  @override
  String get pfEffectAlarmAndMute => 'Alarm i wyciszenie';

  @override
  String get pfEffectToggleOffline => 'Przełącz tryb offline';

  @override
  String get pfEffectToggleRadioTx => 'Przełącz nadawanie radiowe';

  @override
  String get pfEffectToggleTxPower => 'Przełącz moc nadawania';

  @override
  String get pfEffectToggleFm => 'Przełącz radio FM';

  @override
  String get pfEffectPrevChannel => 'Poprzedni kanał';

  @override
  String get pfEffectNextChannel => 'Następny kanał';

  @override
  String get pfEffectTCall => 'Ton T (1750 Hz)';

  @override
  String get pfEffectPrevRegion => 'Poprzedni region';

  @override
  String get pfEffectNextRegion => 'Następny region';

  @override
  String get pfEffectToggleChScan => 'Przełącz skanowanie kanałów';

  @override
  String get pfEffectMainPtt => 'Główny PTT';

  @override
  String get pfEffectSubPtt => 'Dodatkowy PTT';

  @override
  String get pfEffectToggleMonitor => 'Przełącz monitor';

  @override
  String get pfEffectBtPairing => 'Parowanie Bluetooth';

  @override
  String get pfEffectToggleDoubleCh => 'Przełącz podwójny kanał';

  @override
  String get pfEffectToggleAbCh => 'Przełącz kanał A/B';

  @override
  String get pfEffectSendLocation => 'Wyślij lokalizację';

  @override
  String get pfEffectOneClickLink => 'Połączenie jednym kliknięciem';

  @override
  String get pfEffectVolDown => 'Zmniejsz głośność';

  @override
  String get pfEffectVolUp => 'Zwiększ głośność';

  @override
  String get pfEffectToggleMute => 'Przełącz wyciszenie';

  @override
  String pfEffectUnknown(int effect) {
    return 'Nieznane ($effect)';
  }

  @override
  String get importChannelsTitle => 'Importuj kanały';

  @override
  String importChannelsTitleWith(String name) {
    return 'Importuj kanały — $name';
  }

  @override
  String get importIntro =>
      'Przeciągnij kanał z lewej strony na slot radiotelefonu lub wybierz kanał i slot, a następnie dotknij strzałki. Dotknij ikony informacji, aby zobaczyć szczegóły. Kanały są zapisywane w radiotelefonie tylko po dotknięciu OK.';

  @override
  String importOkCount(int count) {
    return 'OK ($count)';
  }

  @override
  String importImportedHeader(int count) {
    return 'Zaimportowane ($count)';
  }

  @override
  String get importNoChannels => 'Brak zaimportowanych kanałów.';

  @override
  String importRadioChannelsHeader(int count) {
    return 'Kanały radiotelefonu ($count)';
  }

  @override
  String get importNoRadioChannels => 'Brak kanałów radiotelefonu.';

  @override
  String get importMoveTooltip => 'Przenieś wybrany kanał do wybranego slotu';

  @override
  String get importCopyAllTooltip =>
      'Skopiuj wszystkie zaimportowane kanały 1:1 do slotów radiotelefonu';

  @override
  String importChannelShort(int number) {
    return 'Kanał $number';
  }

  @override
  String get importClearTooltip => 'Wyczyść oczekujące przypisanie';

  @override
  String get importChannelDetails => 'Szczegóły kanału';

  @override
  String get riTitle => 'Informacje o radiotelefonie';

  @override
  String get riNoRadioConnected => 'Brak połączonego radiotelefonu';

  @override
  String get riConnectPrompt =>
      'Połącz radiotelefon, aby wyświetlić jego informacje.';

  @override
  String riRadioFallback(int id) {
    return 'Radiotelefon $id';
  }

  @override
  String get riSectionRadio => 'Radiotelefon';

  @override
  String get riSectionDeviceInfo => 'Informacje o urządzeniu';

  @override
  String get riSectionDeviceStatus => 'Stan urządzenia';

  @override
  String get riSectionDeviceSettings => 'Ustawienia urządzenia';

  @override
  String get riSectionBss => 'Ustawienia BSS';

  @override
  String get riSectionPosition => 'Pozycja';

  @override
  String get riName => 'Nazwa';

  @override
  String get riStatus => 'Stan';

  @override
  String get riSettingsLabel => 'Ustawienia';

  @override
  String get riNoData => 'Brak danych';

  @override
  String get riNoGpsData => 'Brak danych GPS';

  @override
  String get riNoGpsLock => 'Brak pozycji GPS';

  @override
  String get riGpsLocked => 'Ustalono pozycję GPS';

  @override
  String get riTrue => 'Tak';

  @override
  String get riFalse => 'Nie';

  @override
  String get riPresent => 'Obecny';

  @override
  String get riNotPresent => 'Nieobecny';

  @override
  String get riSupported => 'Obsługiwane';

  @override
  String get riNotSupported => 'Nieobsługiwane';

  @override
  String get riCurrent => 'Bieżący';

  @override
  String get riOff => 'Wył.';

  @override
  String riChannelValue(int number) {
    return 'Kanał $number';
  }

  @override
  String riSeconds(int count) {
    return '$count sekund(y)';
  }

  @override
  String riMeters(String value) {
    return '$value metrów';
  }

  @override
  String riDegrees(String value) {
    return '$value stopni';
  }

  @override
  String get riProductId => 'ID produktu';

  @override
  String get riVendorId => 'ID producenta';

  @override
  String get riDmrSupport => 'Obsługa DMR';

  @override
  String get riGmrsSupport => 'Obsługa GMRS';

  @override
  String get riHardwareSpeaker => 'Głośnik sprzętowy';

  @override
  String get riHardwareVersion => 'Wersja sprzętu';

  @override
  String get riSoftwareVersion => 'Wersja oprogramowania';

  @override
  String get riRegionCount => 'Liczba regionów';

  @override
  String get riMediumPower => 'Średnia moc';

  @override
  String get riChannelCount => 'Liczba kanałów';

  @override
  String get riNoaa => 'NOAA';

  @override
  String get riWeather => 'Pogoda';

  @override
  String riWeatherChannel(int number) {
    return 'Pogoda $number';
  }

  @override
  String get riBroadcastFm => 'Radio FM';

  @override
  String get riRadioLabel => 'Radiotelefon';

  @override
  String get riVfo => 'VFO';

  @override
  String get riFreqRangeCount => 'Liczba zakresów częstotliwości';

  @override
  String get riPowerOn => 'Włączone';

  @override
  String get riInTx => 'Nadawanie';

  @override
  String get riInRx => 'Odbieranie';

  @override
  String get riDoubleChannelLabel => 'Podwójny kanał';

  @override
  String get riScanning => 'Skanowanie';

  @override
  String get riCurrentChannelId => 'ID bieżącego kanału';

  @override
  String get riGpsLockedLabel => 'GPS zablokowany';

  @override
  String get riHfpConnected => 'HFP połączony';

  @override
  String get riAocConnected => 'AOC połączony';

  @override
  String get riRssi => 'RSSI';

  @override
  String get riCurrentRegion => 'Bieżący region';

  @override
  String get riAccuracy => 'Dokładność';

  @override
  String get riReceivedTime => 'Czas odbioru';

  @override
  String get riGpsTimeLocal => 'Czas lokalny GPS';

  @override
  String get riGpsTimeUtcLabel => 'Czas UTC GPS';

  @override
  String get tabDetach => 'Odłącz...';

  @override
  String get tabClear => 'Wyczyść';

  @override
  String get tabSaveToFile => 'Zapisz do pliku...';

  @override
  String get commonNoRadioConnected => 'Brak połączonego radiotelefonu.';

  @override
  String errorOpeningFileDialog(String error) {
    return 'Błąd podczas otwierania okna dialogowego pliku: $error';
  }

  @override
  String errorSavingFile(String error) {
    return 'Błąd podczas zapisywania pliku: $error';
  }

  @override
  String get debugSaveTitle => 'Zapisz dziennik debugowania';

  @override
  String debugLogSavedTo(String path) {
    return 'Dziennik debugowania zapisany w $path';
  }

  @override
  String get debugShowBluetoothFrames => 'Pokaż ramki Bluetooth';

  @override
  String get debugLoopbackMode => 'Tryb pętli zwrotnej';

  @override
  String get debugQueryDeviceNames => 'Zapytaj o nazwy urządzeń';

  @override
  String get debugRawCommand => 'Surowe polecenie...';

  @override
  String get debugAutoScroll => 'Automatyczne przewijanie';

  @override
  String get debugFirmwareUpdate => 'Aktualizacja oprogramowania układowego...';

  @override
  String get debugShowBuiltInMenus => 'Pokaż wbudowane menu';

  @override
  String get packetsCopyHex => 'Kopiuj pakiet HEX';

  @override
  String get packetsHexCopied => 'Pakiet HEX skopiowany do schowka';

  @override
  String get packetsSaveTitle => 'Zapisz zapis pakietów';

  @override
  String get packetsSaved => 'Zapis pakietów zapisany';

  @override
  String packetsSavedTo(String path) {
    return 'Zapis pakietów zapisany w $path';
  }

  @override
  String get packetsShowDecode => 'Pokaż dekodowanie pakietów';

  @override
  String get packetsEmpty => 'Brak zarejestrowanych pakietów';

  @override
  String get packetsColTime => 'Czas';

  @override
  String get packetsColChannel => 'Kanał';

  @override
  String get packetsColData => 'Dane';

  @override
  String get commonAdd => 'Dodaj';

  @override
  String get commonEdit => 'Edytuj';

  @override
  String get commonEditEllipsis => 'Edytuj...';

  @override
  String get commonAddEllipsis => 'Dodaj...';

  @override
  String get commonExportEllipsis => 'Eksportuj...';

  @override
  String get commonImportEllipsis => 'Importuj...';

  @override
  String get contactsTypeGeneric => 'Stacje ogólne';

  @override
  String get contactsTypeAprs => 'Stacje APRS';

  @override
  String get contactsTypeTerminal => 'Stacje terminalowe';

  @override
  String get contactsTypeBbs => 'Stacje BBS';

  @override
  String get contactsTypeWinlink => 'Stacje Winlink';

  @override
  String get contactsTypeTorrent => 'Stacje Torrent';

  @override
  String get contactsTypeAgwpe => 'Stacje AGWPE';

  @override
  String get contactsExists =>
      'Stacja o tym znaku wywoławczym i typie już istnieje';

  @override
  String get contactsRemovePrompt => 'Usunąć wybraną stację?';

  @override
  String get contactsNoExport => 'Brak stacji do wyeksportowania';

  @override
  String get contactsExportTitle => 'Eksportuj stacje';

  @override
  String get contactsImportTitle => 'Importuj stacje';

  @override
  String contactsExported(int count) {
    return 'Wyeksportowano $count stacji';
  }

  @override
  String contactsImported(int count) {
    return 'Zaimportowano $count stacji';
  }

  @override
  String get contactsUnableOpen => 'Nie można otworzyć książki adresowej';

  @override
  String get contactsInvalid => 'Nieprawidłowa książka adresowa';

  @override
  String get contactsColCallsign => 'Znak wywoławczy';

  @override
  String get contactsColName => 'Nazwa';

  @override
  String get contactsColDescription => 'Opis';

  @override
  String terminalHeaderWith(String callsign) {
    return 'Terminal - $callsign';
  }

  @override
  String get terminalNoRadio => 'Brak radiotelefonu dostępnego do połączenia.';

  @override
  String get terminalShowCallsign => 'Pokaż znak wywoławczy';

  @override
  String get terminalWordWrap => 'Zawijanie wierszy';

  @override
  String get terminalWaitForConnection => 'Oczekiwanie na połączenie...';

  @override
  String get terminalWaitingForConnection => 'Oczekiwanie na połączenie...';

  @override
  String terminalConnectedFrom(String callsign) {
    return 'Połączono z $callsign';
  }

  @override
  String get terminalSend => 'Wyślij';

  @override
  String terminalConnectedTo(String callsign) {
    return 'Połączono z $callsign';
  }

  @override
  String terminalConnectingTo(String callsign) {
    return 'Łączenie z $callsign...';
  }

  @override
  String get terminalInvalidCallsignDest => 'Nieprawidłowy znak wywoławczy/cel';

  @override
  String get terminalInvalidCallsign => 'Nieprawidłowy znak wywoławczy';

  @override
  String get terminalNotConnected => 'Nie połączono';

  @override
  String terminalError(String error) {
    return 'Błąd: $error';
  }

  @override
  String get terminalBrotli =>
      'Odebrano pakiet skompresowany Brotli (nieobsługiwany)';

  @override
  String get terminalSendFile => 'Wyślij plik...';

  @override
  String get terminalSaveFileTitle => 'Zapisz odebrany plik';

  @override
  String get terminalCancelTransfer => 'Anuluj transfer';

  @override
  String get terminalTransferInProgress => 'Transfer pliku jest już w toku';

  @override
  String terminalSendingFile(String filename) {
    return 'Wysyłanie $filename...';
  }

  @override
  String terminalReceivingFile(String filename) {
    return 'Odbieranie $filename...';
  }

  @override
  String terminalFileSent(String filename) {
    return 'Plik wysłany: $filename';
  }

  @override
  String terminalFileReceived(String filename, int bytes) {
    return 'Plik odebrany: $filename ($bytes bajtów)';
  }

  @override
  String terminalFileTransferError(String message) {
    return 'Błąd transferu pliku: $message';
  }

  @override
  String get audioSectionDevices => 'Urządzenia';

  @override
  String get audioRefreshDevices => 'Odśwież listę urządzeń';

  @override
  String get audioOutput => 'Wyjście';

  @override
  String get audioInput => 'Wejście';

  @override
  String get audioVolume => 'Głośność';

  @override
  String get audioSquelch => 'Squelch';

  @override
  String get audioSectionComputer => 'Komputer';

  @override
  String get audioApplication => 'Aplikacja';

  @override
  String get audioMaster => 'Główny';

  @override
  String get audioMicGain => 'Wzmocnienie mikrofonu';

  @override
  String get audioMicNotAvailable =>
      'Nagrywanie z mikrofonu jest niedostępne na tej platformie.';

  @override
  String get audioMicNotSupported =>
      'Nagrywanie z mikrofonu nie jest tutaj obsługiwane.';

  @override
  String get audioSpectRadio => 'Spektrograf radiowy';

  @override
  String get audioSpectMic => 'Spektrograf mikrofonu';

  @override
  String get audioSpectNone => 'Spektrograf';

  @override
  String get audioSpectMenuNone => 'Brak spektrografu';

  @override
  String get audioDartQuality => 'Jakość odbioru DART';

  @override
  String get audioDartSignalAnalysis => 'Analiza sygnału DART';

  @override
  String get audioDefault => 'Domyślne';

  @override
  String get audioMute => 'Wycisz';

  @override
  String get audioUnmute => 'Wyłącz wyciszenie';

  @override
  String get audioEnable => 'Włącz';

  @override
  String get audioDisable => 'Wyłącz';

  @override
  String get audioNa => 'Nd.';

  @override
  String get bbsHeaderActive => 'BBS - Aktywny';

  @override
  String get bbsActivate => 'Aktywuj';

  @override
  String get bbsDeactivate => 'Dezaktywuj';

  @override
  String get bbsViewTraffic => 'Wyświetl ruch';

  @override
  String get bbsClearTraffic => 'Wyczyść ruch';

  @override
  String get bbsClearStats => 'Wyczyść statystyki';

  @override
  String get bbsColCallSign => 'Znak wywoławczy';

  @override
  String get bbsColLastSeen => 'Ostatnio widziany';

  @override
  String get bbsColStats => 'Statystyki';

  @override
  String get bbsTraffic => 'Ruch';

  @override
  String get bbsJustNow => 'Przed chwilą';

  @override
  String bbsMinAgo(int n) {
    return '$n min temu';
  }

  @override
  String bbsHoursAgo(int n) {
    return '$n godz. temu';
  }

  @override
  String bbsDaysAgo(int n) {
    return '$n dni temu';
  }

  @override
  String get commonDelete => 'Usuń';

  @override
  String get torrentAddFile => 'Dodaj plik';

  @override
  String get torrentShowDetails => 'Pokaż szczegóły';

  @override
  String get torrentFileSaved => 'Plik zapisany.';

  @override
  String get torrentFileDataUnavailable =>
      'Błąd zapisu: dane pliku niedostępne';

  @override
  String get torrentUnknownError => 'Nieznany błąd';

  @override
  String get torrentSaveTitle => 'Zapisz plik torrent';

  @override
  String get torrentNoRadios =>
      'Brak połączonego radiotelefonu. Najpierw połącz radiotelefon.';

  @override
  String get torrentMultiRadio =>
      'Tryb torrent z wieloma radiotelefonami nie jest jeszcze obsługiwany.';

  @override
  String get torrentDropSingle => 'Upuść tylko jeden plik.';

  @override
  String get torrentDeletePrompt => 'Usunąć wybrany plik torrent?';

  @override
  String get torrentPause => 'Wstrzymaj';

  @override
  String get torrentShare => 'Udostępnij';

  @override
  String get torrentRequest => 'Zażądaj';

  @override
  String get torrentSaveAs => 'Zapisz jako...';

  @override
  String get torrentDropToShare => 'Upuść plik, aby udostępnić';

  @override
  String get torrentNoFiles =>
      'Brak plików torrent. Dodaj plik lub upuść jeden, aby udostępnić.';

  @override
  String get torrentUnknownSource => 'Nieznane';

  @override
  String get torrentColFile => 'Plik';

  @override
  String get torrentColMode => 'Tryb';

  @override
  String get torrentDetailFileName => 'Nazwa pliku';

  @override
  String get torrentDetailSource => 'Źródło';

  @override
  String get torrentDetailFileSize => 'Rozmiar pliku';

  @override
  String torrentBytes(int count) {
    return '$count bajtów';
  }

  @override
  String get torrentDetailCompression => 'Kompresja';

  @override
  String get torrentDetailBlocks => 'Bloki';

  @override
  String get torrentDetailsTitle => 'Szczegóły torrent';

  @override
  String get torrentSelectPrompt => 'Wybierz torrent, aby wyświetlić szczegóły';

  @override
  String get torrentModePaused => 'Wstrzymany';

  @override
  String get torrentModeSharing => 'Udostępnianie';

  @override
  String get torrentModeRequesting => 'Żądanie';

  @override
  String get torrentModeError => 'Błąd';

  @override
  String get torrentCompUnknown => 'Nieznana';

  @override
  String get mailInbox => 'Odebrane';

  @override
  String get mailOutbox => 'Wychodzące';

  @override
  String get mailDraft => 'Robocze';

  @override
  String get mailSent => 'Wysłane';

  @override
  String get mailArchive => 'Archiwum';

  @override
  String get mailTrash => 'Kosz';

  @override
  String get mailInternet => 'Internet';

  @override
  String get mailDeleteTitle => 'Usuń wiadomość';

  @override
  String get mailMoveToTrashTitle => 'Przenieś do kosza';

  @override
  String get mailDeletePermanent =>
      'Trwale usunąć wybraną wiadomość? Tej operacji nie można cofnąć.';

  @override
  String get mailMoveToTrashPrompt => 'Przenieść wybraną wiadomość do kosza?';

  @override
  String get mailMove => 'Przenieś';

  @override
  String get mailOpen => 'Otwórz';

  @override
  String get mailReply => 'Odpowiedz';

  @override
  String get mailReplyAll => 'Odpowiedz wszystkim';

  @override
  String get mailForward => 'Prześlij dalej';

  @override
  String get mailShowPreview => 'Pokaż podgląd';

  @override
  String get mailBackup => 'Utwórz kopię zapasową poczty...';

  @override
  String get mailRestore => 'Przywróć pocztę...';

  @override
  String get mailShowTraffic => 'Wyświetl ruch...';

  @override
  String mailBackupFailed(String error) {
    return 'Tworzenie kopii zapasowej nie powiodło się: $error';
  }

  @override
  String get mailBackupTitle => 'Kopia zapasowa poczty';

  @override
  String get mailBackupSuccess => 'Kopia zapasowa zakończona pomyślnie.';

  @override
  String get mailRestoreTitle => 'Przywróć pocztę';

  @override
  String get mailRestoreUnableOpen =>
      'Nie można otworzyć pliku kopii zapasowej';

  @override
  String mailRestoreFailed(String error) {
    return 'Przywracanie nie powiodło się: $error';
  }

  @override
  String get mailNew => 'Nowa';

  @override
  String get mailNewMail => 'Nowa wiadomość';

  @override
  String get mailColTime => 'Czas';

  @override
  String get mailColTo => 'Do';

  @override
  String get mailColFrom => 'Od';

  @override
  String get mailColSubject => 'Temat';

  @override
  String get mailSelectPreview => 'Wybierz wiadomość do podglądu';

  @override
  String get commonUnknown => 'Nieznane';

  @override
  String get mapOfflineMode => 'Tryb offline';

  @override
  String get mapOfflineMap => 'Mapa offline';

  @override
  String get mapCacheArea => 'Zapisz obszar w pamięci podręcznej...';

  @override
  String get mapCenterGps => 'Wyśrodkuj na GPS';

  @override
  String get mapShowTracks => 'Pokaż ślady';

  @override
  String get mapShowMarkers => 'Pokaż znaczniki';

  @override
  String get mapShowAirplanes => 'Pokaż samoloty';

  @override
  String get mapLargeMarkers => 'Duże znaczniki';

  @override
  String get mapShowContactsOnly => 'Pokaż tylko kontakty';

  @override
  String get mapFilterAll => 'Wszystkie';

  @override
  String get mapFilterLast30 => 'Ostatnie 30 minut';

  @override
  String get mapFilterLastHour => 'Ostatnia godzina';

  @override
  String get mapFilterLast6 => 'Ostatnie 6 godzin';

  @override
  String get mapFilterLast12 => 'Ostatnie 12 godzin';

  @override
  String get mapFilterLast24 => 'Ostatnie 24 godziny';

  @override
  String get mapCacheTitle => 'Zapisz obszar mapy w pamięci podręcznej';

  @override
  String mapCachePrompt(int count, int minZoom, int maxZoom) {
    return 'Pobrać $count kafelków dla poziomów powiększenia $minZoom–$maxZoom?\n\nSpowoduje to zapisanie wybranego obszaru w pamięci podręcznej do użytku offline.';
  }

  @override
  String get mapDownloadingTitle => 'Pobieranie kafelków';

  @override
  String mapTilesProgress(int done, int total) {
    return '$done / $total kafelków';
  }

  @override
  String get mapDragToSelect =>
      'Przeciągnij, aby wybrać obszar do zapisania w pamięci podręcznej';

  @override
  String get aprsNoChannel => 'Brak radiotelefonu z kanałem APRS';

  @override
  String get aprsNoLoadedChannels =>
      'Brak radiotelefonu z załadowanymi kanałami';

  @override
  String get aprsDetails => 'Szczegóły...';

  @override
  String get aprsShowLocation => 'Pokaż lokalizację...';

  @override
  String get aprsSetReceiver => 'Ustaw jako odbiorcę';

  @override
  String get aprsCopyMessage => 'Kopiuj wiadomość';

  @override
  String get aprsCopyCallsign => 'Kopiuj znak wywoławczy';

  @override
  String get aprsCopyChannel => 'Kopiuj kanał';

  @override
  String get aprsClearTitle => 'Wyczyść wiadomości APRS';

  @override
  String get aprsClearPrompt =>
      'Wyczyścić wszystkie wiadomości APRS? Spowoduje to również usunięcie wszystkich znaczników APRS z mapy. Tej operacji nie można cofnąć.';

  @override
  String get aprsShowAll => 'Pokaż wszystkie wiadomości';

  @override
  String get aprsSendSms => 'Wyślij wiadomość SMS...';

  @override
  String get aprsWeatherReport => 'Raport pogodowy...';

  @override
  String get aprsBeaconSettingsMenu => 'Ustawienia beacona...';

  @override
  String get aprsDropShare => 'Upuść, aby udostępnić ten kanał';

  @override
  String get aprsBeaconWarning =>
      'Nadawanie beacona jest włączone na bieżącym kanale, co nie jest zalecane.';

  @override
  String aprsBeaconActive(String interval) {
    return 'Beacon radiowy jest aktywny, interwał: $interval.';
  }

  @override
  String get aprsBeaconSettings => 'Ustawienia beacona';

  @override
  String aprsIntervalSeconds(int count) {
    return '$count sekund';
  }

  @override
  String get aprsIntervalMinute => '1 minuta';

  @override
  String aprsIntervalMinutes(int count) {
    return '$count minut';
  }

  @override
  String get aprsMissingChannel =>
      'Na połączonym radiotelefonie nie skonfigurowano kanału „APRS”. Dodaj kanał APRS, aby wysyłać i odbierać wiadomości APRS.';

  @override
  String get aprsSetup => 'Konfiguruj';

  @override
  String get aprsTypeMessage => 'Wpisz wiadomość...';

  @override
  String get commonYes => 'Tak';

  @override
  String get commonNo => 'Nie';

  @override
  String get commonSend => 'Wyślij';

  @override
  String commonSavedTo(String path) {
    return 'Zapisano w $path';
  }

  @override
  String commsFailedLoadImage(String error) {
    return 'Nie udało się załadować obrazu: $error';
  }

  @override
  String commsFailedSaveImage(String error) {
    return 'Nie udało się zapisać obrazu: $error';
  }

  @override
  String commsFailedEncodeSstv(String error) {
    return 'Nie udało się zakodować dźwięku SSTV: $error';
  }

  @override
  String commsFailedLoadAudio(String error) {
    return 'Nie udało się załadować dźwięku: $error';
  }

  @override
  String get commsUnsupportedWav => 'Nieobsługiwany lub pusty plik WAV.';

  @override
  String get commsSstvWebUnavailable =>
      'Przechwytywanie/transmisja obrazu SSTV jest niedostępne w wersji web.';

  @override
  String get commsNoRadioVoice =>
      'Brak radiotelefonu połączonego do transmisji głosowej.';

  @override
  String get commsSelectImageTitle => 'Wybierz obraz dla SSTV';

  @override
  String get commsSelectWavTitle => 'Wybierz plik audio WAV';

  @override
  String get commsRecordingWebUnavailable =>
      'Odtwarzanie nagrań z plików jest niedostępne w wersji web.';

  @override
  String get commsFileNoLongerExists => 'Plik już nie istnieje.';

  @override
  String get commsSaveAsTitle => 'Zapisz jako';

  @override
  String get commsTransmitDisabledAprs =>
      'Transmisja jest wyłączona, gdy VFO A jest ustawione na kanał APRS.';

  @override
  String get commsWaitTransmission =>
      'Poczekaj na zakończenie bieżącej transmisji.';

  @override
  String get commsConnectRadioChat =>
      'Połącz radiotelefon przed wysłaniem wiadomości czatu.';

  @override
  String get commsEnableAudioMode =>
      'Włącz dźwięk (przycisk Włącz) przed nadawaniem w tym trybie.';

  @override
  String get commsMicNotSupported =>
      'Nagrywanie z mikrofonu nie jest obsługiwane na tej platformie.';

  @override
  String get commsConnectRadioPtt =>
      'Połącz radiotelefon przed użyciem funkcji Push-to-Talk.';

  @override
  String get commsEnableAudioPtt =>
      'Włącz dźwięk (przycisk Włącz) przed użyciem funkcji Push-to-Talk.';

  @override
  String get commsSwitchChatShare =>
      'Przełącz na tryb czatu, aby udostępnić kanał.';

  @override
  String get commsModePtt => 'PTT';

  @override
  String get commsModeChat => 'Czat';

  @override
  String get commsModeSpeak => 'Mowa';

  @override
  String get commsModeMorse => 'Morse';

  @override
  String get commsModeDtmf => 'DTMF';

  @override
  String get commsRecordAudio => 'Nagraj dźwięk';

  @override
  String get commsSendImage => 'Wyślij obraz...';

  @override
  String get commsSendAudio => 'Wyślij dźwięk...';

  @override
  String get commsPttReleaseSettings => 'Ustawienia zwolnienia PTT...';

  @override
  String get commsClearHistory => 'Wyczyść historię';

  @override
  String get commsShowImage => 'Pokaż obraz...';

  @override
  String get commsPlayRecording => 'Odtwórz nagranie...';

  @override
  String get commsSaveAsMenu => 'Zapisz jako...';

  @override
  String get commsShowLocation => 'Pokaż lokalizację';

  @override
  String get commsClearHistoryPrompt =>
      'Czy na pewno chcesz wyczyścić historię głosową?';

  @override
  String get commsAudioMuted => 'Dźwięk jest wyciszony.';

  @override
  String get commsUnmute => 'Wyłącz wyciszenie';

  @override
  String get commsPttTransmitting => 'Trwa transmisja...';

  @override
  String get commsPttHold => 'PTT - Przytrzymaj, aby nadawać';

  @override
  String get commsDtmfHint => 'Wprowadź cyfry DTMF (0-9, *, #)...';

  @override
  String get mailComposeNewTitle => 'Nowa wiadomość';

  @override
  String get mailComposeEditTitle => 'Edytuj wiadomość';

  @override
  String get mailDiscardChanges => 'Odrzucić zmiany w tej wiadomości?';

  @override
  String get mailDiscardMessage => 'Odrzucić tę wiadomość?';

  @override
  String get mailDiscard => 'Odrzuć';

  @override
  String get mailAddCc => 'Dodaj DW';

  @override
  String get mailCc => 'DW';

  @override
  String get mailRemoveCc => 'Usuń DW';

  @override
  String get mailMessageLabel => 'Wiadomość';

  @override
  String get mailSaveDraft => 'Zapisz wersję roboczą';

  @override
  String get mailAttachmentsLabel => 'Załączniki';

  @override
  String get mailAddAttachment => 'Dodaj załącznik';

  @override
  String get mailRemoveAttachment => 'Usuń załącznik';

  @override
  String get mailSaveAttachment => 'Zapisz załącznik';

  @override
  String get mailAttachmentDropHint =>
      'Przeciągnij pliki tutaj, aby je załączyć';

  @override
  String mailAttachmentReadFailed(String name) {
    return 'Nie udało się odczytać pliku: $name';
  }

  @override
  String mailAttachmentSaved(String name) {
    return 'Zapisano „$name”';
  }

  @override
  String mailAttachmentLargeWarning(String size) {
    return 'Duże załączniki ($size) mogą wymagać dużo czasu podczas wysyłania przez radio.';
  }

  @override
  String get smsTitle => 'Wyślij wiadomość SMS';

  @override
  String get smsPhoneNumber => 'Numer telefonu';

  @override
  String get smsIntro =>
      'Możesz wysyłać wiadomości SMS do telefonów w USA, Portoryko, Kanadzie, Australii i Wielkiej Brytanii, jeśli numer wcześniej zaakceptował usługę. Możesz zarejestrować się tutaj: ';

  @override
  String get locationTitle => 'Lokalizacja';

  @override
  String get beaconIntro =>
      'Zmień sposób, w jaki radiotelefon nadaje informacje o sobie, w tym lokalizację, napięcie i niestandardową wiadomość. Inne stacje w pobliżu mogą zobaczyć te informacje.';

  @override
  String beaconRadio(String name) {
    return 'Radiotelefon: $name';
  }

  @override
  String get beaconSection => 'Beacon';

  @override
  String get beaconPacketFormat => 'Format pakietu';

  @override
  String get beaconInterval => 'Interwał beacona';

  @override
  String get beaconAprsCallsign => 'Znak wywoławczy APRS';

  @override
  String get beaconCallsignHint => 'Znak wywoławczy - ID stacji';

  @override
  String get beaconCallsignInvalid =>
      'Wprowadź prawidłowy znak wywoławczy i ID stacji (np. W1AW-5)';

  @override
  String get beaconAprsMessage => 'Wiadomość APRS';

  @override
  String get beaconShareLocation => 'Udostępnij lokalizację';

  @override
  String get beaconSendVoltage => 'Wyślij napięcie';

  @override
  String get beaconAllowPositionCheck => 'Zezwól na sprawdzanie pozycji';

  @override
  String get beaconChannelCurrent => 'Bieżący (niezalecane)';

  @override
  String beaconEverySeconds(int n) {
    return 'Co $n sekund';
  }

  @override
  String beaconEveryMinutes(int n) {
    return 'Co $n minut';
  }

  @override
  String get assConnectTerminal => 'Połącz ze stacją terminalową';

  @override
  String get assConnectBbs => 'Połącz ze stacją BBS';

  @override
  String get assConnectWinlink => 'Połącz z bramą Winlink';

  @override
  String get assConnectStation => 'Połącz ze stacją';

  @override
  String get assNew => 'Nowa…';

  @override
  String get attSelectFile => 'Wybierz plik do udostępnienia';

  @override
  String get attCompressing => 'Kompresowanie...';

  @override
  String get attTitle => 'Dodaj plik torrent';

  @override
  String get attSelect => 'Wybierz...';

  @override
  String get attDescriptionOptional => 'Opis (opcjonalnie)';

  @override
  String get stationTitleVoice => 'Stacja głosowa';

  @override
  String get stationTitleAprs => 'Stacja APRS';

  @override
  String get stationTitleTerminal => 'Stacja terminalowa';

  @override
  String get stationTitleWinlink => 'Brama Winlink';

  @override
  String get stationTitleGeneric => 'Stacja';

  @override
  String get stationTypeOptionVoice => 'Stacja głosowa / ogólna';

  @override
  String get stationTypeLabel => 'Typ stacji';

  @override
  String get stationAprsRoute => 'Trasa APRS';

  @override
  String get stationUseAuth => 'Użyj uwierzytelniania wiadomości';

  @override
  String get stationAuthPassword => 'Hasło uwierzytelniania';

  @override
  String get stationPasswordRequired => 'Wymagane hasło';

  @override
  String get stationTerminalProtocol => 'Protokół terminalowy';

  @override
  String get stationAx25Destination => 'Cel AX.25 (np. CALL-1)';

  @override
  String get stationAx25Invalid => 'Nieprawidłowy adres AX.25';

  @override
  String get stationModem => 'Modem';

  @override
  String get apdTitle => 'Szczegóły pakietu APRS';

  @override
  String get apdCopyAll => 'Kopiuj wszystko';

  @override
  String get apdCopyValue => 'Kopiuj wartość';

  @override
  String get apdValueCopied => 'Wartość skopiowana';

  @override
  String get apdAllValuesCopied => 'Wszystkie wartości skopiowane';

  @override
  String get apdNoDetails => 'Brak dostępnych szczegółów.';

  @override
  String get apdShowLocation => 'Pokaż lokalizację...';

  @override
  String get acfgTitle => 'Konfiguruj kanał APRS';

  @override
  String get acfgIntro =>
      'Częstotliwość APRS różni się w zależności od regionu świata. Skorzystaj z tej strony, aby znaleźć odpowiednią częstotliwość do skonfigurowania kanału APRS.';

  @override
  String get acfgConfiguration => 'Konfiguracja APRS';

  @override
  String get acfgFrequency => 'Częstotliwość';

  @override
  String get acfgFrequencyHint =>
      '144.39 w Ameryce Północnej\n144.80 w Europie';

  @override
  String get acfgChannelOverwritten => 'Wybrany kanał zostanie nadpisany';

  @override
  String get sstvSendTitle => 'Wyślij obraz SSTV';

  @override
  String sstvSendTitleNamed(String name) {
    return 'Wyślij obraz SSTV - $name';
  }

  @override
  String get sstvMode => 'Tryb:';

  @override
  String sstvTransmitTime(String time) {
    return 'Czas transmisji: ~$time';
  }

  @override
  String get msgdTitle => 'Szczegóły wiadomości';

  @override
  String get msgdFieldType => 'Typ';

  @override
  String get msgdFieldDirection => 'Kierunek';

  @override
  String get msgdFieldTime => 'Czas';

  @override
  String get msgdFieldSource => 'Źródło';

  @override
  String get msgdFieldReceiver => 'Odbiorca';

  @override
  String get msgdFieldDuration => 'Czas trwania';

  @override
  String get msgdFieldLatitude => 'Szerokość geograficzna';

  @override
  String get msgdFieldLongitude => 'Długość geograficzna';

  @override
  String get msgdFieldMessage => 'Wiadomość';

  @override
  String get msgdFieldFile => 'Plik';

  @override
  String get msgdDirReceived => 'Odebrano';

  @override
  String get msgdDirSent => 'Wysłano';

  @override
  String get msgdTypeVoice => 'Głos';

  @override
  String get msgdTypeVoiceClip => 'Klip głosowy';

  @override
  String get msgdTypeRecording => 'Nagranie';

  @override
  String get msgdTypeSstvPicture => 'Obraz SSTV';

  @override
  String get msgdTypeIdentification => 'Identyfikacja';

  @override
  String get msgdTypeChatMessage => 'Wiadomość czatu';

  @override
  String get msgdTypeAx25Packet => 'Pakiet AX.25';

  @override
  String get rpbFailedToLoad => 'Nie udało się załadować nagrania.';

  @override
  String get ivwFailedToLoad => 'Nie udało się załadować obrazu.';

  @override
  String get rawTitle => 'Surowe polecenie radiowe';

  @override
  String get rawCommand => 'Polecenie';

  @override
  String get rawHexPayload => 'Ładunek HEX (opcjonalnie)';

  @override
  String get rawResponse => 'Odpowiedź';

  @override
  String get identTitle => 'Ustawienia zwolnienia PTT';

  @override
  String get identDescription =>
      'Gdy włączone, wysyła Twój znak wywoławczy i/lub informacje o pozycji za każdym razem, gdy zwolnisz przycisk PTT na kanale, na którym nadajesz.';

  @override
  String get identCallsignHint => 'Wprowadź znak wywoławczy - ID stacji';

  @override
  String get identSendCallsign => 'Wyślij znak wywoławczy';

  @override
  String get identSendPosition => 'Wyślij pozycję';

  @override
  String get commonOn => 'Wł.';

  @override
  String get commonOff => 'Wył.';

  @override
  String get commonNone => 'Brak';

  @override
  String chChannelNumber(int n) {
    return 'Kanał $n';
  }

  @override
  String chChShort(int n) {
    return 'Kanał $n';
  }

  @override
  String get chMoreSettings => 'Więcej ustawień';

  @override
  String get chChannelNameHint => 'Nazwa kanału';

  @override
  String get chFrequencyMhz => 'Częstotliwość (MHz)';

  @override
  String get chReceiveMhz => 'Odbiór (MHz)';

  @override
  String get chTransmitMhz => 'Nadawanie (MHz)';

  @override
  String get chMode => 'Tryb';

  @override
  String get chPower => 'Moc';

  @override
  String get chBandwidth => 'Szerokość pasma';

  @override
  String get chReceiveTone => 'Ton odbioru (CTCSS / DCS)';

  @override
  String get chTransmitTone => 'Ton nadawania (CTCSS / DCS)';

  @override
  String get chDisableTransmit => 'Wyłącz nadawanie';

  @override
  String get chMute => 'Wycisz';

  @override
  String get chScan => 'Skanowanie';

  @override
  String get chTalkAround => 'Talk around';

  @override
  String get chDeemphasis => 'Deemphasis';

  @override
  String get chPowerHigh => 'Wysoka';

  @override
  String get chPowerMedium => 'Średnia';

  @override
  String get chPowerLow => 'Niska';

  @override
  String get chBandwidthWide => '25 KHz szerokie';

  @override
  String get chBandwidthNarrow => '12.5 KHz wąskie';

  @override
  String get channelImportFetching =>
      'Pobieranie kanału ze strony internetowej…';

  @override
  String get channelImportUnsupportedSite =>
      'Ta witryna nie jest obsługiwana przy imporcie kanałów.';

  @override
  String get channelImportFetchFailed =>
      'Nie udało się pobrać strony internetowej.';

  @override
  String get channelImportParseFailed =>
      'Nie znaleziono szczegółów kanału na tej stronie.';

  @override
  String get chClearTitle => 'Wyczyść kanał';

  @override
  String chClearConfirm(int n) {
    return 'Wyczyścić kanał $n?\n\nSpowoduje to usunięcie częstotliwości, nazwy i ustawień tego slotu z radiotelefonu.';
  }

  @override
  String get cdRxFrequency => 'Częstotliwość RX';

  @override
  String get cdTxFrequency => 'Częstotliwość TX';

  @override
  String get cdRxModulation => 'Modulacja RX';

  @override
  String get cdTxModulation => 'Modulacja TX';

  @override
  String get cdRxTone => 'Ton RX';

  @override
  String get cdTxTone => 'Ton TX';

  @override
  String get cdTxDisabled => 'Nadawanie wyłączone';

  @override
  String get cdTalkAround => 'Talk around';

  @override
  String get cdEmpty => '(puste)';

  @override
  String get cdBandwidthWide => '25 kHz (szerokie)';

  @override
  String get cdBandwidthNarrow => '12.5 kHz (wąskie)';

  @override
  String get gpsDetailsTitle => 'Szczegóły GPS';

  @override
  String get gpsDisabled => 'GPS wyłączony';

  @override
  String get gpsLock => 'Blokada GPS';

  @override
  String get gpsNoLock => 'Brak blokady GPS';

  @override
  String get mdbgTitle => 'Ruch Winlink';

  @override
  String get mdbgNoTraffic => 'Obecnie brak ruchu.';

  @override
  String get fwTitle => 'Aktualizacja oprogramowania radiotelefonu';

  @override
  String get fwStatusInitial =>
      'Sprawdź dostępność aktualizacji oprogramowania online lub załaduj plik oprogramowania z dysku.';

  @override
  String get fwErrNotConnected => 'Radiotelefon nie jest połączony.';

  @override
  String get fwErrNoDeviceInfo =>
      'Informacje o urządzeniu radiotelefonu nie są jeszcze dostępne.';

  @override
  String get fwStatusChecking =>
      'Sprawdzanie dostępności aktualizacji oprogramowania…';

  @override
  String get fwErrNoServerInfo =>
      'Serwer producenta nie zwrócił informacji o oprogramowaniu.';

  @override
  String fwUpdateAvailable(String version) {
    return 'Dostępna jest aktualizacja oprogramowania $version. Zapoznaj się z informacjami o wydaniu poniżej, a następnie pobierz, aby zaktualizować.';
  }

  @override
  String fwErrCheckFailed(String error) {
    return 'Sprawdzanie aktualizacji nie powiodło się: $error';
  }

  @override
  String get fwPickTitle => 'Wybierz plik oprogramowania';

  @override
  String fwLoaded(String name, String size, String md5) {
    return 'Załadowano $name: $size (MD5 $md5…).';
  }

  @override
  String fwErrLoadFailed(String error) {
    return 'Nie można załadować pliku oprogramowania: $error';
  }

  @override
  String get fwSaveTitle => 'Zapisz plik oprogramowania';

  @override
  String fwSavedTo(String path) {
    return 'Oprogramowanie zapisane w $path';
  }

  @override
  String fwErrSaveFailed(String error) {
    return 'Nie można zapisać pliku oprogramowania: $error';
  }

  @override
  String get fwStatusDownloading => 'Pobieranie i składanie oprogramowania…';

  @override
  String get fwProgressStarting => 'Rozpoczynanie…';

  @override
  String fwReady(String size, String md5) {
    return 'Oprogramowanie gotowe: $size (MD5 $md5…).';
  }

  @override
  String fwErrDownloadFailed(String error) {
    return 'Pobieranie nie powiodło się: $error';
  }

  @override
  String get fwStatusWriting =>
      'Zapisywanie oprogramowania w radiotelefonie. Nie wyłączaj go.';

  @override
  String get fwProgressTransferring => 'Przesyłanie…';

  @override
  String fwErrTransferFailed(String error) {
    return 'Przesyłanie oprogramowania nie powiodło się: $error';
  }

  @override
  String get fwStatusRebooting =>
      'Radiotelefon jest uruchamiany ponownie. Ponowne łączenie…';

  @override
  String get fwProgressWaitingRestart =>
      'Oczekiwanie na ponowne uruchomienie radiotelefonu…';

  @override
  String fwErrReconnectFailed(String error) {
    return 'Ponowne połączenie po ponownym uruchomieniu nie powiodło się: $error';
  }

  @override
  String get fwErrReconnectNull =>
      'Nie udało się ponownie połączyć z radiotelefonem po ponownym uruchomieniu. Oprogramowanie zostało przesłane, ale niepotwierdzone. Połącz ponownie ręcznie i spróbuj jeszcze raz.';

  @override
  String get fwStatusFinalising => 'Finalizowanie aktualizacji…';

  @override
  String get fwProgressConfirming => 'Potwierdzanie…';

  @override
  String fwErrConfirmFailed(String error) {
    return 'Potwierdzenie aktualizacji nie powiodło się: $error';
  }

  @override
  String get fwStatusComplete =>
      'Aktualizacja oprogramowania zakończona! Radiotelefon działa teraz na nowym oprogramowaniu.';

  @override
  String get fwProgressDownloadPatch => 'Pobieranie łatki';

  @override
  String get fwProgressDownloadBase => 'Pobieranie obrazu bazowego';

  @override
  String get fwProgressAssemble => 'Składanie oprogramowania';

  @override
  String fwProgressBytes(String label, String done, String total) {
    return '$label ($done / $total)';
  }

  @override
  String fwProgressTransferringBytes(String done, String total) {
    return 'Przesyłanie ($done / $total)';
  }

  @override
  String fwCurrentFirmware(String version) {
    return 'Bieżące oprogramowanie: $version';
  }

  @override
  String get fwErrGeneric => 'Wystąpił błąd.';

  @override
  String get fwIdleDisclosure =>
      'Sprawdzanie online kontaktuje się z serwerem producenta radiotelefonu (rpc.benshikj.com) i wysyła tylko identyfikator produktu Twojego radiotelefonu. Nic nie jest wysyłane, dopóki nie dotkniesz opcji Sprawdź aktualizacje.';

  @override
  String get fwWhatsNew => 'Nowości';

  @override
  String get fwConfirmWarning =>
      'Ostrzeżenie: Utrzymuj radiotelefon włączony, naładowany i w zasięgu Bluetooth przez cały proces. Radiotelefon zostanie w tym czasie ponownie uruchomiony. Przerwanie aktualizacji może wymagać ręcznego odzyskiwania.';

  @override
  String get fwFromFile => 'Z pliku…';

  @override
  String get fwCheckForUpdate => 'Sprawdź aktualizacje';

  @override
  String get fwDownload => 'Pobierz';

  @override
  String get fwSave => 'Zapisz…';

  @override
  String get fwFlashNow => 'Wgraj teraz';

  @override
  String get fwRetry => 'Ponów';

  @override
  String get wxTitle => 'Zażądaj raportu pogodowego';

  @override
  String get wxIntro => 'Zażądaj raportu pogodowego przez APRS. ';

  @override
  String get wxLocation => 'Lokalizacja';

  @override
  String get wxLocationHelper =>
      'Miasto/stan w USA lub kod pocztowy USA lub współrzędne 41.123/-121.334';

  @override
  String get wxTime => 'Czas';

  @override
  String get wxReport => 'Raport';

  @override
  String get wxToday => 'Dziś';

  @override
  String get wxTonight => 'Dziś wieczorem';

  @override
  String get wxTomorrow => 'Jutro';

  @override
  String get wxTomorrowNight => 'Jutro wieczorem';

  @override
  String get wxMonday => 'Poniedziałek';

  @override
  String get wxMondayNight => 'Poniedziałek wieczorem';

  @override
  String get wxTuesday => 'Wtorek';

  @override
  String get wxTuesdayNight => 'Wtorek wieczorem';

  @override
  String get wxWednesday => 'Środa';

  @override
  String get wxWednesdayNight => 'Środa wieczorem';

  @override
  String get wxThursday => 'Czwartek';

  @override
  String get wxThursdayNight => 'Czwartek wieczorem';

  @override
  String get wxFriday => 'Piątek';

  @override
  String get wxFridayNight => 'Piątek wieczorem';

  @override
  String get wxSaturday => 'Sobota';

  @override
  String get wxSaturdayNight => 'Sobota wieczorem';

  @override
  String get wxSunday => 'Niedziela';

  @override
  String get wxSundayNight => 'Niedziela wieczorem';

  @override
  String get wxReportBrief => 'Krótki, Skrócona prognoza, tylko USA';

  @override
  String get wxReportFull => 'Pełny, Bardziej szczegółowa prognoza, tylko USA';

  @override
  String get wxReportCurrent => 'Bieżący, Najbliższa stacja NWS, tylko USA';

  @override
  String get wxReportMetar => 'METAR, Stacja ICAO w formacie METAR';

  @override
  String get wxReportCwop => 'CWOP, Najbliższa stacja CWOP';
}
