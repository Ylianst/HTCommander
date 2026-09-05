// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Handi-Talkie Commander';

  @override
  String get menuFile => 'File';

  @override
  String get menuConnect => 'Connetti...';

  @override
  String get menuDisconnect => 'Disconnetti';

  @override
  String get menuSettings => 'Impostazioni...';

  @override
  String get menuExit => 'Esci';

  @override
  String get menuRadios => 'Radio';

  @override
  String get menuDualWatch => 'Dual-Watch';

  @override
  String get menuScan => 'Scansione';

  @override
  String get menuRegions => 'Regioni';

  @override
  String get menuFmRadio => 'Radio FM...';

  @override
  String get menuExportChannels => 'Esporta canali...';

  @override
  String get menuImportChannels => 'Importa canali...';

  @override
  String get menuMacRadio => 'Radio';

  @override
  String get menuMacDisplay => 'Schermo';

  @override
  String get fmRadioTitle => 'Radio FM';

  @override
  String fmRadioMhz(String value) {
    return '${value}MHz';
  }

  @override
  String get fmRadioOff => 'Spenta';

  @override
  String get fmRadioPowerTooltip => 'Accendi o spegni la radio FM';

  @override
  String get radioPowerTooltip => 'Accendi o spegni la radio';

  @override
  String get radioPoweredOff => 'La radio è spenta';

  @override
  String get fmRadioSeekDownTooltip => 'Cerca indietro';

  @override
  String get fmRadioStepDownTooltip => 'Sintonizza in giù';

  @override
  String get fmRadioStopTooltip => 'Spegni';

  @override
  String get fmRadioStepUpTooltip => 'Sintonizza in su';

  @override
  String get fmRadioSeekUpTooltip => 'Cerca avanti';

  @override
  String get fmRadioStationsHeader => 'Stazioni preferite';

  @override
  String get fmRadioAddStationTooltip => 'Aggiungi la frequenza corrente';

  @override
  String get fmRadioNoStations => 'Nessuna stazione preferita';

  @override
  String get fmRadioStationNameLabel => 'Nome stazione';

  @override
  String get fmRadioRenameTitle => 'Nome stazione';

  @override
  String get fmRadioDeleteTitle => 'Elimina stazione';

  @override
  String fmRadioDeleteMessage(String name) {
    return 'Rimuovere \"$name\" dalle stazioni preferite?';
  }

  @override
  String get commonClose => 'Chiudi';

  @override
  String get commonCancel => 'Annulla';

  @override
  String get commonOk => 'OK';

  @override
  String get stationConnectErrorTitle => 'Impossibile connettersi';

  @override
  String get stationConnectErrorEdit => 'Modifica contatto';

  @override
  String stationConnectErrorRegion(String region) {
    return 'La regione \"$region\" configurata per questo contatto non è stata trovata sulla radio. Vuoi modificare il contatto?';
  }

  @override
  String stationConnectErrorChannel(String channel) {
    return 'Il canale \"$channel\" configurato per questo contatto non è stato trovato sulla radio. Vuoi modificare il contatto?';
  }

  @override
  String get stationConnectErrorNoChannel =>
      'Nessun canale è configurato per questo contatto. Vuoi modificare il contatto?';

  @override
  String get aboutCheckForUpdates => 'Verifica aggiornamenti';

  @override
  String aboutVersionAuthor(String version) {
    return 'Versione $version\nYlian Saint-Hilaire, KK7VZT\nOpen Source, licenza Apache 2.0';
  }

  @override
  String get settingsLanguage => 'Lingua';

  @override
  String get settingsLanguageHint =>
      'Scegli la lingua usata dall\'applicazione. \'Predefinita di sistema\' segue la lingua del dispositivo.';

  @override
  String get settingsThemeMode => 'Tema';

  @override
  String get settingsThemeModeHint =>
      'Scegli l\'aspetto chiaro o scuro. \'Predefinito di sistema\' segue l\'impostazione del dispositivo.';

  @override
  String get settingsThemeModeSystem => 'Predefinito di sistema';

  @override
  String get settingsThemeModeLight => 'Chiaro';

  @override
  String get settingsThemeModeDark => 'Scuro';

  @override
  String get languageSystem => 'Predefinita di sistema';

  @override
  String get languageEnglish => 'Inglese';

  @override
  String get languageFrench => 'Francese';

  @override
  String get languageSpanish => 'Spagnolo';

  @override
  String get languageChinese => 'Cinese';

  @override
  String get languageJapanese => 'Giapponese';

  @override
  String get languageHindi => 'Hindi';

  @override
  String get languageGerman => 'Tedesco';

  @override
  String get languagePolish => 'Polacco';

  @override
  String get languageItalian => 'Italiano';

  @override
  String get menuAudio => 'Audio';

  @override
  String get menuAudioEnabled => 'Audio abilitato';

  @override
  String get menuSoftwareModem => 'Modem software';

  @override
  String get menuModemDisabled => 'Disabilitato';

  @override
  String get menuDartTransmitLevel => 'Livello di trasmissione DART';

  @override
  String get menuDartLevel0 => 'Livello 0 (BPSK, LDPC 1/2)';

  @override
  String get menuDartLevel1 => 'Livello 1 (QPSK, LDPC 1/2)';

  @override
  String get menuDartLevel2 => 'Livello 2 (QPSK, LDPC 2/3)';

  @override
  String get menuDartLevel3 => 'Livello 3 (8PSK, LDPC 2/3)';

  @override
  String get menuDartLevel4 => 'Livello 4 (16QAM, LDPC 3/4)';

  @override
  String get menuDartLevel5 => 'Livello 5 (16QAM, LDPC 5/6)';

  @override
  String get menuDartLevelF => 'Livello F (4-FSK, LDPC 1/2)';

  @override
  String get menuAprsModem => 'Modem APRS';

  @override
  String get menuView => 'Visualizza';

  @override
  String get menuRadio => 'Radio';

  @override
  String get menuTabs => 'Schede';

  @override
  String get menuTabNames => 'Nomi delle schede';

  @override
  String get menuShowAllTabs => 'Mostra tutte le schede';

  @override
  String get menuAllChannels => 'Tutti i canali';

  @override
  String get menuChannelFrequency => 'Frequenza del canale';

  @override
  String get menuStatusBar => 'Barra di stato';

  @override
  String get menuHelp => 'Aiuto';

  @override
  String get menuRadioInformation => 'Informazioni radio...';

  @override
  String get menuGpsInformation => 'Informazioni GPS...';

  @override
  String get menuCheckForUpdatesEllipsis => 'Verifica aggiornamenti...';

  @override
  String get menuCheckForUpdates => 'Verifica aggiornamenti';

  @override
  String get menuAbout => 'Informazioni su...';

  @override
  String get tabComms => 'Comms';

  @override
  String get tabAudio => 'Audio';

  @override
  String get tabAprs => 'APRS';

  @override
  String get tabMap => 'Mappa';

  @override
  String get tabMail => 'Posta';

  @override
  String get tabTerminal => 'Terminale';

  @override
  String get tabContacts => 'Contatti';

  @override
  String get tabBbs => 'BBS';

  @override
  String get tabTorrent => 'Torrent';

  @override
  String get tabPackets => 'Pacchetti';

  @override
  String get tabDebug => 'Debug';

  @override
  String get tabRadio => 'Radio';

  @override
  String get stateDisconnected => 'Disconnesso';

  @override
  String get stateConnecting => 'Connessione in corso...';

  @override
  String get stateConnected => 'Connesso';

  @override
  String get stateUnableToConnect => 'Impossibile connettersi';

  @override
  String get stateAccessDenied => 'Accesso negato';

  @override
  String get stateSelectRadio => 'Seleziona radio';

  @override
  String statusBattery(int percent) {
    return 'Batteria: $percent%';
  }

  @override
  String get statusCheckingBluetooth => 'Verifica del Bluetooth...';

  @override
  String get statusBluetoothNotAvailable => 'Bluetooth non disponibile';

  @override
  String get statusScanningForRadios => 'Ricerca di radio...';

  @override
  String get statusErrorScanning => 'Errore durante la ricerca di radio';

  @override
  String get statusNoCompatibleRadios => 'Nessuna radio compatibile trovata';

  @override
  String get statusAllRadiosConnected => 'Tutte le radio sono già connesse';

  @override
  String statusConnectingTo(String name) {
    return 'Connessione a $name...';
  }

  @override
  String statusConnectedTo(String name) {
    return 'Connesso a $name';
  }

  @override
  String statusFailedToConnect(String name) {
    return 'Connessione a $name non riuscita';
  }

  @override
  String get statusDisconnecting => 'Disconnessione in corso...';

  @override
  String get settingsTabLicense => 'Licenza';

  @override
  String get settingsTabAprs => 'APRS';

  @override
  String get settingsTabComms => 'Comms';

  @override
  String get settingsTabWinlink => 'Winlink';

  @override
  String get settingsTabEchoLink => 'EchoLink';

  @override
  String get settingsTabAllStar => 'AllStarLink';

  @override
  String get settingsAllStarIntro =>
      'Connettiti a un nodo AllStarLink tramite internet usando IAX2.';

  @override
  String get settingsAllStarNodes => 'Nodi salvati';

  @override
  String get settingsAllStarNoNodes =>
      'Nessun nodo configurato. Aggiungi un nodo per connetterti.';

  @override
  String get settingsAllStarAddNode => 'Aggiungi nodo';

  @override
  String get settingsAllStarEditNode => 'Modifica nodo';

  @override
  String get settingsAllStarNodeName => 'Nome';

  @override
  String get settingsAllStarNodeNameHint => 'es. Il mio ripetitore';

  @override
  String get settingsAllStarNodeHost => 'Host';

  @override
  String get settingsAllStarNodePort => 'Porta';

  @override
  String get settingsAllStarNodeUser => 'Nome utente IAX';

  @override
  String get settingsAllStarNodeSecret => 'Secret IAX';

  @override
  String get settingsAllStarNodeNumber => 'Numero nodo';

  @override
  String get settingsAllStarNodeHelp =>
      'L\'host, il nome utente IAX e il secret provengono dal file iax.conf del nodo; il numero del nodo è il nodo AllStarLink a cui vuoi connetterti.';

  @override
  String get settingsAllStarDeleteNode => 'Elimina nodo';

  @override
  String settingsAllStarDeleteNodeConfirm(String name) {
    return 'Rimuovere \"$name\" dai nodi salvati?';
  }

  @override
  String get settingsAllStarAccount => 'Account AllStarLink';

  @override
  String get settingsAllStarAccountIntro =>
      'Usa il tuo account del portale AllStarLink per connetterti ai nodi pubblici (WT) senza credenziali per singolo nodo.';

  @override
  String get settingsAllStarAccountForCallsign =>
      'Inserisci la password dell\'account del portale AllStarLink del tuo nominativo.';

  @override
  String get settingsAllStarAccountPassword => 'Password account';

  @override
  String get settingsAllStarAuthenticate => 'Autentica';

  @override
  String get settingsAllStarReauthenticate => 'Autentica di nuovo';

  @override
  String settingsAllStarAccountAuthorized(String callsign) {
    return 'Autorizzato come $callsign';
  }

  @override
  String get settingsAllStarAccountNotAuthorized => 'Non autorizzato';

  @override
  String get settingsAllStarAuthSuccess => 'Autenticazione riuscita.';

  @override
  String settingsAllStarAuthFailed(String message) {
    return 'Autenticazione non riuscita: $message';
  }

  @override
  String get settingsAllStarNoCallsign =>
      'Imposta il tuo nominativo nelle impostazioni del nominativo prima di autenticarti.';

  @override
  String get settingsAllStarAuthMode => 'Autenticazione';

  @override
  String get settingsAllStarAuthModeAccount => 'Account (WT)';

  @override
  String get settingsAllStarAuthModeNode => 'Credenziali nodo';

  @override
  String get settingsAllStarHostTitle => 'Ospita un nodo';

  @override
  String get settingsAllStarHostIntro =>
      'Instrada l\'audio tra una radio e la rete AllStarLink. Ottieni un numero di nodo e una password da allstarlink.org, poi blocca una radio su AllStarLink nella scheda Comms.';

  @override
  String get settingsAllStarHostPassword => 'Password nodo';

  @override
  String get settingsAllStarHostPort => 'Porta IAX';

  @override
  String get settingsAllStarHostRegistration => 'Registrazione';

  @override
  String get settingsAllStarHostRegIax => 'AllStarLink (IAX)';

  @override
  String get settingsAllStarHostRegHttp => 'AllStarLink (HTTP)';

  @override
  String get settingsAllStarHostRegNone => 'Nessuna (privato)';

  @override
  String get settingsAllStarHostAllowWt =>
      'Consenti connessioni Web Transceiver';

  @override
  String get settingsAllStarHostAllowWtHint =>
      'Consenti alle persone che usano il client pubblico Web Transceiver di AllStarLink di connettersi al tuo nodo. Il token del portale di ogni chiamante viene verificato con AllStarLink.';

  @override
  String settingsAllStarHostNote(int port) {
    return 'L\'hosting richiede l\'inoltro di UDP $port a questo computer. In qualità di operatore di controllo sei responsabile di tutto l\'audio instradato verso l\'RF.';
  }

  @override
  String get settingsTabServers => 'Server';

  @override
  String get settingsTabMap => 'Mappa';

  @override
  String get settingsTabLimits => 'Limiti';

  @override
  String get settingsTabApplication => 'Applicazione';

  @override
  String get settingsAdd => 'Aggiungi';

  @override
  String get settingsRemove => 'Rimuovi';

  @override
  String get settingsDownload => 'Scarica';

  @override
  String get settingsRetry => 'Riprova';

  @override
  String get settingsPreview => 'Anteprima';

  @override
  String get settingsNone => 'Nessuno';

  @override
  String get settingsLicenseInfo =>
      'Negli Stati Uniti è necessaria una licenza di radioamatore per trasmettere. Visita il sito web dell\'ARRL per maggiori informazioni su come ottenere la licenza.';

  @override
  String get settingsCallSignStationId => 'Nominativo e ID stazione';

  @override
  String get settingsCallSign => 'Nominativo';

  @override
  String get settingsCallSignHint => 'es. W1AW';

  @override
  String get settingsStationId => 'ID stazione';

  @override
  String get settingsAllowTransmit =>
      'Consenti a questa applicazione di trasmettere';

  @override
  String get settingsCallSignHelp =>
      'Inserisci un nominativo valido (almeno 3 caratteri) per abilitare la trasmissione';

  @override
  String get settingsLocation => 'Posizione';

  @override
  String get settingsLocationInfo =>
      'Scegli da dove proviene la tua posizione attuale. Viene inviata alla radio e usata per APRS-IS e il tracciamento dei satelliti.';

  @override
  String get settingsLocationSourceGps => 'Dal GPS (radio o GPS seriale)';

  @override
  String get settingsLocationSourceManual => 'Imposta manualmente';

  @override
  String get settingsLocationLatitude => 'Latitudine';

  @override
  String get settingsLocationLongitude => 'Longitudine';

  @override
  String get settingsLocationSelectOnMap => 'Seleziona sulla mappa…';

  @override
  String get settingsLocationNotSet =>
      'Nessuna posizione impostata. Seleziona una posizione sulla mappa.';

  @override
  String get locationPickerTitle => 'Seleziona posizione';

  @override
  String get locationPickerHint =>
      'Sposta e ingrandisci la mappa in modo che l\'indicatore sia sulla tua posizione, poi premi OK.';

  @override
  String get settingsAprsIntro =>
      'Configura i percorsi di instradamento APRS per la trasmissione dei pacchetti.';

  @override
  String get settingsAprsRoutes => 'Percorsi APRS';

  @override
  String get settingsAprsIsTitle => 'Gateway internet';

  @override
  String get settingsAprsIsIntro =>
      'Connettiti alla rete APRS-IS per inviare e ricevere pacchetti APRS tramite internet e per instradare i pacchetti tra internet e l\'RF.';

  @override
  String get settingsAprsIsNoCallSign =>
      'Imposta il tuo nominativo nella scheda Licenza per abilitare APRS-IS.';

  @override
  String get settingsAprsIsEnable => 'Abilita APRS-IS';

  @override
  String get settingsAprsIsPasscode => 'Passcode';

  @override
  String settingsAprsIsPasscodeFor(String callSign) {
    return 'Passcode per $callSign';
  }

  @override
  String get settingsAprsIsPasscodeHint => 'Inserisci il tuo passcode APRS-IS';

  @override
  String get settingsAprsIsServer => 'Server';

  @override
  String get settingsAprsIsServerRegion => 'Regione del server';

  @override
  String get settingsAprsIsRegionWorldwide => 'Mondiale';

  @override
  String get settingsAprsIsRegionNorthAmerica => 'Nord America';

  @override
  String get settingsAprsIsRegionSouthAmerica => 'Sud America';

  @override
  String get settingsAprsIsRegionEurope => 'Europa';

  @override
  String get settingsAprsIsRegionAsia => 'Asia';

  @override
  String get settingsAprsIsRegionOceania => 'Oceania';

  @override
  String get settingsAprsIsRegionCustom => 'Personalizzato';

  @override
  String get settingsAprsIsRange => 'Raggio';

  @override
  String get settingsAprsIsRangeOff => 'Solo messaggi per me';

  @override
  String settingsAprsIsRangeMiles(int miles) {
    return '$miles miglia';
  }

  @override
  String settingsAprsIsRangeKm(int km) {
    return '$km km';
  }

  @override
  String get settingsAprsIsCenter => 'Centro (ultimo GPS)';

  @override
  String get settingsAprsIsNoPosition => 'Nessuna posizione GPS ancora';

  @override
  String get settingsAprsIsRangeHelp =>
      'Ricevi il traffico APRS entro questo raggio dalla tua ultima posizione GPS confermata, ottenuta da una radio o da un GPS seriale.';

  @override
  String get settingsAprsIsGateToRf =>
      'Instrada i messaggi da internet all\'RF (IGate)';

  @override
  String get settingsAprsIsGateToRfHelp =>
      'Trasmetti sull\'RF i messaggi provenienti da internet per le stazioni ascoltate localmente nell\'ultima ora. Richiede una radio con un canale APRS.';

  @override
  String get settingsAprsCloudNotifications =>
      'Notifiche push (aprs.meshcentral.com)';

  @override
  String get settingsAprsCloudNotificationsHelp =>
      'Registrati al server aprs.meshcentral.com per ricevere come notifiche push i messaggi APRS indirizzati alla tua stazione, anche quando l\'app è chiusa. Richiede che APRS-IS sia abilitato con un passcode valido.';

  @override
  String get settingsAprsFiTitle => 'Recupero da APRS.fi';

  @override
  String get settingsAprsFiIntro =>
      'Fornisci la tua chiave API personale di aprs.fi per recuperare i messaggi APRS indirizzati a te ricevuti mentre questa app era offline. I messaggi vengono uniti a quelli che hai già.';

  @override
  String get settingsAprsFiApiKey => 'Chiave API aprs.fi';

  @override
  String get settingsAprsFiApiKeyHint => 'Inserisci la tua chiave API aprs.fi';

  @override
  String get settingsAprsFiTestNoKey => 'Inserisci prima una chiave API.';

  @override
  String get settingsAprsFiTestNoCallSign => 'Imposta prima il tuo nominativo.';

  @override
  String get settingsAprsFiTestMessagesTitle => 'Messaggi di test APRS.fi';

  @override
  String settingsAprsFiTestSuccess(int count) {
    return 'Riuscito, trovati $count messaggi.';
  }

  @override
  String get settingsEditRoute => 'Modifica percorso';

  @override
  String get settingsEditRouteProtected =>
      'Il percorso integrato non può essere modificato';

  @override
  String get settingsDeleteRoute => 'Elimina percorso';

  @override
  String get settingsDeleteRouteProtected =>
      'Il percorso integrato non può essere rimosso';

  @override
  String get settingsCommsIntro =>
      'Configura le impostazioni di riconoscimento vocale e sintesi vocale.';

  @override
  String get settingsSpeechToText => 'Da voce a testo';

  @override
  String get settingsSpeechToTextInfo =>
      'Trascrive in testo l\'audio radio ricevuto. Funziona completamente offline su questo dispositivo; l\'audio non viene mai scritto su disco.';

  @override
  String get settingsModel => 'Modello';

  @override
  String get settingsRecognitionLanguage => 'Lingua di riconoscimento';

  @override
  String get settingsRecognitionLanguageHelp =>
      'Le modifiche alla lingua hanno effetto al successivo avvio del motore.';

  @override
  String get settingsStatus => 'Stato';

  @override
  String settingsModelInstalled(String suffix) {
    return 'Modello installato$suffix';
  }

  @override
  String settingsDownloadingModelPct(String percent) {
    return 'Download del modello… $percent%';
  }

  @override
  String get settingsDownloadingModel => 'Download del modello…';

  @override
  String settingsInstallingModelPct(String percent) {
    return 'Installazione del modello… $percent%';
  }

  @override
  String get settingsInstallingModel => 'Installazione del modello…';

  @override
  String get settingsModelInstallError => 'Impossibile installare il modello.';

  @override
  String settingsModelNotDownloaded(String downloadLabel) {
    return 'Modello non scaricato. $downloadLabel avviene una sola volta e viene memorizzato in cache su questo dispositivo.';
  }

  @override
  String settingsBytesOf(String received, String total) {
    return '$received di $total';
  }

  @override
  String get settingsRemoveSttModelTitle =>
      'Rimuovere il modello da voce a testo?';

  @override
  String settingsRemoveSttModelBody(String name) {
    return 'Il modello \"$name\" scaricato verrà eliminato per liberare spazio su disco. Verrà scaricato di nuovo al successivo utilizzo.';
  }

  @override
  String get settingsTextToSpeech => 'Da testo a voce';

  @override
  String get settingsTextToSpeechInfo =>
      'Usato quando si invia testo in modalità \"Parla\" dalla scheda Comms.';

  @override
  String get settingsTtsUnavailableTitle =>
      'La sintesi vocale non è disponibile';

  @override
  String get settingsVoice => 'Voce';

  @override
  String get settingsSpeechRate => 'Velocità del parlato';

  @override
  String get settingsPitch => 'Tono';

  @override
  String get settingsLoadingVoices => 'Caricamento delle voci…';

  @override
  String get settingsSystemDefault => 'Predefinito di sistema';

  @override
  String get settingsLangAutoDetect => 'Rilevamento automatico';

  @override
  String get settingsLangChinese => 'Cinese';

  @override
  String get settingsLangJapanese => 'Giapponese';

  @override
  String get settingsLangKorean => 'Coreano';

  @override
  String get settingsLangCantonese => 'Cantonese';

  @override
  String get settingsWinlinkIntro =>
      'Configura le impostazioni email Winlink per l\'email via radio.';

  @override
  String get settingsWinlinkAccount => 'Account Winlink';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsWinlinkAccountHelp =>
      'Basato sul tuo nominativo dalla scheda Licenza';

  @override
  String get settingsPassword => 'Password';

  @override
  String settingsPasswordFor(String account) {
    return 'Password per $account';
  }

  @override
  String get settingsUseStationIdWinlink => 'Usa l\'ID stazione per Winlink';

  @override
  String get settingsEchoLinkIntro =>
      'Configura EchoLink per parlare con altre stazioni tramite internet.';

  @override
  String get settingsEchoLinkAccount => 'Account EchoLink';

  @override
  String get settingsEchoLinkAccountHelp =>
      'Basato sul tuo nominativo dalla scheda Licenza';

  @override
  String get settingsEchoLinkLocation => 'Posizione';

  @override
  String get settingsEchoLinkLocationHelp =>
      'Mostrata alle altre stazioni nella directory, come la tua città e regione.';

  @override
  String get settingsEchoLinkNoCallSign =>
      'Inserisci il tuo nominativo nella scheda Licenza per abilitare EchoLink.';

  @override
  String get settingsEchoLinkTestSuccess => 'Le credenziali sono valide.';

  @override
  String get settingsEchoLinkTestBadPassword => 'Password errata.';

  @override
  String get settingsEchoLinkTestValidation =>
      'Il tuo nominativo è in fase di convalida da parte di EchoLink. Può richiedere fino a un giorno.';

  @override
  String get settingsEchoLinkTestUnreachable =>
      'Impossibile raggiungere il server della directory EchoLink.';

  @override
  String get settingsEchoLinkTestInconclusive =>
      'Impossibile verificare le credenziali. Consulta il log di debug per la risposta del server.';

  @override
  String get settingsEchoLinkCreateAccount => 'Crea un nuovo account EchoLink';

  @override
  String get settingsEchoLinkCreateAccountHelp =>
      'Non hai ancora un account EchoLink? Registra il tuo nominativo con un indirizzo email e una nuova password.';

  @override
  String get settingsEchoLinkCreateAccountButton => 'Crea account';

  @override
  String get settingsEchoLinkCreateAccountTitle => 'Crea account EchoLink';

  @override
  String settingsEchoLinkCreateAccountIntro(String callsign) {
    return 'Registra $callsign con EchoLink. Dopo la creazione dell\'account devi convalidare il tuo nominativo fornendo la prova della licenza prima di poterti connettere.';
  }

  @override
  String get settingsEchoLinkEmail => 'Email';

  @override
  String get settingsEchoLinkEmailInvalid =>
      'Inserisci un indirizzo email valido.';

  @override
  String get settingsEchoLinkNewPassword => 'Nuova password';

  @override
  String get settingsEchoLinkConfirmPassword => 'Conferma password';

  @override
  String get settingsEchoLinkPasswordMismatch =>
      'Le password non corrispondono.';

  @override
  String get settingsEchoLinkCreating => 'Creazione dell\'account…';

  @override
  String get settingsEchoLinkAccountCreated =>
      'Account creato. Convalida il tuo nominativo per attivarlo.';

  @override
  String get settingsEchoLinkAccountAlreadyValid =>
      'Questo nominativo è già registrato e pronto all\'uso.';

  @override
  String get settingsEchoLinkAccountExists =>
      'Questo nominativo è già registrato con una password diversa. Inserisci la tua password esistente oppure reimpostala sul sito web di EchoLink.';

  @override
  String get settingsEchoLinkValidatePrompt =>
      'Il tuo account è stato creato. Ora devi convalidare il tuo nominativo fornendo la prova della licenza sul sito web di EchoLink. Aprirlo ora?';

  @override
  String get settingsEchoLinkValidateNow => 'Convalida ora';

  @override
  String get settingsServersIntro =>
      'Configura le impostazioni dei server locali.';

  @override
  String get settingsLocalServers => 'Server locali';

  @override
  String get settingsEnableWebServer => 'Abilita server web';

  @override
  String get settingsPort => 'Porta:';

  @override
  String get settingsEnableAgwpeServer => 'Abilita server AGWPE';

  @override
  String get settingsHomeAssistant => 'Home Assistant';

  @override
  String get settingsHomeAssistantDescription =>
      'Esponi ogni radio connessa a Home Assistant tramite MQTT per il monitoraggio e il controllo.';

  @override
  String get settingsEnableHomeAssistant => 'Abilita Home Assistant';

  @override
  String get settingsHomeAssistantMqttUrl => 'URL MQTT';

  @override
  String get settingsHomeAssistantUsername => 'Nome utente';

  @override
  String get settingsHomeAssistantPassword => 'Password';

  @override
  String get settingsHomeAssistantTestSuccess =>
      'Successo: connesso al broker.';

  @override
  String get settingsMapIntroGps =>
      'Configura le origini dati per il GPS e il tracciamento aerei.';

  @override
  String get settingsMapIntroNoGps =>
      'Configura le origini dati per il tracciamento aerei.';

  @override
  String get settingsGpsSerialPort => 'Porta seriale GPS';

  @override
  String get settingsSerialPort => 'Porta seriale';

  @override
  String get settingsBaudRate => 'Velocità in baud';

  @override
  String get settingsShareGpsLocation =>
      'Condividi la posizione del GPS seriale';

  @override
  String get settingsShareGpsLocationHelp =>
      'Invia la posizione del GPS seriale alla radio connessa affinché trasmetta la tua posizione attuale.';

  @override
  String get settingsAirplaneTracking => 'Tracciamento aerei (dump1090)';

  @override
  String get settingsServerUrl => 'URL del server';

  @override
  String get settingsTestConnection => 'Prova connessione';

  @override
  String get settingsTest => 'Prova';

  @override
  String get settingsTestTesting => 'Prova in corso...';

  @override
  String get settingsTestEmptyAddress =>
      'Non riuscita: indirizzo del server vuoto';

  @override
  String settingsTestFailedHttp(int code) {
    return 'Non riuscita: HTTP $code';
  }

  @override
  String settingsTestSuccess(int count) {
    return 'Successo, $count aerei trovati.';
  }

  @override
  String get settingsTestUnexpectedJson =>
      'Non riuscita: formato JSON imprevisto';

  @override
  String get settingsTestTimedOut => 'Non riuscita: richiesta scaduta';

  @override
  String get settingsTestInvalidJson =>
      'Non riuscita: risposta JSON non valida';

  @override
  String get settingsTestFailed => 'Non riuscita';

  @override
  String get settingsTestConnectionFailedTitle =>
      'Prova di connessione non riuscita';

  @override
  String get settingsLimitsIntro =>
      'Limita quanti elementi cronologici vengono conservati tra i riavvii dell\'app. Imposta su \"Illimitato\" per conservare tutto.';

  @override
  String get settingsHistoryLimits => 'Limiti della cronologia';

  @override
  String get settingsUnlimited => 'Illimitato';

  @override
  String get settingsLimitAprsMessages => 'Messaggi APRS';

  @override
  String get settingsLimitPackets => 'Pacchetti';

  @override
  String get settingsLimitSstvImages => 'Immagini SSTV';

  @override
  String get settingsLimitCommEvents => 'Eventi di comunicazione';

  @override
  String settingsLimitCurrent(int count) {
    return 'Attuale: $count';
  }

  @override
  String settingsLimitItemsDeleted(int count) {
    return '$count elementi verranno eliminati';
  }

  @override
  String get settingsDeleteHistoryTitle =>
      'Eliminare gli elementi della cronologia?';

  @override
  String settingsDeleteHistoryBody(String items) {
    return 'Questi limiti elimineranno definitivamente i più vecchi:\n\n$items\n\nQuesta operazione non può essere annullata.';
  }

  @override
  String settingsDeleteAprsMessages(int count) {
    return '$count messaggi APRS';
  }

  @override
  String settingsDeletePackets(int count) {
    return '$count pacchetti';
  }

  @override
  String settingsDeleteSstvImages(int count) {
    return '$count immagini SSTV';
  }

  @override
  String settingsDeleteCommEvents(int count) {
    return '$count eventi di comunicazione';
  }

  @override
  String get settingsAddAprsRoute => 'Aggiungi percorso APRS';

  @override
  String get settingsEditAprsRoute => 'Modifica percorso APRS';

  @override
  String get settingsName => 'Nome';

  @override
  String get settingsNameHint => 'es. Standard';

  @override
  String get settingsDuplicateRoute =>
      'Esiste già un percorso con questo nome.';

  @override
  String get settingsPath => 'Percorso';

  @override
  String get commonError => 'Errore';

  @override
  String get commonConnect => 'Connetti';

  @override
  String get commonDisconnect => 'Disconnetti';

  @override
  String get commonRename => 'Rinomina';

  @override
  String get commonRemove => 'Rimuovi';

  @override
  String connectScanError(String error) {
    return 'Ricerca dei dispositivi Bluetooth non riuscita: $error';
  }

  @override
  String get connectNoRadiosTitle => 'Nessuna radio trovata';

  @override
  String get connectNoRadiosBody =>
      'Non è stato trovato alcun dispositivo radio compatibile.\n\nAssicurati che la tua radio sia accesa e che il Bluetooth sia abilitato.';

  @override
  String get connectAllConnectedTitle => 'Tutte connesse';

  @override
  String get connectAllConnectedBody =>
      'Tutti i dispositivi radio rilevati sono già connessi.';

  @override
  String get connectBluetoothOffTitle => 'Bluetooth non disponibile';

  @override
  String get connectBluetoothOffBody =>
      'Il Bluetooth non è disponibile o è disattivato.\n\nAbilita il Bluetooth nelle impostazioni del dispositivo e riprova.';

  @override
  String get radioConnectionTitle => 'Connessione radio';

  @override
  String get radioConnectionEmpty =>
      'Nessuna radio compatibile trovata.\nAssicurati che la tua radio sia accesa e che il Bluetooth sia abilitato.';

  @override
  String get radioConnectionInternet => 'Internet';

  @override
  String get radioRenameTitle => 'Rinomina radio';

  @override
  String get radioRenamePrompt =>
      'Inserisci un nome personalizzato per questa radio:';

  @override
  String get radioRenameHint => 'Lascia vuoto per usare il nome predefinito';

  @override
  String get updateTitle => 'Aggiornamento software';

  @override
  String get updateChecking => 'Verifica degli aggiornamenti...';

  @override
  String updateVersionAvailable(String version) {
    return 'La versione $version è disponibile.';
  }

  @override
  String updateFreshDownload(String version) {
    return 'La versione $version richiede un nuovo download.';
  }

  @override
  String updateUnsupported(String version) {
    return 'Questa versione non è più supportata. Aggiorna alla $version.';
  }

  @override
  String get updateUpToDate => 'Stai usando la versione più recente.';

  @override
  String updateCheckFailed(String error) {
    return 'Verifica aggiornamenti non riuscita: $error';
  }

  @override
  String get updateDownloading => 'Download dell\'aggiornamento...';

  @override
  String get updateDownloaded =>
      'Aggiornamento scaricato. Pronto per l\'installazione.';

  @override
  String updateDownloadFailed(String error) {
    return 'Download non riuscito: $error';
  }

  @override
  String updateInstallFailed(String error) {
    return 'Installazione non riuscita: $error';
  }

  @override
  String updateDiagnosticsLog(String path) {
    return 'Se l\'aggiornamento non si completa, consulta il log diagnostico:\n$path';
  }

  @override
  String get updateInstallRestart => 'Installa e riavvia';

  @override
  String get updateCheckAgain => 'Controlla di nuovo';

  @override
  String get regionsTitle => 'Rinomina regioni';

  @override
  String regionsMaxChars(int count) {
    return 'I nomi delle regioni possono avere fino a $count caratteri.';
  }

  @override
  String regionLabel(int number) {
    return 'Regione $number';
  }

  @override
  String get gpsInfoTitle => 'Informazioni GPS';

  @override
  String get gpsSectionConnection => 'Connessione';

  @override
  String get gpsSectionFix => 'Fix GPS';

  @override
  String get gpsSectionPosition => 'Posizione';

  @override
  String get gpsSectionMotion => 'Movimento';

  @override
  String get gpsSectionTime => 'Ora';

  @override
  String get gpsPortStatus => 'Stato della porta';

  @override
  String get gpsNotConfigured => 'Non configurata';

  @override
  String get gpsOpenReceiving => 'Aperta — Ricezione dati';

  @override
  String get gpsPermDeniedLinux =>
      'Autorizzazione negata — aggiungi il tuo utente al gruppo \'dialout\' (sudo usermod -aG dialout \$USER), poi esci e accedi di nuovo.';

  @override
  String get gpsPermDenied =>
      'Autorizzazione negata — l\'app non può accedere a questa porta.';

  @override
  String get gpsPortError =>
      'Errore della porta — impossibile aprire la porta seriale.';

  @override
  String get gpsFix => 'Fix';

  @override
  String get gpsFixQuality => 'Qualità del fix';

  @override
  String get gpsSatellites => 'Satelliti';

  @override
  String get gpsNoData => 'Nessun dato';

  @override
  String get gpsActive => 'Attivo';

  @override
  String get gpsNoFix => 'Nessun fix';

  @override
  String get gpsQualGps => 'Fix GPS (1)';

  @override
  String get gpsQualDgps => 'Fix DGPS (2)';

  @override
  String get gpsQualInvalid => 'Non valido (0)';

  @override
  String gpsQualUnknown(int quality) {
    return '$quality (sconosciuto)';
  }

  @override
  String get gpsLatitude => 'Latitudine';

  @override
  String get gpsLatitudeDms => 'Latitudine (DMS)';

  @override
  String get gpsLongitude => 'Longitudine';

  @override
  String get gpsLongitudeDms => 'Longitudine (DMS)';

  @override
  String get gpsAltitude => 'Altitudine';

  @override
  String get gpsSpeed => 'Velocità';

  @override
  String get gpsHeading => 'Direzione';

  @override
  String get gpsTimeUtc => 'Ora GPS (UTC)';

  @override
  String get gpsDate => 'Data GPS';

  @override
  String get gpsLastUpdate => 'Ultimo aggiornamento';

  @override
  String get trustedDevicesTitle => 'Dispositivi attendibili';

  @override
  String get trustedRemoveTitle => 'Rimuovi dispositivo attendibile';

  @override
  String trustedRemoveMessage(String name) {
    return 'Rimuovere \"$name\" dall\'elenco dei dispositivi attendibili della radio?';
  }

  @override
  String get trustedNoDevices => 'Nessun dispositivo attendibile trovato.';

  @override
  String get pfConfigTitle => 'Configura pulsanti';

  @override
  String get pfSaveToRadio => 'Salva sulla radio';

  @override
  String get pfNoRadio => 'Nessuna radio connessa.';

  @override
  String get pfNoButtons =>
      'Questa radio non ha segnalato pulsanti programmabili.';

  @override
  String get pfIntro =>
      'Scegli cosa fa ciascun pulsante programmabile per ogni tipo di pressione. Le modifiche vengono scritte sulla radio quando salvi.';

  @override
  String pfButtonLabel(int number) {
    return 'Pulsante $number';
  }

  @override
  String get pfActionShort => 'Pressione breve';

  @override
  String get pfActionLong => 'Pressione lunga';

  @override
  String get pfActionVeryLong => 'Pressione molto lunga';

  @override
  String get pfActionVeryVeryLong => 'Pressione lunghissima';

  @override
  String get pfActionDouble => 'Doppia pressione';

  @override
  String get pfActionTriple => 'Tripla pressione';

  @override
  String get pfActionRepeat => 'Ripetizione';

  @override
  String get pfActionPressDown => 'Premuto';

  @override
  String get pfActionRelease => 'Rilascio';

  @override
  String get pfActionLongRelease => 'Rilascio lungo';

  @override
  String get pfActionVeryLongRelease => 'Rilascio molto lungo';

  @override
  String get pfActionVeryVeryLongRelease => 'Rilascio lunghissimo';

  @override
  String pfActionUnknown(int action) {
    return 'Azione $action';
  }

  @override
  String get pfEffectDisabled => 'Disabilitato';

  @override
  String get pfEffectAlarm => 'Allarme';

  @override
  String get pfEffectAlarmAndMute => 'Allarme e silenzia';

  @override
  String get pfEffectToggleOffline => 'Attiva/disattiva offline';

  @override
  String get pfEffectToggleRadioTx => 'Attiva/disattiva TX radio';

  @override
  String get pfEffectToggleTxPower => 'Attiva/disattiva potenza TX';

  @override
  String get pfEffectToggleFm => 'Attiva/disattiva radio FM';

  @override
  String get pfEffectPrevChannel => 'Canale precedente';

  @override
  String get pfEffectNextChannel => 'Canale successivo';

  @override
  String get pfEffectTCall => 'T-Call (1750 Hz)';

  @override
  String get pfEffectPrevRegion => 'Regione precedente';

  @override
  String get pfEffectNextRegion => 'Regione successiva';

  @override
  String get pfEffectToggleChScan => 'Attiva/disattiva scansione canali';

  @override
  String get pfEffectMainPtt => 'PTT principale';

  @override
  String get pfEffectSubPtt => 'PTT secondario';

  @override
  String get pfEffectToggleMonitor => 'Attiva/disattiva monitor';

  @override
  String get pfEffectBtPairing => 'Associazione Bluetooth';

  @override
  String get pfEffectToggleDoubleCh => 'Attiva/disattiva doppio canale';

  @override
  String get pfEffectToggleAbCh => 'Attiva/disattiva canale A/B';

  @override
  String get pfEffectSendLocation => 'Invia posizione';

  @override
  String get pfEffectOneClickLink => 'Collegamento con un clic';

  @override
  String get pfEffectVolDown => 'Abbassa volume';

  @override
  String get pfEffectVolUp => 'Alza volume';

  @override
  String get pfEffectToggleMute => 'Attiva/disattiva silenzia';

  @override
  String pfEffectUnknown(int effect) {
    return 'Sconosciuto ($effect)';
  }

  @override
  String get importChannelsTitle => 'Importa canali';

  @override
  String importChannelsTitleWith(String name) {
    return 'Importa canali — $name';
  }

  @override
  String get importIntro =>
      'Trascina un canale dalla sinistra su uno slot della radio, oppure seleziona un canale e uno slot e premi la freccia. Tocca l\'icona info per i dettagli. I canali vengono scritti sulla radio solo quando premi OK.';

  @override
  String importOkCount(int count) {
    return 'OK ($count)';
  }

  @override
  String importImportedHeader(int count) {
    return 'Importati ($count)';
  }

  @override
  String get importNoChannels => 'Nessun canale importato.';

  @override
  String importRadioChannelsHeader(int count) {
    return 'Canali radio ($count)';
  }

  @override
  String get importNoRadioChannels => 'Nessun canale radio.';

  @override
  String get importMoveTooltip =>
      'Sposta il canale selezionato nello slot selezionato';

  @override
  String get importCopyAllTooltip =>
      'Copia tutti i canali importati negli slot della radio 1:1';

  @override
  String importChannelShort(int number) {
    return 'Can $number';
  }

  @override
  String get importClearTooltip => 'Annulla l\'assegnazione in sospeso';

  @override
  String get importChannelDetails => 'Dettagli canale';

  @override
  String get riTitle => 'Informazioni radio';

  @override
  String get riNoRadioConnected => 'Nessuna radio connessa';

  @override
  String get riConnectPrompt =>
      'Connetti una radio per visualizzarne le informazioni.';

  @override
  String riRadioFallback(int id) {
    return 'Radio $id';
  }

  @override
  String get riSectionRadio => 'Radio';

  @override
  String get riSectionDeviceInfo => 'Informazioni dispositivo';

  @override
  String get riSectionDeviceStatus => 'Stato dispositivo';

  @override
  String get riSectionDeviceSettings => 'Impostazioni dispositivo';

  @override
  String get riSectionBss => 'Impostazioni BSS';

  @override
  String get riSectionPosition => 'Posizione';

  @override
  String get riName => 'Nome';

  @override
  String get riStatus => 'Stato';

  @override
  String get riSettingsLabel => 'Impostazioni';

  @override
  String get riNoData => 'Nessun dato';

  @override
  String get riNoGpsData => 'Nessun dato GPS';

  @override
  String get riNoGpsLock => 'Nessun aggancio GPS';

  @override
  String get riGpsLocked => 'GPS agganciato';

  @override
  String get riTrue => 'Vero';

  @override
  String get riFalse => 'Falso';

  @override
  String get riPresent => 'Presente';

  @override
  String get riNotPresent => 'Non presente';

  @override
  String get riSupported => 'Supportato';

  @override
  String get riNotSupported => 'Non supportato';

  @override
  String get riCurrent => 'Attuale';

  @override
  String get riOff => 'Spento';

  @override
  String riChannelValue(int number) {
    return 'Canale $number';
  }

  @override
  String riSeconds(int count) {
    return '$count secondo/i';
  }

  @override
  String riMeters(String value) {
    return '$value metri';
  }

  @override
  String riDegrees(String value) {
    return '$value gradi';
  }

  @override
  String get riProductId => 'ID prodotto';

  @override
  String get riVendorId => 'ID fornitore';

  @override
  String get riDmrSupport => 'Supporto DMR';

  @override
  String get riGmrsSupport => 'Supporto GMRS';

  @override
  String get riHardwareSpeaker => 'Altoparlante hardware';

  @override
  String get riHardwareVersion => 'Versione hardware';

  @override
  String get riSoftwareVersion => 'Versione software';

  @override
  String get riRegionCount => 'Numero di regioni';

  @override
  String get riMediumPower => 'Potenza media';

  @override
  String get riChannelCount => 'Numero di canali';

  @override
  String get riNoaa => 'NOAA';

  @override
  String get riWeather => 'Meteo';

  @override
  String riWeatherChannel(int number) {
    return 'Meteo $number';
  }

  @override
  String get riBroadcastFm => 'FM broadcast';

  @override
  String get riRadioLabel => 'Radio';

  @override
  String get riVfo => 'VFO';

  @override
  String get riFreqRangeCount => 'Numero di gamme di frequenza';

  @override
  String get riPowerOn => 'Acceso';

  @override
  String get riInTx => 'In TX';

  @override
  String get riInRx => 'In RX';

  @override
  String get riDoubleChannelLabel => 'Doppio canale';

  @override
  String get riScanning => 'Scansione';

  @override
  String get riCurrentChannelId => 'ID canale corrente';

  @override
  String get riGpsLockedLabel => 'GPS agganciato';

  @override
  String get riHfpConnected => 'HFP connesso';

  @override
  String get riAocConnected => 'AOC connesso';

  @override
  String get riRssi => 'RSSI';

  @override
  String get riCurrentRegion => 'Regione corrente';

  @override
  String get riAccuracy => 'Precisione';

  @override
  String get riReceivedTime => 'Ora di ricezione';

  @override
  String get riGpsTimeLocal => 'Ora GPS locale';

  @override
  String get riGpsTimeUtcLabel => 'Ora GPS UTC';

  @override
  String get tabDetach => 'Stacca...';

  @override
  String get tabClear => 'Cancella';

  @override
  String get tabSaveToFile => 'Salva su file...';

  @override
  String get commonNoRadioConnected => 'Nessuna radio connessa.';

  @override
  String errorOpeningFileDialog(String error) {
    return 'Errore durante l\'apertura della finestra dei file: $error';
  }

  @override
  String errorSavingFile(String error) {
    return 'Errore durante il salvataggio del file: $error';
  }

  @override
  String get debugSaveTitle => 'Salva log di debug';

  @override
  String debugLogSavedTo(String path) {
    return 'Log di debug salvato in $path';
  }

  @override
  String get debugShowBluetoothFrames => 'Mostra frame Bluetooth';

  @override
  String get debugLoopbackMode => 'Modalità loopback';

  @override
  String get debugQueryDeviceNames => 'Interroga i nomi dei dispositivi';

  @override
  String get debugRawCommand => 'Comando grezzo...';

  @override
  String get debugAutoScroll => 'Scorrimento automatico';

  @override
  String get debugFirmwareUpdate => 'Aggiornamento firmware...';

  @override
  String get debugShowBuiltInMenus => 'Mostra menu integrati';

  @override
  String get packetsCopyHex => 'Copia pacchetto HEX';

  @override
  String get packetsHexCopied => 'Pacchetto HEX copiato negli appunti';

  @override
  String get packetsCopyPackets => 'Copia pacchetti';

  @override
  String packetsCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pacchetti copiati negli appunti',
      one: '1 pacchetto copiato negli appunti',
    );
    return '$_temp0';
  }

  @override
  String get packetsSaveTitle => 'Salva cattura pacchetti';

  @override
  String get packetsSaved => 'Cattura pacchetti salvata';

  @override
  String packetsSavedTo(String path) {
    return 'Cattura pacchetti salvata in $path';
  }

  @override
  String get packetsShowDecode => 'Mostra decodifica pacchetti';

  @override
  String get packetsEmpty => 'Nessun pacchetto catturato';

  @override
  String get packetsColTime => 'Ora';

  @override
  String get packetsColChannel => 'Canale';

  @override
  String get packetsColRadio => 'Radio';

  @override
  String get packetsColData => 'Dati';

  @override
  String get commonAdd => 'Aggiungi';

  @override
  String get commonEdit => 'Modifica';

  @override
  String get commonEditEllipsis => 'Modifica...';

  @override
  String get commonAddEllipsis => 'Aggiungi...';

  @override
  String get commonExportEllipsis => 'Esporta...';

  @override
  String get commonImportEllipsis => 'Importa...';

  @override
  String get contactsTypeGeneric => 'Stazioni generiche';

  @override
  String get contactsTypeAprs => 'Stazioni APRS';

  @override
  String get contactsTypeTerminal => 'Stazioni terminale';

  @override
  String get contactsTypeBbs => 'Stazioni BBS';

  @override
  String get contactsTypeWinlink => 'Stazioni Winlink';

  @override
  String get contactsTypeTorrent => 'Stazioni Torrent';

  @override
  String get contactsTypeAgwpe => 'Stazioni AGWPE';

  @override
  String get contactsTypeSms => 'Contatti SMS / telefono';

  @override
  String get contactsTypeEmail => 'Contatti email';

  @override
  String get contactsExists =>
      'Esiste già una stazione con questo nominativo e tipo';

  @override
  String get contactsRemovePrompt => 'Rimuovere la stazione selezionata?';

  @override
  String get contactsNoExport => 'Non ci sono stazioni da esportare';

  @override
  String get contactsExportTitle => 'Esporta stazioni';

  @override
  String get contactsImportTitle => 'Importa stazioni';

  @override
  String contactsExported(int count) {
    return 'Esportate $count stazioni';
  }

  @override
  String contactsImported(int count) {
    return 'Importate $count stazioni';
  }

  @override
  String get contactsUnableOpen => 'Impossibile aprire la rubrica';

  @override
  String get contactsInvalid => 'Rubrica non valida';

  @override
  String get contactsColCallsign => 'Nominativo';

  @override
  String get contactsColId => 'ID';

  @override
  String get contactsColName => 'Nome';

  @override
  String get contactsColDescription => 'Descrizione';

  @override
  String terminalHeaderWith(String callsign) {
    return 'Terminale - $callsign';
  }

  @override
  String get terminalNoRadio => 'Nessuna radio disponibile per la connessione.';

  @override
  String get terminalShowCallsign => 'Mostra nominativo';

  @override
  String get terminalWordWrap => 'A capo automatico';

  @override
  String get terminalWaitForConnection => 'Attendi connessione...';

  @override
  String get terminalWaitingForConnection => 'In attesa di connessione...';

  @override
  String terminalConnectedFrom(String callsign) {
    return 'Connesso da $callsign';
  }

  @override
  String get terminalSend => 'Invia';

  @override
  String terminalConnectedTo(String callsign) {
    return 'Connesso a $callsign';
  }

  @override
  String terminalConnectingTo(String callsign) {
    return 'Connessione a $callsign...';
  }

  @override
  String get terminalInvalidCallsignDest =>
      'Nominativo/destinazione non valido';

  @override
  String get terminalInvalidCallsign => 'Nominativo non valido';

  @override
  String get terminalNotConnected => 'Non connesso';

  @override
  String terminalError(String error) {
    return 'Errore: $error';
  }

  @override
  String get terminalBrotli =>
      'Ricevuto un pacchetto compresso con Brotli (non supportato)';

  @override
  String get terminalSendFile => 'Invia file...';

  @override
  String get terminalSaveFileTitle => 'Salva file ricevuto';

  @override
  String get terminalCancelTransfer => 'Annulla trasferimento';

  @override
  String get terminalTransferInProgress =>
      'Un trasferimento di file è già in corso';

  @override
  String terminalSendingFile(String filename) {
    return 'Invio di $filename...';
  }

  @override
  String terminalReceivingFile(String filename) {
    return 'Ricezione di $filename...';
  }

  @override
  String terminalFileSent(String filename) {
    return 'File inviato: $filename';
  }

  @override
  String terminalFileReceived(String filename, int bytes) {
    return 'File ricevuto: $filename ($bytes byte)';
  }

  @override
  String terminalFileTransferError(String message) {
    return 'Errore nel trasferimento del file: $message';
  }

  @override
  String get audioSectionDevices => 'Dispositivi';

  @override
  String get audioRefreshDevices => 'Aggiorna l\'elenco dei dispositivi';

  @override
  String get audioOutput => 'Uscita';

  @override
  String get audioInput => 'Ingresso';

  @override
  String get audioVolume => 'Volume';

  @override
  String get audioSquelch => 'Squelch';

  @override
  String get audioSectionComputer => 'Applicazione';

  @override
  String get audioApplication => 'Volume';

  @override
  String get audioMaster => 'Master';

  @override
  String get audioMicGain => 'Guadagno microfono';

  @override
  String get audioMicNotAvailable =>
      'L\'acquisizione dal microfono non è disponibile su questa piattaforma.';

  @override
  String get audioMicNotSupported =>
      'L\'acquisizione dal microfono non è supportata qui.';

  @override
  String get audioSpectRadio => 'Spettrografo radio';

  @override
  String get audioSpectMic => 'Spettrografo microfono';

  @override
  String get audioSpectNone => 'Spettrografo';

  @override
  String get audioSpectMenuNone => 'Nessuno spettrografo';

  @override
  String get audioDartQuality => 'Qualità di ricezione DART';

  @override
  String get audioDartSignalAnalysis => 'Analisi del segnale DART';

  @override
  String get audioDefault => 'Predefinito';

  @override
  String get audioMute => 'Silenzia';

  @override
  String get audioUnmute => 'Riattiva audio';

  @override
  String get audioEnable => 'Abilita';

  @override
  String get audioDisable => 'Disabilita';

  @override
  String get audioNa => 'N/D';

  @override
  String get bbsHeaderActive => 'BBS - Attivo';

  @override
  String get bbsActivate => 'Attiva';

  @override
  String get bbsDeactivate => 'Disattiva';

  @override
  String get bbsViewTraffic => 'Visualizza traffico';

  @override
  String get bbsClearTraffic => 'Cancella traffico';

  @override
  String get bbsClearStats => 'Cancella statistiche';

  @override
  String get bbsColCallSign => 'Nominativo';

  @override
  String get bbsColLastSeen => 'Visto l\'ultima volta';

  @override
  String get bbsColStats => 'Statistiche';

  @override
  String get bbsTraffic => 'Traffico';

  @override
  String get bbsJustNow => 'Proprio ora';

  @override
  String bbsMinAgo(int n) {
    return '$n min fa';
  }

  @override
  String bbsHoursAgo(int n) {
    return '$n h fa';
  }

  @override
  String bbsDaysAgo(int n) {
    return '$n g fa';
  }

  @override
  String get commonDelete => 'Elimina';

  @override
  String get torrentAddFile => 'Aggiungi file';

  @override
  String get torrentShowDetails => 'Mostra dettagli';

  @override
  String get torrentFileSaved => 'File salvato.';

  @override
  String get torrentFileDataUnavailable =>
      'Errore nel salvataggio del file: dati del file non disponibili';

  @override
  String get torrentUnknownError => 'Errore sconosciuto';

  @override
  String get torrentSaveTitle => 'Salva file torrent';

  @override
  String get torrentNoRadios =>
      'Nessuna radio connessa. Connetti prima una radio.';

  @override
  String get torrentMultiRadio =>
      'La modalità torrent multi-radio non è ancora supportata.';

  @override
  String get torrentDropSingle => 'Trascina un solo file.';

  @override
  String get torrentDeletePrompt => 'Eliminare il file torrent selezionato?';

  @override
  String get torrentPause => 'Pausa';

  @override
  String get torrentShare => 'Condividi';

  @override
  String get torrentRequest => 'Richiedi';

  @override
  String get torrentSaveAs => 'Salva con nome...';

  @override
  String get torrentDropToShare => 'Trascina un file per condividerlo';

  @override
  String get torrentNoFiles =>
      'Nessun file torrent. Aggiungi o trascina un file per condividerlo.';

  @override
  String get torrentUnknownSource => 'Sconosciuta';

  @override
  String get torrentColFile => 'File';

  @override
  String get torrentColMode => 'Modalità';

  @override
  String get torrentDetailFileName => 'Nome file';

  @override
  String get torrentDetailSource => 'Origine';

  @override
  String get torrentDetailFileSize => 'Dimensione file';

  @override
  String torrentBytes(int count) {
    return '$count byte';
  }

  @override
  String get torrentDetailCompression => 'Compressione';

  @override
  String get torrentDetailBlocks => 'Blocchi';

  @override
  String get torrentDetailsTitle => 'Dettagli torrent';

  @override
  String get torrentSelectPrompt =>
      'Seleziona un torrent per visualizzarne i dettagli';

  @override
  String get torrentModePaused => 'In pausa';

  @override
  String get torrentModeSharing => 'In condivisione';

  @override
  String get torrentModeRequesting => 'In richiesta';

  @override
  String get torrentModeError => 'Errore';

  @override
  String get torrentCompUnknown => 'Sconosciuta';

  @override
  String get mailInbox => 'Posta in arrivo';

  @override
  String get mailOutbox => 'Posta in uscita';

  @override
  String get mailDraft => 'Bozza';

  @override
  String get mailSent => 'Inviata';

  @override
  String get mailArchive => 'Archivio';

  @override
  String get mailTrash => 'Cestino';

  @override
  String get mailInternet => 'Internet';

  @override
  String get mailDeleteTitle => 'Elimina posta';

  @override
  String get mailMoveToTrashTitle => 'Sposta nel cestino';

  @override
  String get mailDeletePermanent =>
      'Eliminare definitivamente la posta selezionata? Questa operazione non può essere annullata.';

  @override
  String get mailMoveToTrashPrompt =>
      'Spostare la posta selezionata nel cestino?';

  @override
  String get mailMove => 'Sposta';

  @override
  String get mailOpen => 'Apri';

  @override
  String get mailReply => 'Rispondi';

  @override
  String get mailReplyAll => 'Rispondi a tutti';

  @override
  String get mailForward => 'Inoltra';

  @override
  String get mailShowPreview => 'Mostra anteprima';

  @override
  String get mailBackup => 'Backup della posta...';

  @override
  String get mailRestore => 'Ripristina posta...';

  @override
  String get mailShowTraffic => 'Mostra traffico...';

  @override
  String mailBackupFailed(String error) {
    return 'Backup non riuscito: $error';
  }

  @override
  String get mailBackupTitle => 'Backup della posta';

  @override
  String get mailBackupSuccess => 'Backup completato con successo.';

  @override
  String get mailRestoreTitle => 'Ripristina posta';

  @override
  String get mailRestoreUnableOpen => 'Impossibile aprire il file di backup';

  @override
  String mailRestoreFailed(String error) {
    return 'Ripristino non riuscito: $error';
  }

  @override
  String get mailNew => 'Nuova';

  @override
  String get mailNewMail => 'Nuova posta';

  @override
  String get mailColTime => 'Ora';

  @override
  String get mailColTo => 'A';

  @override
  String get mailColFrom => 'Da';

  @override
  String get mailColSubject => 'Oggetto';

  @override
  String get mailSelectPreview => 'Seleziona un messaggio per l\'anteprima';

  @override
  String get commonUnknown => 'Sconosciuto';

  @override
  String get mapOfflineMode => 'Modalità offline';

  @override
  String get mapOfflineMap => 'Mappa offline';

  @override
  String get mapCacheArea => 'Memorizza area...';

  @override
  String get mapCenterGps => 'Centra sul GPS';

  @override
  String get mapShowTracks => 'Mostra tracce';

  @override
  String get mapShowMarkers => 'Mostra indicatori';

  @override
  String get mapShowAirplanes => 'Mostra aerei';

  @override
  String get mapLargeMarkers => 'Indicatori grandi';

  @override
  String get mapShowAprsSymbols => 'Mostra simboli APRS';

  @override
  String get mapShowContactsOnly => 'Mostra solo i contatti';

  @override
  String get mapFilterAll => 'Tutti';

  @override
  String get mapFilterLast30 => 'Ultimi 30 minuti';

  @override
  String get mapFilterLastHour => 'Ultima ora';

  @override
  String get mapFilterLast6 => 'Ultime 6 ore';

  @override
  String get mapFilterLast12 => 'Ultime 12 ore';

  @override
  String get mapFilterLast24 => 'Ultime 24 ore';

  @override
  String get mapCacheTitle => 'Memorizza area della mappa';

  @override
  String mapCachePrompt(int count, int minZoom, int maxZoom) {
    return 'Scaricare $count tile per i livelli di zoom $minZoom–$maxZoom?\n\nQuesto memorizzerà l\'area selezionata per l\'uso offline.';
  }

  @override
  String get mapDownloadingTitle => 'Download dei tile';

  @override
  String mapTilesProgress(int done, int total) {
    return '$done / $total tile';
  }

  @override
  String get mapDragToSelect =>
      'Trascina per selezionare l\'area da memorizzare';

  @override
  String get mapMeasureTool => 'Misura distanza';

  @override
  String get mapStationMessage => 'Invia messaggio';

  @override
  String get mapStationCenter => 'Zoom sulla stazione';

  @override
  String get mapStationAddContact => 'Aggiungi contatto';

  @override
  String get mapStationsHere => 'Stazioni qui';

  @override
  String get aprsNoChannel => 'Nessuna radio con un canale APRS è disponibile';

  @override
  String get aprsNoLoadedChannels =>
      'Nessuna radio con canali caricati è disponibile';

  @override
  String get aprsDetails => 'Dettagli...';

  @override
  String get aprsShowLocation => 'Mostra posizione...';

  @override
  String get aprsSetReceiver => 'Imposta come ricevitore';

  @override
  String get aprsCopyMessage => 'Copia messaggio';

  @override
  String get aprsCopyCallsign => 'Copia nominativo';

  @override
  String get callsignLookup => 'Cerca...';

  @override
  String get aprsCopyChannel => 'Copia canale';

  @override
  String get aprsClearTitle => 'Cancella messaggi APRS';

  @override
  String get aprsClearPrompt =>
      'Cancellare tutti i messaggi APRS? Questo rimuove anche tutti gli indicatori APRS dalla mappa. Questa operazione non può essere annullata.';

  @override
  String get aprsClearContactPrompt =>
      'Cancellare tutti i messaggi con questo contatto? Questa operazione non può essere annullata.';

  @override
  String get aprsShowAll => 'Mostra telemetria';

  @override
  String get aprsShowAprsIs => 'Mostra traffico internet';

  @override
  String get aprsMessengerMode => 'Modalità messenger';

  @override
  String get aprsAllMessages => 'Tutti i messaggi';

  @override
  String get aprsAddContact => 'Aggiungi contatto...';

  @override
  String get aprsNoConversations => 'Nessuna conversazione';

  @override
  String get aprsSelectConversation => 'Seleziona una conversazione';

  @override
  String get aprsSendSms => 'Invia messaggio SMS...';

  @override
  String get aprsWeatherReport => 'Bollettino meteo...';

  @override
  String get aprsBeaconSettingsMenu => 'Impostazioni beacon...';

  @override
  String get aprsSoftwareBeaconMenu => 'Beacon software...';

  @override
  String get softwareBeaconTitle => 'Beacon software';

  @override
  String get softwareBeaconIntro =>
      'Il beacon software trasmette periodicamente la tua posizione o il tuo stato APRS sul canale \"APRS\" utilizzando il tuo nominativo. Viene inviato tramite Internet (APRS-IS) quando configurato e anche tramite la radio selezionata, quando ne viene scelta una.';

  @override
  String get softwareBeaconSymbol => 'Simbolo APRS';

  @override
  String get softwareBeaconMessage => 'Messaggio';

  @override
  String get softwareBeaconMessageHint => 'Testo di stato facoltativo';

  @override
  String get softwareBeaconIncludeLocation => 'Includi la mia posizione';

  @override
  String get softwareBeaconRadio => 'Radio preferita';

  @override
  String get softwareBeaconInternetOnly => 'Solo Internet';

  @override
  String get softwareBeaconNoCallsign =>
      'Configura il tuo nominativo nelle Impostazioni prima di usare il beacon software.';

  @override
  String get aprsDigipeaterMenu => 'Digipeater...';

  @override
  String get digipeaterTitle => 'Digipeater APRS';

  @override
  String get digipeaterIntro =>
      'Il digipeater ritrasmette i pacchetti APRS idonei che ascolta sul canale APRS. Quando è abilitato, la radio selezionata è bloccata sul canale APRS.';

  @override
  String get digipeaterEnable => 'Abilita digipeater';

  @override
  String get digipeaterRadio => 'Radio';

  @override
  String get digipeaterHandleWideN => 'Ripeti i pacchetti WIDEn-N';

  @override
  String get digipeaterFillIn => 'Solo fill-in (WIDE1-1)';

  @override
  String get digipeaterSubstituteCall =>
      'Inserisci il mio nominativo nel percorso';

  @override
  String get digipeaterMaxHops => 'Salti massimi';

  @override
  String get digipeaterDedupSeconds => 'Finestra di deduplicazione (s)';

  @override
  String get digipeaterAliases => 'Alias personalizzati';

  @override
  String get digipeaterAliasesHint => 'es. RELAY, WIDE1-1';

  @override
  String get digipeaterAliasesInvalid =>
      'Uno o più alias non sono nominativi validi.';

  @override
  String get digipeaterNoCallsign =>
      'Configura il tuo nominativo nelle impostazioni prima di usare il digipeater.';

  @override
  String get digipeaterNoAprsChannel =>
      'La radio selezionata non ha un canale APRS. Configurane uno per abilitare il digipeater.';

  @override
  String get aprsDropShare => 'Trascina per condividere questo canale';

  @override
  String get aprsBeaconWarning =>
      'Il beacon è abilitato sul canale corrente, cosa non consigliata.';

  @override
  String aprsBeaconActive(String interval) {
    return 'Il beacon radio è attivo, intervallo: $interval.';
  }

  @override
  String get aprsBeaconSettings => 'Impostazioni beacon';

  @override
  String aprsIntervalSeconds(int count) {
    return '$count secondi';
  }

  @override
  String get aprsIntervalMinute => '1 minuto';

  @override
  String aprsIntervalMinutes(int count) {
    return '$count minuti';
  }

  @override
  String get aprsMissingChannel =>
      'Nessun canale \"APRS\" è configurato sulla radio connessa. Aggiungi un canale APRS per inviare e ricevere messaggi APRS.';

  @override
  String aprsMissingRoute(String route) {
    return 'Il percorso APRS \"$route\" per questo contatto non esiste più. I messaggi verranno inviati senza percorso digipeater finché non aggiorni il contatto.';
  }

  @override
  String get aprsSetup => 'Configura';

  @override
  String get aprsTypeMessage => 'Scrivi un messaggio...';

  @override
  String get commonYes => 'Sì';

  @override
  String get commonNo => 'No';

  @override
  String get commonSend => 'Invia';

  @override
  String commonSavedTo(String path) {
    return 'Salvato in $path';
  }

  @override
  String commsFailedLoadImage(String error) {
    return 'Impossibile caricare l\'immagine: $error';
  }

  @override
  String commsFailedSaveImage(String error) {
    return 'Impossibile salvare l\'immagine: $error';
  }

  @override
  String commsFailedEncodeSstv(String error) {
    return 'Impossibile codificare l\'audio SSTV: $error';
  }

  @override
  String commsFailedLoadAudio(String error) {
    return 'Impossibile caricare l\'audio: $error';
  }

  @override
  String get commsUnsupportedWav => 'File WAV non supportato o vuoto.';

  @override
  String get commsSstvWebUnavailable =>
      'Il salvataggio/trasmissione di immagini SSTV non è disponibile sul web.';

  @override
  String get commsNoRadioVoice =>
      'Nessuna radio è connessa per la trasmissione vocale.';

  @override
  String get commsSelectImageTitle => 'Seleziona immagine per SSTV';

  @override
  String get commsSelectWavTitle => 'Seleziona audio WAV';

  @override
  String get commsRecordingWebUnavailable =>
      'La riproduzione di registrazioni da file non è disponibile sul web.';

  @override
  String get commsFileNoLongerExists => 'Il file non esiste più.';

  @override
  String get commsSaveAsTitle => 'Salva con nome';

  @override
  String get commsTransmitDisabledAprs =>
      'La trasmissione è disabilitata mentre il VFO A è impostato sul canale APRS.';

  @override
  String get commsWaitTransmission =>
      'Attendi il completamento della trasmissione corrente.';

  @override
  String get commsConnectRadioChat =>
      'Connetti una radio prima di inviare un messaggio in chat.';

  @override
  String get commsEnableAudioMode =>
      'Abilita l\'audio (il pulsante Abilita) prima di inviare in questa modalità.';

  @override
  String get commsMicNotSupported =>
      'L\'acquisizione dal microfono non è supportata su questa piattaforma.';

  @override
  String get commsConnectRadioPtt =>
      'Connetti una radio prima di usare il push-to-talk.';

  @override
  String get commsEnableAudioPtt =>
      'Abilita l\'audio (il pulsante Abilita) prima di usare il push-to-talk.';

  @override
  String get commsSwitchChatShare =>
      'Passa alla modalità Chat per condividere un canale.';

  @override
  String get commsModePtt => 'PTT';

  @override
  String get commsModeChat => 'Chat';

  @override
  String get commsModeSpeak => 'Parla';

  @override
  String get commsModeMorse => 'Morse';

  @override
  String get commsModeDtmf => 'DTMF';

  @override
  String get commsRecordAudio => 'Registra audio';

  @override
  String get commsSendImage => 'Invia immagine...';

  @override
  String get commsSendAudio => 'Invia audio...';

  @override
  String get commsPttReleaseSettings => 'Impostazioni rilascio PTT...';

  @override
  String get commsClearHistory => 'Cancella cronologia';

  @override
  String get commsShowImage => 'Mostra immagine...';

  @override
  String get commsPlayRecording => 'Riproduci registrazione...';

  @override
  String get commsSaveAsMenu => 'Salva con nome...';

  @override
  String get commsShowLocation => 'Mostra posizione';

  @override
  String get commsClearHistoryPrompt =>
      'Vuoi davvero cancellare la cronologia vocale?';

  @override
  String get commsAudioMuted => 'L\'audio è silenziato.';

  @override
  String get commsUnmute => 'Riattiva audio';

  @override
  String get commsDeemphasisWarning =>
      'La de-enfasi del canale VFO A è attiva e degraderà i trasferimenti di dati.';

  @override
  String get commsPttTransmitting => 'Trasmissione in corso';

  @override
  String get commsPttHold => 'PTT - Tieni premuto per trasmettere';

  @override
  String get commsDtmfHint => 'Inserisci cifre DTMF (0-9, *, #)...';

  @override
  String get commsChannelInfo => 'Informazioni canale';

  @override
  String get commsAllStarNodeTitle => 'Nodo AllStarLink';

  @override
  String get commsAllStarNodeStart => 'Avvia nodo';

  @override
  String get commsAllStarNodeNotConfigured =>
      'Imposta il numero del nodo AllStarLink e la password in Impostazioni → AllStarLink prima di ospitare un nodo.';

  @override
  String commsAllStarNodeControlOpNotice(String node) {
    return 'Ospitare il nodo AllStarLink $node? Questa radio instraderà tutto l\'audio della rete verso l\'RF. Sei l\'operatore di controllo e sei responsabile di tutte le trasmissioni.';
  }

  @override
  String commsAllStarNodeHosting(int count) {
    return 'Hosting del nodo AllStarLink ($count collegati)';
  }

  @override
  String get mailComposeNewTitle => 'Nuovo messaggio';

  @override
  String get mailComposeEditTitle => 'Modifica messaggio';

  @override
  String get mailDiscardChanges => 'Ignorare le modifiche a questo messaggio?';

  @override
  String get mailDiscardMessage => 'Ignorare questo messaggio?';

  @override
  String get mailDiscard => 'Ignora';

  @override
  String get mailAddCc => 'Aggiungi Cc';

  @override
  String get mailCc => 'Cc';

  @override
  String get mailRemoveCc => 'Rimuovi Cc';

  @override
  String get mailAddContact => 'Aggiungi dai contatti';

  @override
  String get mailContactsTitle => 'Contatti';

  @override
  String get mailNoContacts => 'Nessun contatto trovato';

  @override
  String get mailAddToContacts => 'Aggiungi ai contatti';

  @override
  String get mailMessageLabel => 'Messaggio';

  @override
  String get mailSaveDraft => 'Salva bozza';

  @override
  String get mailAttachmentsLabel => 'Allegati';

  @override
  String get mailAddAttachment => 'Aggiungi allegato';

  @override
  String get mailRemoveAttachment => 'Rimuovi allegato';

  @override
  String get mailSaveAttachment => 'Salva allegato';

  @override
  String get mailAttachmentDropHint => 'Trascina qui i file per allegarli';

  @override
  String mailAttachmentReadFailed(String name) {
    return 'Impossibile leggere il file: $name';
  }

  @override
  String mailAttachmentSaved(String name) {
    return 'Salvato \"$name\"';
  }

  @override
  String mailAttachmentLargeWarning(String size) {
    return 'Gli allegati di grandi dimensioni ($size) possono richiedere molto tempo per l\'invio via radio.';
  }

  @override
  String get smsTitle => 'Invia messaggio SMS';

  @override
  String get smsPhoneNumber => 'Numero di telefono';

  @override
  String get smsIntro =>
      'Puoi inviare messaggi SMS ai telefoni in USA, Porto Rico, Canada, Australia e Regno Unito purché il numero abbia già aderito al servizio. Puoi aderire su: ';

  @override
  String get locationTitle => 'Posizione';

  @override
  String get beaconIntro =>
      'Modifica il modo in cui la radio trasmette le informazioni su se stessa, inclusi posizione, tensione e un messaggio personalizzato. Le altre stazioni nei dintorni potranno vedere queste informazioni.';

  @override
  String beaconRadio(String name) {
    return 'Radio: $name';
  }

  @override
  String get beaconSection => 'Beacon';

  @override
  String get beaconPacketFormat => 'Formato pacchetto';

  @override
  String get beaconInterval => 'Intervallo beacon';

  @override
  String get beaconAprsCallsign => 'Nominativo APRS';

  @override
  String get beaconCallsignHint => 'Nominativo - ID stazione';

  @override
  String get beaconCallsignInvalid =>
      'Inserisci un nominativo e un ID stazione validi (es. W1AW-5)';

  @override
  String get beaconAprsMessage => 'Messaggio APRS';

  @override
  String get beaconAprsPath => 'Percorso APRS';

  @override
  String get beaconAprsPathInvalid =>
      'Inserisci una o due stazioni valide separate da una virgola (es. WIDE1-1,WIDE2-1)';

  @override
  String get beaconShareLocation => 'Condividi posizione';

  @override
  String get beaconSendVoltage => 'Invia tensione';

  @override
  String get beaconAllowPositionCheck => 'Consenti verifica posizione';

  @override
  String get beaconChannelCurrent => 'Attuale (non consigliato)';

  @override
  String beaconEverySeconds(int n) {
    return 'Ogni $n secondi';
  }

  @override
  String beaconEveryMinutes(int n) {
    return 'Ogni $n minuti';
  }

  @override
  String get assConnectTerminal => 'Connetti alla stazione terminale';

  @override
  String get assConnectBbs => 'Connetti alla stazione BBS';

  @override
  String get assConnectWinlink => 'Connetti al gateway Winlink';

  @override
  String get assConnectStation => 'Connetti alla stazione';

  @override
  String get assNew => 'Nuova…';

  @override
  String get attSelectFile => 'Seleziona il file da condividere';

  @override
  String get attCompressing => 'Compressione in corso...';

  @override
  String get attTitle => 'Aggiungi file torrent';

  @override
  String get attSelect => 'Seleziona...';

  @override
  String get attDescriptionOptional => 'Descrizione (facoltativa)';

  @override
  String get stationTitleVoice => 'Stazione vocale';

  @override
  String get stationTitleAprs => 'Stazione APRS';

  @override
  String get stationTitleTerminal => 'Stazione terminale';

  @override
  String get stationTitleWinlink => 'Gateway Winlink';

  @override
  String get stationTitleGeneric => 'Stazione';

  @override
  String get stationTitleSms => 'Contatto SMS / telefono';

  @override
  String get stationTitleEmail => 'Contatto email';

  @override
  String get stationPhoneNumber => 'Numero di telefono';

  @override
  String get stationEmail => 'Indirizzo email';

  @override
  String get stationInvalidEmail => 'Indirizzo email non valido';

  @override
  String get contactAvatarCustomize => 'Personalizza avatar';

  @override
  String get contactAvatarChooseLogo => 'Scegli logo...';

  @override
  String get contactAvatarChooseImage => 'Scegli immagine...';

  @override
  String get contactAvatarPaste => 'Incolla';

  @override
  String get contactAvatarReset => 'Ripristina predefinito';

  @override
  String get contactAvatarCropTitle => 'Ritaglia immagine';

  @override
  String get contactAvatarImageError => 'Impossibile caricare l\'immagine';

  @override
  String get stationTypeOptionVoice => 'Stazione vocale / generica';

  @override
  String get stationTypeLabel => 'Tipo di stazione';

  @override
  String get stationAprsRoute => 'Percorso APRS';

  @override
  String get stationUseAuth => 'Usa l\'autenticazione dei messaggi';

  @override
  String get stationAuthPassword => 'Password di autenticazione';

  @override
  String get stationPasswordRequired => 'Password richiesta';

  @override
  String get stationTerminalProtocol => 'Protocollo terminale';

  @override
  String get stationAx25Destination => 'Destinazione AX.25 (es. CALL-1)';

  @override
  String get stationAx25Invalid => 'Indirizzo AX.25 non valido';

  @override
  String get stationModem => 'Modem';

  @override
  String get apdTitle => 'Dettagli pacchetto APRS';

  @override
  String get apdCopyAll => 'Copia tutto';

  @override
  String get apdCopyValue => 'Copia valore';

  @override
  String get apdValueCopied => 'Valore copiato';

  @override
  String get apdAllValuesCopied => 'Tutti i valori copiati';

  @override
  String get apdNoDetails => 'Nessun dettaglio disponibile.';

  @override
  String get apdShowLocation => 'Mostra posizione...';

  @override
  String get acfgTitle => 'Configura canale APRS';

  @override
  String get acfgIntro =>
      'La frequenza APRS cambia a seconda della regione del mondo. Usa questo sito per trovare la frequenza corretta per configurare il canale APRS.';

  @override
  String get acfgConfiguration => 'Configurazione APRS';

  @override
  String get acfgFrequency => 'Frequenza';

  @override
  String get acfgFrequencyHint => '144.39 in Nord America\n144.80 in Europa';

  @override
  String get acfgChannelOverwritten =>
      'Il canale selezionato verrà sovrascritto';

  @override
  String get sstvSendTitle => 'Invia immagine SSTV';

  @override
  String sstvSendTitleNamed(String name) {
    return 'Invia immagine SSTV - $name';
  }

  @override
  String get sstvMode => 'Modalità:';

  @override
  String sstvTransmitTime(String time) {
    return 'Tempo di trasmissione: ~$time';
  }

  @override
  String get msgdTitle => 'Dettagli messaggio';

  @override
  String get msgdFieldType => 'Tipo';

  @override
  String get msgdFieldDirection => 'Direzione';

  @override
  String get msgdFieldTime => 'Ora';

  @override
  String get msgdFieldSource => 'Origine';

  @override
  String get msgdFieldReceiver => 'Ricevitore';

  @override
  String get msgdFieldDuration => 'Durata';

  @override
  String get msgdFieldLatitude => 'Latitudine';

  @override
  String get msgdFieldLongitude => 'Longitudine';

  @override
  String get msgdFieldMessage => 'Messaggio';

  @override
  String get msgdFieldFile => 'File';

  @override
  String get msgdDirReceived => 'Ricevuto';

  @override
  String get msgdDirSent => 'Inviato';

  @override
  String get msgdTypeVoice => 'Voce';

  @override
  String get msgdTypeVoiceClip => 'Clip vocale';

  @override
  String get msgdTypeRecording => 'Registrazione';

  @override
  String get msgdTypeSstvPicture => 'Immagine SSTV';

  @override
  String get msgdTypeIdentification => 'Identificazione';

  @override
  String get msgdTypeChatMessage => 'Messaggio chat';

  @override
  String get msgdTypeAx25Packet => 'Pacchetto AX.25';

  @override
  String get rpbFailedToLoad => 'Impossibile caricare la registrazione.';

  @override
  String get ivwFailedToLoad => 'Impossibile caricare l\'immagine.';

  @override
  String get rawTitle => 'Comando radio grezzo';

  @override
  String get rawCommand => 'Comando';

  @override
  String get rawHexPayload => 'Payload HEX (facoltativo)';

  @override
  String get rawResponse => 'Risposta';

  @override
  String get identTitle => 'Impostazioni rilascio PTT';

  @override
  String get identDescription =>
      'Se abilitato, invia il tuo nominativo e/o le informazioni sulla posizione ogni volta che rilasci il PTT sul canale su cui stai trasmettendo.';

  @override
  String get identCallsignHint => 'Inserisci nominativo - ID stazione';

  @override
  String get identCallsignDisplayNote =>
      'Il nominativo inserito qui viene mostrato sul display della radio.';

  @override
  String get identSendCallsign => 'Invia nominativo';

  @override
  String get identSendPosition => 'Invia posizione';

  @override
  String get commonOn => 'Attivo';

  @override
  String get commonOff => 'Spento';

  @override
  String get commonNone => 'Nessuno';

  @override
  String chChannelNumber(int n) {
    return 'Canale $n';
  }

  @override
  String chChShort(int n) {
    return 'Can $n';
  }

  @override
  String get chMoreSettings => 'Altre impostazioni';

  @override
  String get chMore => 'Altro';

  @override
  String get chChannelNameHint => 'Nome canale';

  @override
  String get chFrequencyMhz => 'Frequenza (MHz)';

  @override
  String get chReceiveMhz => 'Ricezione (MHz)';

  @override
  String get chTransmitMhz => 'Trasmissione (MHz)';

  @override
  String get chMode => 'Modalità';

  @override
  String get chPower => 'Potenza';

  @override
  String get chBandwidth => 'Larghezza di banda';

  @override
  String get chReceiveTone => 'Tono di ricezione (CTCSS / DCS)';

  @override
  String get chTransmitTone => 'Tono di trasmissione (CTCSS / DCS)';

  @override
  String get chDisableTransmit => 'Disabilita trasmissione';

  @override
  String get chMute => 'Silenzia';

  @override
  String get chScan => 'Scansione';

  @override
  String get chTalkAround => 'Talk around';

  @override
  String get chDeemphasis => 'De-enfasi';

  @override
  String get chPowerHigh => 'Alta';

  @override
  String get chPowerMedium => 'Media';

  @override
  String get chPowerLow => 'Bassa';

  @override
  String get chBandwidthWide => '25 KHz larga';

  @override
  String get chBandwidthNarrow => '12,5 KHz stretta';

  @override
  String get channelImportFetching => 'Recupero del canale dalla pagina web…';

  @override
  String get channelImportUnsupportedSite =>
      'Questo sito web non è supportato per l\'importazione dei canali.';

  @override
  String get channelImportFetchFailed => 'Impossibile scaricare la pagina web.';

  @override
  String get channelImportParseFailed =>
      'Impossibile trovare i dettagli del canale in quella pagina.';

  @override
  String get chClearTitle => 'Cancella canale';

  @override
  String chClearConfirm(int n) {
    return 'Cancellare il canale $n?\n\nQuesto rimuove la frequenza, il nome e le impostazioni da questo slot sulla radio.';
  }

  @override
  String get cdRxFrequency => 'Frequenza RX';

  @override
  String get cdTxFrequency => 'Frequenza TX';

  @override
  String get cdRxModulation => 'Modulazione RX';

  @override
  String get cdTxModulation => 'Modulazione TX';

  @override
  String get cdRxTone => 'Tono RX';

  @override
  String get cdTxTone => 'Tono TX';

  @override
  String get cdTxDisabled => 'TX disabilitata';

  @override
  String get cdTalkAround => 'Talk Around';

  @override
  String get cdEmpty => '(vuoto)';

  @override
  String get cdBandwidthWide => '25 kHz (larga)';

  @override
  String get cdBandwidthNarrow => '12,5 kHz (stretta)';

  @override
  String get gpsDetailsTitle => 'Dettagli GPS';

  @override
  String get gpsDisabled => 'GPS disabilitato';

  @override
  String get gpsLock => 'Aggancio GPS';

  @override
  String get gpsNoLock => 'Nessun aggancio GPS';

  @override
  String get mdbgTitle => 'Traffico Winlink';

  @override
  String get mdbgNoTraffic => 'Nessun traffico ancora.';

  @override
  String get fwTitle => 'Aggiornamento firmware radio';

  @override
  String get fwStatusInitial =>
      'Controlla online la disponibilità di un aggiornamento firmware oppure carica un file firmware dal disco.';

  @override
  String get fwErrNotConnected => 'La radio non è connessa.';

  @override
  String get fwErrNoDeviceInfo =>
      'Le informazioni sul dispositivo radio non sono ancora disponibili.';

  @override
  String get fwStatusChecking => 'Verifica di un aggiornamento firmware…';

  @override
  String get fwErrNoServerInfo =>
      'Il server del fornitore non ha restituito informazioni sul firmware.';

  @override
  String fwUpdateAvailable(String version) {
    return 'È disponibile un aggiornamento firmware $version. Consulta le note di rilascio qui sotto, quindi scarica per aggiornare.';
  }

  @override
  String fwErrCheckFailed(String error) {
    return 'Verifica aggiornamento non riuscita: $error';
  }

  @override
  String get fwPickTitle => 'Seleziona file firmware';

  @override
  String fwLoaded(String name, String size, String md5) {
    return 'Caricato $name: $size (MD5 $md5…).';
  }

  @override
  String fwErrLoadFailed(String error) {
    return 'Impossibile caricare il file firmware: $error';
  }

  @override
  String get fwSaveTitle => 'Salva file firmware';

  @override
  String fwSavedTo(String path) {
    return 'Firmware salvato in $path';
  }

  @override
  String fwErrSaveFailed(String error) {
    return 'Impossibile salvare il file firmware: $error';
  }

  @override
  String get fwStatusDownloading => 'Download e assemblaggio del firmware…';

  @override
  String get fwProgressStarting => 'Avvio…';

  @override
  String fwReady(String size, String md5) {
    return 'Firmware pronto: $size (MD5 $md5…).';
  }

  @override
  String fwErrDownloadFailed(String error) {
    return 'Download non riuscito: $error';
  }

  @override
  String get fwStatusWriting =>
      'Scrittura del firmware sulla radio. Non spegnerla.';

  @override
  String get fwProgressTransferring => 'Trasferimento…';

  @override
  String fwErrTransferFailed(String error) {
    return 'Trasferimento del firmware non riuscito: $error';
  }

  @override
  String get fwStatusRebooting => 'La radio si sta riavviando. Riconnessione…';

  @override
  String get fwProgressWaitingRestart => 'In attesa del riavvio della radio…';

  @override
  String fwErrReconnectFailed(String error) {
    return 'Riconnessione non riuscita dopo il riavvio: $error';
  }

  @override
  String get fwErrReconnectNull =>
      'Impossibile riconnettersi alla radio dopo il riavvio. Il firmware è stato trasferito ma non confermato. Riconnettiti manualmente e riprova.';

  @override
  String get fwStatusFinalising => 'Finalizzazione dell\'aggiornamento…';

  @override
  String get fwProgressConfirming => 'Conferma…';

  @override
  String fwErrConfirmFailed(String error) {
    return 'Conferma dell\'aggiornamento non riuscita: $error';
  }

  @override
  String get fwStatusComplete =>
      'Aggiornamento firmware completato! La radio ora esegue il nuovo firmware.';

  @override
  String get fwProgressDownloadPatch => 'Download della patch';

  @override
  String get fwProgressDownloadBase => 'Download dell\'immagine di base';

  @override
  String get fwProgressAssemble => 'Assemblaggio del firmware';

  @override
  String fwProgressBytes(String label, String done, String total) {
    return '$label ($done / $total)';
  }

  @override
  String fwProgressTransferringBytes(String done, String total) {
    return 'Trasferimento ($done / $total)';
  }

  @override
  String fwCurrentFirmware(String version) {
    return 'Firmware attuale: $version';
  }

  @override
  String get fwErrGeneric => 'Si è verificato un errore.';

  @override
  String get fwIdleDisclosure =>
      'La verifica online contatta il server del fornitore della radio (rpc.benshikj.com) e invia solo l\'ID prodotto della tua radio. Non viene inviato nulla finché non premi Verifica aggiornamento.';

  @override
  String get fwWhatsNew => 'Novità';

  @override
  String get fwConfirmWarning =>
      'Attenzione: tieni la radio accesa, carica e nel raggio del Bluetooth per l\'intero processo. La radio si riavvierà a metà del processo. Interrompere l\'aggiornamento può richiedere un ripristino manuale.';

  @override
  String get fwFromFile => 'Da file…';

  @override
  String get fwCheckForUpdate => 'Verifica aggiornamento';

  @override
  String get fwDownload => 'Scarica';

  @override
  String get fwSave => 'Salva…';

  @override
  String get fwFlashNow => 'Flash ora';

  @override
  String get fwRetry => 'Riprova';

  @override
  String get wxTitle => 'Richiedi bollettino meteo';

  @override
  String get wxIntro => 'Richiedi un bollettino meteo usando APRS. ';

  @override
  String get wxLocation => 'Posizione';

  @override
  String get wxLocationHelper =>
      'Città/stato USA o codice postale USA, oppure coordinate 41.123/-121.334';

  @override
  String get wxTime => 'Ora';

  @override
  String get wxReport => 'Bollettino';

  @override
  String get wxToday => 'Oggi';

  @override
  String get wxTonight => 'Stanotte';

  @override
  String get wxTomorrow => 'Domani';

  @override
  String get wxTomorrowNight => 'Domani notte';

  @override
  String get wxMonday => 'Lunedì';

  @override
  String get wxMondayNight => 'Lunedì notte';

  @override
  String get wxTuesday => 'Martedì';

  @override
  String get wxTuesdayNight => 'Martedì notte';

  @override
  String get wxWednesday => 'Mercoledì';

  @override
  String get wxWednesdayNight => 'Mercoledì notte';

  @override
  String get wxThursday => 'Giovedì';

  @override
  String get wxThursdayNight => 'Giovedì notte';

  @override
  String get wxFriday => 'Venerdì';

  @override
  String get wxFridayNight => 'Venerdì notte';

  @override
  String get wxSaturday => 'Sabato';

  @override
  String get wxSaturdayNight => 'Sabato notte';

  @override
  String get wxSunday => 'Domenica';

  @override
  String get wxSundayNight => 'Domenica notte';

  @override
  String get wxReportBrief => 'Sintetico, previsione breve, solo USA';

  @override
  String get wxReportFull => 'Completo, previsione più dettagliata, solo USA';

  @override
  String get wxReportCurrent => 'Attuale, stazione NWS più vicina, solo USA';

  @override
  String get wxReportMetar => 'METAR, stazione ICAO in formato METAR';

  @override
  String get wxReportCwop => 'CWOP, stazione CWOP più vicina';

  @override
  String get cslViewCallsign => 'Cerca nominativo...';

  @override
  String get cslAddContact => 'Aggiungi come contatto';

  @override
  String get cslTitle => 'Ricerca nominativo';

  @override
  String cslLookingUp(String callsign) {
    return 'Ricerca di $callsign...';
  }

  @override
  String cslNotFound(String callsign) {
    return 'Nessun record trovato per $callsign.';
  }

  @override
  String get cslNoDatabase =>
      'Nessun database di nominativi è installato. Scaricalo nelle Impostazioni per abilitare le ricerche offline.';

  @override
  String get cslUnsupported =>
      'La ricerca offline dei nominativi non è disponibile su questa piattaforma.';

  @override
  String get cslFieldCallsign => 'Nominativo';

  @override
  String get cslFieldName => 'Nome';

  @override
  String get cslFieldClass => 'Classe di licenza';

  @override
  String get cslFieldStatus => 'Stato';

  @override
  String get cslFieldLocation => 'Posizione';

  @override
  String get cslFieldExpires => 'Scadenza';

  @override
  String get cslFieldCountry => 'Paese';

  @override
  String get cslFieldContinent => 'Continente';

  @override
  String get cslFieldQualifications => 'Qualifiche';

  @override
  String get cslUsDetails => 'Dettagli licenza USA';

  @override
  String get cslCaDetails => 'Dettagli licenza canadese';

  @override
  String get cslSourceUs => 'Stati Uniti (FCC)';

  @override
  String get cslSourceCanada => 'Canada (ISED)';

  @override
  String get cslSectionTitle => 'Database nominativi';

  @override
  String get cslButtonDatabases => 'Database';

  @override
  String get cslButtonLookup => 'Ricerca';

  @override
  String get cslSectionIntro =>
      'Ricerca offline dei nominativi dei radioamatori statunitensi usando i dati del database delle licenze FCC.';

  @override
  String get cslNotInstalled => 'Non installato';

  @override
  String cslInstalledInfo(String version) {
    return '$version';
  }

  @override
  String get cslDownload => 'Scarica';

  @override
  String get cslUpdate => 'Verifica aggiornamento';

  @override
  String get cslDelete => 'Elimina';

  @override
  String cslDownloading(String percent) {
    return 'Download $percent%';
  }

  @override
  String get cslInstalling => 'Installazione...';

  @override
  String get cslUpToDate => 'Il database dei nominativi è aggiornato.';

  @override
  String get cslUpToDateButton => 'Aggiornato';

  @override
  String cslDownloadFailed(String error) {
    return 'Download non riuscito: $error';
  }

  @override
  String get cslDeleteTitle => 'Elimina database nominativi';

  @override
  String get cslDeleteMessage =>
      'Eliminare il database dei nominativi scaricato? Potrai scaricarlo di nuovo in seguito.';

  @override
  String get cslAutoUpdateWifi => 'Aggiornamento automatico tramite Wi-Fi';

  @override
  String get cslAutoUpdateWifiSubtitle =>
      'Mantieni aggiornati automaticamente i database installati, solo tramite Wi-Fi o connessioni cablate, per evitare costi di dati mobili.';
}
