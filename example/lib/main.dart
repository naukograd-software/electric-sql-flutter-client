import 'dart:async';
import 'dart:io';

import 'package:electric_sql_flutter_client/electric_sql_flutter_client.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Init sqlite3 FFI (desktop/tests)
  sqfliteFfiInit();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Electric SQL Example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ShapeStream _stream;
  late final Shape _shape;
  late final DatabaseFactory _dbFactory;
  Database? _db;
  List<Map<String, dynamic>> _rows = [];
  String? _status;

  static const defaultShapeUrl = 'http://localhost:3000/v1/shape';

  @override
  void initState() {
    super.initState();
    _dbFactory = databaseFactoryFfi;
    _init();
  }

  Future<void> _init() async {
    try {
      _db = await _dbFactory.openDatabase(inMemoryDatabasePath);
      await _db!.execute('CREATE TABLE IF NOT EXISTS widgets (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, priority INT NOT NULL DEFAULT 10)');

      final url = const String.fromEnvironment('ELECTRIC_SHAPE_URL', defaultValue: defaultShapeUrl);
      _stream = ShapeStream(ShapeStreamOptions(
        url: url,
        params: {
          'table': 'widgets',
        },
        subscribe: true,
      ));
      _shape = Shape(_stream);

      _shape.subscribe(({required value, required rows}) async {
        // keep sqlite copy in sync (naive: clear & insert)
        await _db!.transaction((txn) async {
          await txn.delete('widgets');
          for (final row in rows) {
            await txn.insert('widgets', {
              'id': row['id'],
              'name': row['name'],
              'priority': row['priority'] ?? 10,
            });
          }
        });
        final result = await _db!.query('widgets', orderBy: 'id ASC');
        setState(() {
          _rows = result;
          _status = 'Connected: ${_stream.isConnected()} | UpToDate: ${_stream.isUpToDate} | Rows: ${_rows.length}';
        });
      });

      // Initial fetch to populate UI
      final initialRows = await _shape.rows;
      await _db!.transaction((txn) async {
        await txn.delete('widgets');
        for (final row in initialRows) {
          await txn.insert('widgets', {
            'id': row['id'],
            'name': row['name'],
            'priority': row['priority'] ?? 10,
          });
        }
      });
      final result = await _db!.query('widgets', orderBy: 'id ASC');
      setState(() {
        _rows = result;
        _status = 'Connected: ${_stream.isConnected()} | UpToDate: ${_stream.isUpToDate} | Rows: ${_rows.length}';
      });
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  @override
  void dispose() {
    _shape.unsubscribeAll();
    _db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Electric SQL + sqflite_common_ffi')),
      body: Column(
        children: [
          if (_status != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_status!, style: const TextStyle(fontSize: 12)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (context, index) {
                final row = _rows[index];
                return ListTile(
                  title: Text(row['name']?.toString() ?? ''),
                  subtitle: Text('id=${row['id']}, priority=${row['priority']}'),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    final id = await _db!.insert('widgets', {'name': 'local-${DateTime.now().millisecondsSinceEpoch}', 'priority': 10});
                    setState(() => _rows.add({'id': id, 'name': 'local', 'priority': 10}));
                  },
                  child: const Text('Insert local (sqlite)'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // Принудительно получить up-to-date от сервера
                    await _stream.forceDisconnectAndRefresh();
                  },
                  child: const Text('Refresh from server'),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}


