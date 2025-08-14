import 'dart:async';
import 'dart:convert';

import 'constants.dart';
import 'error.dart';

class BackoffOptions {
  final int initialDelay;
  final int maxDelay;
  final double multiplier;
  final void Function()? onFailedAttempt;
  final bool debug;

  const BackoffOptions({
    this.initialDelay = 100,
    this.maxDelay = 10000,
    this.multiplier = 1.3,
    this.onFailedAttempt,
    this.debug = false,
  });
}

typedef FetchClient = Future<FetchResponse> Function(String url, {Map<String, String>? headers, Object? body, String method, FutureOr<bool> Function()? isAborted});

class FetchResponse {
  final int status;
  final Map<String, String> headers;
  final String body;
  const FetchResponse({required this.status, required this.headers, required this.body});

  bool get ok => status >= 200 && status < 300;
}

Future<FetchResponse> createFetchWithBackoff(
  Future<FetchResponse> Function(String url, {Map<String, String>? headers, Object? body, String method, FutureOr<bool> Function()? isAborted}) fetchClient,
  BackoffOptions backoffOptions,
) async {
  throw UnimplementedError('Use createFetchWithBackoffClient to obtain a wrapped client');
}

FetchClient createFetchWithBackoffClient(FetchClient fetchClient, BackoffOptions backoffOptions) {
  return (String url, {Map<String, String>? headers, Object? body, String method = 'GET', FutureOr<bool> Function()? isAborted}) async {
    int delay = backoffOptions.initialDelay;
    int attempt = 0;
    while (true) {
      try {
        final res = await fetchClient(url, headers: headers, body: body, method: method, isAborted: isAborted);
        if (res.ok) return res;
        final err = await _fetchErrorFromResponse(res, url);
        throw err;
      } catch (e) {
        backoffOptions.onFailedAttempt?.call();
        if (await _aborted(isAborted)) {
          throw FetchBackoffAbortError();
        } else if (e is FetchError && e.status >= 400 && e.status < 500 && e.status != 429) {
          throw e;
        } else {
          await Future<void>.delayed(Duration(milliseconds: delay));
          delay = (delay * backoffOptions.multiplier).toInt();
          if (delay > backoffOptions.maxDelay) delay = backoffOptions.maxDelay;
          if (backoffOptions.debug) {
            attempt += 1;
            // ignore: avoid_print
            print('Retry attempt #$attempt after ${delay}ms');
          }
        }
      }
    }
  };
}

Future<bool> _aborted(FutureOr<bool> Function()? isAborted) async {
  if (isAborted == null) return false;
  final v = isAborted();
  return v is Future<bool> ? await v : v;
}

Future<FetchError> _fetchErrorFromResponse(FetchResponse res, String url) async {
  final headers = res.headers;
  String? text;
  Object? json;
  final contentType = headers['content-type'];
  if (contentType != null && contentType.contains('application/json')) {
    try {
      json = jsonDecode(res.body);
    } catch (_) {
      text = res.body;
    }
  } else {
    text = res.body;
  }
  return FetchError(res.status, text, json, headers, url);
}

// Minimal response-headers check wrapper
FetchClient createFetchWithResponseHeadersCheck(FetchClient fetchClient) {
  return (String url, {Map<String, String>? headers, Object? body, String method = 'GET', FutureOr<bool> Function()? isAborted}) async {
    final res = await fetchClient(url, headers: headers, body: body, method: method, isAborted: isAborted);
    if (res.ok) {
      final missing = <String>[];
      void addMissing(List<String> req) => missing.addAll(req.where((h) => !res.headers.containsKey(h)));
      addMissing(['electric-offset', 'electric-handle']);
      final u = Uri.parse(url);
      if (u.queryParameters[liveQueryParam] == 'true') {
        addMissing(['electric-cursor']);
      }
      if (!u.queryParameters.containsKey(liveQueryParam) || u.queryParameters[liveQueryParam] == 'false') {
        addMissing(['electric-schema']);
      }
      if (missing.isNotEmpty) {
        throw MissingHeadersError(url, missing);
      }
    }
    return res;
  };
}


