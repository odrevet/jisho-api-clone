import 'package:postgres/postgres.dart';
import 'database_interface.dart';

class PostgresDatabase with CharacterDetection implements DatabaseInterface {
  late Connection connection;
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;

  PostgresDatabase({
    this.host = 'localhost',
    this.port = 5432,
    required this.database,
    required this.username,
    required this.password,
  });

  @override
  Future<void> initialize() async {
    print('Connecting to PostgreSQL at $host:$port/$database...');

    try {
      connection = await Connection.open(
        Endpoint(
          host: host,
          port: port,
          database: database,
          username: username,
          password: password,
        ),
        settings: ConnectionSettings(sslMode: SslMode.disable),
      );

      // Test connection
      await connection.execute('SELECT 1');
      print('PostgreSQL connection established successfully!');
    } catch (e) {
      throw Exception('Failed to connect to PostgreSQL: $e');
    }
  }

  @override
  Future<void> close() async {
    await connection.close();
  }

  @override
  Future<List<Map<String, dynamic>>> searchExpressions(
      String keyword, {
        int limit = 10,
        int offset = 0,
      }) async {
    String inputType = detectInputType(keyword);
    Result results;

    if (inputType == 'kanji' || inputType == 'kana') {
      String sql = '''
                    SELECT
                    expression.entry.id AS entry_id,
                    expression.sense.id AS sense_id,
                    STRING_AGG(
                        DISTINCT COALESCE(expression.k_ele.keb || ':', '') || expression.r_ele.reb,
                        ','
                    ) AS keb_reb_group,
                    STRING_AGG(DISTINCT expression.gloss.content, ',') AS gloss_group,
                    STRING_AGG(DISTINCT INITCAP(TRIM(expression.pos.description)), ',') AS pos_group,
                    STRING_AGG(DISTINCT expression.dial.name, ',') AS dial_group,
                    STRING_AGG(DISTINCT expression.misc.name, ',') AS misc_group,
                    STRING_AGG(DISTINCT expression.field.name, ',') AS field_group,
                    STRING_AGG(
                        DISTINCT
                        CASE
                            WHEN expression.sense_xref.reb IS NOT NULL
                            THEN COALESCE(expression.sense_xref.keb, '') || ':' || expression.sense_xref.reb
                            WHEN expression.sense_xref.keb IS NOT NULL
                            THEN expression.sense_xref.keb
                        END,
                        ','
                    ) AS xref_group,
                    STRING_AGG(
                        DISTINCT
                        CASE
                            WHEN expression.sense_ant.reb IS NOT NULL
                            THEN COALESCE(expression.sense_ant.keb, '') || ':' || expression.sense_ant.reb
                            WHEN expression.sense_ant.keb IS NOT NULL
                            THEN expression.sense_ant.keb
                        END,
                        ','
                    ) AS ant_group
                FROM expression.entry
                JOIN expression.r_ele
                     ON expression.entry.id = expression.r_ele.id_entry
                JOIN expression.sense
                     ON expression.sense.id_entry = expression.entry.id
                JOIN expression.gloss
                     ON expression.gloss.id_sense = expression.sense.id
                LEFT JOIN expression.k_ele
                     ON expression.entry.id = expression.k_ele.id_entry
                LEFT JOIN expression.sense_pos
                     ON expression.sense.id = expression.sense_pos.id_sense
                LEFT JOIN expression.pos
                     ON expression.sense_pos.id_pos = expression.pos.id
                LEFT JOIN expression.sense_dial
                     ON expression.sense.id = expression.sense_dial.id_sense
                LEFT JOIN expression.dial
                     ON expression.sense_dial.id_dial = expression.dial.id
                LEFT JOIN expression.sense_misc
                     ON expression.sense.id = expression.sense_misc.id_sense
                LEFT JOIN expression.misc
                     ON expression.sense_misc.id_misc = expression.misc.id
                LEFT JOIN expression.sense_field
                     ON expression.sense.id = expression.sense_field.id_sense
                LEFT JOIN expression.field
                     ON expression.sense_field.id_field = expression.field.id
                LEFT JOIN expression.sense_xref
                     ON expression.sense.id = expression.sense_xref.id_sense
                LEFT JOIN expression.sense_ant
                     ON expression.sense.id = expression.sense_ant.id_sense
                WHERE expression.entry.id IN (
                    SELECT expression.entry.id
                    FROM expression.entry
                    JOIN expression.sense
                         ON expression.entry.id = expression.sense.id_entry
                    JOIN expression.r_ele
                         ON expression.entry.id = expression.r_ele.id_entry
                    LEFT JOIN expression.k_ele
                         ON expression.entry.id = expression.k_ele.id_entry
                    WHERE (
                        expression.r_ele.reb ~ @keyword
                        OR expression.k_ele.keb ~ @keyword
                    )
                    GROUP BY expression.entry.id
                    ORDER BY expression.entry.id
                    LIMIT @limit OFFSET @offset
                )
                GROUP BY
                    expression.entry.id,
                    expression.sense.id
                ORDER BY
                    expression.entry.id,
                    expression.sense.id;
''';
      results = await connection.execute(
        Sql.named(sql),
        parameters: {'keyword': keyword, 'limit': limit, 'offset': offset},
      );
    } else {
      // Search in English
      String sql = '''
                    SELECT
                        expression.entry.id AS entry_id,
                        expression.sense.id AS sense_id,
                        STRING_AGG(
                            DISTINCT COALESCE(expression.k_ele.keb || ':', '') || expression.r_ele.reb,
                            ','
                        ) AS keb_reb_group,
                        STRING_AGG(DISTINCT expression.gloss.content, ',') AS gloss_group,
                        STRING_AGG(DISTINCT INITCAP(TRIM(expression.pos.description)), ',') AS pos_group,
                        STRING_AGG(DISTINCT expression.dial.name, ',') AS dial_group,
                        STRING_AGG(DISTINCT expression.misc.name, ',') AS misc_group,
                        STRING_AGG(DISTINCT expression.field.name, ',') AS field_group,
                        STRING_AGG(
                            DISTINCT
                            CASE
                                WHEN expression.sense_xref.reb IS NOT NULL
                                THEN COALESCE(expression.sense_xref.keb, '') || ':' || expression.sense_xref.reb
                                WHEN expression.sense_xref.keb IS NOT NULL
                                THEN expression.sense_xref.keb
                            END,
                            ','
                        ) AS xref_group,
                        STRING_AGG(
                            DISTINCT
                            CASE
                                WHEN expression.sense_ant.reb IS NOT NULL
                                THEN COALESCE(expression.sense_ant.keb, '') || ':' || expression.sense_ant.reb
                                WHEN expression.sense_ant.keb IS NOT NULL
                                THEN expression.sense_ant.keb
                            END,
                            ','
                        ) AS ant_group
                    FROM expression.entry
                    JOIN expression.r_ele
                         ON expression.entry.id = expression.r_ele.id_entry
                    JOIN expression.sense
                         ON expression.sense.id_entry = expression.entry.id
                    JOIN expression.gloss
                         ON expression.gloss.id_sense = expression.sense.id
                    LEFT JOIN expression.k_ele
                         ON expression.entry.id = expression.k_ele.id_entry
                    LEFT JOIN expression.sense_pos
                         ON expression.sense.id = expression.sense_pos.id_sense
                    LEFT JOIN expression.pos
                         ON expression.sense_pos.id_pos = expression.pos.id
                    LEFT JOIN expression.sense_dial
                         ON expression.sense.id = expression.sense_dial.id_sense
                    LEFT JOIN expression.dial
                         ON expression.sense_dial.id_dial = expression.dial.id
                    LEFT JOIN expression.sense_misc
                         ON expression.sense.id = expression.sense_misc.id_sense
                    LEFT JOIN expression.misc
                         ON expression.sense_misc.id_misc = expression.misc.id
                    LEFT JOIN expression.sense_field
                         ON expression.sense.id = expression.sense_field.id_sense
                    LEFT JOIN expression.field
                         ON expression.sense_field.id_field = expression.field.id
                    LEFT JOIN expression.sense_xref
                         ON expression.sense.id = expression.sense_xref.id_sense
                    LEFT JOIN expression.sense_ant
                         ON expression.sense.id = expression.sense_ant.id_sense
                    WHERE expression.entry.id IN (
                        SELECT expression.entry.id
                        FROM expression.entry
                        JOIN expression.sense
                             ON expression.entry.id = expression.sense.id_entry
                        JOIN expression.gloss
                             ON expression.sense.id = expression.gloss.id_sense
                        WHERE expression.gloss.content ~ @keyword
                        GROUP BY expression.entry.id
                        ORDER BY expression.entry.id
                        LIMIT @limit OFFSET @offset
                    )
                    GROUP BY
                        expression.entry.id,
                        expression.sense.id
                    ORDER BY
                        expression.entry.id,
                        expression.sense.id;
      ''';

      results = await connection.execute(
        Sql.named(sql),
        parameters: {'keyword': keyword, 'limit': limit, 'offset': offset},
      );
    }

    return _processExpressionResults(results);
  }

  List<Map<String, dynamic>> _processExpressionResults(Result results) {
    // Group results by entry_id
    Map<int, Map<String, dynamic>> entriesDict = {};

    for (var row in results) {
      // Map PostgreSQL row to column names
      var rowMap = {
        'entry_id': row[0],
        'sense_id': row[1],
        'keb_reb_group': row[2],
        'gloss_group': row[3],
        'pos_group': row[4]?.toString().replaceAll(RegExp(r'\([^)]*\)'), '').trim(),
        'dial_group': row[5],
        'misc_group': row[6],
        'field_group': row[7],
        'xref_group': row[8],
        'ant_group': row[9],
      };

      int entryId = rowMap['entry_id'] as int;

      if (!entriesDict.containsKey(entryId)) {
        entriesDict[entryId] = {
          'japanese': <Map<String, String>>[],
          'senses': <Map<String, dynamic>>[],
        };
      }

      // Parse keb_reb_group to get japanese readings
      String kebReb = rowMap['keb_reb_group']?.toString() ?? '';
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
        'english_definitions':
        rowMap['gloss_group']?.toString().split(',') ?? [],
        'parts_of_speech': rowMap['pos_group']?.toString().split(',') ?? [],
        'links': [],
        'tags': [],
        'restrictions': [],
        'see_also':
        rowMap['xref_group']
            ?.toString()
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList() ??
            [],
        'antonyms':
        rowMap['ant_group']
            ?.toString()
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList() ??
            [],
        'source': [],
        'info': [],
      };

      entriesDict[entryId]!['senses'].add(sense);
    }

    // Convert to list format
    List<Map<String, dynamic>> data = [];
    entriesDict.forEach((entryId, entryData) {
      List<Map<String, String>> japanese =
      entryData['japanese'] as List<Map<String, String>>;
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
        'attribution': {'jmdict': true, 'jmnedict': false, 'dbpedia': false},
      });
    });

    return data;
  }
}