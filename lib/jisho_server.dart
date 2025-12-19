import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'database_interface.dart';

class JishoApiServer {
  final DatabaseInterface database;
  static const int itemsPerPage = 10;

  JishoApiServer(this.database);

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

    // Parse page parameter (default to 1)
    int page = 1;
    if (params['page'] != null) {
      try {
        page = int.parse(params['page']!);
        if (page < 1) {
          return _jsonResponse(
            {'meta': {'status': 400}, 'error': 'page parameter must be >= 1'},
            statusCode: 400,
          );
        }
      } catch (e) {
        return _jsonResponse(
          {'meta': {'status': 400}, 'error': 'page parameter must be a valid integer'},
          statusCode: 400,
        );
      }
    }

    // Calculate offset based on page number
    int offset = (page - 1) * itemsPerPage;

    try {
      print('Search keyword: $keyword, page: $page, offset: $offset');

      List<Map<String, dynamic>> words = await database.searchExpressions(
        keyword,
        limit: itemsPerPage,
        offset: offset,
      );

      return _jsonResponse({
        'meta': {'status': 200},
        'data': words,
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