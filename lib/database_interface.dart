/// Abstract interface for database operations
abstract class DatabaseInterface {
  /// Initialize the database connection
  Future<void> initialize();

  /// Close the database connection
  Future<void> close();

  /// Search for expressions/words in the database
  Future<List<Map<String, dynamic>>> searchExpressions(
      String keyword, {
        int limit = 20,
        int offset = 0,
      });
}

/// Mixin providing character detection utilities
mixin CharacterDetection {
  /// Detect if a character is kanji
  bool isKanji(String char) {
    if (char.isEmpty) return false;
    int code = char.codeUnitAt(0);
    return code >= 0x4e00 && code <= 0x9fff;
  }

  /// Detect if a character is hiragana
  bool isHiragana(String char) {
    if (char.isEmpty) return false;
    int code = char.codeUnitAt(0);
    return code >= 0x3040 && code <= 0x309f;
  }

  /// Detect if a character is katakana
  bool isKatakana(String char) {
    if (char.isEmpty) return false;
    int code = char.codeUnitAt(0);
    return code >= 0x30a0 && code <= 0x30ff;
  }

  /// Detect the input type (kanji, kana, or romaji)
  String detectInputType(String keyword) {
    if (keyword.isEmpty) return 'romaji';

    bool hasKanji = keyword.runes.any((rune) => isKanji(String.fromCharCode(rune)));
    bool hasHiragana = keyword.runes.any((rune) => isHiragana(String.fromCharCode(rune)));
    bool hasKatakana = keyword.runes.any((rune) => isKatakana(String.fromCharCode(rune)));

    if (hasKanji) return 'kanji';
    if (hasHiragana || hasKatakana) return 'kana';
    return 'romaji';
  }
}