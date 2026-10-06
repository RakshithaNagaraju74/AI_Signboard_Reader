import 'dart:async';

/// Serializes spoken announcements so live scanning, voice commands and
/// safety messages never compete for the Android TTS channel.
class AnnouncementQueueService {
  final Future<void> Function(String text, {bool interrupt}) _speak;
  final List<_QueuedAnnouncement> _queue = [];
  bool _running = false;
  bool _stopped = false;

  AnnouncementQueueService(this._speak);

  Future<void> enqueue(
    String text, {
    bool interrupt = false,
    bool priority = false,
  }) async {
    final value = text.trim();
    if (value.isEmpty) return;

    final completer = Completer<void>();
    final item = _QueuedAnnouncement(
      text: value,
      interrupt: interrupt,
      completer: completer,
    );

    if (priority) {
      _queue.insert(0, item);
    } else {
      _queue.add(item);
    }

    unawaited(_drain());
    return completer.future;
  }

  Future<void> _drain() async {
    if (_running || _stopped) return;
    _running = true;

    try {
      while (!_stopped && _queue.isNotEmpty) {
        final item = _queue.removeAt(0);
        try {
          await _speak(
            item.text,
            interrupt: item.interrupt,
          );
          if (!item.completer.isCompleted) {
            item.completer.complete();
          }
        } catch (error, stack) {
          if (!item.completer.isCompleted) {
            item.completer.completeError(error, stack);
          }
        }
      }
    } finally {
      _running = false;
    }
  }

  void clear() {
    for (final item in _queue) {
      if (!item.completer.isCompleted) {
        item.completer.complete();
      }
    }
    _queue.clear();
  }

  Future<void> stopAndClear() async {
    _stopped = true;
    clear();
    await Future<void>.delayed(Duration.zero);
    _stopped = false;
  }

  bool get isSpeakingOrQueued => _running || _queue.isNotEmpty;
}

class _QueuedAnnouncement {
  final String text;
  final bool interrupt;
  final Completer<void> completer;

  _QueuedAnnouncement({
    required this.text,
    required this.interrupt,
    required this.completer,
  });
}
