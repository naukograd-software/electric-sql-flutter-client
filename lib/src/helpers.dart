import 'types.dart';

bool isChangeMessage(Message message) => message.containsKey('key');

bool isControlMessage(Message message) => !isChangeMessage(message);

bool isUpToDateMessage(Message message) {
  if (isControlMessage(message)) {
    final headers = message['headers'] as Map<String, dynamic>?;
    final control = headers?['control'];
    return control == 'up-to-date';
  }
  return false;
}

Offset? getOffset(Message message) {
  final headers = message['headers'] as Map<String, dynamic>?;
  final lsn = headers?['global_last_seen_lsn'];
  if (lsn is String && lsn.isNotEmpty) {
    return '${lsn}_0';
  }
  return null;
}


