import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'api_service.dart';
import 'socket.dart';

class ChatService {
  /// Fetches the current user's Firebase ID Token for endpoint authorization
  static Future<String?> _getIdToken([bool forceRefresh = false]) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      return await user?.getIdToken(forceRefresh);
    } catch (e) {
      debugPrint('⚠️ ChatService: Failed to fetch ID Token: $e');
      return null;
    }
  }

  /// Ensures backend URL is discovered before executing HTTP calls
  static Future<String> _getResolvedBaseUrl() async {
    if (ApiService.baseUrl == null) {
      await ApiService.initBackend();
    }
    return ApiService.baseUrl!;
  }

  // ==========================================
  // 💬 SOCKET.IO REAL-TIME CHAT ACTIONS
  // ==========================================

  /// Joins a specific chat room to listen for real-time messages
  static void joinChatRoom(String chatId) {
    if (chatId.isEmpty) return;
    SocketService.emit('join_chat', {'chatId': chatId});
    debugPrint('💬 Joined chat room: $chatId');
  }

  /// Leaves a specific chat room
  static void leaveChatRoom(String chatId) {
    if (chatId.isEmpty) return;
    SocketService.emit('leave_chat', {'chatId': chatId});
    debugPrint('💬 Left chat room: $chatId');
  }

  /// Emits a message payload over Socket.IO (with citizen profile metadata)
  static void sendMessage({
    required String chatId,
    required String senderId,
    required String text,
    String senderRole = 'citizen',
    String? recipientUid,
    String? citizenId,   // e.g., "CID00000001"
    String? citizenName, // e.g., "Juan Dela Cruz"
  }) {
    final payload = {
      'chatId': chatId,
      'senderId': senderId,
      'senderRole': senderRole,
      'text': text,
      if (recipientUid != null) 'recipientUid': recipientUid,
      if (citizenId != null) 'citizenId': citizenId,
      if (citizenName != null) 'citizenName': citizenName,
    };

    SocketService.emit('send_message', payload);
    debugPrint('📤 Socket message emitted: $payload');
  }

  /// Marks a chat as read by the user
  static void markChatAsRead(String chatId) {
    if (chatId.isEmpty) return;
    SocketService.emit('mark_read', {
      'chatId': chatId,
      'userRole': 'citizen',
    });
  }

  /// Listens for real-time incoming messages
  static void listenForMessages(Function(Map<String, dynamic> messageData) onMessageReceived) {
    SocketService.off('receive_message'); // Clear duplicates

    SocketService.on('receive_message', (data) {
      debugPrint('📩 Socket message received: $data');
      if (data is Map<String, dynamic>) {
        onMessageReceived(data);
      } else if (data is String) {
        onMessageReceived(jsonDecode(data));
      }
    });
  }

  /// Stops listening for incoming messages
  static void stopListeningForMessages() {
    SocketService.off('receive_message');
  }

  // ==========================================
  // 🌐 REST API ENDPOINTS
  // ==========================================

  /// Fetches historical chat messages from Node.js Express REST route
  static Future<List<Map<String, dynamic>>> fetchMessageHistory(String chatId, {int limit = 50}) async {
    try {
      final baseUrl = await _getResolvedBaseUrl();
      final token = await _getIdToken();
      final targetUrl = '$baseUrl/chats/$chatId/messages?limit=$limit';

      debugPrint('📡 Fetching chat history from: $targetUrl');

      final response = await http.get(
        Uri.parse(targetUrl),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      debugPrint('📥 Chat History Status Code: ${response.statusCode}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body);
        if (body['success'] == true && body['data'] != null) {
          return List<Map<String, dynamic>>.from(body['data']);
        }
      }
      debugPrint('⚠️ Failed to parse chat history: ${response.body}');
      return [];
    } catch (e) {
      debugPrint('❌ Exception in fetchMessageHistory: $e');
      return [];
    }
  }

  /// REST fallback to send a message if WebSocket connection drops (with citizen profile metadata)
  static Future<bool> sendMessageViaRest({
    required String chatId,
    required String senderId,
    required String text,
    String senderRole = 'citizen',
    String? recipientUid,
    String? citizenId,   // e.g., "CID00000001"
    String? citizenName, // e.g., "Juan Dela Cruz"
  }) async {
    try {
      final baseUrl = await _getResolvedBaseUrl();
      final token = await _getIdToken();
      final targetUrl = '$baseUrl/chats/send';

      debugPrint('📡 Sending REST message to: $targetUrl');

      final response = await http.post(
        Uri.parse(targetUrl),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'chatId': chatId,
          'senderId': senderId,
          'senderRole': senderRole,
          'text': text,
          if (recipientUid != null) 'recipientUid': recipientUid,
          if (citizenId != null) 'citizenId': citizenId,
          if (citizenName != null) 'citizenName': citizenName,
        }),
      );

      debugPrint('📥 REST Send Status Code: ${response.statusCode}');
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('❌ Exception in sendMessageViaRest: $e');
      return false;
    }
  }
}