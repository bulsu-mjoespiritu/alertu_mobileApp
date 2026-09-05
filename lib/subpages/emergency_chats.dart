import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart' as chat_core;
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:alertu_flutter/services/bubble_service.dart';

// 🎵 Import Services
import 'package:alertu_flutter/services/messagetone_service.dart';
import 'package:alertu_flutter/services/notifmessage_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SimpleChat extends StatefulWidget {
  final String? chatId;
  final String? channelName;
  final RtcEngine? engine;
  final String? recipientUid;

  // Citizen Details Parameters (Optional overrides)
  final String? citizenId;   // e.g., "CID00000001"
  final String? citizenName; // e.g., "Juan Dela Cruz"

  const SimpleChat({
    super.key,
    this.chatId,
    this.channelName,
    this.engine,
    this.recipientUid,
    this.citizenId,
    this.citizenName,
  });

  @override
  State<SimpleChat> createState() => _SimpleChatState();
}

class _SimpleChatState extends State<SimpleChat> with WidgetsBindingObserver {
  late final chat_core.InMemoryChatController _chatController;
  late final String _currentUserId;
  late final String _activeChatId;
  StreamSubscription<QuerySnapshot>? _messageSubscription;
  bool _isLoading = true;

  bool _isInitialLoad = true;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  // Dynamic Citizen Profile State
  String? _resolvedCitizenId;
  String? _resolvedCitizenName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    NotifMessageService.initialize();
    BubbleService.stopBubble();

    _chatController = chat_core.InMemoryChatController();

    final currentFirebaseUser = auth.FirebaseAuth.instance.currentUser;
    _currentUserId = currentFirebaseUser?.uid ?? 'guest_citizen';
    _activeChatId = widget.chatId ?? widget.channelName ?? 'emergency_general';

    // Seed state from constructor parameters if available
    _resolvedCitizenId = widget.citizenId;
    _resolvedCitizenName = widget.citizenName;

    // Initialize Chat Header & Fetch Missing Citizen Metadata
    _syncChatMetaData();

    // Subscribe to Firestore Real-Time Snapshot Stream
    _subscribeToFirestoreMessages();
  }

  /// Fetches citizen details from Firestore if not provided via constructor
  Future<Map<String, String>> _getCitizenDetails() async {
    if (_resolvedCitizenId != null && _resolvedCitizenName != null) {
      return {
        'citizenId': _resolvedCitizenId!,
        'citizenName': _resolvedCitizenName!,
      };
    }

    final user = auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {'citizenId': 'UNKNOWN', 'citizenName': 'Emergency Citizen'};
    }

    try {
      // 1. Query by authUid
      var docQuery = await FirebaseFirestore.instance
          .collection('citizens')
          .where('authUid', isEqualTo: user.uid)
          .limit(1)
          .get();

      // 2. Query fallback by uid
      if (docQuery.docs.isEmpty) {
        docQuery = await FirebaseFirestore.instance
            .collection('citizens')
            .where('uid', isEqualTo: user.uid)
            .limit(1)
            .get();
      }

      if (docQuery.docs.isNotEmpty) {
        final data = docQuery.docs.first.data();
        final rawCid = data['citizenID'] ?? data['citizenId'] ?? data['cid'] ?? data['CID'];

        final resolvedId = rawCid?.toString() ?? 'UNKNOWN';
        final resolvedName = data['fullName']?.toString() ??
            data['name']?.toString() ??
            data['submitterName']?.toString() ??
            user.displayName ??
            'Emergency Citizen';

        return {
          'citizenId': resolvedId,
          'citizenName': resolvedName,
        };
      }
    } catch (e) {
      debugPrint("Error fetching citizen profile for chat: $e");
    }

    return {
      'citizenId': 'UNKNOWN',
      'citizenName': user.displayName ?? user.email ?? 'Emergency Citizen',
    };
  }

  /// Ensures the parent chat document contains updated citizen metadata for Dispatch
  Future<void> _syncChatMetaData() async {
    try {
      // Fetch details from Firestore if necessary
      final details = await _getCitizenDetails();

      if (mounted) {
        setState(() {
          _resolvedCitizenId = details['citizenId'];
          _resolvedCitizenName = details['citizenName'];
        });
      }

      final chatDocRef = FirebaseFirestore.instance.collection('chats').doc(_activeChatId);
      final docSnap = await chatDocRef.get();

      final Map<String, dynamic> updateData = {
        'chatId': _activeChatId,
        'citizenUid': _currentUserId,
        if (_resolvedCitizenId != null) 'citizenId': _resolvedCitizenId,
        if (_resolvedCitizenName != null) 'citizenName': _resolvedCitizenName,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (!docSnap.exists) {
        updateData['createdAt'] = FieldValue.serverTimestamp();
      }

      await chatDocRef.set(updateData, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Failed to sync chat metadata: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
  }

  void _subscribeToFirestoreMessages() {
    final messagesQuery = FirebaseFirestore.instance
        .collection('chats')
        .doc(_activeChatId)
        .collection('messages')
        .orderBy('timestamp', descending: false);

    _messageSubscription = messagesQuery.snapshots().listen(
          (snapshot) {
        final List<chat_core.TextMessage> loadedMessages = snapshot.docs.map((docSnap) {
          final data = docSnap.data();
          final String senderId = data['senderId'] ?? 'unknown';
          final String text = data['text'] ?? '';
          final String msgId = docSnap.id;

          DateTime createdAt = DateTime.now().toUtc();
          if (data['timestamp'] != null) {
            if (data['timestamp'] is Timestamp) {
              createdAt = (data['timestamp'] as Timestamp).toDate().toUtc();
            } else if (data['timestamp'] is String) {
              createdAt = DateTime.tryParse(data['timestamp'])?.toUtc() ?? createdAt;
            }
          }

          return chat_core.TextMessage(
            id: msgId,
            authorId: senderId,
            createdAt: createdAt,
            text: text,
          );
        })
            .toList()
          ..sort((a, b) {
            final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return aTime.compareTo(bTime);
          });

        if (_isInitialLoad) {
          _isInitialLoad = false;
        } else {
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final data = change.doc.data() as Map<String, dynamic>? ?? {};
              final String senderRole = (data['senderRole'] ?? '').toString().toLowerCase();
              final String senderId = (data['senderId'] ?? '').toString();
              final String text = (data['text'] ?? 'New Message').toString();

              final bool isFromOtherUser = senderRole == 'admin' ||
                  senderRole == 'dispatcher' ||
                  (senderRole != 'citizen' && senderId != _currentUserId);

              if (isFromOtherUser) {
                MessageToneService.playMessageTone();
                _triggerLocalNotification(
                  messageText: text,
                  chatId: _activeChatId,
                );
              }
            }
          }
        }

        _chatController.setMessages(loadedMessages);

        if (mounted && _isLoading) {
          setState(() {
            _isLoading = false;
          });
        }
      },
      onError: (error) {
        debugPrint("Error listening to real-time chat snapshot: $error");
        if (mounted && _isLoading) {
          setState(() {
            _isLoading = false;
          });
        }
      },
    );

    _resetUnreadCount();
  }

  void _triggerLocalNotification({
    required String messageText,
    required String chatId,
  }) {
    final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(100000);

    NotifMessageService.showChatNotification(
      id: notificationId,
      title: '🚨 Emergency Dispatcher',
      body: messageText,
      payload: chatId,
    );
  }

  Future<void> _resetUnreadCount() async {
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_activeChatId)
          .set({'unreadCountUser': 0}, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Failed to reset unread count: $e");
    }
  }

  Future<void> _handleMessageSend(String text) async {
    if (text.trim().isEmpty) return;

    final cleanText = text.trim();
    final chatDocRef = FirebaseFirestore.instance.collection('chats').doc(_activeChatId);
    final newMsgRef = chatDocRef.collection('messages').doc();

    // Re-verify citizen details in case state wasn't initialized
    if (_resolvedCitizenId == null || _resolvedCitizenName == null) {
      final details = await _getCitizenDetails();
      _resolvedCitizenId = details['citizenId'];
      _resolvedCitizenName = details['citizenName'];
    }

    try {
      // 1. Write message document to subcollection (includes citizen profile details)
      await newMsgRef.set({
        'id': newMsgRef.id,
        'chatId': _activeChatId,
        'senderId': _currentUserId,
        'text': cleanText,
        'senderRole': 'citizen',
        'recipientUid': widget.recipientUid ?? '',
        if (_resolvedCitizenId != null) 'citizenId': _resolvedCitizenId,
        if (_resolvedCitizenName != null) 'citizenName': _resolvedCitizenName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. Update parent conversation metadata along with Citizen Information
      await chatDocRef.set({
        'lastMessage': cleanText,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'unreadCountAdmin': FieldValue.increment(1),
        'citizenUid': _currentUserId,
        if (_resolvedCitizenId != null) 'citizenId': _resolvedCitizenId,
        if (_resolvedCitizenName != null) 'citizenName': _resolvedCitizenName,
      }, SetOptions(merge: true));

    } catch (e) {
      debugPrint('Failed to send Firestore message: $e');
    }
  }

  Future<void> _maximizeCall() async {
    await BubbleService.stopBubble();
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BubbleService.stopBubble();
    _messageSubscription?.cancel();
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final String displayName = _resolvedCitizenName ?? widget.citizenName ?? 'Citizen';
    final String displayCid = _resolvedCitizenId ?? widget.citizenId ?? _activeChatId;
    final String titleText = '$displayName ($displayCid)';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        title: Text(titleText),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.phoneCall, color: Colors.greenAccent),
            tooltip: 'Return to Call',
            onPressed: _maximizeCall,
          ),
        ],
      ),
      body: Column(
        children: [
          GestureDetector(
            onTap: _maximizeCall,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: isDark ? const Color(0xFF14532D) : Colors.green.shade800,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.phoneCall, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Ongoing Call Active • Tap to return to video',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(
              child: CircularProgressIndicator(
                color: isDark ? Colors.greenAccent : Colors.green,
              ),
            )
                : Chat(
              theme: isDark
                  ? chat_core.ChatTheme.dark()
                  : chat_core.ChatTheme.light(),
              backgroundColor: isDark
                  ? const Color(0xFF121212)
                  : Colors.white,

              chatController: _chatController,
              currentUserId: _currentUserId,
              onMessageSend: _handleMessageSend,
              resolveUser: (chat_core.UserID id) async {
                if (id == _currentUserId) {
                  return chat_core.User(
                    id: id,
                    name: _resolvedCitizenName ?? widget.citizenName ?? 'Me',
                  );
                }
                return const chat_core.User(
                  id: 'dispatcher',
                  name: 'Dispatch',
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}