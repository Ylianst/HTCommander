import 'package:flutter/widgets.dart';

import 'data_broker.dart';

/// Manages the application's active [Locale] for internationalization.
///
/// The selected language is persisted via the [DataBroker] under the
/// `Language` key on device 0 (the same store used by the settings dialog).
  /// The stored value is a language tag: `system` (follow the OS locale), `en`,
  /// `fr`, `es`, `zh`, `ja`, `hi`, `de` or `pl`. The active [Locale] is exposed as a [ValueNotifier] so that the
/// top-level `MaterialApp` can rebuild whenever the language changes.
class LocaleController {
  LocaleController._();

  /// Singleton instance shared across the application.
  static final LocaleController instance = LocaleController._();

  /// DataBroker key used to persist the selected language tag.
  static const String storageKey = 'Language';

  /// Sentinel language tag meaning "follow the operating system locale".
  static const String systemTag = 'system';

  /// Language tags the application ships translations for.
  static const List<String> supportedLanguageTags = ['en', 'fr', 'es', 'zh', 'ja', 'hi', 'de', 'pl', 'it'];

  /// The active locale, or `null` to follow the operating system locale.
  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  /// Loads the persisted language selection and applies it to [locale]. Call
  /// once during application startup before building the `MaterialApp`.
  void load() {
    final tag = DataBroker.getValue<String>(0, storageKey, systemTag) ??
        systemTag;
    locale.value = _localeForTag(tag);
  }

  /// The persisted language tag (`system`, `en`, `fr`, `es`, `zh`, `ja`, `hi`, `de`, `pl`, ...).
  String get languageTag {
    final loc = locale.value;
    return loc == null ? systemTag : loc.languageCode;
  }

  /// Updates the active language and persists the choice. Pass [systemTag] to
  /// follow the operating system locale.
  void setLanguage(String tag) {
    final newLocale = _localeForTag(tag);
    locale.value = newLocale;
    DataBroker.dispatch(deviceId: 0, name: storageKey, data: tag);
  }

  Locale? _localeForTag(String tag) {
    if (tag == systemTag) return null;
    if (supportedLanguageTags.contains(tag)) return Locale(tag);
    // Unknown tag: fall back to following the system locale.
    return null;
  }

  /// Resolves the active locale against the app's [supportedLocales], defaulting
  /// to English for any unsupported system locale.
  ///
  /// Flutter's default resolution falls back to the *first* supported locale
  /// when none match the device, which would show German for e.g. an Italian
  /// device. This callback forces English as the neutral fallback instead.
  static Locale localeListResolutionCallback(
    List<Locale>? locales,
    Iterable<Locale> supportedLocales,
  ) {
    if (locales != null) {
      for (final locale in locales) {
        for (final supported in supportedLocales) {
          if (supported.languageCode == locale.languageCode) return supported;
        }
      }
    }
    return supportedLocales.firstWhere(
      (locale) => locale.languageCode == 'en',
      orElse: () => supportedLocales.first,
    );
  }
}
