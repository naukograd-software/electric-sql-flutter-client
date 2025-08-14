import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<ProcessResult> runPsql(String sql) async {
  final result = await Process.run(
    'docker',
    [
      'compose',
      '-f',
      'docker-compose.yaml',
      'exec',
      '-T',
      'postgres',
      'psql',
      '-U',
      'postgres',
      '-d',
      'postgres',
      '-c',
      sql,
    ],
  );
  if (result.exitCode != 0) {
    throw Exception('psql failed: ${result.stderr}');
  }
  return result;
}

Future<String> insertWidget({String? id, required String name}) async {
  if (id != null) {
    await runPsql("INSERT INTO widgets (id, name) VALUES ($id, '$name');");
    return id;
  } else {
    final res = await runPsql("INSERT INTO widgets (name) VALUES ('$name') RETURNING id;");
    final out = (res.stdout as String).trim();
    final lines = const LineSplitter().convert(out);
    // naive parse: second to last line contains id
    final line = lines.reversed.firstWhere((l) => RegExp(r"^\s*\d+\s*").hasMatch(l), orElse: () => '');
    final match = RegExp(r"(\d+)").firstMatch(line);
    if (match == null) throw Exception('Failed to parse inserted id');
    return match.group(1)!;
  }
}

Future<void> updateWidget({required String id, required String name}) async {
  await runPsql("UPDATE widgets SET name = '$name' WHERE id = $id;");
}

Future<void> deleteWidget({required String id}) async {
  await runPsql("DELETE FROM widgets WHERE id = $id;");
}


