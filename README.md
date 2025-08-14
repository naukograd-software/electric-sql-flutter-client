# Electric SQL Flutter Client

[![Pub Version](https://img.shields.io/pub/v/electric_sql_flutter_client)](https://pub.dev/packages/electric_sql_flutter_client)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Flutter/Dart client for [ElectricSQL](https://electric-sql.com). ElectricSQL is a Postgres sync engine that allows you to sync subsets of your Postgres data into local apps, services and environments.

## 🚀 Features

- **Real-time data synchronization** - automatic synchronization of data between Postgres and local applications
- **Shape-based synchronization** - sync only the data subsets you need
- **Offline-first approach** - work with data locally with subsequent synchronization
- **Reactive updates** - automatic UI updates when data changes
- **Flutter support** - native integration with Flutter applications
- **TypeScript compatibility** - based on the official TypeScript client

## 📦 Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  electric_sql_flutter_client: ^0.0.1
```

Then run:

```bash
flutter pub get
```

## 🏃‍♂️ Quick Start

### 1. Setup ElectricSQL Server

Make sure you have an ElectricSQL server running. Follow the [official guide](https://electric-sql.com/docs/intro) for setup.

### 2. Create Client

```dart
import 'package:electric_sql_flutter_client/electric_sql_flutter_client.dart';

// Create data stream
final stream = ShapeStream(ShapeStreamOptions(
  url: 'http://localhost:3000/v1/shape',
  params: {
    'table': 'widgets',
  },
  subscribe: true,
));

// Create shape for data operations
final shape = Shape(stream);
```

### 3. Subscribe to Changes

```dart
// Subscribe to data changes
shape.subscribe(({required value, required rows}) {
  // Handle updated data
  print('Received ${rows.length} records');
  
  // Update local database
  updateLocalDatabase(rows);
});
```

### 4. Get Data

```dart
// Get current data
final rows = await shape.rows;
print('Current data: $rows');

// Force refresh
await stream.forceDisconnectAndRefresh();
```

## 📖 Usage Examples

### Basic SQLite Synchronization

```dart
import 'package:electric_sql_flutter_client/electric_sql_flutter_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DataSyncService {
  late final ShapeStream _stream;
  late final Shape _shape;
  late final Database _db;

  Future<void> initialize() async {
    // Initialize SQLite
    _db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS widgets (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        name TEXT NOT NULL, 
        priority INT NOT NULL DEFAULT 10
      )
    ''');

    // Create ElectricSQL client
    _stream = ShapeStream(ShapeStreamOptions(
      url: 'http://localhost:3000/v1/shape',
      params: {'table': 'widgets'},
      subscribe: true,
    ));
    _shape = Shape(_stream);

    // Subscribe to changes
    _shape.subscribe(({required value, required rows}) async {
      await _syncToLocalDatabase(rows);
    });
  }

  Future<void> _syncToLocalDatabase(List<Map<String, dynamic>> rows) async {
    await _db.transaction((txn) async {
      await txn.delete('widgets');
      for (final row in rows) {
        await txn.insert('widgets', {
          'id': row['id'],
          'name': row['name'],
          'priority': row['priority'] ?? 10,
        });
      }
    });
  }
}
```

### Flutter Widget Integration

```dart
class SyncWidget extends StatefulWidget {
  @override
  _SyncWidgetState createState() => _SyncWidgetState();
}

class _SyncWidgetState extends State<SyncWidget> {
  List<Map<String, dynamic>> _data = [];
  String _status = 'Connecting...';

  @override
  void initState() {
    super.initState();
    _initializeSync();
  }

  Future<void> _initializeSync() async {
    final stream = ShapeStream(ShapeStreamOptions(
      url: 'http://localhost:3000/v1/shape',
      params: {'table': 'widgets'},
      subscribe: true,
    ));
    
    final shape = Shape(stream);
    
    shape.subscribe(({required value, required rows}) {
      setState(() {
        _data = rows;
        _status = 'Synchronized: ${rows.length} records';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(_status),
        Expanded(
          child: ListView.builder(
            itemCount: _data.length,
            itemBuilder: (context, index) {
              final item = _data[index];
              return ListTile(
                title: Text(item['name'] ?? ''),
                subtitle: Text('ID: ${item['id']}'),
              );
            },
          ),
        ),
      ],
    );
  }
}
```

## 🔧 Configuration

### ShapeStreamOptions

```dart
ShapeStreamOptions(
  url: 'http://localhost:3000/v1/shape', // ElectricSQL server URL
  params: {
    'table': 'widgets', // Table to synchronize
    'filter': 'priority > 5', // Optional filter
  },
  subscribe: true, // Auto-subscribe to changes
  backoffOptions: BackoffDefaults(), // Retry settings
)
```

### Error Handling

```dart
try {
  final rows = await shape.rows;
} on FetchError catch (e) {
  print('Network error: ${e.message}');
} catch (e) {
  print('Unknown error: $e');
}
```

## 🏗️ Architecture

This client is based on the official ElectricSQL TypeScript client and provides:

- **ShapeStream** - data stream for synchronization
- **Shape** - interface for data operations
- **Error handling** - built-in network error handling
- **Auto-retry** - configurable retry strategy
- **TypeScript compatibility** - full compatibility with official API

## 📚 Documentation

- [Official ElectricSQL Documentation](https://electric-sql.com/docs/intro)
- [Shapes Guide](https://electric-sql.com/docs/guides/shapes)
- [Authentication Guide](https://electric-sql.com/docs/guides/auth)
- [Writes Guide](https://electric-sql.com/docs/guides/writes)

## 🤝 Community

- [Discord Community](https://discord.gg/electric-sql)
- [GitHub Repository](https://github.com/electric-sql)
- [Example Applications](https://electric-sql.com/docs/intro#examples)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🚧 Development Status

This client is under active development. API may change until stable release.

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md) for change history.
