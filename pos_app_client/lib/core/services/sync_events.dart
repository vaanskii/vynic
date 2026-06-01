import 'dart:async';

enum SyncEventType { menu, orders, reservations, tables, connection }

class SyncEvent {
  SyncEvent({required this.type, this.action, this.payload});

  final SyncEventType type;
  final String? action;
  final Map<String, dynamic>? payload;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type.name,
    if (action != null) 'action': action,
    if (payload != null) 'payload': payload,
  };
}

class SyncHub {
  SyncHub._();

  static void Function(SyncEvent event)? onLocalChange;
  static final StreamController<SyncEvent> _eventBus =
      StreamController<SyncEvent>.broadcast();

  static Stream<SyncEvent> get events => _eventBus.stream;

  static void notify(SyncEvent event) {
    try {
      onLocalChange?.call(event);
      _eventBus.add(event);
    } catch (_) {
      // swallow errors to avoid breaking the caller.
    }
  }
}
