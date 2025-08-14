import 'dart:async';

import 'abort.dart';
import 'constants.dart';
import 'error.dart';
import 'fetch.dart';
import 'helpers.dart';
import 'parser.dart';
import 'types.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

typedef HeaderValue = FutureOr<String> Function();
typedef ExternalHeadersRecord = Map<String, dynamic>; // String or HeaderValue
typedef ParamValue = Object? Function(); // function producing serializable value
typedef ExternalParamsRecord = Map<String, Object?>; // values must be serializable as query params

typedef ShapeStreamErrorHandler = FutureOr<Map<String, dynamic>?> Function(Object error);

class ShapeStreamOptions {
  final String url;
  final Offset? offset;
  final String? handle;
  ExternalHeadersRecord? headers;
  ExternalParamsRecord? params;
  final bool subscribe;
  final bool experimentalLiveSse;
  final AbortSignal? signal;
  final BackoffOptions? backoffOptions;
  final MessageParser? parser;
  final ShapeStreamErrorHandler? onError;
  final FetchClient? fetchClient;

  ShapeStreamOptions({
    required this.url,
    this.offset,
    this.handle,
    this.headers,
    this.params,
    this.subscribe = true,
    this.experimentalLiveSse = false,
    this.signal,
    this.backoffOptions,
    this.parser,
    this.onError,
    this.fetchClient,
  });
}

class ShapeStream implements ShapeStreamInterface {
  final ShapeStreamOptions options;
  Object? _error;
  final FetchClient _fetchClient;
  final FetchClient _sseFetchClient; // kept for structure parity
  final MessageParser _messageParser;

  final Map<num, List<Function>> _subscribers = {};
  bool _started = false;
  String _state = 'active'; // 'active' | 'pause-requested' | 'paused'
  Offset _lastOffset;
  String _liveCacheBuster = '';
  int? _lastSyncedAt;
  bool _isUpToDate = false;
  bool _connected = false;
  String? _shapeHandle;
  Schema? _schema;
  ShapeStreamErrorHandler? _onError;
  AbortController? _requestAbortController;
  bool _isRefreshing = false;
  Completer<void>? _tickCompleter;
  Future<void> _messageChain = Future.value();

  ShapeStream(this.options)
      : _lastOffset = options.offset ?? '-1',
        _shapeHandle = options.handle,
        _messageParser = options.parser ?? MessageParser(),
        _onError = options.onError,
        _sseFetchClient = createFetchWithResponseHeadersCheck(
          createFetchWithBackoffClient(
            options.fetchClient ?? _baseFetchClient,
            options.backoffOptions ?? const BackoffOptions(),
          ),
        ),
        _fetchClient = createFetchWithResponseHeadersCheck(
          createFetchWithBackoffClient(
            options.fetchClient ?? _baseFetchClient,
            options.backoffOptions ?? const BackoffOptions(),
          ),
        ) {
    _validateOptions(options);
  }

  static Future<FetchResponse> _baseFetchClient(String url, {Map<String, String>? headers, Object? body, String method = 'GET', FutureOr<bool> Function()? isAborted}) async {
    final uri = Uri.parse(url);
    http.Response resp;
    if (method.toUpperCase() == 'GET') {
      resp = await http.get(uri, headers: headers);
    } else if (method.toUpperCase() == 'POST') {
      resp = await http.post(uri, headers: headers, body: body);
    } else if (method.toUpperCase() == 'PUT') {
      resp = await http.put(uri, headers: headers, body: body);
    } else if (method.toUpperCase() == 'DELETE') {
      resp = await http.delete(uri, headers: headers, body: body);
    } else {
      resp = await http.Request(method, uri)
          .send()
          .then(http.Response.fromStream);
    }
    final headerMap = <String, String>{};
    resp.headers.forEach((k, v) => headerMap[k.toLowerCase()] = v);
    return FetchResponse(status: resp.statusCode, headers: headerMap, body: resp.body);
  }

  String? get shapeHandle => _shapeHandle;
  Object? get error => _error;
  bool get isUpToDate => _isUpToDate;
  Offset get lastOffset => _lastOffset;

  @override
  void Function() subscribe(Function(List<Message>) callback, [void Function(Object error)? onError]) {
    final id = DateTime.now().microsecondsSinceEpoch + _subscribers.length;
    _subscribers[id] = [callback, onError ?? (Object _) {}];
    if (!_started) {
      _start();
    }
    return () {
      _subscribers.remove(id);
    };
  }

  @override
  void unsubscribeAll() {
    _subscribers.clear();
  }

  @override
  bool isLoading() => !_isUpToDate;

  @override
  int? lastSyncedAt() => _lastSyncedAt;

  @override
  int lastSynced() => _lastSyncedAt == null ? 1 << 31 : DateTime.now().millisecondsSinceEpoch - _lastSyncedAt!;

  @override
  bool isConnected() => _connected;

  @override
  bool hasStarted() => _started;

  Future<void> _start() async {
    _started = true;
    try {
      await _requestShape();
    } catch (err) {
      _error = err;
      if (_onError != null) {
        final retryOpts = await _onError!(err);
        if (retryOpts is Map<String, dynamic>) {
          _reset();
          if (retryOpts.containsKey('params')) {
            options.params = Map<String, Object?>.from(retryOpts['params'] as Map);
          }
          if (retryOpts.containsKey('headers')) {
            options.headers = Map<String, dynamic>.from(retryOpts['headers'] as Map);
          }
          _started = false;
          _start();
        }
        return;
      }
      rethrow;
    } finally {
      _connected = false;
      _tickCompleter?.completeError(StateError('stopped'));
      _tickCompleter = null;
    }
  }

  Future<void> _requestShape() async {
    if (_state == 'pause-requested') {
      _state = 'paused';
      return;
    }
    if (!options.subscribe && ((options.signal?.aborted ?? false) || _isUpToDate)) {
      return;
    }

    final resumingFromPause = _state == 'paused';
    _state = 'active';

    final constructed = await _constructUrl(options.url, resumingFromPause);
    final aborter = _createAbortListener(options.signal);
    final requestAbortController = _requestAbortController!;
    try {
      await _fetchShape(
        fetchUrl: constructed.fetchUrl,
        requestAbortController: requestAbortController,
        headers: constructed.requestHeaders,
        resumingFromPause: resumingFromPause,
      );
    } catch (e) {
      if (requestAbortController.signal.aborted && requestAbortController.signal.reason == forceDisconnectAndRefresh) {
        return _requestShape();
      }
      if (e is FetchBackoffAbortError) {
        if (requestAbortController.signal.aborted && requestAbortController.signal.reason == pauseStream) {
          _state = 'paused';
        }
        return;
      }
      if (e is! FetchError) rethrow;
      if (e.status == 409) {
        final newShapeHandle = e.headers[shapeHandleHeader];
        _reset(newShapeHandle);
        // In TS they publish the JSON body as messages here; we skip for now
        return _requestShape();
      } else {
        _sendErrorToSubscribers(e);
        throw e;
      }
    } finally {
      if (aborter != null && options.signal != null) {
        // no event listeners to remove in this minimal impl
      }
      _requestAbortController = null;
    }

    _tickCompleter?.complete();
    _tickCompleter = null;
    return _requestShape();
  }

  Future<_ConstructedUrl> _constructUrl(String url, bool resumingFromPause) async {
    final requestHeaders = await _resolveHeaders(options.headers);
    final params = _convertWhereParamsToObj(options.params);

    final uri = Uri.parse(url);
    final qp = Map<String, String>.from(uri.queryParameters);

    qp[offsetQueryParam] = _lastOffset;
    if (_isUpToDate) {
      if (!_isRefreshing && !resumingFromPause) {
        qp[liveQueryParam] = 'true';
      }
      qp[liveCacheBusterQueryParam] = _liveCacheBuster;
    }
    if (_shapeHandle != null) {
      qp[shapeHandleQueryParam] = _shapeHandle!;
    }

    if (params != null) {
      _validateParams(params);
      for (final entry in params.entries) {
        final key = entry.key;
        final value = entry.value;
        if (value == null) continue;
        if (value is String) {
          qp[key] = value;
        } else if (value is Map) {
          value.forEach((k, v) {
            qp['$key[$k]'] = '$v';
          });
        } else if (value is List) {
          qp[key] = value.join(',');
        } else {
          qp[key] = value.toString();
        }
      }
    }

    final fetchUrl = uri.replace(queryParameters: Map.fromEntries(qp.entries.toList()..sort((a, b) => a.key.compareTo(b.key))));
    return _ConstructedUrl(fetchUrl: fetchUrl, requestHeaders: requestHeaders);
  }

  void _validateOptions(ShapeStreamOptions opts) {
    if (opts.url.isEmpty) {
      throw MissingShapeUrlError();
    }
    if (opts.offset != null && opts.offset != '-1' && (opts.handle == null || opts.handle!.isEmpty)) {
      throw MissingShapeHandleError();
    }
    if (opts.params != null) {
      _validateParams(opts.params!);
    }
  }

  void _validateParams(Map<String, Object?> params) {
    const reserved = {
      liveCacheBusterQueryParam,
      shapeHandleQueryParam,
      liveQueryParam,
      offsetQueryParam,
    };
    final used = params.keys.where((k) => reserved.contains(k)).toList();
    if (used.isNotEmpty) {
      throw ReservedParamError(used);
    }
  }

  Map<String, Object?>? _convertWhereParamsToObj(Map<String, Object?>? allPgParams) {
    if (allPgParams == null) return null;
    final dynamic positional = allPgParams['params'];
    if (positional is List) {
      final asMap = <String, String>{
        for (int i = 0; i < positional.length; i++) '${i + 1}': '${positional[i]}'
      };
      return {
        ...allPgParams,
        'params': asMap,
      };
    }
    return allPgParams;
  }

  AbortController? _createAbortListener(AbortSignal? signal) {
    _requestAbortController = AbortController();
    if (signal != null) {
      if (signal.aborted) {
        _requestAbortController!.abort(signal.reason);
      }
    }
    return _requestAbortController;
  }

  Future<void> _onInitialResponse(FetchResponse response, Uri url) async {
    final headers = response.headers;
    final shapeHandle = headers[shapeHandleHeader];
    if (shapeHandle != null) _shapeHandle = shapeHandle;

    final lastOffset = headers[chunkLastOffsetHeader];
    if (lastOffset != null) _lastOffset = lastOffset;

    final liveCacheBuster = headers[liveCacheBusterHeader];
    if (liveCacheBuster != null) _liveCacheBuster = liveCacheBuster;

    // schema header is JSON
    final schemaHeader = headers[shapeSchemaHeader];
    if (_schema == null && schemaHeader != null && schemaHeader.isNotEmpty) {
      final raw = jsonDecode(schemaHeader) as Map;
      _schema = raw.map((k, v) => MapEntry(k as String, (v as Map).cast<String, dynamic>()));
    }

    if (response.status == 204) {
      _lastSyncedAt = DateTime.now().millisecondsSinceEpoch;
    }
  }

  Future<void> _onMessages(List<Message> batch) async {
    if (batch.isNotEmpty) {
      final Message lastMessage = batch.last;
      if (isUpToDateMessage(lastMessage)) {
        final off = getOffset(lastMessage);
        if (off != null) _lastOffset = off;
        _lastSyncedAt = DateTime.now().millisecondsSinceEpoch;
        _isUpToDate = true;
      }
      await _publish(batch);
    }
  }

  Future<void> _fetchShape({required Uri fetchUrl, required AbortController requestAbortController, required Map<String, String> headers, bool resumingFromPause = false}) async {
    // Use SSE when applicable
    if (_isUpToDate && options.experimentalLiveSse && !_isRefreshing && !resumingFromPause) {
      final sseUrl = fetchUrl.replace(queryParameters: {
        ...fetchUrl.queryParameters,
        experimentalLiveSseQueryParam: 'true',
      });
      return _requestShapeSSE(
        fetchUrl: sseUrl,
        requestAbortController: requestAbortController,
        headers: headers,
      );
    }

    final res = await _fetchClient(fetchUrl.toString(), headers: headers, method: 'GET', isAborted: () async => requestAbortController.signal.aborted);
    _connected = true;
    await _onInitialResponse(res, fetchUrl);
    final schema = _schema!;
    final body = res.body.isNotEmpty ? res.body : '[]';
    final parsed = _messageParser.parseMessages(body, schema);
    final messages = parsed.cast<Message>();
    await _onMessages(messages);
  }

  Future<void> _requestShapeSSE({required Uri fetchUrl, required AbortController requestAbortController, required Map<String, String> headers}) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', fetchUrl);
      req.headers.addAll(headers);
      req.headers['accept'] = 'text/event-stream';
      final streamed = await client.send(req);

      // Check required headers presence (like createFetchWithResponseHeadersCheck)
      final responseHeaders = <String, String>{};
      streamed.headers.forEach((k, v) => responseHeaders[k.toLowerCase()] = v);

      // Validate headers
      final missing = <String>[];
      void addMissing(List<String> req) => missing.addAll(req.where((h) => !responseHeaders.containsKey(h)));
      addMissing(const ['electric-offset', 'electric-handle']);
      // SSE implies live=true
      addMissing(const ['electric-cursor']);
      if (missing.isNotEmpty) {
        throw MissingHeadersError(fetchUrl.toString(), missing);
      }

      // onopen
      await _onInitialResponse(
        FetchResponse(status: streamed.statusCode, headers: responseHeaders, body: ''),
        fetchUrl,
      );
      _connected = true;

      // Parse SSE stream
      final subscription = streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(null);

      final List<String> dataLines = [];
      final completer = Completer<void>();
      subscription.onData((line) {
        if (requestAbortController.signal.aborted) {
          subscription.cancel();
          return;
        }
        if (line.startsWith('data:')) {
          dataLines.add(line.substring(5).trimLeft());
        } else if (line.isEmpty) {
          // Dispatch event
          if (dataLines.isNotEmpty) {
            final data = dataLines.join('\n');
            dataLines.clear();
            if (data.isNotEmpty) {
              final schema = _schema!;
              final message = _messageParser.parseMessage(data, schema);
              _handleSseMessage(message.cast<String, dynamic>());
            }
          }
        }
      });
      subscription.onError((error, __) {
        completer.completeError(error);
      });
      subscription.onDone(() {
        completer.complete();
      });

      await completer.future;

      if (requestAbortController.signal.aborted) {
        throw FetchBackoffAbortError();
      }
    } finally {
      client.close();
    }
  }

  void _handleSseMessage(Message message) {
    // Buffer messages until up-to-date, then publish
    _sseBuffer ??= <Message>[];
    _sseBuffer!.add(message);
    if (isUpToDateMessage(message)) {
      final buffer = _sseBuffer!;
      _sseBuffer = null;
      _onMessages(buffer);
    }
  }

  List<Message>? _sseBuffer;

  void _pause() {
    if (_started && _state == 'active') {
      _state = 'pause-requested';
      _requestAbortController?.abort(pauseStream);
    }
  }

  void _resume() {
    if (_started && _state == 'paused') {
      _start();
    }
  }

  Future<void> forceDisconnectAndRefresh() async {
    _isRefreshing = true;
    if (_isUpToDate && !(_requestAbortController?.signal.aborted ?? true)) {
      _requestAbortController?.abort(forceDisconnectAndRefresh);
    }
    await _nextTick();
    _isRefreshing = false;
  }

  Future<void> _publish(List<Message> messages) async {
    _messageChain = _messageChain.then((_) async {
      for (final sub in _subscribers.values) {
        final callback = sub[0] as Function(List<Message>);
        try {
          await Future.sync(() => callback(messages));
        } catch (err) {
          scheduleMicrotask(() => throw err!);
        }
      }
    });
    await _messageChain;
  }

  void _sendErrorToSubscribers(Object error) {
    for (final sub in _subscribers.values) {
      final errorFn = sub.length > 1 ? sub[1] as Function(Object) : null;
      errorFn?.call(error);
    }
  }

  void _reset([String? handle]) {
    _lastOffset = '-1';
    _liveCacheBuster = '';
    _shapeHandle = handle;
    _isUpToDate = false;
    _connected = false;
    _schema = null;
  }

  Future<void> _nextTick() async {
    _tickCompleter ??= Completer<void>();
    return _tickCompleter!.future.whenComplete(() => _tickCompleter = null);
  }

  Future<Map<String, String>> _resolveHeaders(ExternalHeadersRecord? headers) async {
    if (headers == null) return {};
    final List<MapEntry<String, String>> entries = [];
    for (final e in headers.entries) {
      final v = e.value;
      if (v is String) {
        entries.add(MapEntry(e.key, v));
      } else if (v is HeaderValue) {
        final resolved = await Future.sync(v);
        entries.add(MapEntry(e.key, resolved));
      }
    }
    return Map<String, String>.fromEntries(entries);
  }
}

abstract class ShapeStreamInterface {
  void Function() subscribe(Function(List<Message>) callback, [Function(Object error)? onError]);
  void unsubscribeAll();
  bool isLoading();
  int? lastSyncedAt();
  int lastSynced();
  bool isConnected();
  bool hasStarted();
  bool get isUpToDate;
  Offset get lastOffset;
  String? get shapeHandle;
  Object? get error;
  Future<void> forceDisconnectAndRefresh();
}

class _ConstructedUrl {
  final Uri fetchUrl;
  final Map<String, String> requestHeaders;
  _ConstructedUrl({required this.fetchUrl, required this.requestHeaders});
}


