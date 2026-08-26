import 'dart:async';

import 'package:alertu_flutter/services/socket.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:alertu_flutter/homepage.dart';
import 'package:alertu_flutter/login.dart';
import 'package:alertu_flutter/email_sending.dart';
import 'package:alertu_flutter/complete_profile.dart';
import 'package:alertu_flutter/terms_conditions.dart';
import 'package:alertu_flutter/services/api_service.dart';
import 'package:alertu_flutter/services/notification_service.dart';
import 'package:alertu_flutter/disable_modal.dart';

class Wrapper extends ConsumerStatefulWidget {
  const Wrapper({super.key});

  @override
  ConsumerState<Wrapper> createState() => _WrapperState();
}

class _WrapperState extends ConsumerState<Wrapper> with WidgetsBindingObserver {
  String? _currentUserId;
  String? _currentCitizenId;
  bool _isOnHomepage = false;
  bool _isAppInForeground = true;
  Timer? _presenceLifecycleTimer;
  bool _fcmSyncInFlight = false;
  String? _fcmSyncedUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SocketService.initSocket();
  }

  @override
  void dispose() {
    _presenceLifecycleTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _leaveCurrentSocketRooms();
    _updatePresence(isActive: false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_currentUserId == null || !_isOnHomepage) return;

    switch (state) {
      case AppLifecycleState.resumed:
      // Cancel a pending offline transition when the user returns quickly.
        _presenceLifecycleTimer?.cancel();
        _presenceLifecycleTimer = null;
        _isAppInForeground = true;

        // Presence is event-driven: emit online once on foreground entry;
        // there is no periodic heartbeat or artificial always-online state.
        _updatePresence(isActive: true);
        _joinTargetedSocketRooms(_currentUserId, _currentCitizenId);
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _isAppInForeground = false;
        _presenceLifecycleTimer?.cancel();

        // A short debounce prevents false offline/online flicker during
        // transient Flutter inactive transitions (for example, a system
        // dialog or activity hand-off). A real app switch reaches this timer.
        _presenceLifecycleTimer = Timer(const Duration(milliseconds: 700), () {
          if (mounted && !_isAppInForeground) {
            _updatePresence(isActive: false);
          }
        });
        break;

      case AppLifecycleState.detached:
        _presenceLifecycleTimer?.cancel();
        _presenceLifecycleTimer = null;
        _isAppInForeground = false;
        _updatePresence(isActive: false);
        break;
    }
  }

  void _updatePresence({required bool isActive}) {
    final uid = _currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      SocketService.emitPresence(uid: uid, isActive: isActive);
    } catch (e) {
      debugPrint("Socket.IO presence emit error: $e");
    }
  }

  /// Joins targeted citizen rooms so real-time updates reach ONLY this account
  void _joinTargetedSocketRooms(String? authUid, String? citizenId) {
    try {
      if (authUid != null && authUid.isNotEmpty) {
        SocketService.emit('join_room', authUid);
        debugPrint("📡 [Socket] Joined authUid room: $authUid");
      }
      if (citizenId != null && citizenId.isNotEmpty) {
        SocketService.emit('join_room', citizenId);
        debugPrint("📡 [Socket] Joined citizenID room: $citizenId");
      }
    } catch (e) {
      debugPrint("Socket.IO join_room error: $e");
    }
  }

  /// Leaves socket rooms on logout or account switch to prevent cross-account event leaks
  void _leaveCurrentSocketRooms() {
    try {
      if (_currentUserId != null && _currentUserId!.isNotEmpty) {
        SocketService.emit('leave_room', _currentUserId);
      }
      if (_currentCitizenId != null && _currentCitizenId!.isNotEmpty) {
        SocketService.emit('leave_room', _currentCitizenId);
      }
    } catch (e) {
      debugPrint("Socket.IO leave_room error: $e");
    }
  }

  Future<void> _syncFcmToken(String userId) async {
    if (_fcmSyncInFlight || _fcmSyncedUserId == userId) return;
    _fcmSyncInFlight = true;

    try {
      final notificationsEnabled =
      await NotificationService.instance.areNotificationsEnabled();
      if (!notificationsEnabled) {
        debugPrint('🔕 FCM token registration skipped: notifications disabled.');
        _fcmSyncedUserId = userId;
        return;
      }

      final token = await NotificationService.instance.getFcmToken();
      if (token != null) {
        await ApiService.registerFcmToken(token);
        _fcmSyncedUserId = userId;
      }
    } catch (error) {
      debugPrint("FCM token registration warning: $error");
    } finally {
      _fcmSyncInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (SocketService.isAccountDeactivatedFlag) {
            if (_isOnHomepage) {
              _isOnHomepage = false;
              _leaveCurrentSocketRooms();
              _updatePresence(isActive: false);
            }
            return const DisableModal(isDialog: false);
          }

          final user = snapshot.data;

          // Detect User Account Switching or Logout
          if (user?.uid != _currentUserId) {
            if (_currentUserId != null) {
              _leaveCurrentSocketRooms();
              _isOnHomepage = false;
              _updatePresence(isActive: false);
            }
            _currentUserId = user?.uid;
            _fcmSyncedUserId = null;

          }

          // 🔴 IF USER IS LOGGED OUT: Return Login Widget
          if (user == null) {
            if (_isOnHomepage) {
              _leaveCurrentSocketRooms();
              _isOnHomepage = false;
              _updatePresence(isActive: false);
            }
            return const Login();
          }

          // 🟢 IF USER IS LOGGED IN: Fetch Firestore Profile and Route
          return FutureBuilder<Map<String, dynamic>?>(
            key: ValueKey(user.uid),
            future: () async {
              try {
                await user.reload();
              } catch (_) {}

              try {
                var querySnapshot = await FirebaseFirestore.instance
                    .collection('citizens')
                    .where('authUid', isEqualTo: user.uid)
                    .limit(1)
                    .get(const GetOptions(source: Source.serverAndCache));

                if (querySnapshot.docs.isNotEmpty) {
                  return querySnapshot.docs.first.data();
                }

                querySnapshot = await FirebaseFirestore.instance
                    .collection('citizens')
                    .where('uid', isEqualTo: user.uid)
                    .limit(1)
                    .get();

                if (querySnapshot.docs.isNotEmpty) {
                  return querySnapshot.docs.first.data();
                }

                final directDoc = await FirebaseFirestore.instance
                    .collection('citizens')
                    .doc(user.uid)
                    .get();

                if (directDoc.exists) {
                  return directDoc.data();
                }
              } catch (e) {
                debugPrint("Error fetching citizen profile: $e");
              }

              return null;
            }(),
            builder: (context, profileSnapshot) {
              if (profileSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final currentUser = FirebaseAuth.instance.currentUser;
              if (currentUser == null) {
                if (_isOnHomepage) {
                  _leaveCurrentSocketRooms();
                  _isOnHomepage = false;
                  _updatePresence(isActive: false);
                }
                return const Login();
              }

              final data = profileSnapshot.data;
              final docExists = data != null;

              // Email/password users must verify before any profile routing.
              // The OTP flow persists this state in Firestore; Firebase's native
              // flag is also accepted for accounts verified outside the app.
              final usesPasswordProvider = currentUser.providerData.any(
                    (provider) => provider.providerId == 'password',
              );
              final firestoreEmailVerified = data?['emailVerified'] == true;
              final isEmailVerified = currentUser.emailVerified || firestoreEmailVerified;
              if (usesPasswordProvider && !isEmailVerified) {
                if (_isOnHomepage) {
                  _leaveCurrentSocketRooms();
                  _isOnHomepage = false;
                  _updatePresence(isActive: false);
                }
                return const EmailSendingScreen();
              }

              // 🚫 ACCOUNT DISABLED CHECK
              final bool isDisabledFlag = data?['isDisabled'] == true;
              final String statusStr = data?['status']?.toString().trim().toLowerCase() ?? '';
              final bool isStatusDisabled =
                  statusStr == 'disabled' || statusStr == 'deactivated' || statusStr == 'inactive';
              final bool isAccountDisabled = docExists && (isDisabledFlag || isStatusDisabled);

              if (isAccountDisabled) {
                if (_isOnHomepage) {
                  _leaveCurrentSocketRooms();
                  _isOnHomepage = false;
                  _updatePresence(isActive: false);
                }
                return const DisableModal(isDialog: false);
              }

              // Extract CID identifiers
              final rawCid = data?['citizenID'] ?? data?['citizenId'] ?? data?['cid'] ?? data?['citizen_id'] ?? data?['CID'];
              final String? citizenId = rawCid?.toString();
              _currentCitizenId = citizenId;
              final bool hasCitizenId = citizenId != null && citizenId.trim().isNotEmpty;

              final String fullName = data?['fullName']?.toString() ?? currentUser.displayName ?? '';
              final String phoneNumber = data?['phoneNumber']?.toString() ?? data?['phone']?.toString() ?? '';
              final String zone = data?['zone']?.toString() ?? '';

              final bool hasPhone = phoneNumber.isNotEmpty && phoneNumber != 'No Phone Record';
              final bool hasZone = zone.isNotEmpty && zone != 'Unassigned Sector';
              final bool dpaAccepted = data?['dpaAccepted'] == true;

              // -----------------------------------------------------------------
              // ROUTING RULES
              // -----------------------------------------------------------------

              // RULE 1: Profile complete and terms accepted -> Homepage
              if (hasCitizenId && hasPhone && hasZone && dpaAccepted) {
                _syncFcmToken(currentUser.uid);
                if (!_isOnHomepage) {
                  _isOnHomepage = true;
                  _updatePresence(isActive: true);
                  _joinTargetedSocketRooms(currentUser.uid, citizenId);
                }
                return const Homepage();
              }

              // RULE 2: Admin-created citizen profile data complete, BUT needs terms agreement
              if (hasPhone && hasZone && !dpaAccepted) {
                if (_isOnHomepage) {
                  _leaveCurrentSocketRooms();
                  _isOnHomepage = false;
                  _updatePresence(isActive: false);
                }
                return TermsAndConditionsScreen(
                  fullName: fullName,
                  phoneNumber: phoneNumber,
                  zone: zone,
                );
              }

              // Email verification is enforced above before profile routing.

              // RULE 4: Missing profile details -> Complete Profile Screen
              if (_isOnHomepage) {
                _leaveCurrentSocketRooms();
                _isOnHomepage = false;
                _updatePresence(isActive: false);
              }
              return CompleteProfile(user: currentUser);
            },
          );
        },
      ),
    );
  }
}