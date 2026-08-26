import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SocketService {
  static io.Socket? _socket;

  /// Notifier for Riverpod/UI to listen to live connection status changes
  static final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);

  static bool isAccountDeactivatedFlag = false;

  static io.Socket? get socket => _socket;
  static bool get isConnected => _socket?.connected ?? false;

  /// Tracks active session state and joined rooms across network reconnects
  static String? _activeUserId;
  static String? _activeCitizenId;
  static String? _activeRole;
  static bool _lastPresenceState = false;

  static final Set<String> _activeRooms = <String>{};
  static final Set<String> _activeChatRooms = <String>{};
  static final Set<String> _activeSosRooms = <String>{};

  /// 🎯 SINGLE SOURCE OF TRUTH ID NORMALIZER
  static String _formatSosDocKey(String rawId) {
    final String clean = rawId.trim();
    if (clean.isEmpty) return '';
    return clean.startsWith('sos_') ? clean : 'sos_$clean';
  }

  /// Resolves the single canonical document/room ID for an active citizen.
  static String getCanonicalSosId({String? providedCitizenId, String? providedUid}) {
    final currentUser = FirebaseAuth.instance.currentUser;

    final String rawCitizenId = (providedCitizenId ?? _activeCitizenId ?? '').trim();
    if (rawCitizenId.isNotEmpty) {
      return _formatSosDocKey(rawCitizenId);
    }

    final String rawUid = (providedUid ?? _activeUserId ?? currentUser?.uid ?? '').trim();
    return _formatSosDocKey(rawUid);
  }

  /// Cleanly parses and normalizes backend base URL to avoid invalid ports (e.g. :0) or /api paths
  static String _sanitizeOriginUrl(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      // Construct clean scheme + host (e.g., https://alertu-server-production.up.railway.app)
      // Standard ports (80/443) or omitted ports will be clean without :0
      if (uri.hasPort && uri.port != 0 && uri.port != 80 && uri.port != 443) {
        return '${uri.scheme}://${uri.host}:${uri.port}';
      }
      return '${uri.scheme}://${uri.host}';
    } catch (_) {
      // Direct string fallback if URI parsing fails
      String clean = rawUrl.trim();
      if (clean.endsWith('/')) clean = clean.substring(0, clean.length - 1);
      if (clean.endsWith('/api')) clean = clean.substring(0, clean.length - 4);
      return clean;
    }
  }

  /// Initializes and connects the Socket.IO client using the backend base URL.
  static Future<void> initSocket() async {
    if (_socket != null && _socket!.connected) {
      if (_activeUserId != null && _lastPresenceState) {
        emitPresence(
          uid: _activeUserId!,
          citizenId: _activeCitizenId,
          isActive: true,
          role: _activeRole,
        );
      }
      return;
    }

    try {
      if (ApiService.baseUrl == null) {
        await ApiService.initBackend();
      }

      final String rawBaseUrl = ApiService.baseUrl!;
      final String origin = _sanitizeOriginUrl(rawBaseUrl);

      debugPrint('⚡ Initializing Socket.IO connection to: $origin');

      if (_socket != null) {
        _socket!.dispose();
        _socket = null;
      }

      final Completer<void> connectionCompleter = Completer<void>();

      // Build production-friendly Socket Options using OptionBuilder
      final io.OptionBuilder optionBuilder = io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(25)
          .setReconnectionDelay(1000);

      _socket = io.io(origin, optionBuilder.build());

      _socket!.onConnect((_) {
        debugPrint('✅ Socket.IO Connected successfully! (ID: ${_socket!.id})');
        isConnectedNotifier.value = true;

        if (!connectionCompleter.isCompleted) {
          connectionCompleter.complete();
        }

        // 🟢 RESTORE PRESENCE & ROOM MEMBERSHIPS ON RECONNECT
        if (_activeUserId != null) {
          final String uid = _activeUserId!;
          registerUserRoom(uid, _activeCitizenId, _activeRole);

          if (_lastPresenceState) {
            final Map<String, dynamic> payload = {
              'uid': uid,
              'authUid': uid,
              'citizenID': _activeCitizenId ?? uid,
              'cid': _activeCitizenId ?? uid,
              'role': _activeRole ?? 'citizen',
              'isActive': true,
            };

            _socket!.emit('set_presence', payload);
            _socket!.emit('user_online', payload);
          }
        }

        // 🔄 RESTORE ROOM SUBSCRIPTIONS
        for (final room in _activeRooms) {
          _socket!.emit('join_room', room);
        }
        for (final chatId in _activeChatRooms) {
          _socket!.emit('join_chat', {'chatId': chatId});
        }
        for (final sosDocKey in _activeSosRooms) {
          _socket!.emit('sos:join_room', {'sosId': sosDocKey});
        }
      });

      _socket!.onDisconnect((reason) {
        debugPrint('⚠️ Socket.IO Disconnected: $reason');
        isConnectedNotifier.value = false;
      });

      _socket!.onConnectError((data) {
        debugPrint('❌ Socket.IO Connection Error: $data');
        isConnectedNotifier.value = false;
        if (!connectionCompleter.isCompleted) {
          connectionCompleter.completeError(data ?? "Socket connection error");
        }
      });

      _socket!.onError((data) {
        debugPrint('❌ Socket.IO General Error: $data');
      });

      _socket!.connect();

      await connectionCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⚠️ Socket connection attempt timed out after 10s.');
        },
      );
    } catch (e) {
      debugPrint('❌ CRITICAL SOCKET EXCEPTION: $e');
      isConnectedNotifier.value = false;
    }
  }

  /// Ensures socket connection is active before firing critical events
  static Future<void> ensureConnected() async {
    if (_socket == null || !_socket!.connected) {
      await initSocket();
    }
  }

  /// Registers user, role, and citizen ID mapping on backend socket instance
  static void registerUserRoom(String uid, [String? citizenId, String? role]) {
    _activeUserId = uid;
    _activeCitizenId = citizenId;
    _activeRole = role ?? 'citizen';

    final payload = {
      'uid': uid,
      'authUid': uid,
      'citizenID': citizenId ?? uid,
      'cid': citizenId ?? uid,
      'role': _activeRole,
    };

    emit('register_user', payload);
  }

  /// Generic Room Joining & Leaving
  static void joinRoom(String roomName) {
    if (roomName.isNotEmpty) {
      _activeRooms.add(roomName);
      emit('join_room', roomName);
    }
  }

  static void leaveRoom(String roomName) {
    if (roomName.isNotEmpty) {
      _activeRooms.remove(roomName);
      emit('leave_room', roomName);
    }
  }

  /// Emits live presence events (`user_online` / `user_offline` / `set_presence`) over Socket.IO
  static Future<void> emitPresence({
    required String uid,
    String? citizenId,
    required bool isActive,
    String? role,
  }) async {
    _activeUserId = uid;
    _activeCitizenId = citizenId;
    _activeRole = role ?? 'citizen';
    _lastPresenceState = isActive;

    final Map<String, dynamic> payload = {
      'uid': uid,
      'authUid': uid,
      'citizenID': citizenId ?? uid,
      'cid': citizenId ?? uid,
      'role': _activeRole,
      'isActive': isActive,
    };

    if (_socket == null || !_socket!.connected) {
      if (isActive) {
        debugPrint('🔌 Socket disconnected upon wake. Initiating connection...');
        await initSocket();
      } else {
        return;
      }
    }

    registerUserRoom(uid, citizenId, role);

    emit('set_presence', payload);
    emit(isActive ? 'user_online' : 'user_offline', payload);
  }

  // =========================================================================
  // 🚨 EMERGENCY SOS HANDLER ENGINE (UPSERT/SINGLE-DOCUMENT COMPATIBLE)
  // =========================================================================

  /// Triggers emergency SOS alert (Emits `sos:trigger_alert`)
  static Future<void> triggerSOSAlert(Map<String, dynamic> sosPayload) async {
    await ensureConnected();

    final currentUser = FirebaseAuth.instance.currentUser;

    final String rawCitizenId = (sosPayload['citizenID'] ??
        sosPayload['citizenId'] ??
        _activeCitizenId ??
        '')
        .toString();

    final String citizenUid = (sosPayload['citizenUid'] ??
        _activeUserId ??
        currentUser?.uid ??
        '')
        .toString();

    final String docKey = getCanonicalSosId(
      providedCitizenId: rawCitizenId,
      providedUid: citizenUid,
    );

    final String citizenName = sosPayload['citizenName'] ??
        sosPayload['submitterName'] ??
        currentUser?.displayName ??
        'Emergency Citizen';

    final String citizenEmail = sosPayload['citizenEmail'] ??
        sosPayload['submitterEmail'] ??
        currentUser?.email ??
        'N/A';

    final String citizenPhone = sosPayload['citizenPhone'] ??
        sosPayload['submitterPhone'] ??
        sosPayload['phone'] ??
        currentUser?.phoneNumber ??
        'N/A';

    final List<dynamic> emergencyContacts = sosPayload['emergencyContacts'] ??
        sosPayload['contacts'] ??
        [];

    final payload = {
      ...sosPayload,
      'sosId': docKey,
      'id': docKey,
      'targetRoom': docKey,
      'status': sosPayload['status'] ?? 'ACTIVE',
      'citizenUid': citizenUid,
      'citizenID': rawCitizenId.isNotEmpty ? rawCitizenId : (_activeCitizenId ?? citizenUid),
      'citizenName': citizenName,
      'submitterName': citizenName,
      'citizenEmail': citizenEmail,
      'submitterEmail': citizenEmail,
      'citizenPhone': citizenPhone,
      'submitterPhone': citizenPhone,
      'phone': citizenPhone,
      'emergencyContacts': emergencyContacts,
      'sosDetails': sosPayload['sosDetails'] ?? sosPayload['notes'] ?? 'Emergency SOS Alert Triggered',
      'triggeredAt': DateTime.now().toIso8601String(),
    };

    joinSOSRoom(docKey);

    emit('sos:trigger_alert', payload);
    debugPrint('🚨 [Socket] Single-Document SOS Alert Trigger Emitted for Key: $docKey');
  }

  /// Joins dedicated SOS incident room (Emits `sos:join_room`)
  static void joinSOSRoom(String sosId) {
    if (sosId.isNotEmpty) {
      final String docKey = _formatSosDocKey(sosId);
      _activeSosRooms.add(docKey);
      emit('sos:join_room', {'sosId': docKey});
    }
  }

  /// Leaves dedicated SOS incident room (Emits `sos:leave_room`)
  static void leaveSOSRoom(String sosId) {
    if (sosId.isNotEmpty) {
      final String docKey = _formatSosDocKey(sosId);
      _activeSosRooms.remove(docKey);
      emit('sos:leave_room', {'sosId': docKey});
    }
  }

  /// Sends real-time GIS location updates during an ongoing SOS
  static void updateSOSLocation({
    required String sosId,
    required Map<String, dynamic> gisLocation,
    String? citizenUid,
  }) {
    final String docKey = _formatSosDocKey(sosId);
    emit('sos:update_location', {
      'sosId': docKey,
      'citizenUid': citizenUid ?? _activeUserId ?? FirebaseAuth.instance.currentUser?.uid,
      'gisLocation': gisLocation,
    });
  }

  /// Listens for live location updates for an active SOS
  static void listenForSOSLocationUpdates(Function(dynamic data) onLocationUpdated) {
    if (_socket == null) return;
    _socket!.off('sos:location_updated');
    _socket!.on('sos:location_updated', (data) {
      debugPrint('📍 SOS Location Update Received: $data');
      onLocationUpdated(data);
    });
  }

  /// Listens for SOS status updates broadcasted by admins/responders
  static void listenForSOSStatusUpdates(Function(dynamic data) onStatusUpdated) {
    if (_socket == null) return;
    _socket!.off('sos:status_updated');
    _socket!.on('sos:status_updated', (data) {
      debugPrint('🚨 SOS Status Updated: $data');
      onStatusUpdated(data);
    });
  }

  // =========================================================================
  // 💬 CHAT ENGINE HANDLERS
  // =========================================================================

  static void joinChat(String chatId) {
    if (chatId.isNotEmpty) {
      _activeChatRooms.add(chatId);
      emit('join_chat', {'chatId': chatId});
    }
  }

  static void leaveChat(String chatId) {
    if (chatId.isNotEmpty) {
      _activeChatRooms.remove(chatId);
      emit('leave_chat', {'chatId': chatId});
    }
  }

  static void sendMessage(Map<String, dynamic> messagePayload) {
    emit('send_message', messagePayload);
  }

  static void sendTypingIndicator({
    required String chatId,
    required bool isTyping,
    required String senderRole,
    required String senderId,
  }) {
    emit('typing_indicator', {
      'chatId': chatId,
      'isTyping': isTyping,
      'senderRole': senderRole,
      'senderId': senderId,
    });
  }

  static void markChatAsRead({required String chatId, required String userRole}) {
    emit('mark_read', {
      'chatId': chatId,
      'userRole': userRole,
    });
  }

  // =========================================================================
  // 📞 AGORA CALL SIGNALING EVENTS
  // =========================================================================

  static void sendCallInvite({
    required String targetRoom,
    required String channelName,
    required bool isVideo,
    String? callerName,
    String? citizenId,
  }) {
    emit('call_invite', {
      'targetRoom': targetRoom,
      'channelName': channelName,
      'isVideo': isVideo,
      'callerName': callerName ?? 'Emergency Dispatch',
      'citizenId': citizenId,
      'callerId': _socket?.id,
      'senderSocketId': _socket?.id,
    });
  }

  static void acceptCall({
    required String channelName,
    String? targetRoom,
    String? targetSocketId,
  }) {
    emit('call_accept', {
      'channelName': channelName,
      'targetRoom': targetRoom ?? channelName,
      'targetSocketId': targetSocketId,
      'callerId': targetSocketId,
      'senderSocketId': _socket?.id,
    });
  }

  static void rejectCall({
    required String channelName,
    String? targetRoom,
    String? targetSocketId,
    String? reason,
  }) {
    emit('call_reject', {
      'channelName': channelName,
      'targetRoom': targetRoom ?? channelName,
      'targetSocketId': targetSocketId,
      'callerId': targetSocketId,
      'reason': reason ?? 'Call Rejected',
      'senderSocketId': _socket?.id,
    });
  }

  static void endCall({
    required String channelName,
    String? targetRoom,
  }) {
    emit('call_ended', {
      'channelName': channelName,
      'targetRoom': targetRoom ?? channelName,
      'senderSocketId': _socket?.id,
    });
  }

  static void listenForCallEvents({
    Function(dynamic data)? onIncomingCall,
    Function(dynamic data)? onCallAccepted,
    Function(dynamic data)? onCallRejected,
    Function(dynamic data)? onCallEnded,
  }) {
    if (_socket == null) return;

    clearCallListeners();

    if (onIncomingCall != null) {
      _socket!.on('call_invite', (data) {
        debugPrint('📞 Incoming Call Invite: $data');
        onIncomingCall(data);
      });
    }

    if (onCallAccepted != null) {
      _socket!.on('call_accept', (data) {
        debugPrint('✅ Call Accepted: $data');
        onCallAccepted(data);
      });
    }

    if (onCallRejected != null) {
      _socket!.on('call_reject', (data) {
        debugPrint('🚫 Call Rejected: $data');
        onCallRejected(data);
      });
    }

    if (onCallEnded != null) {
      _socket!.on('call_ended', (data) {
        debugPrint('⏹️ Call Ended Signal Received: $data');
        onCallEnded(data);
      });
    }
  }

  static void clearCallListeners() {
    _socket?.off('call_invite');
    _socket?.off('call_accept');
    _socket?.off('call_reject');
    _socket?.off('call_ended');
  }

  // =========================================================================
  // GENERAL UTILITIES
  // =========================================================================

  static void emit(String event, [dynamic data]) {
    if (_socket == null || !_socket!.connected) {
      debugPrint('⚠️ Cannot emit "$event": Socket is not connected.');
      return;
    }
    _socket!.emit(event, data);
  }

  static void on(String event, Function(dynamic data) handler) {
    _socket?.on(event, handler);
  }

  static void off(String event) {
    _socket?.off(event);
  }

  static void disconnect() {
    if (_socket != null) {
      clearCallListeners();
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _activeUserId = null;
      _activeCitizenId = null;
      _lastPresenceState = false;
      _activeRooms.clear();
      _activeChatRooms.clear();
      _activeSosRooms.clear();
      isConnectedNotifier.value = false;
      debugPrint('🔌 Socket.IO manually disconnected.');
    }
  }

  static void listenForAccountDeactivation(Function(dynamic data) onDeactivated) {
    if (_socket == null) return;
    _socket!.off('citizen_deactivated');
    _socket!.off('account_disabled');
    _socket!.off('account:disabled');

    void handleDeactivation(dynamic data) {
      isAccountDeactivatedFlag = true;
      onDeactivated(data);
    }

    _socket!.on('citizen_deactivated', handleDeactivation);
    _socket!.on('account_disabled', handleDeactivation);
    _socket!.on('account:disabled', handleDeactivation);
  }

  static void listenForProfileUpdates(Function(dynamic data) onProfileUpdated) {
    if (_socket == null) return;
    _socket!.off('citizen_updated');
    _socket!.off('profile_updated');

    void handleUpdate(dynamic data) {
      onProfileUpdated(data);
    }

    _socket!.on('citizen_updated', handleUpdate);
    _socket!.on('profile_updated', handleUpdate);
  }
}