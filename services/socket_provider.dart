import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/socket.dart';

/// Provider to watch real-time socket connection state (true/false)
final socketConnectionProvider = NotifierProvider<SocketConnectionNotifier, bool>(() {
  return SocketConnectionNotifier();
});

class SocketConnectionNotifier extends Notifier<bool> {
  @override
  bool build() {
    // 1. Initial value from SocketService
    final initialConnected = SocketService.isConnected;

    // 2. Setup listener callback
    void listener() {
      state = SocketService.isConnectedNotifier.value;
    }

    // 3. Attach listener
    SocketService.isConnectedNotifier.addListener(listener);

    // 4. Auto-clean listener when provider is disposed
    ref.onDispose(() {
      SocketService.isConnectedNotifier.removeListener(listener);
    });

    return initialConnected;
  }
}