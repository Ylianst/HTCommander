// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Handi-Talkie Commander';

  @override
  String get menuFile => 'ファイル';

  @override
  String get menuConnect => '接続...';

  @override
  String get menuDisconnect => '切断';

  @override
  String get menuSettings => '設定...';

  @override
  String get menuExit => '終了';

  @override
  String get menuRadios => '無線機';

  @override
  String get menuDualWatch => 'デュアルワッチ';

  @override
  String get menuScan => 'スキャン';

  @override
  String get menuRegions => 'リージョン';

  @override
  String get menuTrustedDevices => '信頼できるデバイス...';

  @override
  String get menuButtons => 'ボタン...';

  @override
  String get menuFmRadio => 'FMラジオ...';

  @override
  String get menuExportChannels => 'チャンネルをエクスポート...';

  @override
  String get menuImportChannels => 'チャンネルをインポート...';

  @override
  String get menuMacRadio => '無線機';

  @override
  String get menuMacDisplay => '表示';

  @override
  String get fmRadioTitle => 'FMラジオ';

  @override
  String fmRadioMhz(String value) {
    return '${value}MHz';
  }

  @override
  String get fmRadioOff => 'オフ';

  @override
  String get fmRadioPowerTooltip => 'FMラジオのオン/オフ';

  @override
  String get fmRadioSeekDownTooltip => '下方向にシーク';

  @override
  String get fmRadioStepDownTooltip => '周波数を下げる';

  @override
  String get fmRadioStopTooltip => 'オフにする';

  @override
  String get fmRadioStepUpTooltip => '周波数を上げる';

  @override
  String get fmRadioSeekUpTooltip => '上方向にシーク';

  @override
  String get fmRadioStationsHeader => 'お気に入りの放送局';

  @override
  String get fmRadioAddStationTooltip => '現在の周波数を追加';

  @override
  String get fmRadioNoStations => 'お気に入りの放送局がありません';

  @override
  String get fmRadioStationNameLabel => '放送局名';

  @override
  String get fmRadioRenameTitle => '放送局名';

  @override
  String get fmRadioDeleteTitle => '放送局を削除';

  @override
  String fmRadioDeleteMessage(String name) {
    return '「$name」をお気に入りの放送局から削除しますか？';
  }

  @override
  String get commonClose => '閉じる';

  @override
  String get commonCancel => 'キャンセル';

  @override
  String get commonOk => 'OK';

  @override
  String get aboutCheckForUpdates => '更新を確認';

  @override
  String aboutVersionAuthor(String version) {
    return 'バージョン $version\nYlian Saint-Hilaire, KK7VZT\nオープンソース、Apache 2.0 ライセンス';
  }

  @override
  String get settingsLanguage => '言語';

  @override
  String get settingsLanguageHint =>
      'アプリケーションで使用する言語を選択します。「システムのデフォルト」はデバイスの言語に従います。';

  @override
  String get settingsThemeMode => 'テーマ';

  @override
  String get settingsThemeModeHint =>
      'ライトまたはダークの外観を選択します。「システムのデフォルト」はデバイスの設定に従います。';

  @override
  String get settingsThemeModeSystem => 'システムのデフォルト';

  @override
  String get settingsThemeModeLight => 'ライト';

  @override
  String get settingsThemeModeDark => 'ダーク';

  @override
  String get languageSystem => 'システムのデフォルト';

  @override
  String get languageEnglish => '英語';

  @override
  String get languageFrench => 'フランス語';

  @override
  String get languageSpanish => 'スペイン語';

  @override
  String get languageChinese => '中国語';

  @override
  String get languageJapanese => '日本語';

  @override
  String get languageHindi => 'ヒンディー語';

  @override
  String get languageGerman => 'ドイツ語';

  @override
  String get languagePolish => 'ポーランド語';

  @override
  String get menuAudio => 'オーディオ';

  @override
  String get menuAudioEnabled => 'オーディオを有効化';

  @override
  String get menuSoftwareModem => 'ソフトウェアモデム';

  @override
  String get menuModemDisabled => '無効';

  @override
  String get menuDartTransmitLevel => 'DART 送信レベル';

  @override
  String get menuDartLevel0 => 'レベル 0（BPSK、LDPC 1/2）';

  @override
  String get menuDartLevel1 => 'レベル 1（QPSK、LDPC 1/2）';

  @override
  String get menuDartLevel2 => 'レベル 2（QPSK、LDPC 2/3）';

  @override
  String get menuDartLevel3 => 'レベル 3（8PSK、LDPC 2/3）';

  @override
  String get menuDartLevel4 => 'レベル 4（16QAM、LDPC 3/4）';

  @override
  String get menuDartLevel5 => 'レベル 5（16QAM、LDPC 5/6）';

  @override
  String get menuDartLevelF => 'レベル F（4-FSK、LDPC 1/2）';

  @override
  String get menuAprsModem => 'APRS モデム';

  @override
  String get menuView => '表示';

  @override
  String get menuRadio => '無線機';

  @override
  String get menuTabs => 'タブ';

  @override
  String get menuTabNames => 'タブ名';

  @override
  String get menuShowAllTabs => 'すべてのタブを表示';

  @override
  String get menuAllChannels => 'すべてのチャンネル';

  @override
  String get menuChannelFrequency => 'チャンネル周波数';

  @override
  String get menuHelp => 'ヘルプ';

  @override
  String get menuRadioInformation => '無線機の情報...';

  @override
  String get menuGpsInformation => 'GPS 情報...';

  @override
  String get menuCheckForUpdatesEllipsis => '更新を確認...';

  @override
  String get menuCheckForUpdates => 'アップデートを確認';

  @override
  String get menuAbout => 'このアプリについて...';

  @override
  String get tabComms => '通信';

  @override
  String get tabAudio => 'オーディオ';

  @override
  String get tabAprs => 'APRS';

  @override
  String get tabMap => '地図';

  @override
  String get tabMail => 'メール';

  @override
  String get tabTerminal => 'ターミナル';

  @override
  String get tabContacts => '連絡先';

  @override
  String get tabBbs => 'BBS';

  @override
  String get tabTorrent => 'トレント';

  @override
  String get tabPackets => 'パケット';

  @override
  String get tabDebug => 'デバッグ';

  @override
  String get tabRadio => '無線機';

  @override
  String get stateDisconnected => '切断済み';

  @override
  String get stateConnecting => '接続中...';

  @override
  String get stateConnected => '接続済み';

  @override
  String get stateUnableToConnect => '接続できません';

  @override
  String get stateAccessDenied => 'アクセスが拒否されました';

  @override
  String get stateSelectRadio => '無線機を選択';

  @override
  String statusBattery(int percent) {
    return 'バッテリー: $percent %';
  }

  @override
  String get statusCheckingBluetooth => 'Bluetooth を確認中...';

  @override
  String get statusBluetoothNotAvailable => 'Bluetooth を利用できません';

  @override
  String get statusScanningForRadios => '無線機を検索中...';

  @override
  String get statusErrorScanning => '無線機の検索中にエラーが発生しました';

  @override
  String get statusNoCompatibleRadios => '対応する無線機が見つかりません';

  @override
  String get statusAllRadiosConnected => 'すべての無線機が既に接続されています';

  @override
  String statusConnectingTo(String name) {
    return '$name に接続中...';
  }

  @override
  String statusConnectedTo(String name) {
    return '$name に接続しました';
  }

  @override
  String statusFailedToConnect(String name) {
    return '$name への接続に失敗しました';
  }

  @override
  String get statusDisconnecting => '切断中...';

  @override
  String get settingsTabLicense => 'ライセンス';

  @override
  String get settingsTabAprs => 'APRS';

  @override
  String get settingsTabComms => '通信';

  @override
  String get settingsTabWinlink => 'Winlink';

  @override
  String get settingsTabServers => 'サーバー';

  @override
  String get settingsTabMap => '地図';

  @override
  String get settingsTabLimits => '制限';

  @override
  String get settingsTabApplication => 'アプリケーション';

  @override
  String get settingsAdd => '追加';

  @override
  String get settingsRemove => '削除';

  @override
  String get settingsDownload => 'ダウンロード';

  @override
  String get settingsRetry => '再試行';

  @override
  String get settingsPreview => 'プレビュー';

  @override
  String get settingsNone => 'なし';

  @override
  String get settingsLicenseInfo =>
      '米国では、送信にはアマチュア無線免許が必要です。免許の取得について詳しくは ARRL のウェブサイトをご覧ください。';

  @override
  String get settingsCallSignStationId => 'コールサインと局 ID';

  @override
  String get settingsCallSign => 'コールサイン';

  @override
  String get settingsCallSignHint => '例: W1AW';

  @override
  String get settingsStationId => '局 ID';

  @override
  String get settingsAllowTransmit => 'このアプリケーションによる送信を許可';

  @override
  String get settingsCallSignHelp => '送信を有効にするには有効なコールサイン（3 文字以上）を入力してください';

  @override
  String get settingsAprsIntro => 'パケット送信用の APRS ルーティングパスを設定します。';

  @override
  String get settingsAprsRoutes => 'APRS ルート';

  @override
  String get settingsEditRoute => 'ルートを編集';

  @override
  String get settingsEditRouteProtected => '組み込みルートは編集できません';

  @override
  String get settingsDeleteRoute => 'ルートを削除';

  @override
  String get settingsDeleteRouteProtected => '組み込みルートは削除できません';

  @override
  String get settingsCommsIntro => '音声認識と音声合成の設定を行います。';

  @override
  String get settingsSpeechToText => '音声認識';

  @override
  String get settingsSpeechToTextInfo =>
      '受信した無線オーディオをテキストに変換します。このデバイス上で完全にオフラインで動作し、オーディオがディスクに保存されることはありません。';

  @override
  String get settingsModel => 'モデル';

  @override
  String get settingsRecognitionLanguage => '認識言語';

  @override
  String get settingsRecognitionLanguageHelp => '言語の変更は次回エンジン起動時に有効になります。';

  @override
  String get settingsStatus => '状態';

  @override
  String settingsModelInstalled(String suffix) {
    return 'モデルがインストールされました$suffix';
  }

  @override
  String settingsDownloadingModelPct(String percent) {
    return 'モデルをダウンロード中… $percent %';
  }

  @override
  String get settingsDownloadingModel => 'モデルをダウンロード中…';

  @override
  String settingsInstallingModelPct(String percent) {
    return 'モデルをインストール中… $percent %';
  }

  @override
  String get settingsInstallingModel => 'モデルをインストール中…';

  @override
  String get settingsModelInstallError => 'モデルをインストールできませんでした。';

  @override
  String settingsModelNotDownloaded(String downloadLabel) {
    return 'モデルがダウンロードされていません。$downloadLabelは一度だけ行われ、このデバイスにキャッシュされます。';
  }

  @override
  String settingsBytesOf(String received, String total) {
    return '$received / $total';
  }

  @override
  String get settingsRemoveSttModelTitle => '音声認識モデルを削除しますか？';

  @override
  String settingsRemoveSttModelBody(String name) {
    return 'ディスク容量を解放するため、ダウンロード済みのモデル「$name」を削除します。次回使用時に再度ダウンロードされます。';
  }

  @override
  String get settingsTextToSpeech => '音声合成';

  @override
  String get settingsTextToSpeechInfo => '「通信」タブで「音声」モードでテキストを送信するときに使用されます。';

  @override
  String get settingsTtsUnavailableTitle => '音声合成を利用できません';

  @override
  String get settingsVoice => '音声';

  @override
  String get settingsSpeechRate => '話速';

  @override
  String get settingsPitch => 'ピッチ';

  @override
  String get settingsLoadingVoices => '音声を読み込み中…';

  @override
  String get settingsSystemDefault => 'システムのデフォルト';

  @override
  String get settingsLangAutoDetect => '自動検出';

  @override
  String get settingsLangChinese => '中国語';

  @override
  String get settingsLangJapanese => '日本語';

  @override
  String get settingsLangKorean => '韓国語';

  @override
  String get settingsLangCantonese => '広東語';

  @override
  String get settingsWinlinkIntro => '無線経由のメール用に Winlink メッセージ設定を行います。';

  @override
  String get settingsWinlinkAccount => 'Winlink アカウント';

  @override
  String get settingsAccount => 'アカウント';

  @override
  String get settingsWinlinkAccountHelp => '「ライセンス」タブのコールサインに基づきます';

  @override
  String get settingsPassword => 'パスワード';

  @override
  String get settingsUseStationIdWinlink => 'Winlink に局 ID を使用';

  @override
  String get settingsServersIntro => 'ローカルサーバーの設定を行います。';

  @override
  String get settingsLocalServers => 'ローカルサーバー';

  @override
  String get settingsEnableWebServer => 'Web サーバーを有効化';

  @override
  String get settingsPort => 'ポート:';

  @override
  String get settingsEnableAgwpeServer => 'AGWPE サーバーを有効化';

  @override
  String get settingsHomeAssistant => 'Home Assistant';

  @override
  String get settingsHomeAssistantDescription =>
      '接続された各無線機を MQTT 経由で Home Assistant に公開し、監視と制御を行います。';

  @override
  String get settingsEnableHomeAssistant => 'Home Assistant を有効にする';

  @override
  String get settingsHomeAssistantMqttUrl => 'MQTT URL';

  @override
  String get settingsHomeAssistantUsername => 'ユーザー名';

  @override
  String get settingsHomeAssistantPassword => 'パスワード';

  @override
  String get settingsHomeAssistantTestSuccess => '成功: ブローカーに接続しました。';

  @override
  String get settingsMapIntroGps => 'GPS と航空機追跡のデータソースを設定します。';

  @override
  String get settingsMapIntroNoGps => '航空機追跡のデータソースを設定します。';

  @override
  String get settingsGpsSerialPort => 'GPS シリアルポート';

  @override
  String get settingsSerialPort => 'シリアルポート';

  @override
  String get settingsBaudRate => 'ボーレート';

  @override
  String get settingsShareGpsLocation => 'シリアル GPS 位置情報を共有';

  @override
  String get settingsShareGpsLocationHelp =>
      '接続中の無線機にシリアル GPS 位置情報を送信し、現在位置をブロードキャストさせます。';

  @override
  String get settingsAirplaneTracking => '航空機追跡（dump1090）';

  @override
  String get settingsServerUrl => 'サーバー URL';

  @override
  String get settingsTestConnection => '接続をテスト';

  @override
  String get settingsTest => 'テスト';

  @override
  String get settingsTestTesting => 'テスト中...';

  @override
  String get settingsTestEmptyAddress => '失敗: サーバーアドレスが空です';

  @override
  String settingsTestFailedHttp(int code) {
    return '失敗: HTTP $code';
  }

  @override
  String settingsTestSuccess(int count) {
    return '成功、$count 機の航空機が見つかりました。';
  }

  @override
  String get settingsTestUnexpectedJson => '失敗: 予期しない JSON 形式';

  @override
  String get settingsTestTimedOut => '失敗: タイムアウト';

  @override
  String get settingsTestInvalidJson => '失敗: 無効な JSON 応答';

  @override
  String get settingsTestFailed => '失敗';

  @override
  String get settingsTestConnectionFailedTitle => '接続テストに失敗しました';

  @override
  String get settingsLimitsIntro => '起動間で保持する履歴項目の数を制限します。「無制限」に設定するとすべて保持します。';

  @override
  String get settingsHistoryLimits => '履歴の制限';

  @override
  String get settingsUnlimited => '無制限';

  @override
  String get settingsLimitAprsMessages => 'APRS メッセージ';

  @override
  String get settingsLimitPackets => 'パケット';

  @override
  String get settingsLimitSstvImages => 'SSTV 画像';

  @override
  String get settingsLimitCommEvents => '通信イベント';

  @override
  String settingsLimitCurrent(int count) {
    return '現在: $count';
  }

  @override
  String settingsLimitItemsDeleted(int count) {
    return '$count 個の項目が削除されます';
  }

  @override
  String get settingsDeleteHistoryTitle => '履歴項目を削除しますか？';

  @override
  String settingsDeleteHistoryBody(String items) {
    return 'これらの制限により、最も古い項目が完全に削除されます:\n\n$items\n\nこの操作は元に戻せません。';
  }

  @override
  String settingsDeleteAprsMessages(int count) {
    return '$count 件の APRS メッセージ';
  }

  @override
  String settingsDeletePackets(int count) {
    return '$count 個のパケット';
  }

  @override
  String settingsDeleteSstvImages(int count) {
    return '$count 枚の SSTV 画像';
  }

  @override
  String settingsDeleteCommEvents(int count) {
    return '$count 件の通信イベント';
  }

  @override
  String get settingsAddAprsRoute => 'APRS ルートを追加';

  @override
  String get settingsEditAprsRoute => 'APRS ルートを編集';

  @override
  String get settingsName => '名前';

  @override
  String get settingsNameHint => '例: 標準';

  @override
  String get settingsDuplicateRoute => 'その名前のルートは既に存在します。';

  @override
  String get settingsPath => 'パス';

  @override
  String get commonError => 'エラー';

  @override
  String get commonConnect => '接続';

  @override
  String get commonDisconnect => '切断';

  @override
  String get commonRename => '名前を変更';

  @override
  String get commonRemove => '削除';

  @override
  String connectScanError(String error) {
    return 'Bluetooth デバイスの検索に失敗しました: $error';
  }

  @override
  String get connectNoRadiosTitle => '無線機が見つかりません';

  @override
  String get connectNoRadiosBody =>
      '対応する無線機デバイスが見つかりませんでした。\n\n無線機の電源が入っていて、Bluetooth が有効になっていることを確認してください。';

  @override
  String get connectAllConnectedTitle => 'すべて接続済み';

  @override
  String get connectAllConnectedBody => '検出されたすべての無線機デバイスは既に接続されています。';

  @override
  String get connectBluetoothOffTitle => 'Bluetooth を利用できません';

  @override
  String get connectBluetoothOffBody =>
      'Bluetooth を利用できないか、無効になっています。\n\nデバイスの設定で Bluetooth を有効にしてから再試行してください。';

  @override
  String get radioConnectionTitle => '無線機の接続';

  @override
  String get radioConnectionEmpty =>
      '対応する無線機が見つかりません。\n無線機の電源が入っていて、Bluetooth が有効になっていることを確認してください。';

  @override
  String get radioRenameTitle => '無線機の名前を変更';

  @override
  String get radioRenamePrompt => 'この無線機のカスタム名を入力してください:';

  @override
  String get radioRenameHint => '空欄のままにするとデフォルト名を使用します';

  @override
  String get updateTitle => 'ソフトウェアの更新';

  @override
  String get updateChecking => '更新を確認中...';

  @override
  String updateVersionAvailable(String version) {
    return 'バージョン $version が利用可能です。';
  }

  @override
  String updateFreshDownload(String version) {
    return 'バージョン $version は新規ダウンロードが必要です。';
  }

  @override
  String updateUnsupported(String version) {
    return 'このバージョンはサポートされなくなりました。$version に更新してください。';
  }

  @override
  String get updateUpToDate => '最新バージョンを使用しています。';

  @override
  String updateCheckFailed(String error) {
    return '更新の確認に失敗しました: $error';
  }

  @override
  String get updateDownloading => '更新をダウンロード中...';

  @override
  String get updateDownloaded => '更新をダウンロードしました。インストールの準備ができました。';

  @override
  String updateDownloadFailed(String error) {
    return 'ダウンロードに失敗しました: $error';
  }

  @override
  String updateInstallFailed(String error) {
    return 'インストールに失敗しました: $error';
  }

  @override
  String updateDiagnosticsLog(String path) {
    return '更新が完了しない場合は、診断ログを確認してください:\n$path';
  }

  @override
  String get updateInstallRestart => 'インストールして再起動';

  @override
  String get updateCheckAgain => '再確認';

  @override
  String get regionsTitle => 'リージョンの名前を変更';

  @override
  String regionsMaxChars(int count) {
    return 'リージョン名は最大 $count 文字まで使用できます。';
  }

  @override
  String regionLabel(int number) {
    return 'リージョン $number';
  }

  @override
  String get gpsInfoTitle => 'GPS 情報';

  @override
  String get gpsSectionConnection => '接続';

  @override
  String get gpsSectionFix => 'GPS 測位';

  @override
  String get gpsSectionPosition => '位置';

  @override
  String get gpsSectionMotion => '動き';

  @override
  String get gpsSectionTime => '時刻';

  @override
  String get gpsPortStatus => 'ポートの状態';

  @override
  String get gpsNotConfigured => '未設定';

  @override
  String get gpsOpenReceiving => 'オープン — データ受信中';

  @override
  String get gpsPermDeniedLinux =>
      '権限が拒否されました — ユーザーを「dialout」グループに追加し（sudo usermod -aG dialout \$USER）、ログアウトして再度ログインしてください。';

  @override
  String get gpsPermDenied => '権限が拒否されました — アプリケーションはこのポートにアクセスできません。';

  @override
  String get gpsPortError => 'ポートエラー — シリアルポートを開けません。';

  @override
  String get gpsFix => '測位';

  @override
  String get gpsFixQuality => '測位品質';

  @override
  String get gpsSatellites => '衛星';

  @override
  String get gpsNoData => 'データなし';

  @override
  String get gpsActive => 'アクティブ';

  @override
  String get gpsNoFix => '測位なし';

  @override
  String get gpsQualGps => 'GPS 測位 (1)';

  @override
  String get gpsQualDgps => 'DGPS 測位 (2)';

  @override
  String get gpsQualInvalid => '無効 (0)';

  @override
  String gpsQualUnknown(int quality) {
    return '$quality（不明）';
  }

  @override
  String get gpsLatitude => '緯度';

  @override
  String get gpsLatitudeDms => '緯度 (DMS)';

  @override
  String get gpsLongitude => '経度';

  @override
  String get gpsLongitudeDms => '経度 (DMS)';

  @override
  String get gpsAltitude => '高度';

  @override
  String get gpsSpeed => '速度';

  @override
  String get gpsHeading => '進行方向';

  @override
  String get gpsTimeUtc => 'GPS 時刻 (UTC)';

  @override
  String get gpsDate => 'GPS 日付';

  @override
  String get gpsLastUpdate => '最終更新';

  @override
  String get trustedDevicesTitle => '信頼できるデバイス';

  @override
  String get trustedRemoveTitle => '信頼できるデバイスを削除';

  @override
  String trustedRemoveMessage(String name) {
    return '無線機の信頼できるデバイスリストから「$name」を削除しますか？';
  }

  @override
  String get trustedNoDevices => '信頼できるデバイスが見つかりません。';

  @override
  String get pfConfigTitle => 'ボタンを設定';

  @override
  String get pfSaveToRadio => '無線機に保存';

  @override
  String get pfNoRadio => '無線機が接続されていません。';

  @override
  String get pfNoButtons => 'この無線機はプログラム可能なボタンを報告していません。';

  @override
  String get pfIntro => '各プログラム可能ボタンについて、押下タイプごとの動作を選択します。保存すると変更が無線機に書き込まれます。';

  @override
  String pfButtonLabel(int number) {
    return 'ボタン $number';
  }

  @override
  String get pfActionShort => '短押し';

  @override
  String get pfActionLong => '長押し';

  @override
  String get pfActionVeryLong => '超長押し';

  @override
  String get pfActionVeryVeryLong => '超々長押し';

  @override
  String get pfActionDouble => 'ダブル押し';

  @override
  String get pfActionTriple => 'トリプル押し';

  @override
  String get pfActionRepeat => 'リピート';

  @override
  String get pfActionPressDown => '押し下げ';

  @override
  String get pfActionRelease => 'リリース';

  @override
  String get pfActionLongRelease => '長リリース';

  @override
  String get pfActionVeryLongRelease => '超長リリース';

  @override
  String get pfActionVeryVeryLongRelease => '超々長リリース';

  @override
  String pfActionUnknown(int action) {
    return '動作 $action';
  }

  @override
  String get pfEffectDisabled => '無効';

  @override
  String get pfEffectAlarm => 'アラーム';

  @override
  String get pfEffectAlarmAndMute => 'アラームとミュート';

  @override
  String get pfEffectToggleOffline => 'オフラインを切り替え';

  @override
  String get pfEffectToggleRadioTx => '無線送信を切り替え';

  @override
  String get pfEffectToggleTxPower => '送信出力を切り替え';

  @override
  String get pfEffectToggleFm => 'FM ラジオを切り替え';

  @override
  String get pfEffectPrevChannel => '前のチャンネル';

  @override
  String get pfEffectNextChannel => '次のチャンネル';

  @override
  String get pfEffectTCall => 'T トーン（1750 Hz）';

  @override
  String get pfEffectPrevRegion => '前のリージョン';

  @override
  String get pfEffectNextRegion => '次のリージョン';

  @override
  String get pfEffectToggleChScan => 'チャンネルスキャンを切り替え';

  @override
  String get pfEffectMainPtt => 'メイン PTT';

  @override
  String get pfEffectSubPtt => 'サブ PTT';

  @override
  String get pfEffectToggleMonitor => 'モニターを切り替え';

  @override
  String get pfEffectBtPairing => 'Bluetooth ペアリング';

  @override
  String get pfEffectToggleDoubleCh => 'デュアルチャンネルを切り替え';

  @override
  String get pfEffectToggleAbCh => 'A/B チャンネルを切り替え';

  @override
  String get pfEffectSendLocation => '位置情報を送信';

  @override
  String get pfEffectOneClickLink => 'ワンクリックリンク';

  @override
  String get pfEffectVolDown => '音量を下げる';

  @override
  String get pfEffectVolUp => '音量を上げる';

  @override
  String get pfEffectToggleMute => 'ミュートを切り替え';

  @override
  String pfEffectUnknown(int effect) {
    return '不明（$effect）';
  }

  @override
  String get importChannelsTitle => 'チャンネルをインポート';

  @override
  String importChannelsTitleWith(String name) {
    return 'チャンネルをインポート — $name';
  }

  @override
  String get importIntro =>
      '左側からチャンネルを無線機の位置へドラッグするか、チャンネルと位置を選択して矢印をタップします。情報アイコンをタップすると詳細が表示されます。チャンネルは OK をタップしたときにのみ無線機に書き込まれます。';

  @override
  String importOkCount(int count) {
    return 'OK（$count）';
  }

  @override
  String importImportedHeader(int count) {
    return 'インポート済み（$count）';
  }

  @override
  String get importNoChannels => 'インポートされたチャンネルはありません。';

  @override
  String importRadioChannelsHeader(int count) {
    return '無線機のチャンネル（$count）';
  }

  @override
  String get importNoRadioChannels => '無線機のチャンネルはありません。';

  @override
  String get importMoveTooltip => '選択したチャンネルを選択した位置に移動';

  @override
  String get importCopyAllTooltip => 'インポートしたすべてのチャンネルを無線機の位置に 1:1 でコピー';

  @override
  String importChannelShort(int number) {
    return 'チャンネル $number';
  }

  @override
  String get importClearTooltip => '保留中の割り当てをクリア';

  @override
  String get importChannelDetails => 'チャンネルの詳細';

  @override
  String get riTitle => '無線機の情報';

  @override
  String get riNoRadioConnected => '無線機が接続されていません';

  @override
  String get riConnectPrompt => '無線機を接続すると情報が表示されます。';

  @override
  String riRadioFallback(int id) {
    return '無線機 $id';
  }

  @override
  String get riSectionRadio => '無線機';

  @override
  String get riSectionDeviceInfo => 'デバイス情報';

  @override
  String get riSectionDeviceStatus => 'デバイスの状態';

  @override
  String get riSectionDeviceSettings => 'デバイス設定';

  @override
  String get riSectionBss => 'BSS 設定';

  @override
  String get riSectionPosition => '位置';

  @override
  String get riName => '名前';

  @override
  String get riStatus => '状態';

  @override
  String get riSettingsLabel => '設定';

  @override
  String get riNoData => 'データなし';

  @override
  String get riNoGpsData => 'GPS データなし';

  @override
  String get riNoGpsLock => 'GPS 測位なし';

  @override
  String get riGpsLocked => 'GPS 測位を取得しました';

  @override
  String get riTrue => 'はい';

  @override
  String get riFalse => 'いいえ';

  @override
  String get riPresent => 'あり';

  @override
  String get riNotPresent => 'なし';

  @override
  String get riSupported => '対応';

  @override
  String get riNotSupported => '非対応';

  @override
  String get riCurrent => '現在';

  @override
  String get riOff => 'オフ';

  @override
  String riChannelValue(int number) {
    return 'チャンネル $number';
  }

  @override
  String riSeconds(int count) {
    return '$count 秒';
  }

  @override
  String riMeters(String value) {
    return '$value メートル';
  }

  @override
  String riDegrees(String value) {
    return '$value 度';
  }

  @override
  String get riProductId => '製品 ID';

  @override
  String get riVendorId => 'ベンダー ID';

  @override
  String get riDmrSupport => 'DMR 対応';

  @override
  String get riGmrsSupport => 'GMRS 対応';

  @override
  String get riHardwareSpeaker => 'ハードウェアスピーカー';

  @override
  String get riHardwareVersion => 'ハードウェアバージョン';

  @override
  String get riSoftwareVersion => 'ソフトウェアバージョン';

  @override
  String get riRegionCount => 'リージョン数';

  @override
  String get riMediumPower => '中出力';

  @override
  String get riChannelCount => 'チャンネル数';

  @override
  String get riNoaa => 'NOAA';

  @override
  String get riWeather => '気象';

  @override
  String riWeatherChannel(int number) {
    return '気象 $number';
  }

  @override
  String get riBroadcastFm => 'FMラジオ';

  @override
  String get riRadioLabel => '無線機';

  @override
  String get riVfo => 'VFO';

  @override
  String get riFreqRangeCount => '周波数範囲数';

  @override
  String get riPowerOn => '電源オン';

  @override
  String get riInTx => '送信中';

  @override
  String get riInRx => '受信中';

  @override
  String get riDoubleChannelLabel => 'デュアルチャンネル';

  @override
  String get riScanning => 'スキャン中';

  @override
  String get riCurrentChannelId => '現在のチャンネル ID';

  @override
  String get riGpsLockedLabel => 'GPS ロック';

  @override
  String get riHfpConnected => 'HFP 接続済み';

  @override
  String get riAocConnected => 'AOC 接続済み';

  @override
  String get riRssi => 'RSSI';

  @override
  String get riCurrentRegion => '現在のリージョン';

  @override
  String get riAccuracy => '精度';

  @override
  String get riReceivedTime => '受信時刻';

  @override
  String get riGpsTimeLocal => 'GPS ローカル時刻';

  @override
  String get riGpsTimeUtcLabel => 'GPS UTC 時刻';

  @override
  String get tabDetach => '切り離し...';

  @override
  String get tabClear => 'クリア';

  @override
  String get tabSaveToFile => 'ファイルに保存...';

  @override
  String get commonNoRadioConnected => '無線機が接続されていません。';

  @override
  String errorOpeningFileDialog(String error) {
    return 'ファイルダイアログを開く際にエラーが発生しました: $error';
  }

  @override
  String errorSavingFile(String error) {
    return 'ファイルの保存中にエラーが発生しました: $error';
  }

  @override
  String get debugSaveTitle => 'デバッグログを保存';

  @override
  String debugLogSavedTo(String path) {
    return 'デバッグログを $path に保存しました';
  }

  @override
  String get debugShowBluetoothFrames => 'Bluetooth フレームを表示';

  @override
  String get debugLoopbackMode => 'ループバックモード';

  @override
  String get debugQueryDeviceNames => 'デバイス名を照会';

  @override
  String get debugRawCommand => '生コマンド...';

  @override
  String get debugAutoScroll => '自動スクロール';

  @override
  String get debugFirmwareUpdate => 'ファームウェア更新...';

  @override
  String get debugShowBuiltInMenus => '組み込みメニューを表示';

  @override
  String get packetsCopyHex => 'HEX パケットをコピー';

  @override
  String get packetsHexCopied => 'HEX パケットをクリップボードにコピーしました';

  @override
  String get packetsSaveTitle => 'パケットキャプチャを保存';

  @override
  String get packetsSaved => 'パケットキャプチャを保存しました';

  @override
  String packetsSavedTo(String path) {
    return 'パケットキャプチャを $path に保存しました';
  }

  @override
  String get packetsShowDecode => 'パケットのデコードを表示';

  @override
  String get packetsEmpty => 'キャプチャされたパケットはありません';

  @override
  String get packetsColTime => '時刻';

  @override
  String get packetsColChannel => 'チャンネル';

  @override
  String get packetsColData => 'データ';

  @override
  String get commonAdd => '追加';

  @override
  String get commonEdit => '編集';

  @override
  String get commonEditEllipsis => '編集...';

  @override
  String get commonAddEllipsis => '追加...';

  @override
  String get commonExportEllipsis => 'エクスポート...';

  @override
  String get commonImportEllipsis => 'インポート...';

  @override
  String get contactsTypeGeneric => '汎用局';

  @override
  String get contactsTypeAprs => 'APRS 局';

  @override
  String get contactsTypeTerminal => 'ターミナル局';

  @override
  String get contactsTypeBbs => 'BBS 局';

  @override
  String get contactsTypeWinlink => 'Winlink 局';

  @override
  String get contactsTypeTorrent => 'トレント局';

  @override
  String get contactsTypeAgwpe => 'AGWPE 局';

  @override
  String get contactsExists => 'このコールサインとタイプの局は既に存在します';

  @override
  String get contactsRemovePrompt => '選択した局を削除しますか？';

  @override
  String get contactsNoExport => 'エクスポートする局がありません';

  @override
  String get contactsExportTitle => '局をエクスポート';

  @override
  String get contactsImportTitle => '局をインポート';

  @override
  String contactsExported(int count) {
    return '$count 局をエクスポートしました';
  }

  @override
  String contactsImported(int count) {
    return '$count 局をインポートしました';
  }

  @override
  String get contactsUnableOpen => 'アドレス帳を開けません';

  @override
  String get contactsInvalid => 'アドレス帳が無効です';

  @override
  String get contactsColCallsign => 'コールサイン';

  @override
  String get contactsColName => '名前';

  @override
  String get contactsColDescription => '説明';

  @override
  String terminalHeaderWith(String callsign) {
    return 'ターミナル - $callsign';
  }

  @override
  String get terminalNoRadio => '接続に使用できる無線機がありません。';

  @override
  String get terminalShowCallsign => 'コールサインを表示';

  @override
  String get terminalWordWrap => '折り返し';

  @override
  String get terminalWaitForConnection => '接続を待機...';

  @override
  String get terminalWaitingForConnection => '接続を待機しています...';

  @override
  String terminalConnectedFrom(String callsign) {
    return '$callsign から接続されました';
  }

  @override
  String get terminalSend => '送信';

  @override
  String terminalConnectedTo(String callsign) {
    return '$callsign に接続しました';
  }

  @override
  String terminalConnectingTo(String callsign) {
    return '$callsign に接続中...';
  }

  @override
  String get terminalInvalidCallsignDest => 'コールサイン/宛先が無効です';

  @override
  String get terminalInvalidCallsign => 'コールサインが無効です';

  @override
  String get terminalNotConnected => '未接続';

  @override
  String terminalError(String error) {
    return 'エラー: $error';
  }

  @override
  String get terminalBrotli => 'Brotli 圧縮パケットを受信しました（非対応）';

  @override
  String get terminalSendFile => 'ファイルを送信...';

  @override
  String get terminalSaveFileTitle => '受信したファイルを保存';

  @override
  String get terminalCancelTransfer => '転送をキャンセル';

  @override
  String get terminalTransferInProgress => 'ファイル転送が既に進行中です';

  @override
  String terminalSendingFile(String filename) {
    return '$filename を送信中...';
  }

  @override
  String terminalReceivingFile(String filename) {
    return '$filename を受信中...';
  }

  @override
  String terminalFileSent(String filename) {
    return 'ファイルを送信しました: $filename';
  }

  @override
  String terminalFileReceived(String filename, int bytes) {
    return 'ファイルを受信しました: $filename（$bytes バイト）';
  }

  @override
  String terminalFileTransferError(String message) {
    return 'ファイル転送エラー: $message';
  }

  @override
  String get audioSectionDevices => 'デバイス';

  @override
  String get audioRefreshDevices => 'デバイスリストを更新';

  @override
  String get audioOutput => '出力';

  @override
  String get audioInput => '入力';

  @override
  String get audioVolume => '音量';

  @override
  String get audioSquelch => 'スケルチ';

  @override
  String get audioSectionComputer => 'コンピューター';

  @override
  String get audioApplication => 'アプリケーション';

  @override
  String get audioMaster => 'マスター';

  @override
  String get audioMicGain => 'マイクゲイン';

  @override
  String get audioMicNotAvailable => 'このプラットフォームではマイクのキャプチャを利用できません。';

  @override
  String get audioMicNotSupported => 'ここではマイクのキャプチャに対応していません。';

  @override
  String get audioSpectRadio => '無線スペクトログラフ';

  @override
  String get audioSpectMic => 'マイクスペクトログラフ';

  @override
  String get audioSpectNone => 'スペクトログラフ';

  @override
  String get audioSpectMenuNone => 'スペクトログラフなし';

  @override
  String get audioDartQuality => 'DART 受信品質';

  @override
  String get audioDartSignalAnalysis => 'DART 信号解析';

  @override
  String get audioDefault => 'デフォルト';

  @override
  String get audioMute => 'ミュート';

  @override
  String get audioUnmute => 'ミュート解除';

  @override
  String get audioEnable => '有効化';

  @override
  String get audioDisable => '無効化';

  @override
  String get audioNa => '該当なし';

  @override
  String get bbsHeaderActive => 'BBS - アクティブ';

  @override
  String get bbsActivate => '有効化';

  @override
  String get bbsDeactivate => '無効化';

  @override
  String get bbsViewTraffic => 'トラフィックを表示';

  @override
  String get bbsClearTraffic => 'トラフィックをクリア';

  @override
  String get bbsClearStats => '統計をクリア';

  @override
  String get bbsColCallSign => 'コールサイン';

  @override
  String get bbsColLastSeen => '最終確認';

  @override
  String get bbsColStats => '統計';

  @override
  String get bbsTraffic => 'トラフィック';

  @override
  String get bbsJustNow => 'たった今';

  @override
  String bbsMinAgo(int n) {
    return '$n 分前';
  }

  @override
  String bbsHoursAgo(int n) {
    return '$n 時間前';
  }

  @override
  String bbsDaysAgo(int n) {
    return '$n 日前';
  }

  @override
  String get commonDelete => '削除';

  @override
  String get torrentAddFile => 'ファイルを追加';

  @override
  String get torrentShowDetails => '詳細を表示';

  @override
  String get torrentFileSaved => 'ファイルを保存しました。';

  @override
  String get torrentFileDataUnavailable => '保存エラー: ファイルデータを利用できません';

  @override
  String get torrentUnknownError => '不明なエラー';

  @override
  String get torrentSaveTitle => 'トレントファイルを保存';

  @override
  String get torrentNoRadios => '無線機が接続されていません。先に無線機を接続してください。';

  @override
  String get torrentMultiRadio => '複数無線機のトレントモードはまだ対応していません。';

  @override
  String get torrentDropSingle => 'ファイルは 1 つだけドロップしてください。';

  @override
  String get torrentDeletePrompt => '選択したトレントファイルを削除しますか？';

  @override
  String get torrentPause => '一時停止';

  @override
  String get torrentShare => '共有';

  @override
  String get torrentRequest => 'リクエスト';

  @override
  String get torrentSaveAs => '名前を付けて保存...';

  @override
  String get torrentDropToShare => '共有するファイルをドロップ';

  @override
  String get torrentNoFiles => 'トレントファイルがありません。共有するファイルを追加またはドロップしてください。';

  @override
  String get torrentUnknownSource => '不明';

  @override
  String get torrentColFile => 'ファイル';

  @override
  String get torrentColMode => 'モード';

  @override
  String get torrentDetailFileName => 'ファイル名';

  @override
  String get torrentDetailSource => 'ソース';

  @override
  String get torrentDetailFileSize => 'ファイルサイズ';

  @override
  String torrentBytes(int count) {
    return '$count バイト';
  }

  @override
  String get torrentDetailCompression => '圧縮';

  @override
  String get torrentDetailBlocks => 'ブロック';

  @override
  String get torrentDetailsTitle => 'トレントの詳細';

  @override
  String get torrentSelectPrompt => '詳細を表示するトレントを選択してください';

  @override
  String get torrentModePaused => '一時停止中';

  @override
  String get torrentModeSharing => '共有中';

  @override
  String get torrentModeRequesting => 'リクエスト中';

  @override
  String get torrentModeError => 'エラー';

  @override
  String get torrentCompUnknown => '不明';

  @override
  String get mailInbox => '受信トレイ';

  @override
  String get mailOutbox => '送信トレイ';

  @override
  String get mailDraft => '下書き';

  @override
  String get mailSent => '送信済み';

  @override
  String get mailArchive => 'アーカイブ';

  @override
  String get mailTrash => 'ゴミ箱';

  @override
  String get mailInternet => 'インターネット';

  @override
  String get mailDeleteTitle => 'メールを削除';

  @override
  String get mailMoveToTrashTitle => 'ゴミ箱に移動';

  @override
  String get mailDeletePermanent => '選択したメールを完全に削除しますか？この操作は元に戻せません。';

  @override
  String get mailMoveToTrashPrompt => '選択したメールをゴミ箱に移動しますか？';

  @override
  String get mailMove => '移動';

  @override
  String get mailOpen => '開く';

  @override
  String get mailReply => '返信';

  @override
  String get mailReplyAll => '全員に返信';

  @override
  String get mailForward => '転送';

  @override
  String get mailShowPreview => 'プレビューを表示';

  @override
  String get mailBackup => 'メールをバックアップ...';

  @override
  String get mailRestore => 'メールを復元...';

  @override
  String get mailShowTraffic => 'トラフィックを表示...';

  @override
  String mailBackupFailed(String error) {
    return 'バックアップに失敗しました: $error';
  }

  @override
  String get mailBackupTitle => 'メールをバックアップ';

  @override
  String get mailBackupSuccess => 'バックアップが正常に完了しました。';

  @override
  String get mailRestoreTitle => 'メールを復元';

  @override
  String get mailRestoreUnableOpen => 'バックアップファイルを開けません';

  @override
  String mailRestoreFailed(String error) {
    return '復元に失敗しました: $error';
  }

  @override
  String get mailNew => '新規';

  @override
  String get mailNewMail => '新規メール';

  @override
  String get mailColTime => '時刻';

  @override
  String get mailColTo => '宛先';

  @override
  String get mailColFrom => '差出人';

  @override
  String get mailColSubject => '件名';

  @override
  String get mailSelectPreview => 'プレビューするメッセージを選択してください';

  @override
  String get commonUnknown => '不明';

  @override
  String get mapOfflineMode => 'オフラインモード';

  @override
  String get mapOfflineMap => 'オフライン地図';

  @override
  String get mapCacheArea => 'エリアをキャッシュ...';

  @override
  String get mapCenterGps => 'GPS を中心に表示';

  @override
  String get mapShowTracks => '軌跡を表示';

  @override
  String get mapShowMarkers => 'マーカーを表示';

  @override
  String get mapShowAirplanes => '航空機を表示';

  @override
  String get mapLargeMarkers => '大きなマーカー';

  @override
  String get mapShowContactsOnly => '連絡先のみ表示';

  @override
  String get mapFilterAll => 'すべて';

  @override
  String get mapFilterLast30 => '過去 30 分';

  @override
  String get mapFilterLastHour => '過去 1 時間';

  @override
  String get mapFilterLast6 => '過去 6 時間';

  @override
  String get mapFilterLast12 => '過去 12 時間';

  @override
  String get mapFilterLast24 => '過去 24 時間';

  @override
  String get mapCacheTitle => '地図エリアをキャッシュ';

  @override
  String mapCachePrompt(int count, int minZoom, int maxZoom) {
    return 'ズームレベル $minZoom〜$maxZoom の $count 個のタイルをダウンロードしますか？\n\n選択したエリアがオフライン使用のためにキャッシュされます。';
  }

  @override
  String get mapDownloadingTitle => 'タイルをダウンロード中';

  @override
  String mapTilesProgress(int done, int total) {
    return '$done / $total タイル';
  }

  @override
  String get mapDragToSelect => 'キャッシュするエリアをドラッグして選択してください';

  @override
  String get aprsNoChannel => 'APRS チャンネルを持つ無線機がありません';

  @override
  String get aprsNoLoadedChannels => 'チャンネルが読み込まれた無線機がありません';

  @override
  String get aprsDetails => '詳細...';

  @override
  String get aprsShowLocation => '位置を表示...';

  @override
  String get aprsSetReceiver => '受信者に設定';

  @override
  String get aprsCopyMessage => 'メッセージをコピー';

  @override
  String get aprsCopyCallsign => 'コールサインをコピー';

  @override
  String get aprsCopyChannel => 'チャンネルをコピー';

  @override
  String get aprsClearTitle => 'APRS メッセージをクリア';

  @override
  String get aprsClearPrompt =>
      'すべての APRS メッセージをクリアしますか？これにより地図上のすべての APRS マーカーも削除されます。この操作は元に戻せません。';

  @override
  String get aprsShowAll => 'すべてのメッセージを表示';

  @override
  String get aprsSendSms => 'SMS メッセージを送信...';

  @override
  String get aprsWeatherReport => '気象レポート...';

  @override
  String get aprsBeaconSettingsMenu => 'ビーコン設定...';

  @override
  String get aprsDigipeaterMenu => 'デジピーター...';

  @override
  String get digipeaterTitle => 'APRS デジピーター';

  @override
  String get digipeaterIntro =>
      'デジピーターは、APRS チャンネルで受信した対象の APRS パケットを再送信します。有効な場合、選択した無線機は APRS チャンネルにロックされます。';

  @override
  String get digipeaterEnable => 'デジピーターを有効にする';

  @override
  String get digipeaterRadio => '無線機';

  @override
  String get digipeaterHandleWideN => 'WIDEn-N パケットを中継する';

  @override
  String get digipeaterFillIn => 'フィルインのみ (WIDE1-1)';

  @override
  String get digipeaterSubstituteCall => '自分のコールサインを経路に挿入する';

  @override
  String get digipeaterMaxHops => '最大ホップ数';

  @override
  String get digipeaterDedupSeconds => '重複除外ウィンドウ (秒)';

  @override
  String get digipeaterAliases => 'カスタムエイリアス';

  @override
  String get digipeaterAliasesHint => '例: RELAY, WIDE1-1';

  @override
  String get digipeaterAliasesInvalid => '1つ以上のエイリアスが有効なコールサインではありません。';

  @override
  String get digipeaterNoCallsign => 'デジピーターを使用する前に、設定でコールサインを構成してください。';

  @override
  String get digipeaterNoAprsChannel =>
      '選択した無線機に APRS チャンネルがありません。デジピーターを有効にするには構成してください。';

  @override
  String get aprsDropShare => 'このチャンネルを共有するにはドロップ';

  @override
  String get aprsBeaconWarning =>
      '現在のチャンネルでビーコンのブロードキャストが有効になっていますが、これは推奨されません。';

  @override
  String aprsBeaconActive(String interval) {
    return '無線ビーコンがアクティブです。間隔: $interval。';
  }

  @override
  String get aprsBeaconSettings => 'ビーコン設定';

  @override
  String aprsIntervalSeconds(int count) {
    return '$count 秒';
  }

  @override
  String get aprsIntervalMinute => '1 分';

  @override
  String aprsIntervalMinutes(int count) {
    return '$count 分';
  }

  @override
  String get aprsMissingChannel =>
      '接続中の無線機に「APRS」チャンネルが設定されていません。APRS メッセージを送受信するには APRS チャンネルを追加してください。';

  @override
  String get aprsSetup => '設定';

  @override
  String get aprsTypeMessage => 'メッセージを入力...';

  @override
  String get commonYes => 'はい';

  @override
  String get commonNo => 'いいえ';

  @override
  String get commonSend => '送信';

  @override
  String commonSavedTo(String path) {
    return '$path に保存しました';
  }

  @override
  String commsFailedLoadImage(String error) {
    return '画像の読み込みに失敗しました: $error';
  }

  @override
  String commsFailedSaveImage(String error) {
    return '画像の保存に失敗しました: $error';
  }

  @override
  String commsFailedEncodeSstv(String error) {
    return 'SSTV オーディオのエンコードに失敗しました: $error';
  }

  @override
  String commsFailedLoadAudio(String error) {
    return 'オーディオの読み込みに失敗しました: $error';
  }

  @override
  String get commsUnsupportedWav => '非対応または空の WAV ファイルです。';

  @override
  String get commsSstvWebUnavailable => 'Web では SSTV 画像の録画/送信を利用できません。';

  @override
  String get commsNoRadioVoice => '音声送信用の無線機が接続されていません。';

  @override
  String get commsSelectImageTitle => 'SSTV 用の画像を選択';

  @override
  String get commsSelectWavTitle => 'WAV オーディオファイルを選択';

  @override
  String get commsRecordingWebUnavailable => 'Web ではファイルからの録音再生を利用できません。';

  @override
  String get commsFileNoLongerExists => 'ファイルはもう存在しません。';

  @override
  String get commsSaveAsTitle => '名前を付けて保存';

  @override
  String get commsTransmitDisabledAprs =>
      'VFO A が APRS チャンネルに設定されている場合、送信は無効になります。';

  @override
  String get commsWaitTransmission => '現在の送信が完了するまでお待ちください。';

  @override
  String get commsConnectRadioChat => 'チャットメッセージを送信する前に無線機を接続してください。';

  @override
  String get commsEnableAudioMode => 'このモードで送信する前にオーディオ（「有効化」ボタン）を有効にしてください。';

  @override
  String get commsMicNotSupported => 'このプラットフォームではマイクのキャプチャに対応していません。';

  @override
  String get commsConnectRadioPtt => 'プッシュトゥトークを使用する前に無線機を接続してください。';

  @override
  String get commsEnableAudioPtt =>
      'プッシュトゥトークを使用する前にオーディオ（「有効化」ボタン）を有効にしてください。';

  @override
  String get commsSwitchChatShare => 'チャンネルを共有するにはチャットモードに切り替えてください。';

  @override
  String get commsModePtt => 'PTT';

  @override
  String get commsModeChat => 'チャット';

  @override
  String get commsModeSpeak => '読み上げ';

  @override
  String get commsModeMorse => 'モールス';

  @override
  String get commsModeDtmf => 'DTMF';

  @override
  String get commsRecordAudio => 'オーディオを録音';

  @override
  String get commsSendImage => '画像を送信...';

  @override
  String get commsSendAudio => 'オーディオを送信...';

  @override
  String get commsPttReleaseSettings => 'PTT リリース設定...';

  @override
  String get commsClearHistory => '履歴をクリア';

  @override
  String get commsShowImage => '画像を表示...';

  @override
  String get commsPlayRecording => '録音を再生...';

  @override
  String get commsSaveAsMenu => '名前を付けて保存...';

  @override
  String get commsShowLocation => '位置を表示';

  @override
  String get commsClearHistoryPrompt => '音声履歴を本当にクリアしますか？';

  @override
  String get commsAudioMuted => 'オーディオはミュートされています。';

  @override
  String get commsUnmute => 'ミュート解除';

  @override
  String get commsPttTransmitting => '送信中...';

  @override
  String get commsPttHold => 'PTT - 押している間送信';

  @override
  String get commsDtmfHint => 'DTMF 数字を入力（0-9、*、#）...';

  @override
  String get mailComposeNewTitle => '新規メッセージ';

  @override
  String get mailComposeEditTitle => 'メッセージを編集';

  @override
  String get mailDiscardChanges => 'このメッセージの変更を破棄しますか？';

  @override
  String get mailDiscardMessage => 'このメッセージを破棄しますか？';

  @override
  String get mailDiscard => '破棄';

  @override
  String get mailAddCc => 'Cc を追加';

  @override
  String get mailCc => 'Cc';

  @override
  String get mailRemoveCc => 'Cc を削除';

  @override
  String get mailMessageLabel => 'メッセージ';

  @override
  String get mailSaveDraft => '下書きを保存';

  @override
  String get mailAttachmentsLabel => '添付ファイル';

  @override
  String get mailAddAttachment => '添付ファイルを追加';

  @override
  String get mailRemoveAttachment => '添付ファイルを削除';

  @override
  String get mailSaveAttachment => '添付ファイルを保存';

  @override
  String get mailAttachmentDropHint => 'ここにファイルをドラッグ＆ドロップして添付';

  @override
  String mailAttachmentReadFailed(String name) {
    return 'ファイルを読み込めませんでした: $name';
  }

  @override
  String mailAttachmentSaved(String name) {
    return '「$name」を保存しました';
  }

  @override
  String mailAttachmentLargeWarning(String size) {
    return '大きな添付ファイル（$size）は無線での送信に時間がかかることがあります。';
  }

  @override
  String get smsTitle => 'SMS メッセージを送信';

  @override
  String get smsPhoneNumber => '電話番号';

  @override
  String get smsIntro =>
      '米国、プエルトリコ、カナダ、オーストラリア、英国の電話に SMS メッセージを送信できます。ただし、その番号が既にサービスを承認している必要があります。次の場所で登録できます: ';

  @override
  String get locationTitle => '位置';

  @override
  String get beaconIntro =>
      '位置、電圧、カスタムメッセージなど、無線機が自身の情報をブロードキャストする方法を変更します。近くの他の局はこの情報を見ることができます。';

  @override
  String beaconRadio(String name) {
    return '無線機: $name';
  }

  @override
  String get beaconSection => 'ビーコン';

  @override
  String get beaconPacketFormat => 'パケット形式';

  @override
  String get beaconInterval => 'ビーコン間隔';

  @override
  String get beaconAprsCallsign => 'APRS コールサイン';

  @override
  String get beaconCallsignHint => 'コールサイン - 局 ID';

  @override
  String get beaconCallsignInvalid => '有効なコールサインと局 ID を入力してください（例: W1AW-5）';

  @override
  String get beaconAprsMessage => 'APRS メッセージ';

  @override
  String get beaconShareLocation => '位置を共有';

  @override
  String get beaconSendVoltage => '電圧を送信';

  @override
  String get beaconAllowPositionCheck => '位置チェックを許可';

  @override
  String get beaconChannelCurrent => '現在（非推奨）';

  @override
  String beaconEverySeconds(int n) {
    return '$n 秒ごと';
  }

  @override
  String beaconEveryMinutes(int n) {
    return '$n 分ごと';
  }

  @override
  String get assConnectTerminal => 'ターミナル局に接続';

  @override
  String get assConnectBbs => 'BBS 局に接続';

  @override
  String get assConnectWinlink => 'Winlink ゲートウェイに接続';

  @override
  String get assConnectStation => '局に接続';

  @override
  String get assNew => '新規…';

  @override
  String get attSelectFile => '共有するファイルを選択';

  @override
  String get attCompressing => '圧縮中...';

  @override
  String get attTitle => 'トレントファイルを追加';

  @override
  String get attSelect => '選択...';

  @override
  String get attDescriptionOptional => '説明（任意）';

  @override
  String get stationTitleVoice => '音声局';

  @override
  String get stationTitleAprs => 'APRS 局';

  @override
  String get stationTitleTerminal => 'ターミナル局';

  @override
  String get stationTitleWinlink => 'Winlink ゲートウェイ';

  @override
  String get stationTitleGeneric => '局';

  @override
  String get stationTypeOptionVoice => '音声 / 汎用局';

  @override
  String get stationTypeLabel => '局のタイプ';

  @override
  String get stationAprsRoute => 'APRS ルート';

  @override
  String get stationUseAuth => 'メッセージ認証を使用';

  @override
  String get stationAuthPassword => '認証パスワード';

  @override
  String get stationPasswordRequired => 'パスワードが必要です';

  @override
  String get stationTerminalProtocol => 'ターミナルプロトコル';

  @override
  String get stationAx25Destination => 'AX.25 宛先（例: CALL-1）';

  @override
  String get stationAx25Invalid => 'AX.25 アドレスが無効です';

  @override
  String get stationModem => 'モデム';

  @override
  String get apdTitle => 'APRS パケットの詳細';

  @override
  String get apdCopyAll => 'すべてコピー';

  @override
  String get apdCopyValue => '値をコピー';

  @override
  String get apdValueCopied => '値をコピーしました';

  @override
  String get apdAllValuesCopied => 'すべての値をコピーしました';

  @override
  String get apdNoDetails => '利用可能な詳細はありません。';

  @override
  String get apdShowLocation => '位置を表示...';

  @override
  String get acfgTitle => 'APRS チャンネルを設定';

  @override
  String get acfgIntro =>
      'APRS 周波数は世界の地域によって異なります。このサイトを使用して適切な周波数を見つけ、APRS チャンネルを設定してください。';

  @override
  String get acfgConfiguration => 'APRS 設定';

  @override
  String get acfgFrequency => '周波数';

  @override
  String get acfgFrequencyHint => '北米 144.39\nヨーロッパ 144.80';

  @override
  String get acfgChannelOverwritten => '選択したチャンネルは上書きされます';

  @override
  String get sstvSendTitle => 'SSTV 画像を送信';

  @override
  String sstvSendTitleNamed(String name) {
    return 'SSTV 画像を送信 - $name';
  }

  @override
  String get sstvMode => 'モード:';

  @override
  String sstvTransmitTime(String time) {
    return '送信時間: 約 $time';
  }

  @override
  String get msgdTitle => 'メッセージの詳細';

  @override
  String get msgdFieldType => 'タイプ';

  @override
  String get msgdFieldDirection => '方向';

  @override
  String get msgdFieldTime => '時刻';

  @override
  String get msgdFieldSource => 'ソース';

  @override
  String get msgdFieldReceiver => '受信者';

  @override
  String get msgdFieldDuration => '長さ';

  @override
  String get msgdFieldLatitude => '緯度';

  @override
  String get msgdFieldLongitude => '経度';

  @override
  String get msgdFieldMessage => 'メッセージ';

  @override
  String get msgdFieldFile => 'ファイル';

  @override
  String get msgdDirReceived => '受信';

  @override
  String get msgdDirSent => '送信';

  @override
  String get msgdTypeVoice => '音声';

  @override
  String get msgdTypeVoiceClip => '音声クリップ';

  @override
  String get msgdTypeRecording => '録音';

  @override
  String get msgdTypeSstvPicture => 'SSTV 画像';

  @override
  String get msgdTypeIdentification => '識別';

  @override
  String get msgdTypeChatMessage => 'チャットメッセージ';

  @override
  String get msgdTypeAx25Packet => 'AX.25 パケット';

  @override
  String get rpbFailedToLoad => '録音の読み込みに失敗しました。';

  @override
  String get ivwFailedToLoad => '画像の読み込みに失敗しました。';

  @override
  String get rawTitle => '生の無線コマンド';

  @override
  String get rawCommand => 'コマンド';

  @override
  String get rawHexPayload => 'HEX ペイロード（任意）';

  @override
  String get rawResponse => '応答';

  @override
  String get identTitle => 'PTT リリース設定';

  @override
  String get identDescription =>
      '有効にすると、送信中のチャンネルで PTT を離すたびに、コールサインや位置情報を送信します。';

  @override
  String get identCallsignHint => 'コールサイン - 局 ID を入力';

  @override
  String get identSendCallsign => 'コールサインを送信';

  @override
  String get identSendPosition => '位置を送信';

  @override
  String get commonOn => 'オン';

  @override
  String get commonOff => 'オフ';

  @override
  String get commonNone => 'なし';

  @override
  String chChannelNumber(int n) {
    return 'チャンネル $n';
  }

  @override
  String chChShort(int n) {
    return 'チャンネル $n';
  }

  @override
  String get chMoreSettings => '詳細設定';

  @override
  String get chChannelNameHint => 'チャンネル名';

  @override
  String get chFrequencyMhz => '周波数 (MHz)';

  @override
  String get chReceiveMhz => '受信 (MHz)';

  @override
  String get chTransmitMhz => '送信 (MHz)';

  @override
  String get chMode => 'モード';

  @override
  String get chPower => '出力';

  @override
  String get chBandwidth => '帯域幅';

  @override
  String get chReceiveTone => '受信トーン（CTCSS / DCS）';

  @override
  String get chTransmitTone => '送信トーン（CTCSS / DCS）';

  @override
  String get chDisableTransmit => '送信を無効化';

  @override
  String get chMute => 'ミュート';

  @override
  String get chScan => 'スキャン';

  @override
  String get chTalkAround => 'トークアラウンド';

  @override
  String get chDeemphasis => 'ディエンファシス';

  @override
  String get chPowerHigh => '高';

  @override
  String get chPowerMedium => '中';

  @override
  String get chPowerLow => '低';

  @override
  String get chBandwidthWide => '25 KHz ワイド';

  @override
  String get chBandwidthNarrow => '12.5 KHz ナロー';

  @override
  String get channelImportFetching => 'ウェブページからチャンネルを取得しています…';

  @override
  String get channelImportUnsupportedSite => 'このウェブサイトはチャンネルのインポートに対応していません。';

  @override
  String get channelImportFetchFailed => 'ウェブページをダウンロードできませんでした。';

  @override
  String get channelImportParseFailed => 'そのページにチャンネル情報が見つかりませんでした。';

  @override
  String get chClearTitle => 'チャンネルをクリア';

  @override
  String chClearConfirm(int n) {
    return 'チャンネル $n をクリアしますか？\n\nこれにより、無線機のこの位置の周波数、名前、設定が削除されます。';
  }

  @override
  String get cdRxFrequency => 'RX 周波数';

  @override
  String get cdTxFrequency => 'TX 周波数';

  @override
  String get cdRxModulation => 'RX 変調';

  @override
  String get cdTxModulation => 'TX 変調';

  @override
  String get cdRxTone => 'RX トーン';

  @override
  String get cdTxTone => 'TX トーン';

  @override
  String get cdTxDisabled => '送信が無効';

  @override
  String get cdTalkAround => 'トークアラウンド';

  @override
  String get cdEmpty => '（空）';

  @override
  String get cdBandwidthWide => '25 kHz（ワイド）';

  @override
  String get cdBandwidthNarrow => '12.5 kHz（ナロー）';

  @override
  String get gpsDetailsTitle => 'GPS の詳細';

  @override
  String get gpsDisabled => 'GPS 無効';

  @override
  String get gpsLock => 'GPS ロック';

  @override
  String get gpsNoLock => 'GPS ロックなし';

  @override
  String get mdbgTitle => 'Winlink トラフィック';

  @override
  String get mdbgNoTraffic => '現在トラフィックはありません。';

  @override
  String get fwTitle => '無線機のファームウェア更新';

  @override
  String get fwStatusInitial =>
      'オンラインでファームウェア更新を確認するか、ディスクからファームウェアファイルを読み込みます。';

  @override
  String get fwErrNotConnected => '無線機が接続されていません。';

  @override
  String get fwErrNoDeviceInfo => '無線機のデバイス情報がまだ利用できません。';

  @override
  String get fwStatusChecking => 'ファームウェア更新を確認中…';

  @override
  String get fwErrNoServerInfo => 'ベンダーサーバーがファームウェア情報を返しませんでした。';

  @override
  String fwUpdateAvailable(String version) {
    return 'ファームウェア更新 $version が利用可能です。以下のリリースノートを確認してから、ダウンロードして更新してください。';
  }

  @override
  String fwErrCheckFailed(String error) {
    return '更新の確認に失敗しました: $error';
  }

  @override
  String get fwPickTitle => 'ファームウェアファイルを選択';

  @override
  String fwLoaded(String name, String size, String md5) {
    return '$name を読み込みました: $size（MD5 $md5…）。';
  }

  @override
  String fwErrLoadFailed(String error) {
    return 'ファームウェアファイルを読み込めません: $error';
  }

  @override
  String get fwSaveTitle => 'ファームウェアファイルを保存';

  @override
  String fwSavedTo(String path) {
    return 'ファームウェアを $path に保存しました';
  }

  @override
  String fwErrSaveFailed(String error) {
    return 'ファームウェアファイルを保存できません: $error';
  }

  @override
  String get fwStatusDownloading => 'ファームウェアをダウンロードして組み立て中…';

  @override
  String get fwProgressStarting => '開始中…';

  @override
  String fwReady(String size, String md5) {
    return 'ファームウェアの準備ができました: $size（MD5 $md5…）。';
  }

  @override
  String fwErrDownloadFailed(String error) {
    return 'ダウンロードに失敗しました: $error';
  }

  @override
  String get fwStatusWriting => 'ファームウェアを無線機に書き込み中です。電源を切らないでください。';

  @override
  String get fwProgressTransferring => '転送中…';

  @override
  String fwErrTransferFailed(String error) {
    return 'ファームウェアの転送に失敗しました: $error';
  }

  @override
  String get fwStatusRebooting => '無線機を再起動しています。再接続中…';

  @override
  String get fwProgressWaitingRestart => '無線機の再起動を待機中…';

  @override
  String fwErrReconnectFailed(String error) {
    return '再起動後の再接続に失敗しました: $error';
  }

  @override
  String get fwErrReconnectNull =>
      '再起動後に無線機に再接続できません。ファームウェアは転送されましたが確認されていません。手動で再接続して再試行してください。';

  @override
  String get fwStatusFinalising => '更新を完了中…';

  @override
  String get fwProgressConfirming => '確認中…';

  @override
  String fwErrConfirmFailed(String error) {
    return '更新の確認に失敗しました: $error';
  }

  @override
  String get fwStatusComplete => 'ファームウェアの更新が完了しました！無線機は新しいファームウェアで動作しています。';

  @override
  String get fwProgressDownloadPatch => 'パッチをダウンロード中';

  @override
  String get fwProgressDownloadBase => 'ベースイメージをダウンロード中';

  @override
  String get fwProgressAssemble => 'ファームウェアを組み立て中';

  @override
  String fwProgressBytes(String label, String done, String total) {
    return '$label（$done / $total）';
  }

  @override
  String fwProgressTransferringBytes(String done, String total) {
    return '転送中（$done / $total）';
  }

  @override
  String fwCurrentFirmware(String version) {
    return '現在のファームウェア: $version';
  }

  @override
  String get fwErrGeneric => 'エラーが発生しました。';

  @override
  String get fwIdleDisclosure =>
      'オンライン確認では無線機ベンダーのサーバー（rpc.benshikj.com）に接続し、無線機の製品識別子のみを送信します。「更新を確認」をタップするまで何も送信されません。';

  @override
  String get fwWhatsNew => '新機能';

  @override
  String get fwConfirmWarning =>
      '警告: プロセス全体を通して無線機の電源を入れ、充電し、Bluetooth の範囲内に保ってください。無線機は途中で再起動します。更新を中断すると手動での復旧が必要になる場合があります。';

  @override
  String get fwFromFile => 'ファイルから…';

  @override
  String get fwCheckForUpdate => '更新を確認';

  @override
  String get fwDownload => 'ダウンロード';

  @override
  String get fwSave => '保存…';

  @override
  String get fwFlashNow => '今すぐ書き込む';

  @override
  String get fwRetry => '再試行';

  @override
  String get wxTitle => '気象レポートを要求';

  @override
  String get wxIntro => 'APRS 経由で気象レポートを要求します。';

  @override
  String get wxLocation => '場所';

  @override
  String get wxLocationHelper => '米国の都市/州または米国の郵便番号、または座標 41.123/-121.334';

  @override
  String get wxTime => '時間帯';

  @override
  String get wxReport => 'レポート';

  @override
  String get wxToday => '今日';

  @override
  String get wxTonight => '今夜';

  @override
  String get wxTomorrow => '明日';

  @override
  String get wxTomorrowNight => '明日の夜';

  @override
  String get wxMonday => '月曜日';

  @override
  String get wxMondayNight => '月曜日の夜';

  @override
  String get wxTuesday => '火曜日';

  @override
  String get wxTuesdayNight => '火曜日の夜';

  @override
  String get wxWednesday => '水曜日';

  @override
  String get wxWednesdayNight => '水曜日の夜';

  @override
  String get wxThursday => '木曜日';

  @override
  String get wxThursdayNight => '木曜日の夜';

  @override
  String get wxFriday => '金曜日';

  @override
  String get wxFridayNight => '金曜日の夜';

  @override
  String get wxSaturday => '土曜日';

  @override
  String get wxSaturdayNight => '土曜日の夜';

  @override
  String get wxSunday => '日曜日';

  @override
  String get wxSundayNight => '日曜日の夜';

  @override
  String get wxReportBrief => '簡易、短期予報、米国のみ';

  @override
  String get wxReportFull => '完全、より詳細な予報、米国のみ';

  @override
  String get wxReportCurrent => '現在、最寄りの NWS 局、米国のみ';

  @override
  String get wxReportMetar => 'METAR、ICAO 局の METAR 形式';

  @override
  String get wxReportCwop => 'CWOP、最寄りの CWOP 局';

  @override
  String get cslViewCallsign => 'コールサインを検索...';

  @override
  String get cslTitle => 'コールサイン検索';

  @override
  String cslLookingUp(String callsign) {
    return '$callsign を検索しています...';
  }

  @override
  String cslNotFound(String callsign) {
    return '$callsign のレコードが見つかりませんでした。';
  }

  @override
  String get cslNoDatabase =>
      'コールサインデータベースがインストールされていません。オフライン検索を有効にするには、設定でダウンロードしてください。';

  @override
  String get cslUnsupported => 'オフラインのコールサイン検索は、このプラットフォームでは利用できません。';

  @override
  String get cslFieldCallsign => 'コールサイン';

  @override
  String get cslFieldName => '名前';

  @override
  String get cslFieldClass => '免許クラス';

  @override
  String get cslFieldStatus => '状態';

  @override
  String get cslFieldLocation => '所在地';

  @override
  String get cslFieldExpires => '有効期限';

  @override
  String get cslSectionTitle => 'コールサインデータベース';

  @override
  String get cslSectionIntro =>
      'FCC 免許データベースのデータを使用した、米国アマチュア無線コールサインのオフライン検索。';

  @override
  String get cslNotInstalled => '未インストール';

  @override
  String cslInstalledInfo(String version, String count) {
    return 'バージョン $version • $count 件';
  }

  @override
  String get cslDownload => 'ダウンロード';

  @override
  String get cslUpdate => '更新を確認';

  @override
  String get cslDelete => '削除';

  @override
  String cslDownloading(String percent) {
    return 'ダウンロード中 $percent%';
  }

  @override
  String get cslInstalling => 'インストール中...';

  @override
  String get cslUpToDate => 'コールサインデータベースは最新です。';

  @override
  String cslDownloadFailed(String error) {
    return 'ダウンロードに失敗しました: $error';
  }

  @override
  String get cslDeleteTitle => 'コールサインデータベースを削除';

  @override
  String get cslDeleteMessage => 'ダウンロードしたコールサインデータベースを削除しますか？後で再度ダウンロードできます。';
}
