# Jisho API Compatible Server

A lightweight Japanese dictionary API server that provides compatibility with the Jisho.org API format. 

This project serves as a foundation for self-hosted Japanese dictionary lookups using local database files.

## Overview

This server aims to be compatible with the Jisho.org API, allowing applications built for Jisho to 

work with a local dictionary backend.

**Current Status:** This is primarily a stub implementation. While the API endpoints return responses 

in the expected Jisho-compatible format, many features are not yet implemented. 

Unimplemented features return empty arrays to maintain compatibility with existing clients.

## Quick Start

### Installation

1. Clone this repository
2. Install dependencies:
```bash
dart pub get
```

### Database Setup

Download the required database files from the [edict_database releases](https://github.com/odrevet/edict_database/releases):
- `expression.db`
- `kanji.db`

Place both files in the root directory of the project.

### Running the Server

```bash
dart run main.dart
```

The server will start on `http://localhost:8080`

### Testing

Try a sample search:
```
http://localhost:8080/api/v1/search/words?keyword=大統領
```

## API Compatibility

This project follows the Jisho.org API structure. Clients expecting Jisho's response format should 

work with this server, though many will return empty arrays until fully implemented.


## Links

- [Jisho.org API Documentation](https://jisho.org/forum/54fefc1f6e73340b1f160000-is-there-any-kind-of-search-api)
- [EDICT Database Source](https://github.com/odrevet/edict_database)
