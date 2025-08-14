class FetchError implements Exception {
  final int status;
  final String? text;
  final Map<String, String> headers;
  final String url;
  final Object? json;
  final String message;

  FetchError(
    this.status,
    this.text,
    this.json,
    this.headers,
    this.url, {
    String? message,
  }) : message = message ?? 'HTTP Error $status at $url: ${text ?? json}';

  @override
  String toString() => 'FetchError($status): $message';
}

class FetchBackoffAbortError implements Exception {
  final String message = 'Fetch with backoff aborted';
  @override
  String toString() => 'FetchBackoffAbortError: $message';
}

class InvalidShapeOptionsError implements Exception {
  final String message;
  InvalidShapeOptionsError(this.message);
  @override
  String toString() => 'InvalidShapeOptionsError: $message';
}

class MissingShapeUrlError implements Exception {
  final String message = 'Invalid shape options: missing required url parameter';
  @override
  String toString() => 'MissingShapeUrlError: $message';
}

class InvalidSignalError implements Exception {
  final String message = 'Invalid signal option. It must be an instance of AbortSignal.';
  @override
  String toString() => 'InvalidSignalError: $message';
}

class MissingShapeHandleError implements Exception {
  final String message = "shapeHandle is required if this isn't an initial fetch (i.e. offset > -1)";
  @override
  String toString() => 'MissingShapeHandleError: $message';
}

class ReservedParamError implements Exception {
  final List<String> reservedParams;
  ReservedParamError(this.reservedParams);
  @override
  String toString() =>
      'ReservedParamError: Cannot use reserved Electric parameter names in custom params: ${reservedParams.join(', ')}';
}

class ParserNullValueError implements Exception {
  final String columnName;
  ParserNullValueError(this.columnName);
  @override
  String toString() => 'ParserNullValueError: Column "$columnName" does not allow NULL values';
}

class ShapeStreamAlreadyRunningError implements Exception {
  final String message = 'ShapeStream is already running';
  @override
  String toString() => 'ShapeStreamAlreadyRunningError: $message';
}

class MissingHeadersError implements Exception {
  final String url;
  final List<String> missingHeaders;
  MissingHeadersError(this.url, this.missingHeaders);

  @override
  String toString() {
    final headerList = missingHeaders.map((h) => '- $h').join('\n');
    final extra = "\nThis is often due to a proxy not setting CORS correctly so that all Electric headers can be read by the client."
        "\nFor more information visit the troubleshooting guide: /docs/guides/troubleshooting/missing-headers";
    return "The response for the shape request to $url didn't include the following required headers:\n$headerList$extra";
  }
}


