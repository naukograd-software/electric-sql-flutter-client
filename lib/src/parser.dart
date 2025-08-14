import 'dart:convert';

import 'error.dart';
import 'types.dart';

typedef ParseFunction = SqlValue Function(String value, [Map<String, dynamic>? additionalInfo]);

final Map<String, ParseFunction> defaultParser = {
  'int2': (v, [_]) => int.parse(v),
  'int4': (v, [_]) => int.parse(v),
  'int8': (v, [_]) => int.parse(v), // Dart has no BigInt JSON, treat as int
  'bool': (v, [_]) => v == 'true' || v == 't',
  'float4': (v, [_]) => double.parse(v),
  'float8': (v, [_]) => double.parse(v),
  'json': (v, [_]) => jsonDecode(v),
  'jsonb': (v, [_]) => jsonDecode(v),
};

SqlValue pgArrayParser(String value, ParseFunction? parser) {
  int i = 0;
  String? char;
  String str = '';
  bool quoted = false;
  int last = 0;
  String? p;

  SqlValue extractValue(String x, int start, int end) {
    String? val = x.substring(start, end);
    val = (val == 'NULL') ? null : val;
    return parser != null ? parser(val ?? 'null') : val;
  }

  List<SqlValue> loop(String x) {
    final List<SqlValue> xs = [];
    for (; i < x.length; i++) {
      char = x[i];
      if (quoted) {
        if (char == '\\') {
          i += 1;
          str += x[i];
        } else if (char == '"') {
          xs.add(parser != null ? parser(str) : str);
          str = '';
          quoted = x[i + 1] == '"';
          last = i + 2;
        } else {
          str += char!;
        }
      } else if (char == '"') {
        quoted = true;
      } else if (char == '{') {
        last = ++i;
        xs.add(loop(x));
      } else if (char == '}') {
        quoted = false;
        if (last < i) xs.add(extractValue(x, last, i));
        last = i + 1;
        break;
      } else if (char == ',' && p != '}' && p != '"') {
        xs.add(extractValue(x, last, i));
        last = i + 1;
      }
      p = char;
    }
    if (last < i) {
      xs.add(extractValue(x, last, i + 1));
    }
    return xs;
  }

  return loop(value).first;
}

class MessageParser {
  final Map<String, ParseFunction> parser;
  MessageParser({Map<String, ParseFunction>? parser})
      : parser = {...defaultParser, ...?parser};

  // Parse a list of messages and return as strongly typed List<Message>
  List<Map<String, dynamic>> parseMessages(String messages, Schema schema) {
    final decoded = jsonDecode(messages, reviver: (key, value) {
      if ((key == 'value' || key == 'old_value') && value is Map) {
        final row = value as Map<String, dynamic>;
        for (final entry in row.entries) {
          row[entry.key] = _parseRow(entry.key, entry.value, schema);
        }
      }
      return value;
    });
    final list = (decoded as List)
        .map<Map<String, dynamic>>((e) => (e as Map).cast<String, dynamic>())
        .toList(growable: false);
    return list;
  }

  // Parse a single message object
  Map<String, dynamic> parseMessage(String message, Schema schema) {
    final decoded = jsonDecode(message, reviver: (key, value) {
      if ((key == 'value' || key == 'old_value') && value is Map) {
        final row = value as Map<String, dynamic>;
        for (final entry in row.entries) {
          row[entry.key] = _parseRow(entry.key, entry.value, schema);
        }
      }
      return value;
    });
    return (decoded as Map).cast<String, dynamic>();
  }

  SqlValue _parseRow(String key, SqlValue value, Schema schema) {
    final columnInfo = schema[key];
    if (columnInfo == null) return value;

    final String type = columnInfo['type'] as String;
    final int? dims = columnInfo['dims'] as int?;
    final Map<String, dynamic> additionalInfo = Map<String, dynamic>.from(columnInfo)
      ..remove('type')
      ..remove('dims');

    final typeParser = parser[type];
    final SqlValue Function(SqlValue v) nullableParser = (SqlValue v) {
      final bool isNullable = !(columnInfo['not_null'] == true);
      if (v == null) {
        if (!isNullable) throw ParserNullValueError(key);
        return null;
      }
      if (v is String) {
        if (typeParser == null) return v;
        return typeParser(v, additionalInfo);
      }
      return v;
    };

    if (dims != null && dims > 0) {
      if (value is String) {
        return nullableParser(pgArrayParser(value, (s, [__]) => typeParser != null ? typeParser(s, additionalInfo) : s));
      }
      return value;
    }

    return nullableParser(value);
  }
}


