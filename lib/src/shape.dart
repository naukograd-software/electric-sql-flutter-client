import 'dart:async';
import 'helpers.dart';
import 'types.dart';
import 'client.dart';
import 'error.dart';

typedef ShapeData = Map<String, Row>;
typedef ShapeChangedCallback = void Function({required ShapeData value, required List<Row> rows});

class Shape {
  final ShapeStreamInterface stream;

  final ShapeData _data = <String, Row>{};
  final Map<num, ShapeChangedCallback> _subscribers = {};
  String _status = 'syncing';
  FetchError? _error;

  Shape(this.stream) {
    stream.subscribe(_process, _handleError);
  }

  bool get isUpToDate => _status == 'up-to-date';
  Offset get lastOffset => stream.lastOffset;
  String? get handle => stream.shapeHandle;

  Future<List<Row>> get rows async => (await value).values.toList();
  List<Row> get currentRows => _data.values.toList();

  Future<ShapeData> get value async {
    if (stream.isUpToDate) return _data;
    final completer = Completer<ShapeData>();
    late void Function() unsubscribe;
    unsubscribe = subscribe(({required value, required rows}) {
      unsubscribe();
      if (_error != null) {
        completer.completeError(_error!);
      } else {
        completer.complete(value);
      }
    });
    return completer.future;
  }

  ShapeData get currentValue => _data;
  FetchError? get error => _error;

  int? lastSyncedAt() => stream.lastSyncedAt();
  int lastSynced() => stream.lastSynced();
  bool isLoading() => stream.isLoading();
  bool isConnected() => stream.isConnected();

  void Function() subscribe(ShapeChangedCallback callback) {
    final id = DateTime.now().microsecondsSinceEpoch + _subscribers.length;
    _subscribers[id] = callback;
    return () => _subscribers.remove(id);
  }

  void unsubscribeAll() => _subscribers.clear();
  int get numSubscribers => _subscribers.length;

  void _process(List<Message> messages) {
    bool shouldNotify = false;
    for (final message in messages) {
      if (isChangeMessage(message)) {
        shouldNotify = _updateShapeStatus('syncing');
        final ch = message;
        final headers = ch['headers'] as Map<String, dynamic>;
        final op = headers['operation'];
        final key = ch['key'] as String;
        final value = (ch['value'] as Map).cast<String, dynamic>();
        if (op == 'insert') {
          _data[key] = value;
        } else if (op == 'update') {
          _data[key] = {...?_data[key], ...value};
        } else if (op == 'delete') {
          _data.remove(key);
        }
      }
      if (isControlMessage(message)) {
        final control = (message['headers'] as Map<String, dynamic>)['control'];
        if (control == 'up-to-date') {
          shouldNotify = _updateShapeStatus('up-to-date');
        } else if (control == 'must-refetch') {
          _data.clear();
          _error = null;
          shouldNotify = _updateShapeStatus('syncing');
        }
      }
    }
    if (shouldNotify) _notify();
  }

  bool _updateShapeStatus(String status) {
    final changed = _status != status;
    _status = status;
    return changed && status == 'up-to-date';
  }

  void _handleError(Object e) {
    if (e is FetchError) {
      _error = e;
      _notify();
    }
  }

  void _notify() {
    // Iterate over a snapshot to avoid concurrent modification during callbacks
    final callbacks = List<ShapeChangedCallback>.from(_subscribers.values);
    for (final cb in callbacks) {
      cb(value: currentValue, rows: currentRows);
    }
  }
}


