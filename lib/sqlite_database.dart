import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'database_interface.dart';

class SQLiteDatabase with CharacterDetection implements DatabaseInterface {
  late Database expressionDb;
  late Database kanjiDb;
  final String expressionDbPath;
  final String kanjiDbPath;

  SQLiteDatabase({
    String? expressionPath,
    String? kanjiPath,
  })  : expressionDbPath = expressionPath ?? path.join(Directory.current.path, 'expression.db'),
        kanjiDbPath = kanjiPath ?? path.join(Directory.current.path, 'kanji.db');

  @override
  Future<void> initialize() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

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

      print('SQLite databases opened successfully!');
    } catch (e) {
      throw Exception('Failed to open databases: $e');
    }
  }

  @override
  Future<void> close() async {
    await expressionDb.close();
    await kanjiDb.close();
  }

  @override
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

      results = await expressionDb.rawQuery(sql, ['*$keyword*', limit, offset]);
    }

    return _processExpressionResults(results);
  }

  List<Map<String, dynamic>> _processExpressionResults(List<Map<String, dynamic>> results) {
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
}