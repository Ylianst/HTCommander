// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Handi-Talkie Commander';

  @override
  String get menuFile => 'Fichier';

  @override
  String get menuConnect => 'Connexion...';

  @override
  String get menuDisconnect => 'Déconnexion';

  @override
  String get menuSettings => 'Paramètres...';

  @override
  String get menuExit => 'Quitter';

  @override
  String get menuDualWatch => 'Double veille';

  @override
  String get menuScan => 'Balayage';

  @override
  String get menuRegions => 'Régions';

  @override
  String get menuTrustedDevices => 'Appareils de confiance...';

  @override
  String get menuButtons => 'Boutons...';

  @override
  String get menuExportChannels => 'Exporter les canaux...';

  @override
  String get menuImportChannels => 'Importer les canaux...';

  @override
  String get menuMacRadio => 'Radio';

  @override
  String get menuMacDisplay => 'Affichage';

  @override
  String get commonClose => 'Fermer';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonOk => 'OK';

  @override
  String get aboutCheckForUpdates => 'Rechercher des mises à jour';

  @override
  String aboutVersionAuthor(String version) {
    return 'Version $version\nYlian Saint-Hilaire, KK7VZT\nLogiciel libre, licence Apache 2.0';
  }

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsLanguageHint =>
      'Choisissez la langue utilisée par l\'application. « Langue du système » suit la langue de votre appareil.';

  @override
  String get settingsThemeMode => 'Thème';

  @override
  String get settingsThemeModeHint =>
      'Choisissez l\'apparence claire ou sombre. « Par défaut du système » suit le réglage de votre appareil.';

  @override
  String get settingsThemeModeSystem => 'Par défaut du système';

  @override
  String get settingsThemeModeLight => 'Clair';

  @override
  String get settingsThemeModeDark => 'Sombre';

  @override
  String get languageSystem => 'Langue du système';

  @override
  String get languageEnglish => 'Anglais';

  @override
  String get languageFrench => 'Français';

  @override
  String get languageSpanish => 'Espagnol';

  @override
  String get languageChinese => 'Chinois';

  @override
  String get languageJapanese => 'Japonais';

  @override
  String get languageHindi => 'Hindi';

  @override
  String get languageGerman => 'Allemand';

  @override
  String get menuAudio => 'Audio';

  @override
  String get menuAudioEnabled => 'Audio activé';

  @override
  String get menuSoftwareModem => 'Modem logiciel';

  @override
  String get menuModemDisabled => 'Désactivé';

  @override
  String get menuDartTransmitLevel => 'Niveau de transmission DART';

  @override
  String get menuDartLevel0 => 'Niveau 0 (BPSK, LDPC 1/2)';

  @override
  String get menuDartLevel1 => 'Niveau 1 (QPSK, LDPC 1/2)';

  @override
  String get menuDartLevel2 => 'Niveau 2 (QPSK, LDPC 2/3)';

  @override
  String get menuDartLevel3 => 'Niveau 3 (8PSK, LDPC 2/3)';

  @override
  String get menuDartLevel4 => 'Niveau 4 (16QAM, LDPC 3/4)';

  @override
  String get menuDartLevel5 => 'Niveau 5 (16QAM, LDPC 5/6)';

  @override
  String get menuDartLevelF => 'Niveau F (4-FSK, LDPC 1/2)';

  @override
  String get menuAprsModem => 'Modem APRS';

  @override
  String get menuView => 'Affichage';

  @override
  String get menuRadio => 'Radio';

  @override
  String get menuTabs => 'Onglets';

  @override
  String get menuTabNames => 'Noms des onglets';

  @override
  String get menuShowAllTabs => 'Afficher tous les onglets';

  @override
  String get menuAllChannels => 'Tous les canaux';

  @override
  String get menuChannelFrequency => 'Fréquence du canal';

  @override
  String get menuHelp => 'Aide';

  @override
  String get menuRadioInformation => 'Informations sur la radio...';

  @override
  String get menuGpsInformation => 'Informations GPS...';

  @override
  String get menuCheckForUpdatesEllipsis => 'Rechercher des mises à jour...';

  @override
  String get menuAbout => 'À propos...';

  @override
  String get tabComms => 'Communications';

  @override
  String get tabAudio => 'Audio';

  @override
  String get tabAprs => 'APRS';

  @override
  String get tabMap => 'Carte';

  @override
  String get tabMail => 'Courrier';

  @override
  String get tabTerminal => 'Terminal';

  @override
  String get tabContacts => 'Contacts';

  @override
  String get tabBbs => 'BBS';

  @override
  String get tabTorrent => 'Torrent';

  @override
  String get tabPackets => 'Paquets';

  @override
  String get tabDebug => 'Débogage';

  @override
  String get tabRadio => 'Radio';

  @override
  String get stateDisconnected => 'Déconnecté';

  @override
  String get stateConnecting => 'Connexion...';

  @override
  String get stateConnected => 'Connecté';

  @override
  String get stateUnableToConnect => 'Connexion impossible';

  @override
  String get stateAccessDenied => 'Accès refusé';

  @override
  String get stateSelectRadio => 'Sélectionner une radio';

  @override
  String statusBattery(int percent) {
    return 'Batterie : $percent %';
  }

  @override
  String get statusCheckingBluetooth => 'Vérification du Bluetooth...';

  @override
  String get statusBluetoothNotAvailable => 'Bluetooth non disponible';

  @override
  String get statusScanningForRadios => 'Recherche de radios...';

  @override
  String get statusErrorScanning => 'Erreur lors de la recherche de radios';

  @override
  String get statusNoCompatibleRadios => 'Aucune radio compatible trouvée';

  @override
  String get statusAllRadiosConnected =>
      'Toutes les radios sont déjà connectées';

  @override
  String statusConnectingTo(String name) {
    return 'Connexion à $name...';
  }

  @override
  String statusConnectedTo(String name) {
    return 'Connecté à $name';
  }

  @override
  String statusFailedToConnect(String name) {
    return 'Échec de la connexion à $name';
  }

  @override
  String get statusDisconnecting => 'Déconnexion...';

  @override
  String get settingsTabLicense => 'Licence';

  @override
  String get settingsTabAprs => 'APRS';

  @override
  String get settingsTabComms => 'Communications';

  @override
  String get settingsTabWinlink => 'Winlink';

  @override
  String get settingsTabServers => 'Serveurs';

  @override
  String get settingsTabMap => 'Carte';

  @override
  String get settingsTabLimits => 'Limites';

  @override
  String get settingsTabApplication => 'Application';

  @override
  String get settingsAdd => 'Ajouter';

  @override
  String get settingsRemove => 'Supprimer';

  @override
  String get settingsDownload => 'Télécharger';

  @override
  String get settingsRetry => 'Réessayer';

  @override
  String get settingsPreview => 'Aperçu';

  @override
  String get settingsNone => 'Aucun';

  @override
  String get settingsLicenseInfo =>
      'Aux États-Unis, vous avez besoin d\'une licence de radioamateur pour émettre. Consultez le site Web de l\'ARRL pour plus d\'informations sur l\'obtention d\'une licence.';

  @override
  String get settingsCallSignStationId => 'Indicatif et ID de station';

  @override
  String get settingsCallSign => 'Indicatif';

  @override
  String get settingsCallSignHint => 'ex. W1AW';

  @override
  String get settingsStationId => 'ID de station';

  @override
  String get settingsAllowTransmit => 'Autoriser cette application à émettre';

  @override
  String get settingsCallSignHelp =>
      'Saisissez un indicatif valide (au moins 3 caractères) pour activer l\'émission';

  @override
  String get settingsAprsIntro =>
      'Configurez les chemins de routage APRS pour la transmission de paquets.';

  @override
  String get settingsAprsRoutes => 'Routes APRS';

  @override
  String get settingsEditRoute => 'Modifier la route';

  @override
  String get settingsEditRouteProtected =>
      'La route intégrée ne peut pas être modifiée';

  @override
  String get settingsDeleteRoute => 'Supprimer la route';

  @override
  String get settingsDeleteRouteProtected =>
      'La route intégrée ne peut pas être supprimée';

  @override
  String get settingsCommsIntro =>
      'Configurez les paramètres de reconnaissance et de synthèse vocale.';

  @override
  String get settingsSpeechToText => 'Reconnaissance vocale';

  @override
  String get settingsSpeechToTextInfo =>
      'Transcrit en texte l\'audio radio reçu. Fonctionne entièrement hors ligne sur cet appareil ; l\'audio n\'est jamais enregistré sur le disque.';

  @override
  String get settingsModel => 'Modèle';

  @override
  String get settingsRecognitionLanguage => 'Langue de reconnaissance';

  @override
  String get settingsRecognitionLanguageHelp =>
      'Les changements de langue prennent effet au prochain démarrage du moteur.';

  @override
  String get settingsStatus => 'État';

  @override
  String settingsModelInstalled(String suffix) {
    return 'Modèle installé$suffix';
  }

  @override
  String settingsDownloadingModelPct(String percent) {
    return 'Téléchargement du modèle… $percent %';
  }

  @override
  String get settingsDownloadingModel => 'Téléchargement du modèle…';

  @override
  String settingsInstallingModelPct(String percent) {
    return 'Installation du modèle… $percent %';
  }

  @override
  String get settingsInstallingModel => 'Installation du modèle…';

  @override
  String get settingsModelInstallError =>
      'Le modèle n\'a pas pu être installé.';

  @override
  String settingsModelNotDownloaded(String downloadLabel) {
    return 'Modèle non téléchargé. $downloadLabel n\'a lieu qu\'une seule fois et est mis en cache sur cet appareil.';
  }

  @override
  String settingsBytesOf(String received, String total) {
    return '$received sur $total';
  }

  @override
  String get settingsRemoveSttModelTitle =>
      'Supprimer le modèle de reconnaissance vocale ?';

  @override
  String settingsRemoveSttModelBody(String name) {
    return 'Le modèle « $name » téléchargé sera supprimé pour libérer de l\'espace disque. Il sera téléchargé à nouveau lors de sa prochaine utilisation.';
  }

  @override
  String get settingsTextToSpeech => 'Synthèse vocale';

  @override
  String get settingsTextToSpeechInfo =>
      'Utilisée lors de l\'envoi de texte en mode « Voix » depuis l\'onglet Communications.';

  @override
  String get settingsTtsUnavailableTitle =>
      'La synthèse vocale n\'est pas disponible';

  @override
  String get settingsVoice => 'Voix';

  @override
  String get settingsSpeechRate => 'Débit de parole';

  @override
  String get settingsPitch => 'Hauteur';

  @override
  String get settingsLoadingVoices => 'Chargement des voix…';

  @override
  String get settingsSystemDefault => 'Valeur par défaut du système';

  @override
  String get settingsLangAutoDetect => 'Détection automatique';

  @override
  String get settingsLangChinese => 'Chinois';

  @override
  String get settingsLangJapanese => 'Japonais';

  @override
  String get settingsLangKorean => 'Coréen';

  @override
  String get settingsLangCantonese => 'Cantonais';

  @override
  String get settingsWinlinkIntro =>
      'Configurez les paramètres de messagerie Winlink pour le courriel par radio.';

  @override
  String get settingsWinlinkAccount => 'Compte Winlink';

  @override
  String get settingsAccount => 'Compte';

  @override
  String get settingsWinlinkAccountHelp =>
      'Basé sur votre indicatif de l\'onglet Licence';

  @override
  String get settingsPassword => 'Mot de passe';

  @override
  String get settingsUseStationIdWinlink =>
      'Utiliser l\'ID de station pour Winlink';

  @override
  String get settingsServersIntro =>
      'Configurez les paramètres des serveurs locaux.';

  @override
  String get settingsLocalServers => 'Serveurs locaux';

  @override
  String get settingsEnableWebServer => 'Activer le serveur Web';

  @override
  String get settingsPort => 'Port :';

  @override
  String get settingsEnableAgwpeServer => 'Activer le serveur AGWPE';

  @override
  String get settingsMapIntroGps =>
      'Configurez les sources de données GPS et de suivi des avions.';

  @override
  String get settingsMapIntroNoGps =>
      'Configurez les sources de données de suivi des avions.';

  @override
  String get settingsGpsSerialPort => 'Port série GPS';

  @override
  String get settingsSerialPort => 'Port série';

  @override
  String get settingsBaudRate => 'Débit en bauds';

  @override
  String get settingsShareGpsLocation => 'Partager la position GPS série';

  @override
  String get settingsShareGpsLocationHelp =>
      'Envoie la position GPS série à la radio connectée pour qu\'elle diffuse votre position actuelle.';

  @override
  String get settingsAirplaneTracking => 'Suivi des avions (dump1090)';

  @override
  String get settingsServerUrl => 'URL du serveur';

  @override
  String get settingsTestConnection => 'Tester la connexion';

  @override
  String get settingsTest => 'Tester';

  @override
  String get settingsTestTesting => 'Test en cours...';

  @override
  String get settingsTestEmptyAddress => 'Échec : adresse du serveur vide';

  @override
  String settingsTestFailedHttp(int code) {
    return 'Échec : HTTP $code';
  }

  @override
  String settingsTestSuccess(int count) {
    return 'Succès, $count avion(s) trouvé(s).';
  }

  @override
  String get settingsTestUnexpectedJson => 'Échec : format JSON inattendu';

  @override
  String get settingsTestTimedOut => 'Échec : délai d\'attente dépassé';

  @override
  String get settingsTestInvalidJson => 'Échec : réponse JSON invalide';

  @override
  String get settingsTestFailed => 'Échec';

  @override
  String get settingsTestConnectionFailedTitle => 'Échec du test de connexion';

  @override
  String get settingsLimitsIntro =>
      'Limitez le nombre d\'éléments d\'historique conservés d\'un démarrage à l\'autre. Réglez sur « Illimité » pour tout conserver.';

  @override
  String get settingsHistoryLimits => 'Limites d\'historique';

  @override
  String get settingsUnlimited => 'Illimité';

  @override
  String get settingsLimitAprsMessages => 'Messages APRS';

  @override
  String get settingsLimitPackets => 'Paquets';

  @override
  String get settingsLimitSstvImages => 'Images SSTV';

  @override
  String get settingsLimitCommEvents => 'Événements de communication';

  @override
  String settingsLimitCurrent(int count) {
    return 'Actuel : $count';
  }

  @override
  String settingsLimitItemsDeleted(int count) {
    return '$count éléments seront supprimés';
  }

  @override
  String get settingsDeleteHistoryTitle =>
      'Supprimer les éléments d\'historique ?';

  @override
  String settingsDeleteHistoryBody(String items) {
    return 'Ces limites supprimeront définitivement les plus anciens :\n\n$items\n\nCette action est irréversible.';
  }

  @override
  String settingsDeleteAprsMessages(int count) {
    return '$count messages APRS';
  }

  @override
  String settingsDeletePackets(int count) {
    return '$count paquets';
  }

  @override
  String settingsDeleteSstvImages(int count) {
    return '$count images SSTV';
  }

  @override
  String settingsDeleteCommEvents(int count) {
    return '$count événements de communication';
  }

  @override
  String get settingsAddAprsRoute => 'Ajouter une route APRS';

  @override
  String get settingsEditAprsRoute => 'Modifier une route APRS';

  @override
  String get settingsName => 'Nom';

  @override
  String get settingsNameHint => 'ex. Standard';

  @override
  String get settingsDuplicateRoute => 'Une route portant ce nom existe déjà.';

  @override
  String get settingsPath => 'Chemin';

  @override
  String get commonError => 'Erreur';

  @override
  String get commonConnect => 'Connexion';

  @override
  String get commonDisconnect => 'Déconnexion';

  @override
  String get commonRename => 'Renommer';

  @override
  String get commonRemove => 'Supprimer';

  @override
  String connectScanError(String error) {
    return 'Échec de la recherche d\'appareils Bluetooth : $error';
  }

  @override
  String get connectNoRadiosTitle => 'Aucune radio trouvée';

  @override
  String get connectNoRadiosBody =>
      'Aucun appareil radio compatible n\'a été trouvé.\n\nAssurez-vous que votre radio est allumée et que le Bluetooth est activé.';

  @override
  String get connectAllConnectedTitle => 'Toutes connectées';

  @override
  String get connectAllConnectedBody =>
      'Tous les appareils radio détectés sont déjà connectés.';

  @override
  String get connectBluetoothOffTitle => 'Bluetooth non disponible';

  @override
  String get connectBluetoothOffBody =>
      'Le Bluetooth n\'est pas disponible ou est désactivé.\n\nVeuillez activer le Bluetooth dans les paramètres de votre appareil et réessayer.';

  @override
  String get radioConnectionTitle => 'Connexion radio';

  @override
  String get radioConnectionEmpty =>
      'Aucune radio compatible trouvée.\nAssurez-vous que votre radio est allumée et que le Bluetooth est activé.';

  @override
  String get radioRenameTitle => 'Renommer la radio';

  @override
  String get radioRenamePrompt =>
      'Saisissez un nom personnalisé pour cette radio :';

  @override
  String get radioRenameHint => 'Laissez vide pour utiliser le nom par défaut';

  @override
  String get updateTitle => 'Mise à jour du logiciel';

  @override
  String get updateChecking => 'Recherche de mises à jour...';

  @override
  String updateVersionAvailable(String version) {
    return 'La version $version est disponible.';
  }

  @override
  String updateFreshDownload(String version) {
    return 'La version $version nécessite un nouveau téléchargement.';
  }

  @override
  String updateUnsupported(String version) {
    return 'Cette version n\'est plus prise en charge. Mettez à jour vers $version.';
  }

  @override
  String get updateUpToDate => 'Vous utilisez la dernière version.';

  @override
  String updateCheckFailed(String error) {
    return 'Échec de la vérification des mises à jour : $error';
  }

  @override
  String get updateDownloading => 'Téléchargement de la mise à jour...';

  @override
  String get updateDownloaded => 'Mise à jour téléchargée. Prête à installer.';

  @override
  String updateDownloadFailed(String error) {
    return 'Échec du téléchargement : $error';
  }

  @override
  String updateInstallFailed(String error) {
    return 'Échec de l\'installation : $error';
  }

  @override
  String updateDiagnosticsLog(String path) {
    return 'Si la mise à jour ne se termine pas, consultez le journal de diagnostic :\n$path';
  }

  @override
  String get updateInstallRestart => 'Installer et redémarrer';

  @override
  String get updateCheckAgain => 'Vérifier à nouveau';

  @override
  String get regionsTitle => 'Renommer les régions';

  @override
  String regionsMaxChars(int count) {
    return 'Les noms de région peuvent comporter jusqu\'à $count caractères.';
  }

  @override
  String regionLabel(int number) {
    return 'Région $number';
  }

  @override
  String get gpsInfoTitle => 'Informations GPS';

  @override
  String get gpsSectionConnection => 'Connexion';

  @override
  String get gpsSectionFix => 'Fix GPS';

  @override
  String get gpsSectionPosition => 'Position';

  @override
  String get gpsSectionMotion => 'Mouvement';

  @override
  String get gpsSectionTime => 'Heure';

  @override
  String get gpsPortStatus => 'État du port';

  @override
  String get gpsNotConfigured => 'Non configuré';

  @override
  String get gpsOpenReceiving => 'Ouvert — réception de données';

  @override
  String get gpsPermDeniedLinux =>
      'Permission refusée — ajoutez votre utilisateur au groupe « dialout » (sudo usermod -aG dialout \$USER), puis déconnectez-vous et reconnectez-vous.';

  @override
  String get gpsPermDenied =>
      'Permission refusée — l\'application ne peut pas accéder à ce port.';

  @override
  String get gpsPortError =>
      'Erreur de port — impossible d\'ouvrir le port série.';

  @override
  String get gpsFix => 'Fix';

  @override
  String get gpsFixQuality => 'Qualité du point';

  @override
  String get gpsSatellites => 'Satellites';

  @override
  String get gpsNoData => 'Aucune donnée';

  @override
  String get gpsActive => 'Actif';

  @override
  String get gpsNoFix => 'Aucun point';

  @override
  String get gpsQualGps => 'Point GPS (1)';

  @override
  String get gpsQualDgps => 'Point DGPS (2)';

  @override
  String get gpsQualInvalid => 'Invalide (0)';

  @override
  String gpsQualUnknown(int quality) {
    return '$quality (inconnu)';
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
  String get gpsSpeed => 'Vitesse';

  @override
  String get gpsHeading => 'Cap';

  @override
  String get gpsTimeUtc => 'Heure GPS (UTC)';

  @override
  String get gpsDate => 'Date GPS';

  @override
  String get gpsLastUpdate => 'Dernière mise à jour';

  @override
  String get trustedDevicesTitle => 'Appareils de confiance';

  @override
  String get trustedRemoveTitle => 'Supprimer l\'appareil de confiance';

  @override
  String trustedRemoveMessage(String name) {
    return 'Retirer « $name » de la liste des appareils de confiance de la radio ?';
  }

  @override
  String get trustedNoDevices => 'Aucun appareil de confiance trouvé.';

  @override
  String get pfConfigTitle => 'Configurer les boutons';

  @override
  String get pfSaveToRadio => 'Enregistrer sur la radio';

  @override
  String get pfNoRadio => 'Aucune radio connectée.';

  @override
  String get pfNoButtons => 'Cette radio ne signale aucun bouton programmable.';

  @override
  String get pfIntro =>
      'Choisissez l\'action de chaque bouton programmable pour chaque type d\'appui. Les changements sont écrits sur la radio lorsque vous enregistrez.';

  @override
  String pfButtonLabel(int number) {
    return 'Bouton $number';
  }

  @override
  String get pfActionShort => 'Appui court';

  @override
  String get pfActionLong => 'Appui long';

  @override
  String get pfActionVeryLong => 'Appui très long';

  @override
  String get pfActionVeryVeryLong => 'Appui très très long';

  @override
  String get pfActionDouble => 'Double appui';

  @override
  String get pfActionTriple => 'Triple appui';

  @override
  String get pfActionRepeat => 'Répétition';

  @override
  String get pfActionPressDown => 'Appui enfoncé';

  @override
  String get pfActionRelease => 'Relâchement';

  @override
  String get pfActionLongRelease => 'Relâchement long';

  @override
  String get pfActionVeryLongRelease => 'Relâchement très long';

  @override
  String get pfActionVeryVeryLongRelease => 'Relâchement très très long';

  @override
  String pfActionUnknown(int action) {
    return 'Action $action';
  }

  @override
  String get pfEffectDisabled => 'Désactivé';

  @override
  String get pfEffectAlarm => 'Alarme';

  @override
  String get pfEffectAlarmAndMute => 'Alarme et sourdine';

  @override
  String get pfEffectToggleOffline => 'Basculer hors ligne';

  @override
  String get pfEffectToggleRadioTx => 'Basculer émission radio';

  @override
  String get pfEffectToggleTxPower => 'Basculer la puissance d\'émission';

  @override
  String get pfEffectToggleFm => 'Basculer la radio FM';

  @override
  String get pfEffectPrevChannel => 'Canal précédent';

  @override
  String get pfEffectNextChannel => 'Canal suivant';

  @override
  String get pfEffectTCall => 'Tonalité T (1750 Hz)';

  @override
  String get pfEffectPrevRegion => 'Région précédente';

  @override
  String get pfEffectNextRegion => 'Région suivante';

  @override
  String get pfEffectToggleChScan => 'Basculer le balayage des canaux';

  @override
  String get pfEffectMainPtt => 'PTT principal';

  @override
  String get pfEffectSubPtt => 'PTT secondaire';

  @override
  String get pfEffectToggleMonitor => 'Basculer le monitoring';

  @override
  String get pfEffectBtPairing => 'Appairage Bluetooth';

  @override
  String get pfEffectToggleDoubleCh => 'Basculer le double canal';

  @override
  String get pfEffectToggleAbCh => 'Basculer le canal A/B';

  @override
  String get pfEffectSendLocation => 'Envoyer la position';

  @override
  String get pfEffectOneClickLink => 'Lien en un clic';

  @override
  String get pfEffectVolDown => 'Baisser le volume';

  @override
  String get pfEffectVolUp => 'Augmenter le volume';

  @override
  String get pfEffectToggleMute => 'Basculer la sourdine';

  @override
  String pfEffectUnknown(int effect) {
    return 'Inconnu ($effect)';
  }

  @override
  String get importChannelsTitle => 'Importer des canaux';

  @override
  String importChannelsTitleWith(String name) {
    return 'Importer des canaux — $name';
  }

  @override
  String get importIntro =>
      'Faites glisser un canal depuis la gauche sur un emplacement de la radio, ou sélectionnez un canal et un emplacement puis appuyez sur la flèche. Appuyez sur l\'icône d\'information pour les détails. Les canaux ne sont écrits sur la radio que lorsque vous appuyez sur OK.';

  @override
  String importOkCount(int count) {
    return 'OK ($count)';
  }

  @override
  String importImportedHeader(int count) {
    return 'Importés ($count)';
  }

  @override
  String get importNoChannels => 'Aucun canal importé.';

  @override
  String importRadioChannelsHeader(int count) {
    return 'Canaux de la radio ($count)';
  }

  @override
  String get importNoRadioChannels => 'Aucun canal radio.';

  @override
  String get importMoveTooltip =>
      'Déplacer le canal sélectionné vers l\'emplacement sélectionné';

  @override
  String get importCopyAllTooltip =>
      'Copier tous les canaux importés vers les emplacements de la radio 1:1';

  @override
  String importChannelShort(int number) {
    return 'Canal $number';
  }

  @override
  String get importClearTooltip => 'Effacer l\'affectation en attente';

  @override
  String get importChannelDetails => 'Détails du canal';

  @override
  String get riTitle => 'Informations sur la radio';

  @override
  String get riNoRadioConnected => 'Aucune radio connectée';

  @override
  String get riConnectPrompt =>
      'Connectez une radio pour afficher ses informations.';

  @override
  String riRadioFallback(int id) {
    return 'Radio $id';
  }

  @override
  String get riSectionRadio => 'Radio';

  @override
  String get riSectionDeviceInfo => 'Informations sur l\'appareil';

  @override
  String get riSectionDeviceStatus => 'État de l\'appareil';

  @override
  String get riSectionDeviceSettings => 'Paramètres de l\'appareil';

  @override
  String get riSectionBss => 'Paramètres BSS';

  @override
  String get riSectionPosition => 'Position';

  @override
  String get riName => 'Nom';

  @override
  String get riStatus => 'État';

  @override
  String get riSettingsLabel => 'Paramètres';

  @override
  String get riNoData => 'Aucune donnée';

  @override
  String get riNoGpsData => 'Aucune donnée GPS';

  @override
  String get riNoGpsLock => 'Aucun point GPS';

  @override
  String get riGpsLocked => 'Point GPS acquis';

  @override
  String get riTrue => 'Vrai';

  @override
  String get riFalse => 'Faux';

  @override
  String get riPresent => 'Présent';

  @override
  String get riNotPresent => 'Absent';

  @override
  String get riSupported => 'Pris en charge';

  @override
  String get riNotSupported => 'Non pris en charge';

  @override
  String get riCurrent => 'Actuel';

  @override
  String get riOff => 'Désactivé';

  @override
  String riChannelValue(int number) {
    return 'Canal $number';
  }

  @override
  String riSeconds(int count) {
    return '$count seconde(s)';
  }

  @override
  String riMeters(String value) {
    return '$value mètres';
  }

  @override
  String riDegrees(String value) {
    return '$value degrés';
  }

  @override
  String get riProductId => 'ID de produit';

  @override
  String get riVendorId => 'ID de fournisseur';

  @override
  String get riDmrSupport => 'Prise en charge DMR';

  @override
  String get riGmrsSupport => 'Prise en charge GMRS';

  @override
  String get riHardwareSpeaker => 'Haut-parleur matériel';

  @override
  String get riHardwareVersion => 'Version matérielle';

  @override
  String get riSoftwareVersion => 'Version logicielle';

  @override
  String get riRegionCount => 'Nombre de régions';

  @override
  String get riMediumPower => 'Puissance moyenne';

  @override
  String get riChannelCount => 'Nombre de canaux';

  @override
  String get riNoaa => 'NOAA';

  @override
  String get riWeather => 'Météo';

  @override
  String riWeatherChannel(int number) {
    return 'Météo $number';
  }

  @override
  String get riBroadcastFm => 'Radio FM';

  @override
  String get riRadioLabel => 'Radio';

  @override
  String get riVfo => 'VFO';

  @override
  String get riFreqRangeCount => 'Nombre de plages de fréquences';

  @override
  String get riPowerOn => 'Sous tension';

  @override
  String get riInTx => 'En émission';

  @override
  String get riInRx => 'En réception';

  @override
  String get riDoubleChannelLabel => 'Double canal';

  @override
  String get riScanning => 'Balayage';

  @override
  String get riCurrentChannelId => 'ID du canal actuel';

  @override
  String get riGpsLockedLabel => 'GPS verrouillé';

  @override
  String get riHfpConnected => 'HFP connecté';

  @override
  String get riAocConnected => 'AOC connecté';

  @override
  String get riRssi => 'RSSI';

  @override
  String get riCurrentRegion => 'Région actuelle';

  @override
  String get riAccuracy => 'Précision';

  @override
  String get riReceivedTime => 'Heure de réception';

  @override
  String get riGpsTimeLocal => 'Heure GPS locale';

  @override
  String get riGpsTimeUtcLabel => 'Heure GPS UTC';

  @override
  String get tabDetach => 'Détacher...';

  @override
  String get tabClear => 'Effacer';

  @override
  String get tabSaveToFile => 'Enregistrer dans un fichier...';

  @override
  String get commonNoRadioConnected => 'Aucune radio connectée.';

  @override
  String errorOpeningFileDialog(String error) {
    return 'Erreur à l\'ouverture de la boîte de dialogue de fichier : $error';
  }

  @override
  String errorSavingFile(String error) {
    return 'Erreur lors de l\'enregistrement du fichier : $error';
  }

  @override
  String get debugSaveTitle => 'Enregistrer le journal de débogage';

  @override
  String debugLogSavedTo(String path) {
    return 'Journal de débogage enregistré dans $path';
  }

  @override
  String get debugShowBluetoothFrames => 'Afficher les trames Bluetooth';

  @override
  String get debugLoopbackMode => 'Mode boucle';

  @override
  String get debugQueryDeviceNames => 'Interroger les noms des appareils';

  @override
  String get debugRawCommand => 'Commande brute...';

  @override
  String get debugAutoScroll => 'Défilement automatique';

  @override
  String get debugFirmwareUpdate => 'Mise à jour du micrologiciel...';

  @override
  String get debugShowBuiltInMenus => 'Afficher les menus intégrés';

  @override
  String get packetsCopyHex => 'Copier le paquet HEX';

  @override
  String get packetsHexCopied => 'Paquet HEX copié dans le presse-papiers';

  @override
  String get packetsSaveTitle => 'Enregistrer la capture de paquets';

  @override
  String get packetsSaved => 'Capture de paquets enregistrée';

  @override
  String packetsSavedTo(String path) {
    return 'Capture de paquets enregistrée dans $path';
  }

  @override
  String get packetsShowDecode => 'Afficher le décodage des paquets';

  @override
  String get packetsEmpty => 'Aucun paquet capturé';

  @override
  String get packetsColTime => 'Heure';

  @override
  String get packetsColChannel => 'Canal';

  @override
  String get packetsColData => 'Données';

  @override
  String get commonAdd => 'Ajouter';

  @override
  String get commonEdit => 'Modifier';

  @override
  String get commonEditEllipsis => 'Modifier...';

  @override
  String get commonAddEllipsis => 'Ajouter...';

  @override
  String get commonExportEllipsis => 'Exporter...';

  @override
  String get commonImportEllipsis => 'Importer...';

  @override
  String get contactsTypeGeneric => 'Stations génériques';

  @override
  String get contactsTypeAprs => 'Stations APRS';

  @override
  String get contactsTypeTerminal => 'Stations Terminal';

  @override
  String get contactsTypeBbs => 'Stations BBS';

  @override
  String get contactsTypeWinlink => 'Stations Winlink';

  @override
  String get contactsTypeTorrent => 'Stations Torrent';

  @override
  String get contactsTypeAgwpe => 'Stations AGWPE';

  @override
  String get contactsExists =>
      'Une station avec cet indicatif et ce type existe déjà';

  @override
  String get contactsRemovePrompt => 'Supprimer la station sélectionnée ?';

  @override
  String get contactsNoExport => 'Aucune station à exporter';

  @override
  String get contactsExportTitle => 'Exporter les stations';

  @override
  String get contactsImportTitle => 'Importer les stations';

  @override
  String contactsExported(int count) {
    return '$count stations exportées';
  }

  @override
  String contactsImported(int count) {
    return '$count stations importées';
  }

  @override
  String get contactsUnableOpen => 'Impossible d\'ouvrir le carnet d\'adresses';

  @override
  String get contactsInvalid => 'Carnet d\'adresses invalide';

  @override
  String get contactsColCallsign => 'Indicatif';

  @override
  String get contactsColName => 'Nom';

  @override
  String get contactsColDescription => 'Description';

  @override
  String terminalHeaderWith(String callsign) {
    return 'Terminal - $callsign';
  }

  @override
  String get terminalNoRadio => 'Aucune radio disponible pour la connexion.';

  @override
  String get terminalShowCallsign => 'Afficher l\'indicatif';

  @override
  String get terminalWordWrap => 'Retour à la ligne';

  @override
  String get terminalWaitForConnection => 'Attendre une connexion...';

  @override
  String get terminalSend => 'Envoyer';

  @override
  String terminalConnectedTo(String callsign) {
    return 'Connecté à $callsign';
  }

  @override
  String terminalConnectingTo(String callsign) {
    return 'Connexion à $callsign...';
  }

  @override
  String get terminalInvalidCallsignDest => 'Indicatif/destination invalide';

  @override
  String get terminalInvalidCallsign => 'Indicatif invalide';

  @override
  String get terminalNotConnected => 'Non connecté';

  @override
  String terminalError(String error) {
    return 'Erreur : $error';
  }

  @override
  String get terminalBrotli =>
      'Paquet compressé Brotli reçu (non pris en charge)';

  @override
  String get audioSectionDevices => 'Périphériques';

  @override
  String get audioRefreshDevices => 'Actualiser la liste des périphériques';

  @override
  String get audioOutput => 'Sortie';

  @override
  String get audioInput => 'Entrée';

  @override
  String get audioVolume => 'Volume';

  @override
  String get audioSquelch => 'Squelch';

  @override
  String get audioSectionComputer => 'Ordinateur';

  @override
  String get audioApplication => 'Application';

  @override
  String get audioMaster => 'Principal';

  @override
  String get audioMicGain => 'Gain micro';

  @override
  String get audioMicNotAvailable =>
      'La capture du microphone n\'est pas disponible sur cette plateforme.';

  @override
  String get audioMicNotSupported =>
      'La capture du microphone n\'est pas prise en charge ici.';

  @override
  String get audioSpectRadio => 'Spectrographe radio';

  @override
  String get audioSpectMic => 'Spectrographe microphone';

  @override
  String get audioSpectNone => 'Spectrographe';

  @override
  String get audioSpectMenuNone => 'Aucun spectrographe';

  @override
  String get audioDartQuality => 'Qualité de réception DART';

  @override
  String get audioDartSignalAnalysis => 'Analyse du signal DART';

  @override
  String get audioDefault => 'Par défaut';

  @override
  String get audioMute => 'Muet';

  @override
  String get audioUnmute => 'Réactiver le son';

  @override
  String get audioEnable => 'Activer';

  @override
  String get audioDisable => 'Désactiver';

  @override
  String get audioNa => 'N/D';

  @override
  String get bbsHeaderActive => 'BBS - Actif';

  @override
  String get bbsActivate => 'Activer';

  @override
  String get bbsDeactivate => 'Désactiver';

  @override
  String get bbsViewTraffic => 'Afficher le trafic';

  @override
  String get bbsClearTraffic => 'Effacer le trafic';

  @override
  String get bbsClearStats => 'Effacer les statistiques';

  @override
  String get bbsColCallSign => 'Indicatif';

  @override
  String get bbsColLastSeen => 'Dernière activité';

  @override
  String get bbsColStats => 'Statistiques';

  @override
  String get bbsTraffic => 'Trafic';

  @override
  String get bbsJustNow => 'À l\'instant';

  @override
  String bbsMinAgo(int n) {
    return 'il y a $n min';
  }

  @override
  String bbsHoursAgo(int n) {
    return 'il y a $n h';
  }

  @override
  String bbsDaysAgo(int n) {
    return 'il y a $n j';
  }

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get torrentAddFile => 'Ajouter un fichier';

  @override
  String get torrentShowDetails => 'Afficher les détails';

  @override
  String get torrentFileSaved => 'Fichier enregistré.';

  @override
  String get torrentFileDataUnavailable =>
      'Erreur d\'enregistrement : données du fichier non disponibles';

  @override
  String get torrentUnknownError => 'Erreur inconnue';

  @override
  String get torrentSaveTitle => 'Enregistrer le fichier torrent';

  @override
  String get torrentNoRadios =>
      'Aucune radio connectée. Connectez d\'abord une radio.';

  @override
  String get torrentMultiRadio =>
      'Le mode torrent multi-radio n\'est pas encore pris en charge.';

  @override
  String get torrentDropSingle => 'Veuillez déposer un seul fichier.';

  @override
  String get torrentDeletePrompt =>
      'Supprimer le fichier torrent sélectionné ?';

  @override
  String get torrentPause => 'Pause';

  @override
  String get torrentShare => 'Partager';

  @override
  String get torrentRequest => 'Demander';

  @override
  String get torrentSaveAs => 'Enregistrer sous...';

  @override
  String get torrentDropToShare => 'Déposez un fichier à partager';

  @override
  String get torrentNoFiles =>
      'Aucun fichier torrent. Ajoutez ou déposez un fichier à partager.';

  @override
  String get torrentUnknownSource => 'Inconnu';

  @override
  String get torrentColFile => 'Fichier';

  @override
  String get torrentColMode => 'Mode';

  @override
  String get torrentDetailFileName => 'Nom du fichier';

  @override
  String get torrentDetailSource => 'Source';

  @override
  String get torrentDetailFileSize => 'Taille du fichier';

  @override
  String torrentBytes(int count) {
    return '$count octets';
  }

  @override
  String get torrentDetailCompression => 'Compression';

  @override
  String get torrentDetailBlocks => 'Blocs';

  @override
  String get torrentDetailsTitle => 'Détails du torrent';

  @override
  String get torrentSelectPrompt =>
      'Sélectionnez un torrent pour afficher les détails';

  @override
  String get torrentModePaused => 'En pause';

  @override
  String get torrentModeSharing => 'Partage';

  @override
  String get torrentModeRequesting => 'Demande en cours';

  @override
  String get torrentModeError => 'Erreur';

  @override
  String get torrentCompUnknown => 'Inconnu';

  @override
  String get mailInbox => 'Boîte de réception';

  @override
  String get mailOutbox => 'Boîte d\'envoi';

  @override
  String get mailDraft => 'Brouillon';

  @override
  String get mailSent => 'Envoyés';

  @override
  String get mailArchive => 'Archive';

  @override
  String get mailTrash => 'Corbeille';

  @override
  String get mailInternet => 'Internet';

  @override
  String get mailDeleteTitle => 'Supprimer le courrier';

  @override
  String get mailMoveToTrashTitle => 'Déplacer vers la corbeille';

  @override
  String get mailDeletePermanent =>
      'Supprimer définitivement le courrier sélectionné ? Cette action est irréversible.';

  @override
  String get mailMoveToTrashPrompt =>
      'Déplacer le courrier sélectionné vers la corbeille ?';

  @override
  String get mailMove => 'Déplacer';

  @override
  String get mailOpen => 'Ouvrir';

  @override
  String get mailReply => 'Répondre';

  @override
  String get mailReplyAll => 'Répondre à tous';

  @override
  String get mailForward => 'Transférer';

  @override
  String get mailShowPreview => 'Afficher l\'aperçu';

  @override
  String get mailBackup => 'Sauvegarder le courrier...';

  @override
  String get mailRestore => 'Restaurer le courrier...';

  @override
  String get mailShowTraffic => 'Afficher le trafic...';

  @override
  String mailBackupFailed(String error) {
    return 'Échec de la sauvegarde : $error';
  }

  @override
  String get mailBackupTitle => 'Sauvegarder le courrier';

  @override
  String get mailBackupSuccess => 'Sauvegarde terminée avec succès.';

  @override
  String get mailRestoreTitle => 'Restaurer le courrier';

  @override
  String get mailRestoreUnableOpen =>
      'Impossible d\'ouvrir le fichier de sauvegarde';

  @override
  String mailRestoreFailed(String error) {
    return 'Échec de la restauration : $error';
  }

  @override
  String get mailNew => 'Nouveau';

  @override
  String get mailNewMail => 'Nouveau courrier';

  @override
  String get mailColTime => 'Heure';

  @override
  String get mailColTo => 'À';

  @override
  String get mailColFrom => 'De';

  @override
  String get mailColSubject => 'Objet';

  @override
  String get mailSelectPreview => 'Sélectionnez un message pour l\'aperçu';

  @override
  String get commonUnknown => 'Inconnu';

  @override
  String get mapOfflineMode => 'Mode hors ligne';

  @override
  String get mapOfflineMap => 'Carte hors ligne';

  @override
  String get mapCacheArea => 'Mettre en cache la zone...';

  @override
  String get mapCenterGps => 'Centrer sur le GPS';

  @override
  String get mapShowTracks => 'Afficher les traces';

  @override
  String get mapShowMarkers => 'Afficher les marqueurs';

  @override
  String get mapShowAirplanes => 'Afficher les avions';

  @override
  String get mapLargeMarkers => 'Grands marqueurs';

  @override
  String get mapShowContactsOnly => 'Afficher uniquement les contacts';

  @override
  String get mapFilterAll => 'Tout';

  @override
  String get mapFilterLast30 => '30 dernières minutes';

  @override
  String get mapFilterLastHour => 'Dernière heure';

  @override
  String get mapFilterLast6 => '6 dernières heures';

  @override
  String get mapFilterLast12 => '12 dernières heures';

  @override
  String get mapFilterLast24 => '24 dernières heures';

  @override
  String get mapCacheTitle => 'Mettre en cache la zone de carte';

  @override
  String mapCachePrompt(int count, int minZoom, int maxZoom) {
    return 'Télécharger $count tuiles pour les niveaux de zoom $minZoom–$maxZoom ?\n\nCela mettra la zone sélectionnée en cache pour une utilisation hors ligne.';
  }

  @override
  String get mapDownloadingTitle => 'Téléchargement des tuiles';

  @override
  String mapTilesProgress(int done, int total) {
    return '$done / $total tuiles';
  }

  @override
  String get mapDragToSelect =>
      'Faites glisser pour sélectionner la zone à mettre en cache';

  @override
  String get aprsNoChannel =>
      'Aucune radio avec un canal APRS n\'est disponible';

  @override
  String get aprsNoLoadedChannels =>
      'Aucune radio avec des canaux chargés n\'est disponible';

  @override
  String get aprsDetails => 'Détails...';

  @override
  String get aprsShowLocation => 'Afficher la position...';

  @override
  String get aprsSetReceiver => 'Définir comme destinataire';

  @override
  String get aprsCopyMessage => 'Copier le message';

  @override
  String get aprsCopyCallsign => 'Copier l\'indicatif';

  @override
  String get aprsCopyChannel => 'Copier le canal';

  @override
  String get aprsClearTitle => 'Effacer les messages APRS';

  @override
  String get aprsClearPrompt =>
      'Effacer tous les messages APRS ? Cela supprime également tous les marqueurs APRS de la carte. Cette action est irréversible.';

  @override
  String get aprsShowAll => 'Afficher tous les messages';

  @override
  String get aprsSendSms => 'Envoyer un message SMS...';

  @override
  String get aprsWeatherReport => 'Rapport météo...';

  @override
  String get aprsBeaconSettingsMenu => 'Paramètres de balise...';

  @override
  String get aprsDropShare => 'Déposez pour partager ce canal';

  @override
  String get aprsBeaconWarning =>
      'La diffusion de balise est activée sur le canal actuel, ce qui n\'est pas recommandé.';

  @override
  String aprsBeaconActive(String interval) {
    return 'La balise radio est active, intervalle : $interval.';
  }

  @override
  String get aprsBeaconSettings => 'Paramètres de balise';

  @override
  String aprsIntervalSeconds(int count) {
    return '$count secondes';
  }

  @override
  String get aprsIntervalMinute => '1 minute';

  @override
  String aprsIntervalMinutes(int count) {
    return '$count minutes';
  }

  @override
  String get aprsMissingChannel =>
      'Aucun canal « APRS » n\'est configuré sur la radio connectée. Ajoutez un canal APRS pour envoyer et recevoir des messages APRS.';

  @override
  String get aprsSetup => 'Configurer';

  @override
  String get aprsTypeMessage => 'Saisissez un message...';

  @override
  String get commonYes => 'Oui';

  @override
  String get commonNo => 'Non';

  @override
  String get commonSend => 'Envoyer';

  @override
  String commonSavedTo(String path) {
    return 'Enregistré dans $path';
  }

  @override
  String commsFailedLoadImage(String error) {
    return 'Échec du chargement de l\'image : $error';
  }

  @override
  String commsFailedSaveImage(String error) {
    return 'Échec de l\'enregistrement de l\'image : $error';
  }

  @override
  String commsFailedEncodeSstv(String error) {
    return 'Échec de l\'encodage audio SSTV : $error';
  }

  @override
  String commsFailedLoadAudio(String error) {
    return 'Échec du chargement de l\'audio : $error';
  }

  @override
  String get commsUnsupportedWav => 'Fichier WAV non pris en charge ou vide.';

  @override
  String get commsSstvWebUnavailable =>
      'L\'enregistrement/la transmission d\'images SSTV n\'est pas disponible sur le Web.';

  @override
  String get commsNoRadioVoice =>
      'Aucune radio n\'est connectée pour la transmission vocale.';

  @override
  String get commsSelectImageTitle => 'Sélectionner une image pour le SSTV';

  @override
  String get commsSelectWavTitle => 'Sélectionner un fichier audio WAV';

  @override
  String get commsRecordingWebUnavailable =>
      'La lecture d\'enregistrements à partir de fichiers n\'est pas disponible sur le Web.';

  @override
  String get commsFileNoLongerExists => 'Le fichier n\'existe plus.';

  @override
  String get commsSaveAsTitle => 'Enregistrer sous';

  @override
  String get commsTransmitDisabledAprs =>
      'La transmission est désactivée lorsque le VFO A est réglé sur le canal APRS.';

  @override
  String get commsWaitTransmission =>
      'Veuillez attendre la fin de la transmission en cours.';

  @override
  String get commsConnectRadioChat =>
      'Connectez une radio avant d\'envoyer un message de discussion.';

  @override
  String get commsEnableAudioMode =>
      'Activez l\'audio (le bouton Activer) avant d\'envoyer dans ce mode.';

  @override
  String get commsMicNotSupported =>
      'La capture du microphone n\'est pas prise en charge sur cette plateforme.';

  @override
  String get commsConnectRadioPtt =>
      'Connectez une radio avant d\'utiliser la fonction push-to-talk.';

  @override
  String get commsEnableAudioPtt =>
      'Activez l\'audio (le bouton Activer) avant d\'utiliser la fonction push-to-talk.';

  @override
  String get commsSwitchChatShare =>
      'Passez en mode Chat pour partager un canal.';

  @override
  String get commsModePtt => 'PTT';

  @override
  String get commsModeChat => 'Chat';

  @override
  String get commsModeSpeak => 'Parler';

  @override
  String get commsModeMorse => 'Morse';

  @override
  String get commsModeDtmf => 'DTMF';

  @override
  String get commsRecordAudio => 'Enregistrer l\'audio';

  @override
  String get commsSendImage => 'Envoyer une image...';

  @override
  String get commsSendAudio => 'Envoyer un audio...';

  @override
  String get commsPttReleaseSettings => 'Paramètres de relâchement PTT...';

  @override
  String get commsClearHistory => 'Effacer l\'historique';

  @override
  String get commsShowImage => 'Afficher l\'image...';

  @override
  String get commsPlayRecording => 'Lire l\'enregistrement...';

  @override
  String get commsSaveAsMenu => 'Enregistrer sous...';

  @override
  String get commsShowLocation => 'Afficher la position';

  @override
  String get commsClearHistoryPrompt =>
      'Voulez-vous vraiment effacer l\'historique vocal ?';

  @override
  String get commsAudioMuted => 'L\'audio est en sourdine.';

  @override
  String get commsUnmute => 'Réactiver le son';

  @override
  String get commsPttTransmitting => 'Transmission en cours...';

  @override
  String get commsPttHold => 'PTT - Maintenir pour transmettre';

  @override
  String get commsDtmfHint => 'Saisissez des chiffres DTMF (0-9, *, #)...';

  @override
  String get mailComposeNewTitle => 'Nouveau message';

  @override
  String get mailComposeEditTitle => 'Modifier le message';

  @override
  String get mailDiscardChanges => 'Ignorer les modifications de ce message ?';

  @override
  String get mailDiscardMessage => 'Ignorer ce message ?';

  @override
  String get mailDiscard => 'Ignorer';

  @override
  String get mailAddCc => 'Ajouter Cc';

  @override
  String get mailCc => 'Cc';

  @override
  String get mailRemoveCc => 'Supprimer Cc';

  @override
  String get mailMessageLabel => 'Message';

  @override
  String get mailSaveDraft => 'Enregistrer le brouillon';

  @override
  String get smsTitle => 'Envoyer un message SMS';

  @override
  String get smsPhoneNumber => 'Numéro de téléphone';

  @override
  String get smsIntro =>
      'Vous pouvez envoyer des SMS vers des téléphones aux États-Unis, à Porto Rico, au Canada, en Australie et au Royaume-Uni, à condition que le numéro ait déjà accepté le service. Vous pouvez vous inscrire sur : ';

  @override
  String get locationTitle => 'Position';

  @override
  String get beaconIntro =>
      'Modifiez la façon dont la radio diffuse des informations sur elle-même, notamment la position, la tension et un message personnalisé. Les autres stations à proximité pourront voir ces informations.';

  @override
  String beaconRadio(String name) {
    return 'Radio : $name';
  }

  @override
  String get beaconSection => 'Balise';

  @override
  String get beaconPacketFormat => 'Format de paquet';

  @override
  String get beaconInterval => 'Intervalle de balise';

  @override
  String get beaconAprsCallsign => 'Indicatif APRS';

  @override
  String get beaconCallsignHint => 'Indicatif - ID de station';

  @override
  String get beaconCallsignInvalid =>
      'Saisissez un indicatif et un ID de station valides (ex. W1AW-5)';

  @override
  String get beaconAprsMessage => 'Message APRS';

  @override
  String get beaconShareLocation => 'Partager la position';

  @override
  String get beaconSendVoltage => 'Envoyer la tension';

  @override
  String get beaconAllowPositionCheck =>
      'Autoriser la vérification de position';

  @override
  String get beaconChannelCurrent => 'Actuel (non recommandé)';

  @override
  String beaconEverySeconds(int n) {
    return 'Toutes les $n secondes';
  }

  @override
  String beaconEveryMinutes(int n) {
    return 'Toutes les $n minutes';
  }

  @override
  String get assConnectTerminal => 'Se connecter à la station Terminal';

  @override
  String get assConnectBbs => 'Se connecter à la station BBS';

  @override
  String get assConnectWinlink => 'Se connecter à la passerelle Winlink';

  @override
  String get assConnectStation => 'Se connecter à la station';

  @override
  String get assNew => 'Nouveau…';

  @override
  String get attSelectFile => 'Sélectionner un fichier à partager';

  @override
  String get attCompressing => 'Compression...';

  @override
  String get attTitle => 'Ajouter un fichier torrent';

  @override
  String get attSelect => 'Sélectionner...';

  @override
  String get attDescriptionOptional => 'Description (facultative)';

  @override
  String get stationTitleVoice => 'Station vocale';

  @override
  String get stationTitleAprs => 'Station APRS';

  @override
  String get stationTitleTerminal => 'Station terminal';

  @override
  String get stationTitleWinlink => 'Passerelle Winlink';

  @override
  String get stationTitleGeneric => 'Station';

  @override
  String get stationTypeOptionVoice => 'Station vocale / générique';

  @override
  String get stationTypeLabel => 'Type de station';

  @override
  String get stationAprsRoute => 'Route APRS';

  @override
  String get stationUseAuth => 'Utiliser l\'authentification des messages';

  @override
  String get stationAuthPassword => 'Mot de passe d\'authentification';

  @override
  String get stationPasswordRequired => 'Mot de passe requis';

  @override
  String get stationTerminalProtocol => 'Protocole terminal';

  @override
  String get stationAx25Destination => 'Destination AX.25 (ex. CALL-1)';

  @override
  String get stationAx25Invalid => 'Adresse AX.25 non valide';

  @override
  String get stationModem => 'Modem';

  @override
  String get apdTitle => 'Détails du paquet APRS';

  @override
  String get apdCopyAll => 'Tout copier';

  @override
  String get apdCopyValue => 'Copier la valeur';

  @override
  String get apdValueCopied => 'Valeur copiée';

  @override
  String get apdAllValuesCopied => 'Toutes les valeurs copiées';

  @override
  String get apdNoDetails => 'Aucun détail disponible.';

  @override
  String get apdShowLocation => 'Afficher l\'emplacement...';

  @override
  String get acfgTitle => 'Configurer le canal APRS';

  @override
  String get acfgIntro =>
      'La fréquence APRS varie selon la région du monde. Utilisez ce site pour trouver la fréquence appropriée afin de configurer le canal APRS.';

  @override
  String get acfgConfiguration => 'Configuration APRS';

  @override
  String get acfgFrequency => 'Fréquence';

  @override
  String get acfgFrequencyHint =>
      '144.39 en Amérique du Nord\n144.80 en Europe';

  @override
  String get acfgChannelOverwritten => 'Le canal sélectionné sera écrasé';

  @override
  String get sstvSendTitle => 'Envoyer une image SSTV';

  @override
  String sstvSendTitleNamed(String name) {
    return 'Envoyer une image SSTV - $name';
  }

  @override
  String get sstvMode => 'Mode :';

  @override
  String sstvTransmitTime(String time) {
    return 'Temps de transmission : ~$time';
  }

  @override
  String get msgdTitle => 'Détails du message';

  @override
  String get msgdFieldType => 'Type';

  @override
  String get msgdFieldDirection => 'Direction';

  @override
  String get msgdFieldTime => 'Heure';

  @override
  String get msgdFieldSource => 'Source';

  @override
  String get msgdFieldReceiver => 'Destinataire';

  @override
  String get msgdFieldDuration => 'Durée';

  @override
  String get msgdFieldLatitude => 'Latitude';

  @override
  String get msgdFieldLongitude => 'Longitude';

  @override
  String get msgdFieldMessage => 'Message';

  @override
  String get msgdFieldFile => 'Fichier';

  @override
  String get msgdDirReceived => 'Reçu';

  @override
  String get msgdDirSent => 'Envoyé';

  @override
  String get msgdTypeVoice => 'Voix';

  @override
  String get msgdTypeVoiceClip => 'Clip vocal';

  @override
  String get msgdTypeRecording => 'Enregistrement';

  @override
  String get msgdTypeSstvPicture => 'Image SSTV';

  @override
  String get msgdTypeIdentification => 'Identification';

  @override
  String get msgdTypeChatMessage => 'Message de discussion';

  @override
  String get msgdTypeAx25Packet => 'Paquet AX.25';

  @override
  String get rpbFailedToLoad => 'Échec du chargement de l\'enregistrement.';

  @override
  String get ivwFailedToLoad => 'Échec du chargement de l\'image.';

  @override
  String get rawTitle => 'Commande radio brute';

  @override
  String get rawCommand => 'Commande';

  @override
  String get rawHexPayload => 'Charge utile HEX (facultative)';

  @override
  String get rawResponse => 'Réponse';

  @override
  String get identTitle => 'Paramètres de relâchement PTT';

  @override
  String get identDescription =>
      'Si activé, envoie votre indicatif et/ou vos informations de localisation chaque fois que vous relâchez le PTT sur le canal sur lequel vous transmettez.';

  @override
  String get identCallsignHint => 'Saisir l\'indicatif - ID de station';

  @override
  String get identSendCallsign => 'Envoyer l\'indicatif';

  @override
  String get identSendPosition => 'Envoyer la position';

  @override
  String get commonOn => 'Activé';

  @override
  String get commonOff => 'Désactivé';

  @override
  String get commonNone => 'Aucun';

  @override
  String chChannelNumber(int n) {
    return 'Canal $n';
  }

  @override
  String chChShort(int n) {
    return 'Canal $n';
  }

  @override
  String get chMoreSettings => 'Plus de paramètres';

  @override
  String get chChannelNameHint => 'Nom du canal';

  @override
  String get chFrequencyMhz => 'Fréquence (MHz)';

  @override
  String get chReceiveMhz => 'Réception (MHz)';

  @override
  String get chTransmitMhz => 'Émission (MHz)';

  @override
  String get chMode => 'Mode';

  @override
  String get chPower => 'Puissance';

  @override
  String get chBandwidth => 'Largeur de bande';

  @override
  String get chReceiveTone => 'Tonalité de réception (CTCSS / DCS)';

  @override
  String get chTransmitTone => 'Tonalité d\'émission (CTCSS / DCS)';

  @override
  String get chDisableTransmit => 'Désactiver l\'émission';

  @override
  String get chMute => 'Muet';

  @override
  String get chScan => 'Balayage';

  @override
  String get chTalkAround => 'Talk around';

  @override
  String get chDeemphasis => 'Désaccentuation';

  @override
  String get chPowerHigh => 'Élevée';

  @override
  String get chPowerMedium => 'Moyenne';

  @override
  String get chPowerLow => 'Faible';

  @override
  String get chBandwidthWide => '25 KHz large';

  @override
  String get chBandwidthNarrow => '12.5 KHz étroite';

  @override
  String get chClearTitle => 'Effacer le canal';

  @override
  String chClearConfirm(int n) {
    return 'Effacer le canal $n ?\n\nCeci supprime la fréquence, le nom et les paramètres de cet emplacement sur la radio.';
  }

  @override
  String get cdRxFrequency => 'Fréquence RX';

  @override
  String get cdTxFrequency => 'Fréquence TX';

  @override
  String get cdRxModulation => 'Modulation RX';

  @override
  String get cdTxModulation => 'Modulation TX';

  @override
  String get cdRxTone => 'Tonalité RX';

  @override
  String get cdTxTone => 'Tonalité TX';

  @override
  String get cdTxDisabled => 'Émission désactivée';

  @override
  String get cdTalkAround => 'Talk around';

  @override
  String get cdEmpty => '(vide)';

  @override
  String get cdBandwidthWide => '25 kHz (large)';

  @override
  String get cdBandwidthNarrow => '12.5 kHz (étroite)';

  @override
  String get gpsDetailsTitle => 'Détails GPS';

  @override
  String get gpsDisabled => 'GPS désactivé';

  @override
  String get gpsLock => 'Verrouillage GPS';

  @override
  String get gpsNoLock => 'Aucun verrouillage GPS';

  @override
  String get mdbgTitle => 'Trafic Winlink';

  @override
  String get mdbgNoTraffic => 'Aucun trafic pour le moment.';

  @override
  String get fwTitle => 'Mise à jour du micrologiciel de la radio';

  @override
  String get fwStatusInitial =>
      'Recherchez une mise à jour du micrologiciel en ligne, ou chargez un fichier de micrologiciel depuis le disque.';

  @override
  String get fwErrNotConnected => 'La radio n\'est pas connectée.';

  @override
  String get fwErrNoDeviceInfo =>
      'Les informations de l\'appareil radio ne sont pas encore disponibles.';

  @override
  String get fwStatusChecking =>
      'Recherche d\'une mise à jour du micrologiciel…';

  @override
  String get fwErrNoServerInfo =>
      'Le serveur du fournisseur n\'a pas renvoyé d\'informations sur le micrologiciel.';

  @override
  String fwUpdateAvailable(String version) {
    return 'Une mise à jour du micrologiciel est disponible $version. Consultez les notes de version ci-dessous, puis téléchargez pour mettre à jour.';
  }

  @override
  String fwErrCheckFailed(String error) {
    return 'Échec de la recherche de mise à jour : $error';
  }

  @override
  String get fwPickTitle => 'Sélectionner un fichier de micrologiciel';

  @override
  String fwLoaded(String name, String size, String md5) {
    return '$name chargé : $size (MD5 $md5…).';
  }

  @override
  String fwErrLoadFailed(String error) {
    return 'Impossible de charger le fichier de micrologiciel : $error';
  }

  @override
  String get fwSaveTitle => 'Enregistrer le fichier de micrologiciel';

  @override
  String fwSavedTo(String path) {
    return 'Micrologiciel enregistré dans $path';
  }

  @override
  String fwErrSaveFailed(String error) {
    return 'Impossible d\'enregistrer le fichier de micrologiciel : $error';
  }

  @override
  String get fwStatusDownloading =>
      'Téléchargement et assemblage du micrologiciel…';

  @override
  String get fwProgressStarting => 'Démarrage…';

  @override
  String fwReady(String size, String md5) {
    return 'Micrologiciel prêt : $size (MD5 $md5…).';
  }

  @override
  String fwErrDownloadFailed(String error) {
    return 'Échec du téléchargement : $error';
  }

  @override
  String get fwStatusWriting =>
      'Écriture du micrologiciel sur la radio. Ne l\'éteignez pas.';

  @override
  String get fwProgressTransferring => 'Transfert…';

  @override
  String fwErrTransferFailed(String error) {
    return 'Échec du transfert du micrologiciel : $error';
  }

  @override
  String get fwStatusRebooting => 'La radio redémarre. Reconnexion…';

  @override
  String get fwProgressWaitingRestart =>
      'En attente du redémarrage de la radio…';

  @override
  String fwErrReconnectFailed(String error) {
    return 'Échec de la reconnexion après le redémarrage : $error';
  }

  @override
  String get fwErrReconnectNull =>
      'Impossible de se reconnecter à la radio après son redémarrage. Le micrologiciel a été transféré mais non confirmé. Reconnectez-vous manuellement et réessayez.';

  @override
  String get fwStatusFinalising => 'Finalisation de la mise à jour…';

  @override
  String get fwProgressConfirming => 'Confirmation…';

  @override
  String fwErrConfirmFailed(String error) {
    return 'Échec de la confirmation de la mise à jour : $error';
  }

  @override
  String get fwStatusComplete =>
      'Mise à jour du micrologiciel terminée ! La radio exécute maintenant le nouveau micrologiciel.';

  @override
  String get fwProgressDownloadPatch => 'Téléchargement du correctif';

  @override
  String get fwProgressDownloadBase => 'Téléchargement de l\'image de base';

  @override
  String get fwProgressAssemble => 'Assemblage du micrologiciel';

  @override
  String fwProgressBytes(String label, String done, String total) {
    return '$label ($done / $total)';
  }

  @override
  String fwProgressTransferringBytes(String done, String total) {
    return 'Transfert ($done / $total)';
  }

  @override
  String fwCurrentFirmware(String version) {
    return 'Micrologiciel actuel : $version';
  }

  @override
  String get fwErrGeneric => 'Une erreur s\'est produite.';

  @override
  String get fwIdleDisclosure =>
      'La vérification en ligne contacte le serveur du fournisseur de la radio (rpc.benshikj.com) et n\'envoie que l\'identifiant de produit de votre radio. Rien n\'est envoyé tant que vous n\'appuyez pas sur Rechercher une mise à jour.';

  @override
  String get fwWhatsNew => 'Nouveautés';

  @override
  String get fwConfirmWarning =>
      'Avertissement : gardez la radio allumée, chargée et à portée Bluetooth pendant tout le processus. La radio redémarrera en cours de route. Interrompre la mise à jour peut nécessiter une récupération manuelle.';

  @override
  String get fwFromFile => 'Depuis un fichier…';

  @override
  String get fwCheckForUpdate => 'Rechercher une mise à jour';

  @override
  String get fwDownload => 'Télécharger';

  @override
  String get fwSave => 'Enregistrer…';

  @override
  String get fwFlashNow => 'Flasher maintenant';

  @override
  String get fwRetry => 'Réessayer';

  @override
  String get wxTitle => 'Demander un bulletin météo';

  @override
  String get wxIntro => 'Demandez un bulletin météo via APRS. ';

  @override
  String get wxLocation => 'Emplacement';

  @override
  String get wxLocationHelper =>
      'Ville/état US ou code postal US, ou coordonnées 41.123/-121.334';

  @override
  String get wxTime => 'Moment';

  @override
  String get wxReport => 'Rapport';

  @override
  String get wxToday => 'Aujourd\'hui';

  @override
  String get wxTonight => 'Ce soir';

  @override
  String get wxTomorrow => 'Demain';

  @override
  String get wxTomorrowNight => 'Demain soir';

  @override
  String get wxMonday => 'Lundi';

  @override
  String get wxMondayNight => 'Lundi soir';

  @override
  String get wxTuesday => 'Mardi';

  @override
  String get wxTuesdayNight => 'Mardi soir';

  @override
  String get wxWednesday => 'Mercredi';

  @override
  String get wxWednesdayNight => 'Mercredi soir';

  @override
  String get wxThursday => 'Jeudi';

  @override
  String get wxThursdayNight => 'Jeudi soir';

  @override
  String get wxFriday => 'Vendredi';

  @override
  String get wxFridayNight => 'Vendredi soir';

  @override
  String get wxSaturday => 'Samedi';

  @override
  String get wxSaturdayNight => 'Samedi soir';

  @override
  String get wxSunday => 'Dimanche';

  @override
  String get wxSundayNight => 'Dimanche soir';

  @override
  String get wxReportBrief => 'Bref, Prévision courte, US uniquement';

  @override
  String get wxReportFull => 'Complet, Prévision plus détaillée, US uniquement';

  @override
  String get wxReportCurrent =>
      'Actuel, Station NWS la plus proche, US uniquement';

  @override
  String get wxReportMetar => 'METAR, Station OACI au format METAR';

  @override
  String get wxReportCwop => 'CWOP, Station CWOP la plus proche';
}
