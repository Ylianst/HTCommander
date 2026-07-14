// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Handi-Talkie Commander';

  @override
  String get menuFile => '文件';

  @override
  String get menuConnect => '连接...';

  @override
  String get menuDisconnect => '断开连接';

  @override
  String get menuSettings => '设置...';

  @override
  String get menuExit => '退出';

  @override
  String get menuDualWatch => '双频监听';

  @override
  String get menuScan => '扫描';

  @override
  String get menuRegions => '分区';

  @override
  String get menuTrustedDevices => '受信任的设备...';

  @override
  String get menuButtons => '按键...';

  @override
  String get menuExportChannels => '导出信道...';

  @override
  String get menuImportChannels => '导入信道...';

  @override
  String get menuMacRadio => '电台';

  @override
  String get menuMacDisplay => '显示';

  @override
  String get commonClose => '关闭';

  @override
  String get commonCancel => '取消';

  @override
  String get commonOk => '确定';

  @override
  String get aboutCheckForUpdates => '检查更新';

  @override
  String aboutVersionAuthor(String version) {
    return '版本 $version\nYlian Saint-Hilaire, KK7VZT\n开源，Apache 2.0 许可证';
  }

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageHint => '选择应用程序使用的语言。“系统默认”将跟随设备语言。';

  @override
  String get languageSystem => '系统默认';

  @override
  String get languageEnglish => '英语';

  @override
  String get languageFrench => '法语';

  @override
  String get languageSpanish => '西班牙语';

  @override
  String get languageChinese => '中文';

  @override
  String get languageJapanese => '日语';

  @override
  String get languageHindi => '印地语';

  @override
  String get languageGerman => '德语';

  @override
  String get menuAudio => '音频';

  @override
  String get menuAudioEnabled => '已启用音频';

  @override
  String get menuSoftwareModem => '软件调制解调器';

  @override
  String get menuModemDisabled => '已禁用';

  @override
  String get menuDartTransmitLevel => 'DART 发送等级';

  @override
  String get menuDartLevel0 => '等级 0（BPSK，LDPC 1/2）';

  @override
  String get menuDartLevel1 => '等级 1（QPSK，LDPC 1/2）';

  @override
  String get menuDartLevel2 => '等级 2（QPSK，LDPC 2/3）';

  @override
  String get menuDartLevel3 => '等级 3（8PSK，LDPC 2/3）';

  @override
  String get menuDartLevel4 => '等级 4（16QAM，LDPC 3/4）';

  @override
  String get menuDartLevel5 => '等级 5（16QAM，LDPC 5/6）';

  @override
  String get menuDartLevelF => '等级 F（4-FSK，LDPC 1/2）';

  @override
  String get menuAprsModem => 'APRS 调制解调器';

  @override
  String get menuView => '视图';

  @override
  String get menuRadio => '电台';

  @override
  String get menuTabs => '标签页';

  @override
  String get menuTabNames => '标签页名称';

  @override
  String get menuShowAllTabs => '显示所有标签页';

  @override
  String get menuAllChannels => '所有信道';

  @override
  String get menuHelp => '帮助';

  @override
  String get menuRadioInformation => '电台信息...';

  @override
  String get menuGpsInformation => 'GPS 信息...';

  @override
  String get menuCheckForUpdatesEllipsis => '检查更新...';

  @override
  String get menuAbout => '关于...';

  @override
  String get tabComms => '通信';

  @override
  String get tabAudio => '音频';

  @override
  String get tabAprs => 'APRS';

  @override
  String get tabMap => '地图';

  @override
  String get tabMail => '邮件';

  @override
  String get tabTerminal => '终端';

  @override
  String get tabContacts => '联系人';

  @override
  String get tabBbs => 'BBS';

  @override
  String get tabTorrent => '种子';

  @override
  String get tabPackets => '数据包';

  @override
  String get tabDebug => '调试';

  @override
  String get tabRadio => '电台';

  @override
  String get stateDisconnected => '已断开';

  @override
  String get stateConnecting => '正在连接...';

  @override
  String get stateConnected => '已连接';

  @override
  String get stateUnableToConnect => '无法连接';

  @override
  String get stateAccessDenied => '访问被拒绝';

  @override
  String get stateSelectRadio => '选择电台';

  @override
  String statusBattery(int percent) {
    return '电量：$percent %';
  }

  @override
  String get statusCheckingBluetooth => '正在检查蓝牙...';

  @override
  String get statusBluetoothNotAvailable => '蓝牙不可用';

  @override
  String get statusScanningForRadios => '正在搜索电台...';

  @override
  String get statusErrorScanning => '搜索电台时出错';

  @override
  String get statusNoCompatibleRadios => '未找到兼容的电台';

  @override
  String get statusAllRadiosConnected => '所有电台均已连接';

  @override
  String statusConnectingTo(String name) {
    return '正在连接到 $name...';
  }

  @override
  String statusConnectedTo(String name) {
    return '已连接到 $name';
  }

  @override
  String statusFailedToConnect(String name) {
    return '连接 $name 失败';
  }

  @override
  String get statusDisconnecting => '正在断开连接...';

  @override
  String get settingsTabLicense => '许可';

  @override
  String get settingsTabAprs => 'APRS';

  @override
  String get settingsTabComms => '通信';

  @override
  String get settingsTabWinlink => 'Winlink';

  @override
  String get settingsTabServers => '服务器';

  @override
  String get settingsTabMap => '地图';

  @override
  String get settingsTabLimits => '限制';

  @override
  String get settingsTabApplication => '应用程序';

  @override
  String get settingsAdd => '添加';

  @override
  String get settingsRemove => '移除';

  @override
  String get settingsDownload => '下载';

  @override
  String get settingsRetry => '重试';

  @override
  String get settingsPreview => '预览';

  @override
  String get settingsNone => '无';

  @override
  String get settingsLicenseInfo => '在美国，发射需要业余无线电执照。有关获取执照的更多信息，请访问 ARRL 网站。';

  @override
  String get settingsCallSignStationId => '呼号和台站 ID';

  @override
  String get settingsCallSign => '呼号';

  @override
  String get settingsCallSignHint => '例如 W1AW';

  @override
  String get settingsStationId => '台站 ID';

  @override
  String get settingsAllowTransmit => '允许此应用程序发射';

  @override
  String get settingsCallSignHelp => '输入有效的呼号（至少 3 个字符）以启用发射';

  @override
  String get settingsAprsIntro => '配置用于数据包发送的 APRS 路由路径。';

  @override
  String get settingsAprsRoutes => 'APRS 路由';

  @override
  String get settingsEditRoute => '编辑路由';

  @override
  String get settingsEditRouteProtected => '内置路由无法编辑';

  @override
  String get settingsDeleteRoute => '删除路由';

  @override
  String get settingsDeleteRouteProtected => '内置路由无法删除';

  @override
  String get settingsCommsIntro => '配置语音识别和语音合成设置。';

  @override
  String get settingsSpeechToText => '语音识别';

  @override
  String get settingsSpeechToTextInfo =>
      '将接收到的电台音频转录为文本。完全在本设备上离线运行；音频绝不会保存到磁盘。';

  @override
  String get settingsModel => '模型';

  @override
  String get settingsRecognitionLanguage => '识别语言';

  @override
  String get settingsRecognitionLanguageHelp => '语言更改将在下次启动引擎时生效。';

  @override
  String get settingsStatus => '状态';

  @override
  String settingsModelInstalled(String suffix) {
    return '模型已安装$suffix';
  }

  @override
  String settingsDownloadingModelPct(String percent) {
    return '正在下载模型… $percent %';
  }

  @override
  String get settingsDownloadingModel => '正在下载模型…';

  @override
  String settingsInstallingModelPct(String percent) {
    return '正在安装模型… $percent %';
  }

  @override
  String get settingsInstallingModel => '正在安装模型…';

  @override
  String get settingsModelInstallError => '无法安装模型。';

  @override
  String settingsModelNotDownloaded(String downloadLabel) {
    return '模型未下载。$downloadLabel仅进行一次，并缓存在本设备上。';
  }

  @override
  String settingsBytesOf(String received, String total) {
    return '$received / $total';
  }

  @override
  String get settingsRemoveSttModelTitle => '移除语音识别模型？';

  @override
  String settingsRemoveSttModelBody(String name) {
    return '将删除已下载的模型“$name”以释放磁盘空间。下次使用时将重新下载。';
  }

  @override
  String get settingsTextToSpeech => '语音合成';

  @override
  String get settingsTextToSpeechInfo => '在“通信”标签页中以“语音”模式发送文本时使用。';

  @override
  String get settingsTtsUnavailableTitle => '语音合成不可用';

  @override
  String get settingsVoice => '语音';

  @override
  String get settingsSpeechRate => '语速';

  @override
  String get settingsPitch => '音调';

  @override
  String get settingsLoadingVoices => '正在加载语音…';

  @override
  String get settingsSystemDefault => '系统默认';

  @override
  String get settingsLangAutoDetect => '自动检测';

  @override
  String get settingsLangChinese => '中文';

  @override
  String get settingsLangJapanese => '日语';

  @override
  String get settingsLangKorean => '韩语';

  @override
  String get settingsLangCantonese => '粤语';

  @override
  String get settingsWinlinkIntro => '配置用于无线电邮件的 Winlink 消息设置。';

  @override
  String get settingsWinlinkAccount => 'Winlink 账户';

  @override
  String get settingsAccount => '账户';

  @override
  String get settingsWinlinkAccountHelp => '基于“许可”标签页中的呼号';

  @override
  String get settingsPassword => '密码';

  @override
  String get settingsUseStationIdWinlink => '为 Winlink 使用台站 ID';

  @override
  String get settingsServersIntro => '配置本地服务器设置。';

  @override
  String get settingsLocalServers => '本地服务器';

  @override
  String get settingsEnableWebServer => '启用 Web 服务器';

  @override
  String get settingsPort => '端口：';

  @override
  String get settingsEnableAgwpeServer => '启用 AGWPE 服务器';

  @override
  String get settingsMapIntroGps => '配置 GPS 和飞机跟踪数据源。';

  @override
  String get settingsMapIntroNoGps => '配置飞机跟踪数据源。';

  @override
  String get settingsGpsSerialPort => 'GPS 串行端口';

  @override
  String get settingsSerialPort => '串行端口';

  @override
  String get settingsBaudRate => '波特率';

  @override
  String get settingsShareGpsLocation => '共享串行 GPS 位置';

  @override
  String get settingsShareGpsLocationHelp => '将串行 GPS 位置发送到已连接的电台，以便广播您的当前位置。';

  @override
  String get settingsAirplaneTracking => '飞机跟踪（dump1090）';

  @override
  String get settingsServerUrl => '服务器 URL';

  @override
  String get settingsTestConnection => '测试连接';

  @override
  String get settingsTest => '测试';

  @override
  String get settingsTestTesting => '正在测试...';

  @override
  String get settingsTestEmptyAddress => '失败：服务器地址为空';

  @override
  String settingsTestFailedHttp(int code) {
    return '失败：HTTP $code';
  }

  @override
  String settingsTestSuccess(int count) {
    return '成功，找到 $count 架飞机。';
  }

  @override
  String get settingsTestUnexpectedJson => '失败：意外的 JSON 格式';

  @override
  String get settingsTestTimedOut => '失败：超时';

  @override
  String get settingsTestInvalidJson => '失败：无效的 JSON 响应';

  @override
  String get settingsTestFailed => '失败';

  @override
  String get settingsTestConnectionFailedTitle => '连接测试失败';

  @override
  String get settingsLimitsIntro => '限制在每次启动之间保留的历史记录条目数量。设置为“无限制”可保留全部。';

  @override
  String get settingsHistoryLimits => '历史记录限制';

  @override
  String get settingsUnlimited => '无限制';

  @override
  String get settingsLimitAprsMessages => 'APRS 消息';

  @override
  String get settingsLimitPackets => '数据包';

  @override
  String get settingsLimitSstvImages => 'SSTV 图像';

  @override
  String get settingsLimitCommEvents => '通信事件';

  @override
  String settingsLimitCurrent(int count) {
    return '当前：$count';
  }

  @override
  String settingsLimitItemsDeleted(int count) {
    return '将删除 $count 个条目';
  }

  @override
  String get settingsDeleteHistoryTitle => '删除历史记录条目？';

  @override
  String settingsDeleteHistoryBody(String items) {
    return '这些限制将永久删除最旧的条目：\n\n$items\n\n此操作无法撤消。';
  }

  @override
  String settingsDeleteAprsMessages(int count) {
    return '$count 条 APRS 消息';
  }

  @override
  String settingsDeletePackets(int count) {
    return '$count 个数据包';
  }

  @override
  String settingsDeleteSstvImages(int count) {
    return '$count 张 SSTV 图像';
  }

  @override
  String settingsDeleteCommEvents(int count) {
    return '$count 个通信事件';
  }

  @override
  String get settingsAddAprsRoute => '添加 APRS 路由';

  @override
  String get settingsEditAprsRoute => '编辑 APRS 路由';

  @override
  String get settingsName => '名称';

  @override
  String get settingsNameHint => '例如 标准';

  @override
  String get settingsDuplicateRoute => '已存在同名的路由。';

  @override
  String get settingsPath => '路径';

  @override
  String get commonError => '错误';

  @override
  String get commonConnect => '连接';

  @override
  String get commonDisconnect => '断开连接';

  @override
  String get commonRename => '重命名';

  @override
  String get commonRemove => '移除';

  @override
  String connectScanError(String error) {
    return '搜索蓝牙设备失败：$error';
  }

  @override
  String get connectNoRadiosTitle => '未找到电台';

  @override
  String get connectNoRadiosBody => '未找到兼容的电台设备。\n\n请确保您的电台已开机且蓝牙已启用。';

  @override
  String get connectAllConnectedTitle => '全部已连接';

  @override
  String get connectAllConnectedBody => '所有检测到的电台设备均已连接。';

  @override
  String get connectBluetoothOffTitle => '蓝牙不可用';

  @override
  String get connectBluetoothOffBody => '蓝牙不可用或已禁用。\n\n请在设备设置中启用蓝牙后重试。';

  @override
  String get radioConnectionTitle => '电台连接';

  @override
  String get radioConnectionEmpty => '未找到兼容的电台。\n请确保您的电台已开机且蓝牙已启用。';

  @override
  String get radioRenameTitle => '重命名电台';

  @override
  String get radioRenamePrompt => '为此电台输入自定义名称：';

  @override
  String get radioRenameHint => '留空以使用默认名称';

  @override
  String get updateTitle => '软件更新';

  @override
  String get updateChecking => '正在检查更新...';

  @override
  String updateVersionAvailable(String version) {
    return '版本 $version 可用。';
  }

  @override
  String updateFreshDownload(String version) {
    return '版本 $version 需要重新下载。';
  }

  @override
  String updateUnsupported(String version) {
    return '此版本不再受支持。请更新到 $version。';
  }

  @override
  String get updateUpToDate => '您正在使用最新版本。';

  @override
  String updateCheckFailed(String error) {
    return '检查更新失败：$error';
  }

  @override
  String get updateDownloading => '正在下载更新...';

  @override
  String get updateDownloaded => '更新已下载。准备安装。';

  @override
  String updateDownloadFailed(String error) {
    return '下载失败：$error';
  }

  @override
  String updateInstallFailed(String error) {
    return '安装失败：$error';
  }

  @override
  String updateDiagnosticsLog(String path) {
    return '如果更新未完成，请查看诊断日志：\n$path';
  }

  @override
  String get updateInstallRestart => '安装并重启';

  @override
  String get updateCheckAgain => '再次检查';

  @override
  String get regionsTitle => '重命名分区';

  @override
  String regionsMaxChars(int count) {
    return '分区名称最多可包含 $count 个字符。';
  }

  @override
  String regionLabel(int number) {
    return '分区 $number';
  }

  @override
  String get gpsInfoTitle => 'GPS 信息';

  @override
  String get gpsSectionConnection => '连接';

  @override
  String get gpsSectionFix => 'GPS 定位';

  @override
  String get gpsSectionPosition => '位置';

  @override
  String get gpsSectionMotion => '运动';

  @override
  String get gpsSectionTime => '时间';

  @override
  String get gpsPortStatus => '端口状态';

  @override
  String get gpsNotConfigured => '未配置';

  @override
  String get gpsOpenReceiving => '已打开 — 正在接收数据';

  @override
  String get gpsPermDeniedLinux =>
      '权限被拒绝 — 请将您的用户添加到“dialout”组（sudo usermod -aG dialout \$USER），然后注销并重新登录。';

  @override
  String get gpsPermDenied => '权限被拒绝 — 应用程序无法访问此端口。';

  @override
  String get gpsPortError => '端口错误 — 无法打开串行端口。';

  @override
  String get gpsFix => '定位';

  @override
  String get gpsFixQuality => '定位质量';

  @override
  String get gpsSatellites => '卫星';

  @override
  String get gpsNoData => '无数据';

  @override
  String get gpsActive => '活动';

  @override
  String get gpsNoFix => '无定位';

  @override
  String get gpsQualGps => 'GPS 定位 (1)';

  @override
  String get gpsQualDgps => 'DGPS 定位 (2)';

  @override
  String get gpsQualInvalid => '无效 (0)';

  @override
  String gpsQualUnknown(int quality) {
    return '$quality（未知）';
  }

  @override
  String get gpsLatitude => '纬度';

  @override
  String get gpsLatitudeDms => '纬度 (DMS)';

  @override
  String get gpsLongitude => '经度';

  @override
  String get gpsLongitudeDms => '经度 (DMS)';

  @override
  String get gpsAltitude => '海拔';

  @override
  String get gpsSpeed => '速度';

  @override
  String get gpsHeading => '航向';

  @override
  String get gpsTimeUtc => 'GPS 时间 (UTC)';

  @override
  String get gpsDate => 'GPS 日期';

  @override
  String get gpsLastUpdate => '上次更新';

  @override
  String get trustedDevicesTitle => '受信任的设备';

  @override
  String get trustedRemoveTitle => '移除受信任的设备';

  @override
  String trustedRemoveMessage(String name) {
    return '将“$name”从电台的受信任设备列表中移除？';
  }

  @override
  String get trustedNoDevices => '未找到受信任的设备。';

  @override
  String get pfConfigTitle => '配置按键';

  @override
  String get pfSaveToRadio => '保存到电台';

  @override
  String get pfNoRadio => '未连接电台。';

  @override
  String get pfNoButtons => '此电台未报告任何可编程按键。';

  @override
  String get pfIntro => '为每个可编程按键选择每种按压类型的操作。保存时更改将写入电台。';

  @override
  String pfButtonLabel(int number) {
    return '按键 $number';
  }

  @override
  String get pfActionShort => '短按';

  @override
  String get pfActionLong => '长按';

  @override
  String get pfActionVeryLong => '超长按';

  @override
  String get pfActionVeryVeryLong => '超超长按';

  @override
  String get pfActionDouble => '双击';

  @override
  String get pfActionTriple => '三击';

  @override
  String get pfActionRepeat => '重复';

  @override
  String get pfActionPressDown => '按下';

  @override
  String get pfActionRelease => '释放';

  @override
  String get pfActionLongRelease => '长释放';

  @override
  String get pfActionVeryLongRelease => '超长释放';

  @override
  String get pfActionVeryVeryLongRelease => '超超长释放';

  @override
  String pfActionUnknown(int action) {
    return '操作 $action';
  }

  @override
  String get pfEffectDisabled => '已禁用';

  @override
  String get pfEffectAlarm => '警报';

  @override
  String get pfEffectAlarmAndMute => '警报并静音';

  @override
  String get pfEffectToggleOffline => '切换离线';

  @override
  String get pfEffectToggleRadioTx => '切换电台发射';

  @override
  String get pfEffectToggleTxPower => '切换发射功率';

  @override
  String get pfEffectToggleFm => '切换 FM 收音机';

  @override
  String get pfEffectPrevChannel => '上一个信道';

  @override
  String get pfEffectNextChannel => '下一个信道';

  @override
  String get pfEffectTCall => 'T 音（1750 Hz）';

  @override
  String get pfEffectPrevRegion => '上一个分区';

  @override
  String get pfEffectNextRegion => '下一个分区';

  @override
  String get pfEffectToggleChScan => '切换信道扫描';

  @override
  String get pfEffectMainPtt => '主 PTT';

  @override
  String get pfEffectSubPtt => '副 PTT';

  @override
  String get pfEffectToggleMonitor => '切换监听';

  @override
  String get pfEffectBtPairing => '蓝牙配对';

  @override
  String get pfEffectToggleDoubleCh => '切换双信道';

  @override
  String get pfEffectToggleAbCh => '切换 A/B 信道';

  @override
  String get pfEffectSendLocation => '发送位置';

  @override
  String get pfEffectOneClickLink => '一键链接';

  @override
  String get pfEffectVolDown => '降低音量';

  @override
  String get pfEffectVolUp => '提高音量';

  @override
  String get pfEffectToggleMute => '切换静音';

  @override
  String pfEffectUnknown(int effect) {
    return '未知（$effect）';
  }

  @override
  String get importChannelsTitle => '导入信道';

  @override
  String importChannelsTitleWith(String name) {
    return '导入信道 — $name';
  }

  @override
  String get importIntro =>
      '将信道从左侧拖动到电台的某个位置，或选择一个信道和一个位置，然后点击箭头。点击信息图标查看详情。仅当您点击“确定”时，信道才会写入电台。';

  @override
  String importOkCount(int count) {
    return '确定（$count）';
  }

  @override
  String importImportedHeader(int count) {
    return '已导入（$count）';
  }

  @override
  String get importNoChannels => '没有已导入的信道。';

  @override
  String importRadioChannelsHeader(int count) {
    return '电台信道（$count）';
  }

  @override
  String get importNoRadioChannels => '没有电台信道。';

  @override
  String get importMoveTooltip => '将所选信道移动到所选位置';

  @override
  String get importCopyAllTooltip => '将所有已导入的信道 1:1 复制到电台位置';

  @override
  String importChannelShort(int number) {
    return '信道 $number';
  }

  @override
  String get importClearTooltip => '清除待处理的分配';

  @override
  String get importChannelDetails => '信道详情';

  @override
  String get riTitle => '电台信息';

  @override
  String get riNoRadioConnected => '未连接电台';

  @override
  String get riConnectPrompt => '连接电台以查看其信息。';

  @override
  String riRadioFallback(int id) {
    return '电台 $id';
  }

  @override
  String get riSectionRadio => '电台';

  @override
  String get riSectionDeviceInfo => '设备信息';

  @override
  String get riSectionDeviceStatus => '设备状态';

  @override
  String get riSectionDeviceSettings => '设备设置';

  @override
  String get riSectionBss => 'BSS 设置';

  @override
  String get riSectionPosition => '位置';

  @override
  String get riName => '名称';

  @override
  String get riStatus => '状态';

  @override
  String get riSettingsLabel => '设置';

  @override
  String get riNoData => '无数据';

  @override
  String get riNoGpsData => '无 GPS 数据';

  @override
  String get riNoGpsLock => '无 GPS 定位';

  @override
  String get riGpsLocked => '已获取 GPS 定位';

  @override
  String get riTrue => '是';

  @override
  String get riFalse => '否';

  @override
  String get riPresent => '存在';

  @override
  String get riNotPresent => '不存在';

  @override
  String get riSupported => '支持';

  @override
  String get riNotSupported => '不支持';

  @override
  String get riCurrent => '当前';

  @override
  String get riOff => '关闭';

  @override
  String riChannelValue(int number) {
    return '信道 $number';
  }

  @override
  String riSeconds(int count) {
    return '$count 秒';
  }

  @override
  String riMeters(String value) {
    return '$value 米';
  }

  @override
  String riDegrees(String value) {
    return '$value 度';
  }

  @override
  String get riProductId => '产品 ID';

  @override
  String get riVendorId => '厂商 ID';

  @override
  String get riDmrSupport => 'DMR 支持';

  @override
  String get riGmrsSupport => 'GMRS 支持';

  @override
  String get riHardwareSpeaker => '硬件扬声器';

  @override
  String get riHardwareVersion => '硬件版本';

  @override
  String get riSoftwareVersion => '软件版本';

  @override
  String get riRegionCount => '分区数量';

  @override
  String get riMediumPower => '中等功率';

  @override
  String get riChannelCount => '信道数量';

  @override
  String get riNoaa => 'NOAA';

  @override
  String get riRadioLabel => '电台';

  @override
  String get riVfo => 'VFO';

  @override
  String get riFreqRangeCount => '频率范围数量';

  @override
  String get riPowerOn => '已开机';

  @override
  String get riInTx => '发射中';

  @override
  String get riInRx => '接收中';

  @override
  String get riDoubleChannelLabel => '双信道';

  @override
  String get riScanning => '扫描中';

  @override
  String get riCurrentChannelId => '当前信道 ID';

  @override
  String get riGpsLockedLabel => 'GPS 已锁定';

  @override
  String get riHfpConnected => 'HFP 已连接';

  @override
  String get riAocConnected => 'AOC 已连接';

  @override
  String get riRssi => 'RSSI';

  @override
  String get riCurrentRegion => '当前分区';

  @override
  String get riAccuracy => '精度';

  @override
  String get riReceivedTime => '接收时间';

  @override
  String get riGpsTimeLocal => 'GPS 本地时间';

  @override
  String get riGpsTimeUtcLabel => 'GPS UTC 时间';

  @override
  String get tabDetach => '分离...';

  @override
  String get tabClear => '清除';

  @override
  String get tabSaveToFile => '保存到文件...';

  @override
  String get commonNoRadioConnected => '未连接电台。';

  @override
  String errorOpeningFileDialog(String error) {
    return '打开文件对话框时出错：$error';
  }

  @override
  String errorSavingFile(String error) {
    return '保存文件时出错：$error';
  }

  @override
  String get debugSaveTitle => '保存调试日志';

  @override
  String debugLogSavedTo(String path) {
    return '调试日志已保存到 $path';
  }

  @override
  String get debugShowBluetoothFrames => '显示蓝牙帧';

  @override
  String get debugLoopbackMode => '环回模式';

  @override
  String get debugQueryDeviceNames => '查询设备名称';

  @override
  String get debugRawCommand => '原始命令...';

  @override
  String get debugAutoScroll => '自动滚动';

  @override
  String get debugFirmwareUpdate => '固件更新...';

  @override
  String get debugShowBuiltInMenus => '显示内置菜单';

  @override
  String get packetsCopyHex => '复制 HEX 数据包';

  @override
  String get packetsHexCopied => 'HEX 数据包已复制到剪贴板';

  @override
  String get packetsSaveTitle => '保存数据包捕获';

  @override
  String get packetsSaved => '数据包捕获已保存';

  @override
  String packetsSavedTo(String path) {
    return '数据包捕获已保存到 $path';
  }

  @override
  String get packetsShowDecode => '显示数据包解码';

  @override
  String get packetsEmpty => '未捕获数据包';

  @override
  String get packetsColTime => '时间';

  @override
  String get packetsColChannel => '信道';

  @override
  String get packetsColData => '数据';

  @override
  String get commonAdd => '添加';

  @override
  String get commonEdit => '编辑';

  @override
  String get commonEditEllipsis => '编辑...';

  @override
  String get commonAddEllipsis => '添加...';

  @override
  String get commonExportEllipsis => '导出...';

  @override
  String get commonImportEllipsis => '导入...';

  @override
  String get contactsTypeGeneric => '通用台站';

  @override
  String get contactsTypeAprs => 'APRS 台站';

  @override
  String get contactsTypeTerminal => '终端台站';

  @override
  String get contactsTypeBbs => 'BBS 台站';

  @override
  String get contactsTypeWinlink => 'Winlink 台站';

  @override
  String get contactsTypeTorrent => '种子台站';

  @override
  String get contactsTypeAgwpe => 'AGWPE 台站';

  @override
  String get contactsExists => '已存在具有此呼号和类型的台站';

  @override
  String get contactsRemovePrompt => '移除所选台站？';

  @override
  String get contactsNoExport => '没有可导出的台站';

  @override
  String get contactsExportTitle => '导出台站';

  @override
  String get contactsImportTitle => '导入台站';

  @override
  String contactsExported(int count) {
    return '已导出 $count 个台站';
  }

  @override
  String contactsImported(int count) {
    return '已导入 $count 个台站';
  }

  @override
  String get contactsUnableOpen => '无法打开通讯录';

  @override
  String get contactsInvalid => '通讯录无效';

  @override
  String get contactsColCallsign => '呼号';

  @override
  String get contactsColName => '名称';

  @override
  String get contactsColDescription => '描述';

  @override
  String terminalHeaderWith(String callsign) {
    return '终端 - $callsign';
  }

  @override
  String get terminalNoRadio => '没有可用于连接的电台。';

  @override
  String get terminalShowCallsign => '显示呼号';

  @override
  String get terminalWordWrap => '自动换行';

  @override
  String get terminalWaitForConnection => '等待连接...';

  @override
  String get terminalSend => '发送';

  @override
  String terminalConnectedTo(String callsign) {
    return '已连接到 $callsign';
  }

  @override
  String terminalConnectingTo(String callsign) {
    return '正在连接到 $callsign...';
  }

  @override
  String get terminalInvalidCallsignDest => '呼号/目标无效';

  @override
  String get terminalInvalidCallsign => '呼号无效';

  @override
  String get terminalNotConnected => '未连接';

  @override
  String terminalError(String error) {
    return '错误：$error';
  }

  @override
  String get terminalBrotli => '收到 Brotli 压缩数据包（不支持）';

  @override
  String get audioSectionDevices => '设备';

  @override
  String get audioRefreshDevices => '刷新设备列表';

  @override
  String get audioOutput => '输出';

  @override
  String get audioInput => '输入';

  @override
  String get audioVolume => '音量';

  @override
  String get audioSquelch => '静噪';

  @override
  String get audioSectionComputer => '计算机';

  @override
  String get audioApplication => '应用程序';

  @override
  String get audioMaster => '主音量';

  @override
  String get audioMicGain => '麦克风增益';

  @override
  String get audioMicNotAvailable => '此平台上麦克风捕获不可用。';

  @override
  String get audioMicNotSupported => '此处不支持麦克风捕获。';

  @override
  String get audioSpectRadio => '电台频谱图';

  @override
  String get audioSpectMic => '麦克风频谱图';

  @override
  String get audioSpectNone => '频谱图';

  @override
  String get audioSpectMenuNone => '无频谱图';

  @override
  String get audioDartQuality => 'DART 接收质量';

  @override
  String get audioDartSignalAnalysis => 'DART 信号分析';

  @override
  String get audioDefault => '默认';

  @override
  String get audioMute => '静音';

  @override
  String get audioUnmute => '取消静音';

  @override
  String get audioEnable => '启用';

  @override
  String get audioDisable => '禁用';

  @override
  String get audioNa => '不适用';

  @override
  String get bbsHeaderActive => 'BBS - 活动';

  @override
  String get bbsActivate => '激活';

  @override
  String get bbsDeactivate => '停用';

  @override
  String get bbsViewTraffic => '查看流量';

  @override
  String get bbsClearTraffic => '清除流量';

  @override
  String get bbsClearStats => '清除统计信息';

  @override
  String get bbsColCallSign => '呼号';

  @override
  String get bbsColLastSeen => '最后活动';

  @override
  String get bbsColStats => '统计信息';

  @override
  String get bbsTraffic => '流量';

  @override
  String get bbsJustNow => '刚刚';

  @override
  String bbsMinAgo(int n) {
    return '$n 分钟前';
  }

  @override
  String bbsHoursAgo(int n) {
    return '$n 小时前';
  }

  @override
  String bbsDaysAgo(int n) {
    return '$n 天前';
  }

  @override
  String get commonDelete => '删除';

  @override
  String get torrentAddFile => '添加文件';

  @override
  String get torrentShowDetails => '显示详情';

  @override
  String get torrentFileSaved => '文件已保存。';

  @override
  String get torrentFileDataUnavailable => '保存时出错：文件数据不可用';

  @override
  String get torrentUnknownError => '未知错误';

  @override
  String get torrentSaveTitle => '保存种子文件';

  @override
  String get torrentNoRadios => '未连接电台。请先连接电台。';

  @override
  String get torrentMultiRadio => '尚不支持多电台种子模式。';

  @override
  String get torrentDropSingle => '请仅拖放一个文件。';

  @override
  String get torrentDeletePrompt => '删除所选种子文件？';

  @override
  String get torrentPause => '暂停';

  @override
  String get torrentShare => '共享';

  @override
  String get torrentRequest => '请求';

  @override
  String get torrentSaveAs => '另存为...';

  @override
  String get torrentDropToShare => '拖放文件以共享';

  @override
  String get torrentNoFiles => '没有种子文件。添加或拖放文件以共享。';

  @override
  String get torrentUnknownSource => '未知';

  @override
  String get torrentColFile => '文件';

  @override
  String get torrentColMode => '模式';

  @override
  String get torrentDetailFileName => '文件名';

  @override
  String get torrentDetailSource => '来源';

  @override
  String get torrentDetailFileSize => '文件大小';

  @override
  String torrentBytes(int count) {
    return '$count 字节';
  }

  @override
  String get torrentDetailCompression => '压缩';

  @override
  String get torrentDetailBlocks => '块';

  @override
  String get torrentDetailsTitle => '种子详情';

  @override
  String get torrentSelectPrompt => '选择一个种子以查看详情';

  @override
  String get torrentModePaused => '已暂停';

  @override
  String get torrentModeSharing => '共享中';

  @override
  String get torrentModeRequesting => '请求中';

  @override
  String get torrentModeError => '错误';

  @override
  String get torrentCompUnknown => '未知';

  @override
  String get mailInbox => '收件箱';

  @override
  String get mailOutbox => '发件箱';

  @override
  String get mailDraft => '草稿';

  @override
  String get mailSent => '已发送';

  @override
  String get mailArchive => '归档';

  @override
  String get mailTrash => '回收站';

  @override
  String get mailInternet => '互联网';

  @override
  String get mailDeleteTitle => '删除邮件';

  @override
  String get mailMoveToTrashTitle => '移至回收站';

  @override
  String get mailDeletePermanent => '永久删除所选邮件？此操作无法撤消。';

  @override
  String get mailMoveToTrashPrompt => '将所选邮件移至回收站？';

  @override
  String get mailMove => '移动';

  @override
  String get mailOpen => '打开';

  @override
  String get mailReply => '回复';

  @override
  String get mailReplyAll => '全部回复';

  @override
  String get mailForward => '转发';

  @override
  String get mailShowPreview => '显示预览';

  @override
  String get mailBackup => '备份邮件...';

  @override
  String get mailRestore => '恢复邮件...';

  @override
  String get mailShowTraffic => '显示流量...';

  @override
  String mailBackupFailed(String error) {
    return '备份失败：$error';
  }

  @override
  String get mailBackupTitle => '备份邮件';

  @override
  String get mailBackupSuccess => '备份成功完成。';

  @override
  String get mailRestoreTitle => '恢复邮件';

  @override
  String get mailRestoreUnableOpen => '无法打开备份文件';

  @override
  String mailRestoreFailed(String error) {
    return '恢复失败：$error';
  }

  @override
  String get mailNew => '新建';

  @override
  String get mailNewMail => '新邮件';

  @override
  String get mailColTime => '时间';

  @override
  String get mailColTo => '收件人';

  @override
  String get mailColFrom => '发件人';

  @override
  String get mailColSubject => '主题';

  @override
  String get mailSelectPreview => '选择一封邮件以预览';

  @override
  String get commonUnknown => '未知';

  @override
  String get mapOfflineMode => '离线模式';

  @override
  String get mapOfflineMap => '离线地图';

  @override
  String get mapCacheArea => '缓存区域...';

  @override
  String get mapCenterGps => '以 GPS 为中心';

  @override
  String get mapShowTracks => '显示轨迹';

  @override
  String get mapShowMarkers => '显示标记';

  @override
  String get mapShowAirplanes => '显示飞机';

  @override
  String get mapLargeMarkers => '大标记';

  @override
  String get mapShowContactsOnly => '仅显示联系人';

  @override
  String get mapFilterAll => '全部';

  @override
  String get mapFilterLast30 => '最近 30 分钟';

  @override
  String get mapFilterLastHour => '最近一小时';

  @override
  String get mapFilterLast6 => '最近 6 小时';

  @override
  String get mapFilterLast12 => '最近 12 小时';

  @override
  String get mapFilterLast24 => '最近 24 小时';

  @override
  String get mapCacheTitle => '缓存地图区域';

  @override
  String mapCachePrompt(int count, int minZoom, int maxZoom) {
    return '下载缩放级别 $minZoom–$maxZoom 的 $count 个瓦片？\n\n这将缓存所选区域以供离线使用。';
  }

  @override
  String get mapDownloadingTitle => '正在下载瓦片';

  @override
  String mapTilesProgress(int done, int total) {
    return '$done / $total 个瓦片';
  }

  @override
  String get mapDragToSelect => '拖动以选择要缓存的区域';

  @override
  String get aprsNoChannel => '没有带 APRS 信道的电台可用';

  @override
  String get aprsNoLoadedChannels => '没有已加载信道的电台可用';

  @override
  String get aprsDetails => '详情...';

  @override
  String get aprsShowLocation => '显示位置...';

  @override
  String get aprsSetReceiver => '设为接收方';

  @override
  String get aprsCopyMessage => '复制消息';

  @override
  String get aprsCopyCallsign => '复制呼号';

  @override
  String get aprsClearTitle => '清除 APRS 消息';

  @override
  String get aprsClearPrompt => '清除所有 APRS 消息？这还将从地图中删除所有 APRS 标记。此操作无法撤消。';

  @override
  String get aprsShowAll => '显示所有消息';

  @override
  String get aprsSendSms => '发送 SMS 消息...';

  @override
  String get aprsWeatherReport => '天气报告...';

  @override
  String get aprsBeaconSettingsMenu => '信标设置...';

  @override
  String get aprsDropShare => '拖放以共享此信道';

  @override
  String get aprsBeaconWarning => '当前信道上已启用信标广播，不建议这样做。';

  @override
  String aprsBeaconActive(String interval) {
    return '电台信标处于活动状态，间隔：$interval。';
  }

  @override
  String get aprsBeaconSettings => '信标设置';

  @override
  String aprsIntervalSeconds(int count) {
    return '$count 秒';
  }

  @override
  String get aprsIntervalMinute => '1 分钟';

  @override
  String aprsIntervalMinutes(int count) {
    return '$count 分钟';
  }

  @override
  String get aprsMissingChannel =>
      '已连接的电台上未配置“APRS”信道。请添加 APRS 信道以发送和接收 APRS 消息。';

  @override
  String get aprsSetup => '设置';

  @override
  String get aprsTypeMessage => '输入消息...';

  @override
  String get commonYes => '是';

  @override
  String get commonNo => '否';

  @override
  String get commonSend => '发送';

  @override
  String commonSavedTo(String path) {
    return '已保存到 $path';
  }

  @override
  String commsFailedLoadImage(String error) {
    return '加载图像失败：$error';
  }

  @override
  String commsFailedSaveImage(String error) {
    return '保存图像失败：$error';
  }

  @override
  String commsFailedEncodeSstv(String error) {
    return '编码 SSTV 音频失败：$error';
  }

  @override
  String commsFailedLoadAudio(String error) {
    return '加载音频失败：$error';
  }

  @override
  String get commsUnsupportedWav => '不支持的 WAV 文件或文件为空。';

  @override
  String get commsSstvWebUnavailable => 'Web 上不支持 SSTV 图像录制/发送。';

  @override
  String get commsNoRadioVoice => '未连接电台以进行语音发送。';

  @override
  String get commsSelectImageTitle => '选择用于 SSTV 的图像';

  @override
  String get commsSelectWavTitle => '选择 WAV 音频文件';

  @override
  String get commsRecordingWebUnavailable => 'Web 上不支持从文件播放录音。';

  @override
  String get commsFileNoLongerExists => '文件不再存在。';

  @override
  String get commsSaveAsTitle => '另存为';

  @override
  String get commsTransmitDisabledAprs => '当 VFO A 设置为 APRS 信道时，发射被禁用。';

  @override
  String get commsWaitTransmission => '请等待当前发送完成。';

  @override
  String get commsConnectRadioChat => '发送聊天消息前请连接电台。';

  @override
  String get commsEnableAudioMode => '在此模式下发送前请启用音频（“启用”按钮）。';

  @override
  String get commsMicNotSupported => '此平台不支持麦克风捕获。';

  @override
  String get commsConnectRadioPtt => '使用一键通功能前请连接电台。';

  @override
  String get commsEnableAudioPtt => '使用一键通功能前请启用音频（“启用”按钮）。';

  @override
  String get commsSwitchChatShare => '切换到聊天模式以共享信道。';

  @override
  String get commsModePtt => 'PTT';

  @override
  String get commsModeChat => '聊天';

  @override
  String get commsModeSpeak => '朗读';

  @override
  String get commsModeMorse => '摩尔斯';

  @override
  String get commsModeDtmf => 'DTMF';

  @override
  String get commsRecordAudio => '录制音频';

  @override
  String get commsSendImage => '发送图像...';

  @override
  String get commsSendAudio => '发送音频...';

  @override
  String get commsPttReleaseSettings => 'PTT 释放设置...';

  @override
  String get commsClearHistory => '清除历史记录';

  @override
  String get commsShowImage => '显示图像...';

  @override
  String get commsPlayRecording => '播放录音...';

  @override
  String get commsSaveAsMenu => '另存为...';

  @override
  String get commsShowLocation => '显示位置';

  @override
  String get commsClearHistoryPrompt => '确定要清除语音历史记录吗？';

  @override
  String get commsAudioMuted => '音频已静音。';

  @override
  String get commsUnmute => '取消静音';

  @override
  String get commsPttTransmitting => '正在发送...';

  @override
  String get commsPttHold => 'PTT - 按住以发送';

  @override
  String get commsDtmfHint => '输入 DTMF 数字（0-9、*、#）...';

  @override
  String get mailComposeNewTitle => '新消息';

  @override
  String get mailComposeEditTitle => '编辑消息';

  @override
  String get mailDiscardChanges => '放弃对此消息的更改？';

  @override
  String get mailDiscardMessage => '放弃此消息？';

  @override
  String get mailDiscard => '放弃';

  @override
  String get mailAddCc => '添加抄送';

  @override
  String get mailCc => '抄送';

  @override
  String get mailRemoveCc => '移除抄送';

  @override
  String get mailMessageLabel => '消息';

  @override
  String get mailSaveDraft => '保存草稿';

  @override
  String get smsTitle => '发送 SMS 消息';

  @override
  String get smsPhoneNumber => '电话号码';

  @override
  String get smsIntro =>
      '您可以向美国、波多黎各、加拿大、澳大利亚和英国的电话发送 SMS 消息，前提是该号码已接受该服务。您可以在此注册：';

  @override
  String get locationTitle => '位置';

  @override
  String get beaconIntro => '修改电台广播其自身信息的方式，包括位置、电压和自定义消息。附近的其他台站将能够看到此信息。';

  @override
  String beaconRadio(String name) {
    return '电台：$name';
  }

  @override
  String get beaconSection => '信标';

  @override
  String get beaconPacketFormat => '数据包格式';

  @override
  String get beaconInterval => '信标间隔';

  @override
  String get beaconAprsCallsign => 'APRS 呼号';

  @override
  String get beaconCallsignHint => '呼号 - 台站 ID';

  @override
  String get beaconCallsignInvalid => '输入有效的呼号和台站 ID（例如 W1AW-5）';

  @override
  String get beaconAprsMessage => 'APRS 消息';

  @override
  String get beaconShareLocation => '共享位置';

  @override
  String get beaconSendVoltage => '发送电压';

  @override
  String get beaconAllowPositionCheck => '允许位置检查';

  @override
  String get beaconChannelCurrent => '当前（不推荐）';

  @override
  String beaconEverySeconds(int n) {
    return '每 $n 秒';
  }

  @override
  String beaconEveryMinutes(int n) {
    return '每 $n 分钟';
  }

  @override
  String get assConnectTerminal => '连接到终端台站';

  @override
  String get assConnectBbs => '连接到 BBS 台站';

  @override
  String get assConnectWinlink => '连接到 Winlink 网关';

  @override
  String get assConnectStation => '连接到台站';

  @override
  String get assNew => '新建…';

  @override
  String get attSelectFile => '选择要共享的文件';

  @override
  String get attCompressing => '正在压缩...';

  @override
  String get attTitle => '添加种子文件';

  @override
  String get attSelect => '选择...';

  @override
  String get attDescriptionOptional => '描述（可选）';

  @override
  String get stationTitleVoice => '语音台站';

  @override
  String get stationTitleAprs => 'APRS 台站';

  @override
  String get stationTitleTerminal => '终端台站';

  @override
  String get stationTitleWinlink => 'Winlink 网关';

  @override
  String get stationTitleGeneric => '台站';

  @override
  String get stationTypeOptionVoice => '语音 / 通用台站';

  @override
  String get stationTypeLabel => '台站类型';

  @override
  String get stationAprsRoute => 'APRS 路由';

  @override
  String get stationUseAuth => '使用消息认证';

  @override
  String get stationAuthPassword => '认证密码';

  @override
  String get stationPasswordRequired => '需要密码';

  @override
  String get stationTerminalProtocol => '终端协议';

  @override
  String get stationAx25Destination => 'AX.25 目标（例如 CALL-1）';

  @override
  String get stationAx25Invalid => 'AX.25 地址无效';

  @override
  String get stationModem => '调制解调器';

  @override
  String get apdTitle => 'APRS 数据包详情';

  @override
  String get apdCopyAll => '全部复制';

  @override
  String get apdCopyValue => '复制值';

  @override
  String get apdValueCopied => '值已复制';

  @override
  String get apdAllValuesCopied => '所有值已复制';

  @override
  String get apdNoDetails => '没有可用的详情。';

  @override
  String get apdShowLocation => '显示位置...';

  @override
  String get acfgTitle => '配置 APRS 信道';

  @override
  String get acfgIntro => 'APRS 频率因世界地区而异。使用此网站查找合适的频率以配置 APRS 信道。';

  @override
  String get acfgConfiguration => 'APRS 配置';

  @override
  String get acfgFrequency => '频率';

  @override
  String get acfgFrequencyHint => '北美 144.39\n欧洲 144.80';

  @override
  String get acfgChannelOverwritten => '所选信道将被覆盖';

  @override
  String get sstvSendTitle => '发送 SSTV 图像';

  @override
  String sstvSendTitleNamed(String name) {
    return '发送 SSTV 图像 - $name';
  }

  @override
  String get sstvMode => '模式：';

  @override
  String sstvTransmitTime(String time) {
    return '发送时间：~$time';
  }

  @override
  String get msgdTitle => '消息详情';

  @override
  String get msgdFieldType => '类型';

  @override
  String get msgdFieldDirection => '方向';

  @override
  String get msgdFieldTime => '时间';

  @override
  String get msgdFieldSource => '来源';

  @override
  String get msgdFieldReceiver => '接收方';

  @override
  String get msgdFieldDuration => '时长';

  @override
  String get msgdFieldLatitude => '纬度';

  @override
  String get msgdFieldLongitude => '经度';

  @override
  String get msgdFieldMessage => '消息';

  @override
  String get msgdFieldFile => '文件';

  @override
  String get msgdDirReceived => '已接收';

  @override
  String get msgdDirSent => '已发送';

  @override
  String get msgdTypeVoice => '语音';

  @override
  String get msgdTypeVoiceClip => '语音片段';

  @override
  String get msgdTypeRecording => '录音';

  @override
  String get msgdTypeSstvPicture => 'SSTV 图像';

  @override
  String get msgdTypeIdentification => '识别';

  @override
  String get msgdTypeChatMessage => '聊天消息';

  @override
  String get msgdTypeAx25Packet => 'AX.25 数据包';

  @override
  String get rpbFailedToLoad => '加载录音失败。';

  @override
  String get ivwFailedToLoad => '加载图像失败。';

  @override
  String get rawTitle => '原始电台命令';

  @override
  String get rawCommand => '命令';

  @override
  String get rawHexPayload => 'HEX 负载（可选）';

  @override
  String get rawResponse => '响应';

  @override
  String get identTitle => 'PTT 释放设置';

  @override
  String get identDescription => '如果启用，每当您在发送所在的信道上释放 PTT 时，都会发送您的呼号和/或位置信息。';

  @override
  String get identCallsignHint => '输入呼号 - 台站 ID';

  @override
  String get identSendCallsign => '发送呼号';

  @override
  String get identSendPosition => '发送位置';

  @override
  String get commonOn => '开启';

  @override
  String get commonOff => '关闭';

  @override
  String get commonNone => '无';

  @override
  String chChannelNumber(int n) {
    return '信道 $n';
  }

  @override
  String chChShort(int n) {
    return '信道 $n';
  }

  @override
  String get chMoreSettings => '更多设置';

  @override
  String get chChannelNameHint => '信道名称';

  @override
  String get chFrequencyMhz => '频率 (MHz)';

  @override
  String get chReceiveMhz => '接收 (MHz)';

  @override
  String get chTransmitMhz => '发射 (MHz)';

  @override
  String get chMode => '模式';

  @override
  String get chPower => '功率';

  @override
  String get chBandwidth => '带宽';

  @override
  String get chReceiveTone => '接收音（CTCSS / DCS）';

  @override
  String get chTransmitTone => '发射音（CTCSS / DCS）';

  @override
  String get chDisableTransmit => '禁用发射';

  @override
  String get chMute => '静音';

  @override
  String get chScan => '扫描';

  @override
  String get chTalkAround => '直通模式';

  @override
  String get chDeemphasis => '去加重';

  @override
  String get chPowerHigh => '高';

  @override
  String get chPowerMedium => '中';

  @override
  String get chPowerLow => '低';

  @override
  String get chBandwidthWide => '25 KHz 宽';

  @override
  String get chBandwidthNarrow => '12.5 KHz 窄';

  @override
  String get chClearTitle => '清除信道';

  @override
  String chClearConfirm(int n) {
    return '清除信道 $n？\n\n这将删除电台上此位置的频率、名称和设置。';
  }

  @override
  String get cdRxFrequency => 'RX 频率';

  @override
  String get cdTxFrequency => 'TX 频率';

  @override
  String get cdRxModulation => 'RX 调制';

  @override
  String get cdTxModulation => 'TX 调制';

  @override
  String get cdRxTone => 'RX 音';

  @override
  String get cdTxTone => 'TX 音';

  @override
  String get cdTxDisabled => '发射已禁用';

  @override
  String get cdTalkAround => '直通模式';

  @override
  String get cdEmpty => '（空）';

  @override
  String get cdBandwidthWide => '25 kHz（宽）';

  @override
  String get cdBandwidthNarrow => '12.5 kHz（窄）';

  @override
  String get gpsDetailsTitle => 'GPS 详情';

  @override
  String get gpsDisabled => 'GPS 已禁用';

  @override
  String get gpsLock => 'GPS 锁定';

  @override
  String get gpsNoLock => '无 GPS 锁定';

  @override
  String get mdbgTitle => 'Winlink 流量';

  @override
  String get mdbgNoTraffic => '暂无流量。';

  @override
  String get fwTitle => '电台固件更新';

  @override
  String get fwStatusInitial => '在线检查固件更新，或从磁盘加载固件文件。';

  @override
  String get fwErrNotConnected => '电台未连接。';

  @override
  String get fwErrNoDeviceInfo => '电台设备信息尚不可用。';

  @override
  String get fwStatusChecking => '正在检查固件更新…';

  @override
  String get fwErrNoServerInfo => '厂商服务器未返回固件信息。';

  @override
  String fwUpdateAvailable(String version) {
    return '有可用的固件更新 $version。请查看下方的发行说明，然后下载以更新。';
  }

  @override
  String fwErrCheckFailed(String error) {
    return '检查更新失败：$error';
  }

  @override
  String get fwPickTitle => '选择固件文件';

  @override
  String fwLoaded(String name, String size, String md5) {
    return '已加载 $name：$size（MD5 $md5…）。';
  }

  @override
  String fwErrLoadFailed(String error) {
    return '无法加载固件文件：$error';
  }

  @override
  String get fwSaveTitle => '保存固件文件';

  @override
  String fwSavedTo(String path) {
    return '固件已保存到 $path';
  }

  @override
  String fwErrSaveFailed(String error) {
    return '无法保存固件文件：$error';
  }

  @override
  String get fwStatusDownloading => '正在下载并组装固件…';

  @override
  String get fwProgressStarting => '正在启动…';

  @override
  String fwReady(String size, String md5) {
    return '固件就绪：$size（MD5 $md5…）。';
  }

  @override
  String fwErrDownloadFailed(String error) {
    return '下载失败：$error';
  }

  @override
  String get fwStatusWriting => '正在将固件写入电台。请勿关机。';

  @override
  String get fwProgressTransferring => '正在传输…';

  @override
  String fwErrTransferFailed(String error) {
    return '固件传输失败：$error';
  }

  @override
  String get fwStatusRebooting => '电台正在重启。正在重新连接…';

  @override
  String get fwProgressWaitingRestart => '正在等待电台重启…';

  @override
  String fwErrReconnectFailed(String error) {
    return '重启后重新连接失败：$error';
  }

  @override
  String get fwErrReconnectNull => '电台重启后无法重新连接。固件已传输但未确认。请手动重新连接并重试。';

  @override
  String get fwStatusFinalising => '正在完成更新…';

  @override
  String get fwProgressConfirming => '正在确认…';

  @override
  String fwErrConfirmFailed(String error) {
    return '确认更新失败：$error';
  }

  @override
  String get fwStatusComplete => '固件更新完成！电台现在运行新固件。';

  @override
  String get fwProgressDownloadPatch => '正在下载补丁';

  @override
  String get fwProgressDownloadBase => '正在下载基础镜像';

  @override
  String get fwProgressAssemble => '正在组装固件';

  @override
  String fwProgressBytes(String label, String done, String total) {
    return '$label（$done / $total）';
  }

  @override
  String fwProgressTransferringBytes(String done, String total) {
    return '正在传输（$done / $total）';
  }

  @override
  String fwCurrentFirmware(String version) {
    return '当前固件：$version';
  }

  @override
  String get fwErrGeneric => '发生了错误。';

  @override
  String get fwIdleDisclosure =>
      '在线检查会联系电台厂商的服务器（rpc.benshikj.com），并且仅发送您电台的产品标识符。在您点击“检查更新”之前，不会发送任何内容。';

  @override
  String get fwWhatsNew => '新增内容';

  @override
  String get fwConfirmWarning =>
      '警告：在整个过程中请保持电台开机、充电并处于蓝牙范围内。电台将在中途重启。中断更新可能需要手动恢复。';

  @override
  String get fwFromFile => '从文件…';

  @override
  String get fwCheckForUpdate => '检查更新';

  @override
  String get fwDownload => '下载';

  @override
  String get fwSave => '保存…';

  @override
  String get fwFlashNow => '立即刷写';

  @override
  String get fwRetry => '重试';

  @override
  String get wxTitle => '请求天气报告';

  @override
  String get wxIntro => '通过 APRS 请求天气报告。';

  @override
  String get wxLocation => '位置';

  @override
  String get wxLocationHelper => '美国城市/州或美国邮编，或坐标 41.123/-121.334';

  @override
  String get wxTime => '时间';

  @override
  String get wxReport => '报告';

  @override
  String get wxToday => '今天';

  @override
  String get wxTonight => '今晚';

  @override
  String get wxTomorrow => '明天';

  @override
  String get wxTomorrowNight => '明晚';

  @override
  String get wxMonday => '星期一';

  @override
  String get wxMondayNight => '星期一晚上';

  @override
  String get wxTuesday => '星期二';

  @override
  String get wxTuesdayNight => '星期二晚上';

  @override
  String get wxWednesday => '星期三';

  @override
  String get wxWednesdayNight => '星期三晚上';

  @override
  String get wxThursday => '星期四';

  @override
  String get wxThursdayNight => '星期四晚上';

  @override
  String get wxFriday => '星期五';

  @override
  String get wxFridayNight => '星期五晚上';

  @override
  String get wxSaturday => '星期六';

  @override
  String get wxSaturdayNight => '星期六晚上';

  @override
  String get wxSunday => '星期日';

  @override
  String get wxSundayNight => '星期日晚上';

  @override
  String get wxReportBrief => '简要，短期预报，仅限美国';

  @override
  String get wxReportFull => '完整，更详细的预报，仅限美国';

  @override
  String get wxReportCurrent => '当前，最近的 NWS 站，仅限美国';

  @override
  String get wxReportMetar => 'METAR，ICAO 站 METAR 格式';

  @override
  String get wxReportCwop => 'CWOP，最近的 CWOP 站';
}
