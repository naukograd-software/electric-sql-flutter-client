class AbortSignal {
  bool aborted;
  Object? reason;
  AbortSignal({this.aborted = false, this.reason});
}

class AbortController {
  final AbortSignal signal = AbortSignal();
  void abort([Object? reason]) {
    signal.aborted = true;
    signal.reason = reason;
  }
}


