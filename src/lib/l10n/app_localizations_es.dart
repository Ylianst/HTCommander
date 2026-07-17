// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Handi-Talkie Commander';

  @override
  String get menuFile => 'Archivo';

  @override
  String get menuConnect => 'Conectar...';

  @override
  String get menuDisconnect => 'Desconectar';

  @override
  String get menuSettings => 'Configuración...';

  @override
  String get menuExit => 'Salir';

  @override
  String get menuRadios => 'Radios';

  @override
  String get menuDualWatch => 'Doble escucha';

  @override
  String get menuScan => 'Escaneo';

  @override
  String get menuRegions => 'Regiones';

  @override
  String get menuTrustedDevices => 'Dispositivos de confianza...';

  @override
  String get menuButtons => 'Botones...';

  @override
  String get menuFmRadio => 'Radio FM...';

  @override
  String get menuExportChannels => 'Exportar canales...';

  @override
  String get menuImportChannels => 'Importar canales...';

  @override
  String get menuMacRadio => 'Radio';

  @override
  String get menuMacDisplay => 'Pantalla';

  @override
  String get fmRadioTitle => 'Radio FM';

  @override
  String fmRadioMhz(String value) {
    return '${value}MHz';
  }

  @override
  String get fmRadioOff => 'Apagada';

  @override
  String get fmRadioPowerTooltip => 'Encender o apagar la radio FM';

  @override
  String get fmRadioSeekDownTooltip => 'Buscar hacia abajo';

  @override
  String get fmRadioStepDownTooltip => 'Bajar frecuencia';

  @override
  String get fmRadioStopTooltip => 'Apagar';

  @override
  String get fmRadioStepUpTooltip => 'Subir frecuencia';

  @override
  String get fmRadioSeekUpTooltip => 'Buscar hacia arriba';

  @override
  String get fmRadioStationsHeader => 'Emisoras preferidas';

  @override
  String get fmRadioAddStationTooltip => 'Añadir la frecuencia actual';

  @override
  String get fmRadioNoStations => 'No hay emisoras preferidas';

  @override
  String get fmRadioStationNameLabel => 'Nombre de la emisora';

  @override
  String get fmRadioRenameTitle => 'Nombre de la emisora';

  @override
  String get fmRadioDeleteTitle => 'Eliminar emisora';

  @override
  String fmRadioDeleteMessage(String name) {
    return '¿Quitar «$name» de tus emisoras preferidas?';
  }

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonOk => 'Aceptar';

  @override
  String get aboutCheckForUpdates => 'Buscar actualizaciones';

  @override
  String aboutVersionAuthor(String version) {
    return 'Versión $version\nYlian Saint-Hilaire, KK7VZT\nCódigo abierto, licencia Apache 2.0';
  }

  @override
  String get settingsLanguage => 'Idioma';

  @override
  String get settingsLanguageHint =>
      'Elija el idioma que usa la aplicación. «Predeterminado del sistema» sigue el idioma de su dispositivo.';

  @override
  String get settingsThemeMode => 'Tema';

  @override
  String get settingsThemeModeHint =>
      'Elija la apariencia clara u oscura. «Predeterminado del sistema» sigue la configuración de su dispositivo.';

  @override
  String get settingsThemeModeSystem => 'Predeterminado del sistema';

  @override
  String get settingsThemeModeLight => 'Claro';

  @override
  String get settingsThemeModeDark => 'Oscuro';

  @override
  String get languageSystem => 'Predeterminado del sistema';

  @override
  String get languageEnglish => 'Inglés';

  @override
  String get languageFrench => 'Francés';

  @override
  String get languageSpanish => 'Español';

  @override
  String get languageChinese => 'Chino';

  @override
  String get languageJapanese => 'Japonés';

  @override
  String get languageHindi => 'Hindi';

  @override
  String get languageGerman => 'Alemán';

  @override
  String get languagePolish => 'Polaco';

  @override
  String get menuAudio => 'Audio';

  @override
  String get menuAudioEnabled => 'Audio activado';

  @override
  String get menuSoftwareModem => 'Módem por software';

  @override
  String get menuModemDisabled => 'Desactivado';

  @override
  String get menuDartTransmitLevel => 'Nivel de transmisión DART';

  @override
  String get menuDartLevel0 => 'Nivel 0 (BPSK, LDPC 1/2)';

  @override
  String get menuDartLevel1 => 'Nivel 1 (QPSK, LDPC 1/2)';

  @override
  String get menuDartLevel2 => 'Nivel 2 (QPSK, LDPC 2/3)';

  @override
  String get menuDartLevel3 => 'Nivel 3 (8PSK, LDPC 2/3)';

  @override
  String get menuDartLevel4 => 'Nivel 4 (16QAM, LDPC 3/4)';

  @override
  String get menuDartLevel5 => 'Nivel 5 (16QAM, LDPC 5/6)';

  @override
  String get menuDartLevelF => 'Nivel F (4-FSK, LDPC 1/2)';

  @override
  String get menuAprsModem => 'Módem APRS';

  @override
  String get menuView => 'Ver';

  @override
  String get menuRadio => 'Radio';

  @override
  String get menuTabs => 'Pestañas';

  @override
  String get menuTabNames => 'Nombres de pestañas';

  @override
  String get menuShowAllTabs => 'Mostrar todas las pestañas';

  @override
  String get menuAllChannels => 'Todos los canales';

  @override
  String get menuChannelFrequency => 'Frecuencia del canal';

  @override
  String get menuHelp => 'Ayuda';

  @override
  String get menuRadioInformation => 'Información de la radio...';

  @override
  String get menuGpsInformation => 'Información GPS...';

  @override
  String get menuCheckForUpdatesEllipsis => 'Buscar actualizaciones...';

  @override
  String get menuAbout => 'Acerca de...';

  @override
  String get tabComms => 'Comunicaciones';

  @override
  String get tabAudio => 'Audio';

  @override
  String get tabAprs => 'APRS';

  @override
  String get tabMap => 'Mapa';

  @override
  String get tabMail => 'Correo';

  @override
  String get tabTerminal => 'Terminal';

  @override
  String get tabContacts => 'Contactos';

  @override
  String get tabBbs => 'BBS';

  @override
  String get tabTorrent => 'Torrent';

  @override
  String get tabPackets => 'Paquetes';

  @override
  String get tabDebug => 'Depuración';

  @override
  String get tabRadio => 'Radio';

  @override
  String get stateDisconnected => 'Desconectado';

  @override
  String get stateConnecting => 'Conectando...';

  @override
  String get stateConnected => 'Conectado';

  @override
  String get stateUnableToConnect => 'No se puede conectar';

  @override
  String get stateAccessDenied => 'Acceso denegado';

  @override
  String get stateSelectRadio => 'Seleccionar una radio';

  @override
  String statusBattery(int percent) {
    return 'Batería: $percent %';
  }

  @override
  String get statusCheckingBluetooth => 'Comprobando Bluetooth...';

  @override
  String get statusBluetoothNotAvailable => 'Bluetooth no disponible';

  @override
  String get statusScanningForRadios => 'Buscando radios...';

  @override
  String get statusErrorScanning => 'Error al buscar radios';

  @override
  String get statusNoCompatibleRadios => 'No se encontraron radios compatibles';

  @override
  String get statusAllRadiosConnected => 'Todas las radios ya están conectadas';

  @override
  String statusConnectingTo(String name) {
    return 'Conectando a $name...';
  }

  @override
  String statusConnectedTo(String name) {
    return 'Conectado a $name';
  }

  @override
  String statusFailedToConnect(String name) {
    return 'Error al conectar a $name';
  }

  @override
  String get statusDisconnecting => 'Desconectando...';

  @override
  String get settingsTabLicense => 'Licencia';

  @override
  String get settingsTabAprs => 'APRS';

  @override
  String get settingsTabComms => 'Comunicaciones';

  @override
  String get settingsTabWinlink => 'Winlink';

  @override
  String get settingsTabServers => 'Servidores';

  @override
  String get settingsTabMap => 'Mapa';

  @override
  String get settingsTabLimits => 'Límites';

  @override
  String get settingsTabApplication => 'Aplicación';

  @override
  String get settingsAdd => 'Agregar';

  @override
  String get settingsRemove => 'Quitar';

  @override
  String get settingsDownload => 'Descargar';

  @override
  String get settingsRetry => 'Reintentar';

  @override
  String get settingsPreview => 'Vista previa';

  @override
  String get settingsNone => 'Ninguno';

  @override
  String get settingsLicenseInfo =>
      'En los Estados Unidos, necesita una licencia de radioaficionado para transmitir. Consulte el sitio web de la ARRL para obtener más información sobre cómo obtener una licencia.';

  @override
  String get settingsCallSignStationId => 'Indicativo e ID de estación';

  @override
  String get settingsCallSign => 'Indicativo';

  @override
  String get settingsCallSignHint => 'ej. W1AW';

  @override
  String get settingsStationId => 'ID de estación';

  @override
  String get settingsAllowTransmit => 'Permitir que esta aplicación transmita';

  @override
  String get settingsCallSignHelp =>
      'Introduzca un indicativo válido (al menos 3 caracteres) para habilitar la transmisión';

  @override
  String get settingsAprsIntro =>
      'Configure las rutas de enrutamiento APRS para la transmisión de paquetes.';

  @override
  String get settingsAprsRoutes => 'Rutas APRS';

  @override
  String get settingsEditRoute => 'Editar ruta';

  @override
  String get settingsEditRouteProtected =>
      'La ruta integrada no se puede editar';

  @override
  String get settingsDeleteRoute => 'Eliminar ruta';

  @override
  String get settingsDeleteRouteProtected =>
      'La ruta integrada no se puede eliminar';

  @override
  String get settingsCommsIntro =>
      'Configure los ajustes de reconocimiento y síntesis de voz.';

  @override
  String get settingsSpeechToText => 'Reconocimiento de voz';

  @override
  String get settingsSpeechToTextInfo =>
      'Transcribe a texto el audio de radio recibido. Funciona completamente sin conexión en este dispositivo; el audio nunca se guarda en el disco.';

  @override
  String get settingsModel => 'Modelo';

  @override
  String get settingsRecognitionLanguage => 'Idioma de reconocimiento';

  @override
  String get settingsRecognitionLanguageHelp =>
      'Los cambios de idioma surten efecto la próxima vez que se inicie el motor.';

  @override
  String get settingsStatus => 'Estado';

  @override
  String settingsModelInstalled(String suffix) {
    return 'Modelo instalado$suffix';
  }

  @override
  String settingsDownloadingModelPct(String percent) {
    return 'Descargando modelo… $percent %';
  }

  @override
  String get settingsDownloadingModel => 'Descargando modelo…';

  @override
  String settingsInstallingModelPct(String percent) {
    return 'Instalando modelo… $percent %';
  }

  @override
  String get settingsInstallingModel => 'Instalando modelo…';

  @override
  String get settingsModelInstallError => 'No se pudo instalar el modelo.';

  @override
  String settingsModelNotDownloaded(String downloadLabel) {
    return 'Modelo no descargado. $downloadLabel ocurre solo una vez y se almacena en caché en este dispositivo.';
  }

  @override
  String settingsBytesOf(String received, String total) {
    return '$received de $total';
  }

  @override
  String get settingsRemoveSttModelTitle =>
      '¿Quitar el modelo de reconocimiento de voz?';

  @override
  String settingsRemoveSttModelBody(String name) {
    return 'Se eliminará el modelo «$name» descargado para liberar espacio en disco. Se volverá a descargar la próxima vez que se use.';
  }

  @override
  String get settingsTextToSpeech => 'Síntesis de voz';

  @override
  String get settingsTextToSpeechInfo =>
      'Se usa al enviar texto en modo «Voz» desde la pestaña Comunicaciones.';

  @override
  String get settingsTtsUnavailableTitle =>
      'La síntesis de voz no está disponible';

  @override
  String get settingsVoice => 'Voz';

  @override
  String get settingsSpeechRate => 'Velocidad de habla';

  @override
  String get settingsPitch => 'Tono';

  @override
  String get settingsLoadingVoices => 'Cargando voces…';

  @override
  String get settingsSystemDefault => 'Predeterminado del sistema';

  @override
  String get settingsLangAutoDetect => 'Detección automática';

  @override
  String get settingsLangChinese => 'Chino';

  @override
  String get settingsLangJapanese => 'Japonés';

  @override
  String get settingsLangKorean => 'Coreano';

  @override
  String get settingsLangCantonese => 'Cantonés';

  @override
  String get settingsWinlinkIntro =>
      'Configure los ajustes de mensajería Winlink para el correo por radio.';

  @override
  String get settingsWinlinkAccount => 'Cuenta Winlink';

  @override
  String get settingsAccount => 'Cuenta';

  @override
  String get settingsWinlinkAccountHelp =>
      'Basado en su indicativo de la pestaña Licencia';

  @override
  String get settingsPassword => 'Contraseña';

  @override
  String get settingsUseStationIdWinlink =>
      'Usar el ID de estación para Winlink';

  @override
  String get settingsServersIntro =>
      'Configure los ajustes de los servidores locales.';

  @override
  String get settingsLocalServers => 'Servidores locales';

  @override
  String get settingsEnableWebServer => 'Habilitar el servidor web';

  @override
  String get settingsPort => 'Puerto:';

  @override
  String get settingsEnableAgwpeServer => 'Habilitar el servidor AGWPE';

  @override
  String get settingsHomeAssistant => 'Home Assistant';

  @override
  String get settingsHomeAssistantDescription =>
      'Expón cada radio conectada a Home Assistant a través de MQTT para supervisión y control.';

  @override
  String get settingsEnableHomeAssistant => 'Habilitar Home Assistant';

  @override
  String get settingsHomeAssistantMqttUrl => 'URL de MQTT';

  @override
  String get settingsHomeAssistantUsername => 'Nombre de usuario';

  @override
  String get settingsHomeAssistantPassword => 'Contraseña';

  @override
  String get settingsHomeAssistantTestSuccess => 'Éxito: conectado al broker.';

  @override
  String get settingsMapIntroGps =>
      'Configure las fuentes de datos de GPS y de seguimiento de aviones.';

  @override
  String get settingsMapIntroNoGps =>
      'Configure las fuentes de datos de seguimiento de aviones.';

  @override
  String get settingsGpsSerialPort => 'Puerto serie GPS';

  @override
  String get settingsSerialPort => 'Puerto serie';

  @override
  String get settingsBaudRate => 'Velocidad en baudios';

  @override
  String get settingsShareGpsLocation => 'Compartir ubicación GPS serie';

  @override
  String get settingsShareGpsLocationHelp =>
      'Envía la ubicación GPS serie a la radio conectada para que difunda su posición actual.';

  @override
  String get settingsAirplaneTracking => 'Seguimiento de aviones (dump1090)';

  @override
  String get settingsServerUrl => 'URL del servidor';

  @override
  String get settingsTestConnection => 'Probar conexión';

  @override
  String get settingsTest => 'Probar';

  @override
  String get settingsTestTesting => 'Probando...';

  @override
  String get settingsTestEmptyAddress => 'Error: dirección del servidor vacía';

  @override
  String settingsTestFailedHttp(int code) {
    return 'Error: HTTP $code';
  }

  @override
  String settingsTestSuccess(int count) {
    return 'Correcto, $count avión(es) encontrado(s).';
  }

  @override
  String get settingsTestUnexpectedJson => 'Error: formato JSON inesperado';

  @override
  String get settingsTestTimedOut => 'Error: tiempo de espera agotado';

  @override
  String get settingsTestInvalidJson => 'Error: respuesta JSON no válida';

  @override
  String get settingsTestFailed => 'Error';

  @override
  String get settingsTestConnectionFailedTitle =>
      'Error en la prueba de conexión';

  @override
  String get settingsLimitsIntro =>
      'Limite la cantidad de elementos de historial que se conservan entre inicios. Establezca en «Ilimitado» para conservar todo.';

  @override
  String get settingsHistoryLimits => 'Límites de historial';

  @override
  String get settingsUnlimited => 'Ilimitado';

  @override
  String get settingsLimitAprsMessages => 'Mensajes APRS';

  @override
  String get settingsLimitPackets => 'Paquetes';

  @override
  String get settingsLimitSstvImages => 'Imágenes SSTV';

  @override
  String get settingsLimitCommEvents => 'Eventos de comunicación';

  @override
  String settingsLimitCurrent(int count) {
    return 'Actual: $count';
  }

  @override
  String settingsLimitItemsDeleted(int count) {
    return 'Se eliminarán $count elementos';
  }

  @override
  String get settingsDeleteHistoryTitle => '¿Eliminar elementos del historial?';

  @override
  String settingsDeleteHistoryBody(String items) {
    return 'Estos límites eliminarán permanentemente los más antiguos:\n\n$items\n\nEsta acción no se puede deshacer.';
  }

  @override
  String settingsDeleteAprsMessages(int count) {
    return '$count mensajes APRS';
  }

  @override
  String settingsDeletePackets(int count) {
    return '$count paquetes';
  }

  @override
  String settingsDeleteSstvImages(int count) {
    return '$count imágenes SSTV';
  }

  @override
  String settingsDeleteCommEvents(int count) {
    return '$count eventos de comunicación';
  }

  @override
  String get settingsAddAprsRoute => 'Agregar ruta APRS';

  @override
  String get settingsEditAprsRoute => 'Editar ruta APRS';

  @override
  String get settingsName => 'Nombre';

  @override
  String get settingsNameHint => 'ej. Estándar';

  @override
  String get settingsDuplicateRoute => 'Ya existe una ruta con ese nombre.';

  @override
  String get settingsPath => 'Ruta';

  @override
  String get commonError => 'Error';

  @override
  String get commonConnect => 'Conectar';

  @override
  String get commonDisconnect => 'Desconectar';

  @override
  String get commonRename => 'Cambiar nombre';

  @override
  String get commonRemove => 'Quitar';

  @override
  String connectScanError(String error) {
    return 'Error al buscar dispositivos Bluetooth: $error';
  }

  @override
  String get connectNoRadiosTitle => 'No se encontraron radios';

  @override
  String get connectNoRadiosBody =>
      'No se encontró ningún dispositivo de radio compatible.\n\nAsegúrese de que su radio esté encendida y que el Bluetooth esté activado.';

  @override
  String get connectAllConnectedTitle => 'Todas conectadas';

  @override
  String get connectAllConnectedBody =>
      'Todos los dispositivos de radio detectados ya están conectados.';

  @override
  String get connectBluetoothOffTitle => 'Bluetooth no disponible';

  @override
  String get connectBluetoothOffBody =>
      'El Bluetooth no está disponible o está desactivado.\n\nActive el Bluetooth en la configuración de su dispositivo e inténtelo de nuevo.';

  @override
  String get radioConnectionTitle => 'Conexión de radio';

  @override
  String get radioConnectionEmpty =>
      'No se encontraron radios compatibles.\nAsegúrese de que su radio esté encendida y que el Bluetooth esté activado.';

  @override
  String get radioRenameTitle => 'Cambiar el nombre de la radio';

  @override
  String get radioRenamePrompt =>
      'Introduzca un nombre personalizado para esta radio:';

  @override
  String get radioRenameHint => 'Deje vacío para usar el nombre predeterminado';

  @override
  String get updateTitle => 'Actualización del software';

  @override
  String get updateChecking => 'Buscando actualizaciones...';

  @override
  String updateVersionAvailable(String version) {
    return 'La versión $version está disponible.';
  }

  @override
  String updateFreshDownload(String version) {
    return 'La versión $version requiere una nueva descarga.';
  }

  @override
  String updateUnsupported(String version) {
    return 'Esta versión ya no es compatible. Actualice a $version.';
  }

  @override
  String get updateUpToDate => 'Está usando la última versión.';

  @override
  String updateCheckFailed(String error) {
    return 'Error al buscar actualizaciones: $error';
  }

  @override
  String get updateDownloading => 'Descargando actualización...';

  @override
  String get updateDownloaded =>
      'Actualización descargada. Lista para instalar.';

  @override
  String updateDownloadFailed(String error) {
    return 'Error en la descarga: $error';
  }

  @override
  String updateInstallFailed(String error) {
    return 'Error en la instalación: $error';
  }

  @override
  String updateDiagnosticsLog(String path) {
    return 'Si la actualización no se completa, consulte el registro de diagnóstico:\n$path';
  }

  @override
  String get updateInstallRestart => 'Instalar y reiniciar';

  @override
  String get updateCheckAgain => 'Buscar de nuevo';

  @override
  String get regionsTitle => 'Cambiar el nombre de las regiones';

  @override
  String regionsMaxChars(int count) {
    return 'Los nombres de región pueden tener hasta $count caracteres.';
  }

  @override
  String regionLabel(int number) {
    return 'Región $number';
  }

  @override
  String get gpsInfoTitle => 'Información GPS';

  @override
  String get gpsSectionConnection => 'Conexión';

  @override
  String get gpsSectionFix => 'Posición GPS';

  @override
  String get gpsSectionPosition => 'Posición';

  @override
  String get gpsSectionMotion => 'Movimiento';

  @override
  String get gpsSectionTime => 'Hora';

  @override
  String get gpsPortStatus => 'Estado del puerto';

  @override
  String get gpsNotConfigured => 'No configurado';

  @override
  String get gpsOpenReceiving => 'Abierto — recibiendo datos';

  @override
  String get gpsPermDeniedLinux =>
      'Permiso denegado — agregue su usuario al grupo «dialout» (sudo usermod -aG dialout \$USER), luego cierre sesión y vuelva a iniciarla.';

  @override
  String get gpsPermDenied =>
      'Permiso denegado — la aplicación no puede acceder a este puerto.';

  @override
  String get gpsPortError =>
      'Error de puerto — no se puede abrir el puerto serie.';

  @override
  String get gpsFix => 'Posición';

  @override
  String get gpsFixQuality => 'Calidad de la posición';

  @override
  String get gpsSatellites => 'Satélites';

  @override
  String get gpsNoData => 'Sin datos';

  @override
  String get gpsActive => 'Activo';

  @override
  String get gpsNoFix => 'Sin posición';

  @override
  String get gpsQualGps => 'Posición GPS (1)';

  @override
  String get gpsQualDgps => 'Posición DGPS (2)';

  @override
  String get gpsQualInvalid => 'No válida (0)';

  @override
  String gpsQualUnknown(int quality) {
    return '$quality (desconocido)';
  }

  @override
  String get gpsLatitude => 'Latitud';

  @override
  String get gpsLatitudeDms => 'Latitud (DMS)';

  @override
  String get gpsLongitude => 'Longitud';

  @override
  String get gpsLongitudeDms => 'Longitud (DMS)';

  @override
  String get gpsAltitude => 'Altitud';

  @override
  String get gpsSpeed => 'Velocidad';

  @override
  String get gpsHeading => 'Rumbo';

  @override
  String get gpsTimeUtc => 'Hora GPS (UTC)';

  @override
  String get gpsDate => 'Fecha GPS';

  @override
  String get gpsLastUpdate => 'Última actualización';

  @override
  String get trustedDevicesTitle => 'Dispositivos de confianza';

  @override
  String get trustedRemoveTitle => 'Quitar dispositivo de confianza';

  @override
  String trustedRemoveMessage(String name) {
    return '¿Quitar «$name» de la lista de dispositivos de confianza de la radio?';
  }

  @override
  String get trustedNoDevices => 'No se encontraron dispositivos de confianza.';

  @override
  String get pfConfigTitle => 'Configurar botones';

  @override
  String get pfSaveToRadio => 'Guardar en la radio';

  @override
  String get pfNoRadio => 'No hay ninguna radio conectada.';

  @override
  String get pfNoButtons =>
      'Esta radio no informa de ningún botón programable.';

  @override
  String get pfIntro =>
      'Elija la acción de cada botón programable para cada tipo de pulsación. Los cambios se escriben en la radio cuando guarda.';

  @override
  String pfButtonLabel(int number) {
    return 'Botón $number';
  }

  @override
  String get pfActionShort => 'Pulsación corta';

  @override
  String get pfActionLong => 'Pulsación larga';

  @override
  String get pfActionVeryLong => 'Pulsación muy larga';

  @override
  String get pfActionVeryVeryLong => 'Pulsación muy muy larga';

  @override
  String get pfActionDouble => 'Doble pulsación';

  @override
  String get pfActionTriple => 'Triple pulsación';

  @override
  String get pfActionRepeat => 'Repetición';

  @override
  String get pfActionPressDown => 'Pulsación mantenida';

  @override
  String get pfActionRelease => 'Liberación';

  @override
  String get pfActionLongRelease => 'Liberación larga';

  @override
  String get pfActionVeryLongRelease => 'Liberación muy larga';

  @override
  String get pfActionVeryVeryLongRelease => 'Liberación muy muy larga';

  @override
  String pfActionUnknown(int action) {
    return 'Acción $action';
  }

  @override
  String get pfEffectDisabled => 'Desactivado';

  @override
  String get pfEffectAlarm => 'Alarma';

  @override
  String get pfEffectAlarmAndMute => 'Alarma y silencio';

  @override
  String get pfEffectToggleOffline => 'Alternar sin conexión';

  @override
  String get pfEffectToggleRadioTx => 'Alternar transmisión de radio';

  @override
  String get pfEffectToggleTxPower => 'Alternar la potencia de transmisión';

  @override
  String get pfEffectToggleFm => 'Alternar la radio FM';

  @override
  String get pfEffectPrevChannel => 'Canal anterior';

  @override
  String get pfEffectNextChannel => 'Canal siguiente';

  @override
  String get pfEffectTCall => 'Tono T (1750 Hz)';

  @override
  String get pfEffectPrevRegion => 'Región anterior';

  @override
  String get pfEffectNextRegion => 'Región siguiente';

  @override
  String get pfEffectToggleChScan => 'Alternar el escaneo de canales';

  @override
  String get pfEffectMainPtt => 'PTT principal';

  @override
  String get pfEffectSubPtt => 'PTT secundario';

  @override
  String get pfEffectToggleMonitor => 'Alternar el monitoreo';

  @override
  String get pfEffectBtPairing => 'Emparejamiento Bluetooth';

  @override
  String get pfEffectToggleDoubleCh => 'Alternar el canal doble';

  @override
  String get pfEffectToggleAbCh => 'Alternar el canal A/B';

  @override
  String get pfEffectSendLocation => 'Enviar la ubicación';

  @override
  String get pfEffectOneClickLink => 'Enlace con un clic';

  @override
  String get pfEffectVolDown => 'Bajar el volumen';

  @override
  String get pfEffectVolUp => 'Subir el volumen';

  @override
  String get pfEffectToggleMute => 'Alternar el silencio';

  @override
  String pfEffectUnknown(int effect) {
    return 'Desconocido ($effect)';
  }

  @override
  String get importChannelsTitle => 'Importar canales';

  @override
  String importChannelsTitleWith(String name) {
    return 'Importar canales — $name';
  }

  @override
  String get importIntro =>
      'Arrastre un canal desde la izquierda a una posición de la radio, o seleccione un canal y una posición y luego pulse la flecha. Pulse el icono de información para ver los detalles. Los canales solo se escriben en la radio cuando pulsa Aceptar.';

  @override
  String importOkCount(int count) {
    return 'Aceptar ($count)';
  }

  @override
  String importImportedHeader(int count) {
    return 'Importados ($count)';
  }

  @override
  String get importNoChannels => 'No hay canales importados.';

  @override
  String importRadioChannelsHeader(int count) {
    return 'Canales de la radio ($count)';
  }

  @override
  String get importNoRadioChannels => 'No hay canales de radio.';

  @override
  String get importMoveTooltip =>
      'Mover el canal seleccionado a la posición seleccionada';

  @override
  String get importCopyAllTooltip =>
      'Copiar todos los canales importados a las posiciones de la radio 1:1';

  @override
  String importChannelShort(int number) {
    return 'Canal $number';
  }

  @override
  String get importClearTooltip => 'Borrar la asignación pendiente';

  @override
  String get importChannelDetails => 'Detalles del canal';

  @override
  String get riTitle => 'Información de la radio';

  @override
  String get riNoRadioConnected => 'No hay ninguna radio conectada';

  @override
  String get riConnectPrompt => 'Conecte una radio para ver su información.';

  @override
  String riRadioFallback(int id) {
    return 'Radio $id';
  }

  @override
  String get riSectionRadio => 'Radio';

  @override
  String get riSectionDeviceInfo => 'Información del dispositivo';

  @override
  String get riSectionDeviceStatus => 'Estado del dispositivo';

  @override
  String get riSectionDeviceSettings => 'Configuración del dispositivo';

  @override
  String get riSectionBss => 'Configuración BSS';

  @override
  String get riSectionPosition => 'Posición';

  @override
  String get riName => 'Nombre';

  @override
  String get riStatus => 'Estado';

  @override
  String get riSettingsLabel => 'Configuración';

  @override
  String get riNoData => 'Sin datos';

  @override
  String get riNoGpsData => 'Sin datos GPS';

  @override
  String get riNoGpsLock => 'Sin posición GPS';

  @override
  String get riGpsLocked => 'Posición GPS adquirida';

  @override
  String get riTrue => 'Verdadero';

  @override
  String get riFalse => 'Falso';

  @override
  String get riPresent => 'Presente';

  @override
  String get riNotPresent => 'Ausente';

  @override
  String get riSupported => 'Compatible';

  @override
  String get riNotSupported => 'No compatible';

  @override
  String get riCurrent => 'Actual';

  @override
  String get riOff => 'Desactivado';

  @override
  String riChannelValue(int number) {
    return 'Canal $number';
  }

  @override
  String riSeconds(int count) {
    return '$count segundo(s)';
  }

  @override
  String riMeters(String value) {
    return '$value metros';
  }

  @override
  String riDegrees(String value) {
    return '$value grados';
  }

  @override
  String get riProductId => 'ID de producto';

  @override
  String get riVendorId => 'ID de proveedor';

  @override
  String get riDmrSupport => 'Compatibilidad con DMR';

  @override
  String get riGmrsSupport => 'Compatibilidad con GMRS';

  @override
  String get riHardwareSpeaker => 'Altavoz de hardware';

  @override
  String get riHardwareVersion => 'Versión de hardware';

  @override
  String get riSoftwareVersion => 'Versión de software';

  @override
  String get riRegionCount => 'Número de regiones';

  @override
  String get riMediumPower => 'Potencia media';

  @override
  String get riChannelCount => 'Número de canales';

  @override
  String get riNoaa => 'NOAA';

  @override
  String get riWeather => 'Meteorología';

  @override
  String riWeatherChannel(int number) {
    return 'Meteorología $number';
  }

  @override
  String get riBroadcastFm => 'Radio FM';

  @override
  String get riRadioLabel => 'Radio';

  @override
  String get riVfo => 'VFO';

  @override
  String get riFreqRangeCount => 'Número de rangos de frecuencia';

  @override
  String get riPowerOn => 'Encendido';

  @override
  String get riInTx => 'En transmisión';

  @override
  String get riInRx => 'En recepción';

  @override
  String get riDoubleChannelLabel => 'Canal doble';

  @override
  String get riScanning => 'Escaneando';

  @override
  String get riCurrentChannelId => 'ID del canal actual';

  @override
  String get riGpsLockedLabel => 'GPS bloqueado';

  @override
  String get riHfpConnected => 'HFP conectado';

  @override
  String get riAocConnected => 'AOC conectado';

  @override
  String get riRssi => 'RSSI';

  @override
  String get riCurrentRegion => 'Región actual';

  @override
  String get riAccuracy => 'Precisión';

  @override
  String get riReceivedTime => 'Hora de recepción';

  @override
  String get riGpsTimeLocal => 'Hora GPS local';

  @override
  String get riGpsTimeUtcLabel => 'Hora GPS UTC';

  @override
  String get tabDetach => 'Separar...';

  @override
  String get tabClear => 'Borrar';

  @override
  String get tabSaveToFile => 'Guardar en un archivo...';

  @override
  String get commonNoRadioConnected => 'No hay ninguna radio conectada.';

  @override
  String errorOpeningFileDialog(String error) {
    return 'Error al abrir el cuadro de diálogo de archivo: $error';
  }

  @override
  String errorSavingFile(String error) {
    return 'Error al guardar el archivo: $error';
  }

  @override
  String get debugSaveTitle => 'Guardar el registro de depuración';

  @override
  String debugLogSavedTo(String path) {
    return 'Registro de depuración guardado en $path';
  }

  @override
  String get debugShowBluetoothFrames => 'Mostrar las tramas Bluetooth';

  @override
  String get debugLoopbackMode => 'Modo de bucle';

  @override
  String get debugQueryDeviceNames =>
      'Consultar los nombres de los dispositivos';

  @override
  String get debugRawCommand => 'Comando sin procesar...';

  @override
  String get debugAutoScroll => 'Desplazamiento automático';

  @override
  String get debugFirmwareUpdate => 'Actualización de firmware...';

  @override
  String get debugShowBuiltInMenus => 'Mostrar los menús integrados';

  @override
  String get packetsCopyHex => 'Copiar el paquete HEX';

  @override
  String get packetsHexCopied => 'Paquete HEX copiado al portapapeles';

  @override
  String get packetsSaveTitle => 'Guardar la captura de paquetes';

  @override
  String get packetsSaved => 'Captura de paquetes guardada';

  @override
  String packetsSavedTo(String path) {
    return 'Captura de paquetes guardada en $path';
  }

  @override
  String get packetsShowDecode => 'Mostrar la decodificación de paquetes';

  @override
  String get packetsEmpty => 'No se han capturado paquetes';

  @override
  String get packetsColTime => 'Hora';

  @override
  String get packetsColChannel => 'Canal';

  @override
  String get packetsColData => 'Datos';

  @override
  String get commonAdd => 'Agregar';

  @override
  String get commonEdit => 'Editar';

  @override
  String get commonEditEllipsis => 'Editar...';

  @override
  String get commonAddEllipsis => 'Agregar...';

  @override
  String get commonExportEllipsis => 'Exportar...';

  @override
  String get commonImportEllipsis => 'Importar...';

  @override
  String get contactsTypeGeneric => 'Estaciones genéricas';

  @override
  String get contactsTypeAprs => 'Estaciones APRS';

  @override
  String get contactsTypeTerminal => 'Estaciones Terminal';

  @override
  String get contactsTypeBbs => 'Estaciones BBS';

  @override
  String get contactsTypeWinlink => 'Estaciones Winlink';

  @override
  String get contactsTypeTorrent => 'Estaciones Torrent';

  @override
  String get contactsTypeAgwpe => 'Estaciones AGWPE';

  @override
  String get contactsExists =>
      'Ya existe una estación con este indicativo y tipo';

  @override
  String get contactsRemovePrompt => '¿Quitar la estación seleccionada?';

  @override
  String get contactsNoExport => 'No hay estaciones para exportar';

  @override
  String get contactsExportTitle => 'Exportar estaciones';

  @override
  String get contactsImportTitle => 'Importar estaciones';

  @override
  String contactsExported(int count) {
    return '$count estaciones exportadas';
  }

  @override
  String contactsImported(int count) {
    return '$count estaciones importadas';
  }

  @override
  String get contactsUnableOpen =>
      'No se puede abrir la libreta de direcciones';

  @override
  String get contactsInvalid => 'Libreta de direcciones no válida';

  @override
  String get contactsColCallsign => 'Indicativo';

  @override
  String get contactsColName => 'Nombre';

  @override
  String get contactsColDescription => 'Descripción';

  @override
  String terminalHeaderWith(String callsign) {
    return 'Terminal - $callsign';
  }

  @override
  String get terminalNoRadio =>
      'No hay ninguna radio disponible para la conexión.';

  @override
  String get terminalShowCallsign => 'Mostrar el indicativo';

  @override
  String get terminalWordWrap => 'Ajuste de línea';

  @override
  String get terminalWaitForConnection => 'Esperar una conexión...';

  @override
  String get terminalSend => 'Enviar';

  @override
  String terminalConnectedTo(String callsign) {
    return 'Conectado a $callsign';
  }

  @override
  String terminalConnectingTo(String callsign) {
    return 'Conectando a $callsign...';
  }

  @override
  String get terminalInvalidCallsignDest => 'Indicativo/destino no válido';

  @override
  String get terminalInvalidCallsign => 'Indicativo no válido';

  @override
  String get terminalNotConnected => 'No conectado';

  @override
  String terminalError(String error) {
    return 'Error: $error';
  }

  @override
  String get terminalBrotli =>
      'Paquete comprimido con Brotli recibido (no compatible)';

  @override
  String get audioSectionDevices => 'Dispositivos';

  @override
  String get audioRefreshDevices => 'Actualizar la lista de dispositivos';

  @override
  String get audioOutput => 'Salida';

  @override
  String get audioInput => 'Entrada';

  @override
  String get audioVolume => 'Volumen';

  @override
  String get audioSquelch => 'Silenciador';

  @override
  String get audioSectionComputer => 'Equipo';

  @override
  String get audioApplication => 'Aplicación';

  @override
  String get audioMaster => 'Principal';

  @override
  String get audioMicGain => 'Ganancia del micrófono';

  @override
  String get audioMicNotAvailable =>
      'La captura del micrófono no está disponible en esta plataforma.';

  @override
  String get audioMicNotSupported =>
      'La captura del micrófono no es compatible aquí.';

  @override
  String get audioSpectRadio => 'Espectrógrafo de radio';

  @override
  String get audioSpectMic => 'Espectrógrafo del micrófono';

  @override
  String get audioSpectNone => 'Espectrógrafo';

  @override
  String get audioSpectMenuNone => 'Sin espectrógrafo';

  @override
  String get audioDartQuality => 'Calidad de recepción DART';

  @override
  String get audioDartSignalAnalysis => 'Análisis de la señal DART';

  @override
  String get audioDefault => 'Predeterminado';

  @override
  String get audioMute => 'Silenciar';

  @override
  String get audioUnmute => 'Reactivar el sonido';

  @override
  String get audioEnable => 'Activar';

  @override
  String get audioDisable => 'Desactivar';

  @override
  String get audioNa => 'N/D';

  @override
  String get bbsHeaderActive => 'BBS - Activo';

  @override
  String get bbsActivate => 'Activar';

  @override
  String get bbsDeactivate => 'Desactivar';

  @override
  String get bbsViewTraffic => 'Ver el tráfico';

  @override
  String get bbsClearTraffic => 'Borrar el tráfico';

  @override
  String get bbsClearStats => 'Borrar las estadísticas';

  @override
  String get bbsColCallSign => 'Indicativo';

  @override
  String get bbsColLastSeen => 'Última actividad';

  @override
  String get bbsColStats => 'Estadísticas';

  @override
  String get bbsTraffic => 'Tráfico';

  @override
  String get bbsJustNow => 'Justo ahora';

  @override
  String bbsMinAgo(int n) {
    return 'hace $n min';
  }

  @override
  String bbsHoursAgo(int n) {
    return 'hace $n h';
  }

  @override
  String bbsDaysAgo(int n) {
    return 'hace $n d';
  }

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get torrentAddFile => 'Agregar un archivo';

  @override
  String get torrentShowDetails => 'Mostrar los detalles';

  @override
  String get torrentFileSaved => 'Archivo guardado.';

  @override
  String get torrentFileDataUnavailable =>
      'Error al guardar: datos del archivo no disponibles';

  @override
  String get torrentUnknownError => 'Error desconocido';

  @override
  String get torrentSaveTitle => 'Guardar el archivo torrent';

  @override
  String get torrentNoRadios =>
      'No hay ninguna radio conectada. Conecte una radio primero.';

  @override
  String get torrentMultiRadio =>
      'El modo torrent con varias radios aún no es compatible.';

  @override
  String get torrentDropSingle => 'Suelte un solo archivo.';

  @override
  String get torrentDeletePrompt =>
      '¿Eliminar el archivo torrent seleccionado?';

  @override
  String get torrentPause => 'Pausar';

  @override
  String get torrentShare => 'Compartir';

  @override
  String get torrentRequest => 'Solicitar';

  @override
  String get torrentSaveAs => 'Guardar como...';

  @override
  String get torrentDropToShare => 'Suelte un archivo para compartir';

  @override
  String get torrentNoFiles =>
      'No hay archivos torrent. Agregue o suelte un archivo para compartir.';

  @override
  String get torrentUnknownSource => 'Desconocido';

  @override
  String get torrentColFile => 'Archivo';

  @override
  String get torrentColMode => 'Modo';

  @override
  String get torrentDetailFileName => 'Nombre del archivo';

  @override
  String get torrentDetailSource => 'Origen';

  @override
  String get torrentDetailFileSize => 'Tamaño del archivo';

  @override
  String torrentBytes(int count) {
    return '$count bytes';
  }

  @override
  String get torrentDetailCompression => 'Compresión';

  @override
  String get torrentDetailBlocks => 'Bloques';

  @override
  String get torrentDetailsTitle => 'Detalles del torrent';

  @override
  String get torrentSelectPrompt =>
      'Seleccione un torrent para ver los detalles';

  @override
  String get torrentModePaused => 'En pausa';

  @override
  String get torrentModeSharing => 'Compartiendo';

  @override
  String get torrentModeRequesting => 'Solicitando';

  @override
  String get torrentModeError => 'Error';

  @override
  String get torrentCompUnknown => 'Desconocido';

  @override
  String get mailInbox => 'Bandeja de entrada';

  @override
  String get mailOutbox => 'Bandeja de salida';

  @override
  String get mailDraft => 'Borrador';

  @override
  String get mailSent => 'Enviados';

  @override
  String get mailArchive => 'Archivo';

  @override
  String get mailTrash => 'Papelera';

  @override
  String get mailInternet => 'Internet';

  @override
  String get mailDeleteTitle => 'Eliminar correo';

  @override
  String get mailMoveToTrashTitle => 'Mover a la papelera';

  @override
  String get mailDeletePermanent =>
      '¿Eliminar permanentemente el correo seleccionado? Esta acción no se puede deshacer.';

  @override
  String get mailMoveToTrashPrompt =>
      '¿Mover el correo seleccionado a la papelera?';

  @override
  String get mailMove => 'Mover';

  @override
  String get mailOpen => 'Abrir';

  @override
  String get mailReply => 'Responder';

  @override
  String get mailReplyAll => 'Responder a todos';

  @override
  String get mailForward => 'Reenviar';

  @override
  String get mailShowPreview => 'Mostrar la vista previa';

  @override
  String get mailBackup => 'Copia de seguridad del correo...';

  @override
  String get mailRestore => 'Restaurar el correo...';

  @override
  String get mailShowTraffic => 'Mostrar el tráfico...';

  @override
  String mailBackupFailed(String error) {
    return 'Error en la copia de seguridad: $error';
  }

  @override
  String get mailBackupTitle => 'Copia de seguridad del correo';

  @override
  String get mailBackupSuccess =>
      'Copia de seguridad completada correctamente.';

  @override
  String get mailRestoreTitle => 'Restaurar el correo';

  @override
  String get mailRestoreUnableOpen =>
      'No se puede abrir el archivo de copia de seguridad';

  @override
  String mailRestoreFailed(String error) {
    return 'Error en la restauración: $error';
  }

  @override
  String get mailNew => 'Nuevo';

  @override
  String get mailNewMail => 'Nuevo correo';

  @override
  String get mailColTime => 'Hora';

  @override
  String get mailColTo => 'Para';

  @override
  String get mailColFrom => 'De';

  @override
  String get mailColSubject => 'Asunto';

  @override
  String get mailSelectPreview => 'Seleccione un mensaje para la vista previa';

  @override
  String get commonUnknown => 'Desconocido';

  @override
  String get mapOfflineMode => 'Modo sin conexión';

  @override
  String get mapOfflineMap => 'Mapa sin conexión';

  @override
  String get mapCacheArea => 'Almacenar el área en caché...';

  @override
  String get mapCenterGps => 'Centrar en el GPS';

  @override
  String get mapShowTracks => 'Mostrar las trazas';

  @override
  String get mapShowMarkers => 'Mostrar los marcadores';

  @override
  String get mapShowAirplanes => 'Mostrar los aviones';

  @override
  String get mapLargeMarkers => 'Marcadores grandes';

  @override
  String get mapShowContactsOnly => 'Mostrar solo los contactos';

  @override
  String get mapFilterAll => 'Todo';

  @override
  String get mapFilterLast30 => 'Últimos 30 minutos';

  @override
  String get mapFilterLastHour => 'Última hora';

  @override
  String get mapFilterLast6 => 'Últimas 6 horas';

  @override
  String get mapFilterLast12 => 'Últimas 12 horas';

  @override
  String get mapFilterLast24 => 'Últimas 24 horas';

  @override
  String get mapCacheTitle => 'Almacenar el área del mapa en caché';

  @override
  String mapCachePrompt(int count, int minZoom, int maxZoom) {
    return '¿Descargar $count teselas para los niveles de zoom $minZoom–$maxZoom?\n\nEsto almacenará el área seleccionada en caché para su uso sin conexión.';
  }

  @override
  String get mapDownloadingTitle => 'Descargando teselas';

  @override
  String mapTilesProgress(int done, int total) {
    return '$done / $total teselas';
  }

  @override
  String get mapDragToSelect =>
      'Arrastre para seleccionar el área que se va a almacenar en caché';

  @override
  String get aprsNoChannel =>
      'No hay ninguna radio con un canal APRS disponible';

  @override
  String get aprsNoLoadedChannels =>
      'No hay ninguna radio con canales cargados disponible';

  @override
  String get aprsDetails => 'Detalles...';

  @override
  String get aprsShowLocation => 'Mostrar la ubicación...';

  @override
  String get aprsSetReceiver => 'Establecer como destinatario';

  @override
  String get aprsCopyMessage => 'Copiar el mensaje';

  @override
  String get aprsCopyCallsign => 'Copiar el indicativo';

  @override
  String get aprsCopyChannel => 'Copiar el canal';

  @override
  String get aprsClearTitle => 'Borrar los mensajes APRS';

  @override
  String get aprsClearPrompt =>
      '¿Borrar todos los mensajes APRS? Esto también elimina todos los marcadores APRS del mapa. Esta acción no se puede deshacer.';

  @override
  String get aprsShowAll => 'Mostrar todos los mensajes';

  @override
  String get aprsSendSms => 'Enviar un mensaje SMS...';

  @override
  String get aprsWeatherReport => 'Informe meteorológico...';

  @override
  String get aprsBeaconSettingsMenu => 'Configuración de baliza...';

  @override
  String get aprsDropShare => 'Suelte para compartir este canal';

  @override
  String get aprsBeaconWarning =>
      'La difusión de baliza está activada en el canal actual, lo cual no se recomienda.';

  @override
  String aprsBeaconActive(String interval) {
    return 'La baliza de radio está activa, intervalo: $interval.';
  }

  @override
  String get aprsBeaconSettings => 'Configuración de baliza';

  @override
  String aprsIntervalSeconds(int count) {
    return '$count segundos';
  }

  @override
  String get aprsIntervalMinute => '1 minuto';

  @override
  String aprsIntervalMinutes(int count) {
    return '$count minutos';
  }

  @override
  String get aprsMissingChannel =>
      'No hay ningún canal «APRS» configurado en la radio conectada. Agregue un canal APRS para enviar y recibir mensajes APRS.';

  @override
  String get aprsSetup => 'Configurar';

  @override
  String get aprsTypeMessage => 'Escriba un mensaje...';

  @override
  String get commonYes => 'Sí';

  @override
  String get commonNo => 'No';

  @override
  String get commonSend => 'Enviar';

  @override
  String commonSavedTo(String path) {
    return 'Guardado en $path';
  }

  @override
  String commsFailedLoadImage(String error) {
    return 'Error al cargar la imagen: $error';
  }

  @override
  String commsFailedSaveImage(String error) {
    return 'Error al guardar la imagen: $error';
  }

  @override
  String commsFailedEncodeSstv(String error) {
    return 'Error al codificar el audio SSTV: $error';
  }

  @override
  String commsFailedLoadAudio(String error) {
    return 'Error al cargar el audio: $error';
  }

  @override
  String get commsUnsupportedWav => 'Archivo WAV no compatible o vacío.';

  @override
  String get commsSstvWebUnavailable =>
      'La grabación/transmisión de imágenes SSTV no está disponible en la web.';

  @override
  String get commsNoRadioVoice =>
      'No hay ninguna radio conectada para la transmisión de voz.';

  @override
  String get commsSelectImageTitle => 'Seleccionar una imagen para SSTV';

  @override
  String get commsSelectWavTitle => 'Seleccionar un archivo de audio WAV';

  @override
  String get commsRecordingWebUnavailable =>
      'La reproducción de grabaciones desde archivos no está disponible en la web.';

  @override
  String get commsFileNoLongerExists => 'El archivo ya no existe.';

  @override
  String get commsSaveAsTitle => 'Guardar como';

  @override
  String get commsTransmitDisabledAprs =>
      'La transmisión está desactivada cuando el VFO A está ajustado al canal APRS.';

  @override
  String get commsWaitTransmission =>
      'Espere a que finalice la transmisión en curso.';

  @override
  String get commsConnectRadioChat =>
      'Conecte una radio antes de enviar un mensaje de chat.';

  @override
  String get commsEnableAudioMode =>
      'Active el audio (el botón Activar) antes de enviar en este modo.';

  @override
  String get commsMicNotSupported =>
      'La captura del micrófono no es compatible con esta plataforma.';

  @override
  String get commsConnectRadioPtt =>
      'Conecte una radio antes de usar la función push-to-talk.';

  @override
  String get commsEnableAudioPtt =>
      'Active el audio (el botón Activar) antes de usar la función push-to-talk.';

  @override
  String get commsSwitchChatShare =>
      'Cambie al modo Chat para compartir un canal.';

  @override
  String get commsModePtt => 'PTT';

  @override
  String get commsModeChat => 'Chat';

  @override
  String get commsModeSpeak => 'Hablar';

  @override
  String get commsModeMorse => 'Morse';

  @override
  String get commsModeDtmf => 'DTMF';

  @override
  String get commsRecordAudio => 'Grabar audio';

  @override
  String get commsSendImage => 'Enviar una imagen...';

  @override
  String get commsSendAudio => 'Enviar audio...';

  @override
  String get commsPttReleaseSettings => 'Configuración de liberación de PTT...';

  @override
  String get commsClearHistory => 'Borrar el historial';

  @override
  String get commsShowImage => 'Mostrar la imagen...';

  @override
  String get commsPlayRecording => 'Reproducir la grabación...';

  @override
  String get commsSaveAsMenu => 'Guardar como...';

  @override
  String get commsShowLocation => 'Mostrar la ubicación';

  @override
  String get commsClearHistoryPrompt =>
      '¿Seguro que desea borrar el historial de voz?';

  @override
  String get commsAudioMuted => 'El audio está silenciado.';

  @override
  String get commsUnmute => 'Reactivar el sonido';

  @override
  String get commsPttTransmitting => 'Transmitiendo...';

  @override
  String get commsPttHold => 'PTT - Mantenga pulsado para transmitir';

  @override
  String get commsDtmfHint => 'Introduzca dígitos DTMF (0-9, *, #)...';

  @override
  String get mailComposeNewTitle => 'Nuevo mensaje';

  @override
  String get mailComposeEditTitle => 'Editar mensaje';

  @override
  String get mailDiscardChanges => '¿Descartar los cambios de este mensaje?';

  @override
  String get mailDiscardMessage => '¿Descartar este mensaje?';

  @override
  String get mailDiscard => 'Descartar';

  @override
  String get mailAddCc => 'Agregar CC';

  @override
  String get mailCc => 'CC';

  @override
  String get mailRemoveCc => 'Quitar CC';

  @override
  String get mailMessageLabel => 'Mensaje';

  @override
  String get mailSaveDraft => 'Guardar borrador';

  @override
  String get mailAttachmentsLabel => 'Archivos adjuntos';

  @override
  String get mailAddAttachment => 'Agregar adjunto';

  @override
  String get mailRemoveAttachment => 'Quitar adjunto';

  @override
  String get mailSaveAttachment => 'Guardar adjunto';

  @override
  String get mailAttachmentDropHint =>
      'Arrastra y suelta archivos aquí para adjuntar';

  @override
  String mailAttachmentReadFailed(String name) {
    return 'No se pudo leer el archivo: $name';
  }

  @override
  String mailAttachmentSaved(String name) {
    return 'Guardado «$name»';
  }

  @override
  String mailAttachmentLargeWarning(String size) {
    return 'Los adjuntos grandes ($size) pueden tardar mucho en enviarse por radio.';
  }

  @override
  String get smsTitle => 'Enviar un mensaje SMS';

  @override
  String get smsPhoneNumber => 'Número de teléfono';

  @override
  String get smsIntro =>
      'Puede enviar mensajes SMS a teléfonos en Estados Unidos, Puerto Rico, Canadá, Australia y el Reino Unido, siempre que el número ya haya aceptado el servicio. Puede registrarse en: ';

  @override
  String get locationTitle => 'Ubicación';

  @override
  String get beaconIntro =>
      'Modifique cómo la radio difunde información sobre sí misma, incluida la posición, el voltaje y un mensaje personalizado. Otras estaciones cercanas podrán ver esta información.';

  @override
  String beaconRadio(String name) {
    return 'Radio: $name';
  }

  @override
  String get beaconSection => 'Baliza';

  @override
  String get beaconPacketFormat => 'Formato de paquete';

  @override
  String get beaconInterval => 'Intervalo de baliza';

  @override
  String get beaconAprsCallsign => 'Indicativo APRS';

  @override
  String get beaconCallsignHint => 'Indicativo - ID de estación';

  @override
  String get beaconCallsignInvalid =>
      'Introduzca un indicativo y un ID de estación válidos (ej. W1AW-5)';

  @override
  String get beaconAprsMessage => 'Mensaje APRS';

  @override
  String get beaconShareLocation => 'Compartir la ubicación';

  @override
  String get beaconSendVoltage => 'Enviar el voltaje';

  @override
  String get beaconAllowPositionCheck => 'Permitir la verificación de posición';

  @override
  String get beaconChannelCurrent => 'Actual (no recomendado)';

  @override
  String beaconEverySeconds(int n) {
    return 'Cada $n segundos';
  }

  @override
  String beaconEveryMinutes(int n) {
    return 'Cada $n minutos';
  }

  @override
  String get assConnectTerminal => 'Conectar a la estación Terminal';

  @override
  String get assConnectBbs => 'Conectar a la estación BBS';

  @override
  String get assConnectWinlink => 'Conectar a la pasarela Winlink';

  @override
  String get assConnectStation => 'Conectar a la estación';

  @override
  String get assNew => 'Nuevo…';

  @override
  String get attSelectFile => 'Seleccionar un archivo para compartir';

  @override
  String get attCompressing => 'Comprimiendo...';

  @override
  String get attTitle => 'Agregar un archivo torrent';

  @override
  String get attSelect => 'Seleccionar...';

  @override
  String get attDescriptionOptional => 'Descripción (opcional)';

  @override
  String get stationTitleVoice => 'Estación de voz';

  @override
  String get stationTitleAprs => 'Estación APRS';

  @override
  String get stationTitleTerminal => 'Estación terminal';

  @override
  String get stationTitleWinlink => 'Pasarela Winlink';

  @override
  String get stationTitleGeneric => 'Estación';

  @override
  String get stationTypeOptionVoice => 'Estación de voz / genérica';

  @override
  String get stationTypeLabel => 'Tipo de estación';

  @override
  String get stationAprsRoute => 'Ruta APRS';

  @override
  String get stationUseAuth => 'Usar la autenticación de mensajes';

  @override
  String get stationAuthPassword => 'Contraseña de autenticación';

  @override
  String get stationPasswordRequired => 'Contraseña requerida';

  @override
  String get stationTerminalProtocol => 'Protocolo terminal';

  @override
  String get stationAx25Destination => 'Destino AX.25 (ej. CALL-1)';

  @override
  String get stationAx25Invalid => 'Dirección AX.25 no válida';

  @override
  String get stationModem => 'Módem';

  @override
  String get apdTitle => 'Detalles del paquete APRS';

  @override
  String get apdCopyAll => 'Copiar todo';

  @override
  String get apdCopyValue => 'Copiar el valor';

  @override
  String get apdValueCopied => 'Valor copiado';

  @override
  String get apdAllValuesCopied => 'Todos los valores copiados';

  @override
  String get apdNoDetails => 'No hay detalles disponibles.';

  @override
  String get apdShowLocation => 'Mostrar la ubicación...';

  @override
  String get acfgTitle => 'Configurar el canal APRS';

  @override
  String get acfgIntro =>
      'La frecuencia APRS varía según la región del mundo. Use este sitio para encontrar la frecuencia adecuada para configurar el canal APRS.';

  @override
  String get acfgConfiguration => 'Configuración APRS';

  @override
  String get acfgFrequency => 'Frecuencia';

  @override
  String get acfgFrequencyHint => '144.39 en Norteamérica\n144.80 en Europa';

  @override
  String get acfgChannelOverwritten => 'El canal seleccionado se sobrescribirá';

  @override
  String get sstvSendTitle => 'Enviar una imagen SSTV';

  @override
  String sstvSendTitleNamed(String name) {
    return 'Enviar una imagen SSTV - $name';
  }

  @override
  String get sstvMode => 'Modo:';

  @override
  String sstvTransmitTime(String time) {
    return 'Tiempo de transmisión: ~$time';
  }

  @override
  String get msgdTitle => 'Detalles del mensaje';

  @override
  String get msgdFieldType => 'Tipo';

  @override
  String get msgdFieldDirection => 'Dirección';

  @override
  String get msgdFieldTime => 'Hora';

  @override
  String get msgdFieldSource => 'Origen';

  @override
  String get msgdFieldReceiver => 'Destinatario';

  @override
  String get msgdFieldDuration => 'Duración';

  @override
  String get msgdFieldLatitude => 'Latitud';

  @override
  String get msgdFieldLongitude => 'Longitud';

  @override
  String get msgdFieldMessage => 'Mensaje';

  @override
  String get msgdFieldFile => 'Archivo';

  @override
  String get msgdDirReceived => 'Recibido';

  @override
  String get msgdDirSent => 'Enviado';

  @override
  String get msgdTypeVoice => 'Voz';

  @override
  String get msgdTypeVoiceClip => 'Clip de voz';

  @override
  String get msgdTypeRecording => 'Grabación';

  @override
  String get msgdTypeSstvPicture => 'Imagen SSTV';

  @override
  String get msgdTypeIdentification => 'Identificación';

  @override
  String get msgdTypeChatMessage => 'Mensaje de chat';

  @override
  String get msgdTypeAx25Packet => 'Paquete AX.25';

  @override
  String get rpbFailedToLoad => 'Error al cargar la grabación.';

  @override
  String get ivwFailedToLoad => 'Error al cargar la imagen.';

  @override
  String get rawTitle => 'Comando de radio sin procesar';

  @override
  String get rawCommand => 'Comando';

  @override
  String get rawHexPayload => 'Carga útil HEX (opcional)';

  @override
  String get rawResponse => 'Respuesta';

  @override
  String get identTitle => 'Configuración de liberación de PTT';

  @override
  String get identDescription =>
      'Si está activado, envía su indicativo o su información de ubicación cada vez que suelta el PTT en el canal en el que está transmitiendo.';

  @override
  String get identCallsignHint => 'Introducir el indicativo - ID de estación';

  @override
  String get identSendCallsign => 'Enviar el indicativo';

  @override
  String get identSendPosition => 'Enviar la posición';

  @override
  String get commonOn => 'Activado';

  @override
  String get commonOff => 'Desactivado';

  @override
  String get commonNone => 'Ninguno';

  @override
  String chChannelNumber(int n) {
    return 'Canal $n';
  }

  @override
  String chChShort(int n) {
    return 'Canal $n';
  }

  @override
  String get chMoreSettings => 'Más ajustes';

  @override
  String get chChannelNameHint => 'Nombre del canal';

  @override
  String get chFrequencyMhz => 'Frecuencia (MHz)';

  @override
  String get chReceiveMhz => 'Recepción (MHz)';

  @override
  String get chTransmitMhz => 'Transmisión (MHz)';

  @override
  String get chMode => 'Modo';

  @override
  String get chPower => 'Potencia';

  @override
  String get chBandwidth => 'Ancho de banda';

  @override
  String get chReceiveTone => 'Tono de recepción (CTCSS / DCS)';

  @override
  String get chTransmitTone => 'Tono de transmisión (CTCSS / DCS)';

  @override
  String get chDisableTransmit => 'Desactivar la transmisión';

  @override
  String get chMute => 'Silenciar';

  @override
  String get chScan => 'Escaneo';

  @override
  String get chTalkAround => 'Talk around';

  @override
  String get chDeemphasis => 'Desénfasis';

  @override
  String get chPowerHigh => 'Alta';

  @override
  String get chPowerMedium => 'Media';

  @override
  String get chPowerLow => 'Baja';

  @override
  String get chBandwidthWide => '25 KHz ancho';

  @override
  String get chBandwidthNarrow => '12.5 KHz estrecho';

  @override
  String get channelImportFetching =>
      'Obteniendo el canal desde la página web…';

  @override
  String get channelImportUnsupportedSite =>
      'Este sitio web no es compatible con la importación de canales.';

  @override
  String get channelImportFetchFailed => 'No se pudo descargar la página web.';

  @override
  String get channelImportParseFailed =>
      'No se encontraron detalles del canal en esa página.';

  @override
  String get chClearTitle => 'Borrar el canal';

  @override
  String chClearConfirm(int n) {
    return '¿Borrar el canal $n?\n\nEsto elimina la frecuencia, el nombre y la configuración de esta posición en la radio.';
  }

  @override
  String get cdRxFrequency => 'Frecuencia RX';

  @override
  String get cdTxFrequency => 'Frecuencia TX';

  @override
  String get cdRxModulation => 'Modulación RX';

  @override
  String get cdTxModulation => 'Modulación TX';

  @override
  String get cdRxTone => 'Tono RX';

  @override
  String get cdTxTone => 'Tono TX';

  @override
  String get cdTxDisabled => 'Transmisión desactivada';

  @override
  String get cdTalkAround => 'Talk around';

  @override
  String get cdEmpty => '(vacío)';

  @override
  String get cdBandwidthWide => '25 kHz (ancho)';

  @override
  String get cdBandwidthNarrow => '12.5 kHz (estrecho)';

  @override
  String get gpsDetailsTitle => 'Detalles GPS';

  @override
  String get gpsDisabled => 'GPS desactivado';

  @override
  String get gpsLock => 'Bloqueo GPS';

  @override
  String get gpsNoLock => 'Sin bloqueo GPS';

  @override
  String get mdbgTitle => 'Tráfico Winlink';

  @override
  String get mdbgNoTraffic => 'No hay tráfico por el momento.';

  @override
  String get fwTitle => 'Actualización del firmware de la radio';

  @override
  String get fwStatusInitial =>
      'Busque una actualización de firmware en línea o cargue un archivo de firmware desde el disco.';

  @override
  String get fwErrNotConnected => 'La radio no está conectada.';

  @override
  String get fwErrNoDeviceInfo =>
      'La información del dispositivo de radio aún no está disponible.';

  @override
  String get fwStatusChecking => 'Buscando una actualización de firmware…';

  @override
  String get fwErrNoServerInfo =>
      'El servidor del proveedor no devolvió información sobre el firmware.';

  @override
  String fwUpdateAvailable(String version) {
    return 'Hay una actualización de firmware disponible $version. Consulte las notas de la versión a continuación y luego descargue para actualizar.';
  }

  @override
  String fwErrCheckFailed(String error) {
    return 'Error al buscar la actualización: $error';
  }

  @override
  String get fwPickTitle => 'Seleccionar un archivo de firmware';

  @override
  String fwLoaded(String name, String size, String md5) {
    return '$name cargado: $size (MD5 $md5…).';
  }

  @override
  String fwErrLoadFailed(String error) {
    return 'No se puede cargar el archivo de firmware: $error';
  }

  @override
  String get fwSaveTitle => 'Guardar el archivo de firmware';

  @override
  String fwSavedTo(String path) {
    return 'Firmware guardado en $path';
  }

  @override
  String fwErrSaveFailed(String error) {
    return 'No se puede guardar el archivo de firmware: $error';
  }

  @override
  String get fwStatusDownloading => 'Descargando y ensamblando el firmware…';

  @override
  String get fwProgressStarting => 'Iniciando…';

  @override
  String fwReady(String size, String md5) {
    return 'Firmware listo: $size (MD5 $md5…).';
  }

  @override
  String fwErrDownloadFailed(String error) {
    return 'Error en la descarga: $error';
  }

  @override
  String get fwStatusWriting =>
      'Escribiendo el firmware en la radio. No la apague.';

  @override
  String get fwProgressTransferring => 'Transfiriendo…';

  @override
  String fwErrTransferFailed(String error) {
    return 'Error al transferir el firmware: $error';
  }

  @override
  String get fwStatusRebooting => 'La radio se está reiniciando. Reconectando…';

  @override
  String get fwProgressWaitingRestart =>
      'Esperando a que la radio se reinicie…';

  @override
  String fwErrReconnectFailed(String error) {
    return 'Error al reconectar tras el reinicio: $error';
  }

  @override
  String get fwErrReconnectNull =>
      'No se puede reconectar con la radio tras su reinicio. El firmware se transfirió pero no se confirmó. Reconéctese manualmente e inténtelo de nuevo.';

  @override
  String get fwStatusFinalising => 'Finalizando la actualización…';

  @override
  String get fwProgressConfirming => 'Confirmando…';

  @override
  String fwErrConfirmFailed(String error) {
    return 'Error al confirmar la actualización: $error';
  }

  @override
  String get fwStatusComplete =>
      '¡Actualización de firmware completada! La radio ahora ejecuta el nuevo firmware.';

  @override
  String get fwProgressDownloadPatch => 'Descargando el parche';

  @override
  String get fwProgressDownloadBase => 'Descargando la imagen base';

  @override
  String get fwProgressAssemble => 'Ensamblando el firmware';

  @override
  String fwProgressBytes(String label, String done, String total) {
    return '$label ($done / $total)';
  }

  @override
  String fwProgressTransferringBytes(String done, String total) {
    return 'Transfiriendo ($done / $total)';
  }

  @override
  String fwCurrentFirmware(String version) {
    return 'Firmware actual: $version';
  }

  @override
  String get fwErrGeneric => 'Se ha producido un error.';

  @override
  String get fwIdleDisclosure =>
      'La verificación en línea contacta con el servidor del proveedor de la radio (rpc.benshikj.com) y solo envía el identificador de producto de su radio. No se envía nada hasta que pulsa Buscar una actualización.';

  @override
  String get fwWhatsNew => 'Novedades';

  @override
  String get fwConfirmWarning =>
      'Advertencia: mantenga la radio encendida, cargada y dentro del alcance de Bluetooth durante todo el proceso. La radio se reiniciará en algún momento. Interrumpir la actualización puede requerir una recuperación manual.';

  @override
  String get fwFromFile => 'Desde un archivo…';

  @override
  String get fwCheckForUpdate => 'Buscar una actualización';

  @override
  String get fwDownload => 'Descargar';

  @override
  String get fwSave => 'Guardar…';

  @override
  String get fwFlashNow => 'Grabar ahora';

  @override
  String get fwRetry => 'Reintentar';

  @override
  String get wxTitle => 'Solicitar un boletín meteorológico';

  @override
  String get wxIntro => 'Solicite un boletín meteorológico mediante APRS. ';

  @override
  String get wxLocation => 'Ubicación';

  @override
  String get wxLocationHelper =>
      'Ciudad/estado de EE. UU. o código postal de EE. UU., o coordenadas 41.123/-121.334';

  @override
  String get wxTime => 'Momento';

  @override
  String get wxReport => 'Informe';

  @override
  String get wxToday => 'Hoy';

  @override
  String get wxTonight => 'Esta noche';

  @override
  String get wxTomorrow => 'Mañana';

  @override
  String get wxTomorrowNight => 'Mañana por la noche';

  @override
  String get wxMonday => 'Lunes';

  @override
  String get wxMondayNight => 'Lunes por la noche';

  @override
  String get wxTuesday => 'Martes';

  @override
  String get wxTuesdayNight => 'Martes por la noche';

  @override
  String get wxWednesday => 'Miércoles';

  @override
  String get wxWednesdayNight => 'Miércoles por la noche';

  @override
  String get wxThursday => 'Jueves';

  @override
  String get wxThursdayNight => 'Jueves por la noche';

  @override
  String get wxFriday => 'Viernes';

  @override
  String get wxFridayNight => 'Viernes por la noche';

  @override
  String get wxSaturday => 'Sábado';

  @override
  String get wxSaturdayNight => 'Sábado por la noche';

  @override
  String get wxSunday => 'Domingo';

  @override
  String get wxSundayNight => 'Domingo por la noche';

  @override
  String get wxReportBrief => 'Breve, Pronóstico corto, solo EE. UU.';

  @override
  String get wxReportFull => 'Completo, Pronóstico más detallado, solo EE. UU.';

  @override
  String get wxReportCurrent =>
      'Actual, Estación NWS más cercana, solo EE. UU.';

  @override
  String get wxReportMetar => 'METAR, Estación OACI en formato METAR';

  @override
  String get wxReportCwop => 'CWOP, Estación CWOP más cercana';
}
