import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

class JishoApiServer {
  late Database expressionDb;
  late Database kanjiDb;

  Future<void> initialize() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Get absolute paths for database files
    final currentDir = Directory.current.path;
    final expressionDbPath = path.join(currentDir, 'expression.db');
    final kanjiDbPath = path.join(currentDir, 'kanji.db');

    // Check if database files exist
    if (!File(expressionDbPath).existsSync()) {
      throw Exception('Database file not found: $expressionDbPath\nPlease place expression.db in the project root directory.');
    }

    if (!File(kanjiDbPath).existsSync()) {
      throw Exception('Database file not found: $kanjiDbPath\nPlease place kanji.db in the project root directory.');
    }

    print('Opening database: $expressionDbPath');
    print('Opening database: $kanjiDbPath');

    try {
      expressionDb = await openDatabase(expressionDbPath, readOnly: true);
      kanjiDb = await openDatabase(kanjiDbPath, readOnly: true);

      // Verify tables exist
      var tables = await expressionDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      print('Expression DB tables: ${tables.map((t) => t['name']).join(', ')}');

      tables = await kanjiDb.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
      print('Kanji DB tables: ${tables.map((t) => t['name']).join(', ')}');

      print('Databases opened successfully!');
    } catch (e) {
      throw Exception('Failed to open databases: $e');
    }
  }

  bool isKanji(String char) {
    if (char.isEmpty) return false;
    int code = char.codeUnitAt(0);
    return code >= 0x4e00 && code <= 0x9fff;
  }

  bool isHiragana(String char) {
    if (char.isEmpty) return false;
    int code = char.codeUnitAt(0);
    return code >= 0x3040 && code <= 0x309f;
  }

  bool isKatakana(String char) {
    if (char.isEmpty) return false;
    int code = char.codeUnitAt(0);
    return code >= 0x30a0 && code <= 0x30ff;
  }

  String detectInputType(String keyword) {
    if (keyword.isEmpty) return 'romaji';

    bool hasKanji = keyword.runes.any((rune) => isKanji(String.fromCharCode(rune)));
    bool hasHiragana = keyword.runes.any((rune) => isHiragana(String.fromCharCode(rune)));
    bool hasKatakana = keyword.runes.any((rune) => isKatakana(String.fromCharCode(rune)));

    if (hasKanji) return 'kanji';
    if (hasHiragana || hasKatakana) return 'kana';
    return 'romaji';
  }

  Future<List<Map<String, dynamic>>> searchExpressions(String keyword, {int limit = 20, int offset = 0}) async {
    String inputType = detectInputType(keyword);
    List<Map<String, dynamic>> results;

    if (inputType == 'kanji' || inputType == 'kana') {
      // Search in Japanese - using subquery to limit entries first
      String sql = '''
        SELECT
            entry.id AS entry_id,
            sense.id AS sense_id,
            GROUP_CONCAT(DISTINCT COALESCE(k_ele.keb || ':', '') || r_ele.reb) keb_reb_group,
            GROUP_CONCAT(DISTINCT gloss.content) AS gloss_group,
            GROUP_CONCAT(DISTINCT pos.name) AS pos_group,
            GROUP_CONCAT(DISTINCT dial.name) AS dial_group,
            GROUP_CONCAT(DISTINCT misc.name) AS misc_group,
            GROUP_CONCAT(DISTINCT field.name) AS field_group,
            GROUP_CONCAT(DISTINCT
                CASE
                    WHEN sense_xref.reb IS NOT NULL
                    THEN COALESCE(sense_xref.keb, '') || ':' || sense_xref.reb
                    WHEN sense_xref.keb IS NOT NULL
                    THEN sense_xref.keb
                END
            ) AS xref_group,
            GROUP_CONCAT(DISTINCT
                CASE
                    WHEN sense_ant.reb IS NOT NULL
                    THEN COALESCE(sense_ant.keb, '') || ':' || sense_ant.reb
                    WHEN sense_ant.keb IS NOT NULL
                    THEN sense_ant.keb
                END
            ) AS ant_group
        FROM entry
            JOIN r_ele ON entry.id = r_ele.id_entry
            JOIN sense ON sense.id_entry = entry.id
            JOIN gloss ON gloss.id_sense = sense.id
            LEFT JOIN k_ele ON entry.id = k_ele.id_entry
            LEFT JOIN sense_pos ON sense.id = sense_pos.id_sense
            LEFT JOIN pos ON sense_pos.id_pos = pos.id
            LEFT JOIN sense_dial ON sense.id = sense_dial.id_sense
            LEFT JOIN dial ON sense_dial.id_dial = dial.id
            LEFT JOIN sense_misc ON sense.id = sense_misc.id_sense
            LEFT JOIN misc ON sense_misc.id_misc = misc.id
            LEFT JOIN sense_field ON sense.id = sense_field.id_sense
            LEFT JOIN field ON sense_field.id_field = field.id
            LEFT JOIN sense_xref ON sense.id = sense_xref.id_sense
            LEFT JOIN sense_ant ON sense.id = sense_ant.id_sense
        WHERE entry.id IN (
            SELECT DISTINCT entry_sub.id 
            FROM entry entry_sub
            JOIN sense sense_sub ON entry_sub.id = sense_sub.id_entry 
            JOIN r_ele ON entry_sub.id = r_ele.id_entry
            LEFT JOIN k_ele ON entry_sub.id = k_ele.id_entry 
            WHERE (r_ele.reb GLOB ? OR k_ele.keb GLOB ?)
            LIMIT ? OFFSET ?
        )
        GROUP BY entry.id, sense.id
      ''';
      results = await expressionDb.rawQuery(sql, ['*$keyword*', '*$keyword*', limit, offset]);
    } else {
      // Search in English - using subquery to limit entries first
      String sql = '''
        SELECT
            entry.id AS entry_id,
            sense.id AS sense_id,
            GROUP_CONCAT(DISTINCT COALESCE(k_ele.keb || ':', '') || r_ele.reb) keb_reb_group,
            GROUP_CONCAT(DISTINCT gloss.content) AS gloss_group,
            GROUP_CONCAT(DISTINCT pos.name) AS pos_group,
            GROUP_CONCAT(DISTINCT dial.name) AS dial_group,
            GROUP_CONCAT(DISTINCT misc.name) AS misc_group,
            GROUP_CONCAT(DISTINCT field.name) AS field_group,
            GROUP_CONCAT(DISTINCT
                CASE
                    WHEN sense_xref.reb IS NOT NULL
                    THEN COALESCE(sense_xref.keb, '') || ':' || sense_xref.reb
                    WHEN sense_xref.keb IS NOT NULL
                    THEN sense_xref.keb
                END
            ) AS xref_group,
            GROUP_CONCAT(DISTINCT
                CASE
                    WHEN sense_ant.reb IS NOT NULL
                    THEN COALESCE(sense_ant.keb, '') || ':' || sense_ant.reb
                    WHEN sense_ant.keb IS NOT NULL
                    THEN sense_ant.keb
                END
            ) AS ant_group
        FROM entry
            JOIN r_ele ON entry.id = r_ele.id_entry
            JOIN sense ON sense.id_entry = entry.id
            JOIN gloss ON gloss.id_sense = sense.id
            LEFT JOIN k_ele ON entry.id = k_ele.id_entry
            LEFT JOIN sense_pos ON sense.id = sense_pos.id_sense
            LEFT JOIN pos ON sense_pos.id_pos = pos.id
            LEFT JOIN sense_dial ON sense.id = sense_dial.id_sense
            LEFT JOIN dial ON sense_dial.id_dial = dial.id
            LEFT JOIN sense_misc ON sense.id = sense_misc.id_sense
            LEFT JOIN misc ON sense_misc.id_misc = misc.id
            LEFT JOIN sense_field ON sense.id = sense_field.id_sense
            LEFT JOIN field ON sense_field.id_field = field.id
            LEFT JOIN sense_xref ON sense.id = sense_xref.id_sense
            LEFT JOIN sense_ant ON sense.id = sense_ant.id_sense
        WHERE entry.id IN (
            SELECT DISTINCT entry_sub.id 
            FROM entry entry_sub
            JOIN sense sense_sub ON entry_sub.id = sense_sub.id_entry 
            JOIN gloss ON sense_sub.id = gloss.id_sense
            WHERE gloss.content GLOB ?
            LIMIT ? OFFSET ?
        )
        GROUP BY entry.id, sense.id
      ''';

      print(sql);
      results = await expressionDb.rawQuery(sql, [keyword, limit, offset]);
    }

    // Group results by entry_id
    Map<int, Map<String, dynamic>> entriesDict = {};

    for (var row in results) {
      int entryId = row['entry_id'] as int;

      if (!entriesDict.containsKey(entryId)) {
        entriesDict[entryId] = {
          'japanese': <Map<String, String>>[],
          'senses': <Map<String, dynamic>>[]
        };
      }

      // Parse keb_reb_group to get japanese readings
      String kebReb = row['keb_reb_group']?.toString() ?? '';
      if (kebReb.isNotEmpty && entriesDict[entryId]!['japanese'].isEmpty) {
        Set<String> seenEntries = {};
        for (String item in kebReb.split(',')) {
          if (seenEntries.contains(item)) continue;
          seenEntries.add(item);

          Map<String, String> japaneseEntry = {};
          if (item.contains(':')) {
            List<String> parts = item.split(':');
            if (parts[0].isNotEmpty) {
              japaneseEntry['word'] = parts[0];
            }
            japaneseEntry['reading'] = parts[1];
          } else {
            japaneseEntry['reading'] = item;
          }
          entriesDict[entryId]!['japanese'].add(japaneseEntry);
        }
      }

      // Add sense
      Map<String, dynamic> sense = {
        'english_definitions': row['gloss_group']?.toString().split(',') ?? [],
        'parts_of_speech': row['pos_group']?.toString().split(',') ?? [],
        'links': [],
        'tags': [],
        'restrictions': [],
        'see_also': row['xref_group']?.toString().split(',').where((s) => s.isNotEmpty).toList() ?? [],
        'antonyms': row['ant_group']?.toString().split(',').where((s) => s.isNotEmpty).toList() ?? [],
        'source': [],
        'info': []
      };

      entriesDict[entryId]!['senses'].add(sense);
    }

    // Convert to list format
    List<Map<String, dynamic>> data = [];
    entriesDict.forEach((entryId, entryData) {
      List<Map<String, String>> japanese = entryData['japanese'] as List<Map<String, String>>;
      String slug = '';
      if (japanese.isNotEmpty) {
        slug = japanese[0]['word'] ?? japanese[0]['reading'] ?? '';
      }

      data.add({
        'slug': slug,
        'is_common': false,
        'tags': [],
        'jlpt': [],
        'japanese': japanese,
        'senses': entryData['senses'],
        'attribution': {
          'jmdict': true,
          'jmnedict': false,
          'dbpedia': false
        }
      });
    });

    return data;
  }

  Future<List<Map<String, dynamic>>> searchKanji(String keyword) async {
    // Extract kanji characters from keyword
    List<String> kanjiChars = [];
    for (int rune in keyword.runes) {
      String char = String.fromCharCode(rune);
      if (isKanji(char)) {
        kanjiChars.add(char);
      }
    }

    if (kanjiChars.isEmpty) {
      return [];
    }

    String placeholders = kanjiChars.map((char) => '?').join(',');
    String sql = '''
      SELECT character.*,
             GROUP_CONCAT(DISTINCT character_radical.id_radical) AS radicals,
             GROUP_CONCAT(DISTINCT on_yomi.reading) AS on_reading,
             GROUP_CONCAT(DISTINCT kun_yomi.reading) AS kun_reading,
             GROUP_CONCAT(DISTINCT meaning.content) AS meanings
        FROM character
             LEFT JOIN character_radical ON character.id = character_radical.id_character
             LEFT JOIN on_yomi ON character.id = on_yomi.id_character
             LEFT JOIN kun_yomi ON kun_yomi.id_character = character.id
             LEFT JOIN meaning ON meaning.id_character = character.id
       WHERE character.id IN ($placeholders)
       GROUP BY character.id
    ''';

    List<Map<String, dynamic>> results = await kanjiDb.rawQuery(sql, kanjiChars);

    List<Map<String, dynamic>> data = [];
    for (var row in results) {
      data.add({
        'kanji': row['id'],
        'grade': row['grade'],
        'stroke_count': row['stroke_count'],
        'meanings': row['meanings']?.toString().split(',') ?? [],
        'kun_readings': row['kun_reading']?.toString().split(',') ?? [],
        'on_readings': row['on_reading']?.toString().split(',') ?? [],
        'name_readings': [],
        'jlpt': null,
        'unicode': row['id'] != null ? '0x${row['id'].toString().codeUnitAt(0).toRadixString(16)}' : null,
        'newspaper_frequency_rank': row['freq']
      });
    }

    return data;
  }

  Response _jsonResponse(Map<String, dynamic> data, {int statusCode = 200}) {
    return Response.ok(
      jsonEncode(data),
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Response> handleSearch(Request request) async {
    final params = request.url.queryParameters;
    final keyword = params['keyword'];

    if (keyword == null || keyword.isEmpty) {
      return _jsonResponse(
        {'meta': {'status': 400}, 'error': 'keyword parameter is required'},
        statusCode: 400,
      );
    }

    try {
      // Keyword is already decoded by the router
      print('Search keyword: $keyword');

      // Search both expressions and kanji
      List<Map<String, dynamic>> words = await searchExpressions(keyword);
      List<Map<String, dynamic>> kanji = await searchKanji(keyword);

      print('Found ${words.length} words and ${kanji.length} kanji');

      return _jsonResponse({
        'meta': {'status': 200},
        'data': words,
        'kanji': kanji
      });
    } catch (e, stackTrace) {
      print('Error: $e');
      print('Stack trace: $stackTrace');
      return _jsonResponse(
        {'meta': {'status': 500}, 'error': e.toString()},
        statusCode: 500,
      );
    }
  }

  Router get router {
    final router = Router();

    router.get('/api/v1/search/words', handleSearch);

    router.get('/', (Request request) {
      return _jsonResponse({
        'name': 'Jisho API Clone',
        'version': '1.0.0',
        'endpoints': {
          '/api/v1/search/words': 'Search for Japanese words and kanji'
        }
      });
    });

    return router;
  }
}

void main() async {
  print('Starting Jisho API Server...');

  final server = JishoApiServer();

  try {
    await server.initialize();
  } catch (e) {
    print('\n❌ ERROR: Failed to initialize server');
    print(e);
    print('\nPlease ensure expression.db and kanji.db are in the project root directory.');
    exit(1);
  }

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(server.router);

  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;

  try {
    final serverInstance = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    print('\n✅ Server running on http://${serverInstance.address.host}:${serverInstance.port}');
    print('Try: http://localhost:$port/api/v1/search/words?keyword=大統領');
  } catch (e) {
    print('\n❌ ERROR: Failed to start server');
    print(e);
    exit(1);
  }
}