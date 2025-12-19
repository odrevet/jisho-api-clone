import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:dotenv/dotenv.dart';
import 'package:jisho_api_clone/database_interface.dart';
import 'package:jisho_api_clone/sqlite_database.dart';
import 'package:jisho_api_clone/postgres_database.dart';
import 'package:jisho_api_clone/jisho_server.dart';

void main() async {
  print('Starting Jisho API Server...');

  // Load environment variables from .env file
  var env = DotEnv(includePlatformEnvironment: true)..load();

  // Read database type from environment variable (default to sqlite)
  final dbType = env['DB_TYPE']?.toLowerCase() ?? 'sqlite';

  print('Loaded DB_TYPE: ${env['DB_TYPE']}');
  print('Using database type: $dbType');

  late DatabaseInterface database;

  try {
    if (dbType == 'postgres' || dbType == 'postgresql') {
      print('Using PostgreSQL database');
      database = PostgresDatabase(
        host: env['POSTGRES_HOST'] ?? 'localhost',
        port: int.tryParse(env['POSTGRES_PORT'] ?? '5432') ?? 5432,
        database: env['POSTGRES_DB'] ?? 'jisho',
        username: env['POSTGRES_USER'] ?? 'postgres',
        password: env['POSTGRES_PASSWORD'] ?? 'postgres',
      );
    } else {
      print('Using SQLite database');
      database = SQLiteDatabase(
        expressionPath: env['EXPRESSION_DB_PATH'],
        kanjiPath: env['KANJI_DB_PATH'],
      );
    }

    await database.initialize();
  } catch (e) {
    print('\n❌ ERROR: Failed to initialize database');
    print(e);
    if (dbType == 'sqlite') {
      print('\nPlease ensure expression.db and kanji.db are in the project root directory.');
      print('Or configure these variables in your .env file:');
      print('  EXPRESSION_DB_PATH=/path/to/expression.db');
      print('  KANJI_DB_PATH=/path/to/kanji.db');
    } else {
      print('\nPlease ensure PostgreSQL is running and configure these variables in your .env file:');
      print('  POSTGRES_HOST=localhost');
      print('  POSTGRES_PORT=5432');
      print('  POSTGRES_DB=jisho');
      print('  POSTGRES_USER=your_username');
      print('  POSTGRES_PASSWORD=your_password');
    }
    exit(1);
  }

  final server = JishoApiServer(database);

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(server.router.call);

  final port = int.tryParse(env['PORT'] ?? '8080') ?? 8080;

  try {
    final serverInstance = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    print('\n✅ Server running on http://${serverInstance.address.host}:${serverInstance.port}');
    print('Database type: $dbType');
    print('Try: http://localhost:$port/api/v1/search/words?keyword=大統領');

    // Handle graceful shutdown
    ProcessSignal.sigint.watch().listen((signal) async {
      print('\n\nShutting down gracefully...');
      await database.close();
      await serverInstance.close();
      exit(0);
    });
  } catch (e) {
    print('\n❌ ERROR: Failed to start server');
    print(e);
    await database.close();
    exit(1);
  }
}