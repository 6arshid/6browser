import 'dart:ui' show Locale;

/// A language voice commands can be spoken in: Whisper's code for it and
/// the tag Android's recognizer takes. The user picks it; guessing from the
/// speech mixed up languages (Danish came out as English or Persian
/// gibberish).
class VoiceLanguage {
  const VoiceLanguage(this.code, this.name, this.nativeName, this.androidTag);

  /// ISO 639-1, as Whisper names it.
  final String code;

  /// In English, for sorting and settings.
  final String name;

  /// As its speakers write it.
  final String nativeName;
  final String androidTag;

  /// "Danish (Dansk)", "English".
  String get label => name == nativeName ? name : '$name ($nativeName)';

  static const english = VoiceLanguage('en', 'English', 'English', 'en-US');
  static const persian = VoiceLanguage('fa', 'Persian', 'فارسی', 'fa-IR');
  static const danish = VoiceLanguage('da', 'Danish', 'Dansk', 'da-DK');

  static VoiceLanguage? byCode(String? code) {
    for (final language in voiceLanguages) {
      if (language.code == code) return language;
    }
    return null;
  }

  /// The first of the user's system languages that can be spoken, else
  /// English.
  static VoiceLanguage fromLocales(Iterable<Locale> locales) {
    for (final locale in locales) {
      final code = switch (locale.languageCode) {
        'nb' || 'nn' => 'no',
        'iw' => 'he',
        'fil' => 'tl',
        final other => other,
      };
      if (byCode(code) case final language?) return language;
    }
    return english;
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'VoiceLanguage($code)';
}

/// The languages Whisper recognizes well (OpenAI lists those under 50% word
/// error rate), by English name. Commands are understood in English,
/// Persian and Danish; in the others what is said is searched for, and a
/// site's name opens it.
const voiceLanguages = [
  VoiceLanguage('af', 'Afrikaans', 'Afrikaans', 'af-ZA'),
  VoiceLanguage('ar', 'Arabic', 'العربية', 'ar-SA'),
  VoiceLanguage('hy', 'Armenian', 'Հայերեն', 'hy-AM'),
  VoiceLanguage('az', 'Azerbaijani', 'Azərbaycanca', 'az-AZ'),
  VoiceLanguage('be', 'Belarusian', 'Беларуская', 'be-BY'),
  VoiceLanguage('bs', 'Bosnian', 'Bosanski', 'bs-BA'),
  VoiceLanguage('bg', 'Bulgarian', 'Български', 'bg-BG'),
  VoiceLanguage('ca', 'Catalan', 'Català', 'ca-ES'),
  VoiceLanguage('zh', 'Chinese', '中文', 'zh-CN'),
  VoiceLanguage('hr', 'Croatian', 'Hrvatski', 'hr-HR'),
  VoiceLanguage('cs', 'Czech', 'Čeština', 'cs-CZ'),
  VoiceLanguage.danish,
  VoiceLanguage('nl', 'Dutch', 'Nederlands', 'nl-NL'),
  VoiceLanguage.english,
  VoiceLanguage('et', 'Estonian', 'Eesti', 'et-EE'),
  VoiceLanguage('fi', 'Finnish', 'Suomi', 'fi-FI'),
  VoiceLanguage('fr', 'French', 'Français', 'fr-FR'),
  VoiceLanguage('gl', 'Galician', 'Galego', 'gl-ES'),
  VoiceLanguage('de', 'German', 'Deutsch', 'de-DE'),
  VoiceLanguage('el', 'Greek', 'Ελληνικά', 'el-GR'),
  VoiceLanguage('he', 'Hebrew', 'עברית', 'he-IL'),
  VoiceLanguage('hi', 'Hindi', 'हिन्दी', 'hi-IN'),
  VoiceLanguage('hu', 'Hungarian', 'Magyar', 'hu-HU'),
  VoiceLanguage('is', 'Icelandic', 'Íslenska', 'is-IS'),
  VoiceLanguage('id', 'Indonesian', 'Bahasa Indonesia', 'id-ID'),
  VoiceLanguage('it', 'Italian', 'Italiano', 'it-IT'),
  VoiceLanguage('ja', 'Japanese', '日本語', 'ja-JP'),
  VoiceLanguage('kn', 'Kannada', 'ಕನ್ನಡ', 'kn-IN'),
  VoiceLanguage('kk', 'Kazakh', 'Қазақ тілі', 'kk-KZ'),
  VoiceLanguage('ko', 'Korean', '한국어', 'ko-KR'),
  VoiceLanguage('lv', 'Latvian', 'Latviešu', 'lv-LV'),
  VoiceLanguage('lt', 'Lithuanian', 'Lietuvių', 'lt-LT'),
  VoiceLanguage('mk', 'Macedonian', 'Македонски', 'mk-MK'),
  VoiceLanguage('ms', 'Malay', 'Bahasa Melayu', 'ms-MY'),
  VoiceLanguage('mi', 'Maori', 'Māori', 'mi-NZ'),
  VoiceLanguage('mr', 'Marathi', 'मराठी', 'mr-IN'),
  VoiceLanguage('ne', 'Nepali', 'नेपाली', 'ne-NP'),
  VoiceLanguage('no', 'Norwegian', 'Norsk', 'nb-NO'),
  VoiceLanguage.persian,
  VoiceLanguage('pl', 'Polish', 'Polski', 'pl-PL'),
  VoiceLanguage('pt', 'Portuguese', 'Português', 'pt-BR'),
  VoiceLanguage('ro', 'Romanian', 'Română', 'ro-RO'),
  VoiceLanguage('ru', 'Russian', 'Русский', 'ru-RU'),
  VoiceLanguage('sr', 'Serbian', 'Српски', 'sr-RS'),
  VoiceLanguage('sk', 'Slovak', 'Slovenčina', 'sk-SK'),
  VoiceLanguage('sl', 'Slovenian', 'Slovenščina', 'sl-SI'),
  VoiceLanguage('es', 'Spanish', 'Español', 'es-ES'),
  VoiceLanguage('sw', 'Swahili', 'Kiswahili', 'sw-KE'),
  VoiceLanguage('sv', 'Swedish', 'Svenska', 'sv-SE'),
  VoiceLanguage('tl', 'Tagalog', 'Tagalog', 'fil-PH'),
  VoiceLanguage('ta', 'Tamil', 'தமிழ்', 'ta-IN'),
  VoiceLanguage('th', 'Thai', 'ไทย', 'th-TH'),
  VoiceLanguage('tr', 'Turkish', 'Türkçe', 'tr-TR'),
  VoiceLanguage('uk', 'Ukrainian', 'Українська', 'uk-UA'),
  VoiceLanguage('ur', 'Urdu', 'اردو', 'ur-PK'),
  VoiceLanguage('vi', 'Vietnamese', 'Tiếng Việt', 'vi-VN'),
  VoiceLanguage('cy', 'Welsh', 'Cymraeg', 'cy-GB'),
];
