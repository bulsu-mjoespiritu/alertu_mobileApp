import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/io_client.dart';
import 'package:adaptive_theme/adaptive_theme.dart';

import 'option_item.dart';
import 'profile_management.dart';
import 'emergency_contactsupdate.dart';
import 'alertu_chatbot.dart';
import 'about_app.dart';
import '../services/socket.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

// --- CUSTOM UNSECURE CACHE MANAGER HELPER ---
class CustomUnsecureCacheManager {
  static const String key = 'unsecureImageCache';

  static final CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 100,
      fileService: HttpFileService(
        httpClient: IOClient(
          HttpClient()
            ..badCertificateCallback =
                (X509Certificate cert, String host, int port) => true,
        ),
      ),
    ),
  );
}

// --- Layout Constants ---
const double basePadding = 16.0;
const double userDetailFraction = 0.40;
const double offset = 0.04;
const double contentFraction = userDetailFraction - offset;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // State variables
  bool _notificationsEnabled = true;

  String _userName = "Citizen User";
  String _userEmail = "user@example.com";
  String? _photoUrl;
  String? _idToken;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _listenToProfileUpdates();
  }

  @override
  void dispose() {
    // Clean up socket listener on widget dispose
    SocketService.socket?.off('profile_updated');
    super.dispose();
  }

  // 🔔 Real-time Socket Listener for Instant Avatar & Profile Updates
  void _listenToProfileUpdates() {
    SocketService.socket?.on('profile_updated', (data) {
      if (mounted) {
        _loadUserProfile();
      }
    });
  }

  // Helper to generate a reliable DiceBear SVG/PNG fallback avatar URL
  String _getDiceBearAvatar(String name) {
    final cleanName = name.trim().isNotEmpty ? name.trim() : 'Citizen User';
    return "https://api.dicebear.com/7.x/initials/png?seed=${Uri.encodeComponent(cleanName)}&backgroundColor=0D47A1&textColor=ffffff";
  }

  // Helper to resolve relative and dynamic base URLs without path duplication
  String _resolveFullUrl(String rawUrl) {
    if (rawUrl.isEmpty) return '';

    String finalUrl = rawUrl;

    // Resolve domain origin from ApiService.baseUrl
    final baseUrl = ApiService.baseUrl ?? '';
    if (baseUrl.isNotEmpty) {
      String cleanBase = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;

      String rootOrigin = cleanBase;
      if (cleanBase.endsWith('/api')) {
        rootOrigin = cleanBase.substring(0, cleanBase.length - 4);
      }

      if (rawUrl.startsWith('/api/')) {
        finalUrl = '$rootOrigin$rawUrl';
      } else if (rawUrl.startsWith('/')) {
        finalUrl = '$cleanBase$rawUrl';
      } else if (rawUrl.contains('/api/media/stream')) {
        final pathIndex = rawUrl.indexOf('/api/media/stream');
        finalUrl = '$rootOrigin${rawUrl.substring(pathIndex)}';
      }
    }

    return finalUrl;
  }

  // Fetch logged in user details & auth token
  Future<void> _loadUserProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.reload();
        final currentUser = FirebaseAuth.instance.currentUser ?? user;
        final token = await currentUser.getIdToken(true);

        final doc = await FirebaseFirestore.instance
            .collection('citizens')
            .doc(currentUser.uid)
            .get();

        if (mounted) {
          final data = doc.data();

          final fetchedPhoto = data?['avatar'] ??
              data?['photoURL'] ??
              data?['photoUrl'] ??
              currentUser.photoURL;

          setState(() {
            _idToken = token;
            _userEmail = currentUser.email ?? "No Email Record";
            if (doc.exists && data != null) {
              _notificationsEnabled = data['notificationsEnabled'] != false;
              _userName = data['fullName'] ?? currentUser.displayName ?? "Citizen User";
            } else {
              _userName = currentUser.displayName ?? "Citizen User";
            }

            if (fetchedPhoto != null && fetchedPhoto.toString().trim().isNotEmpty) {
              _photoUrl = _resolveFullUrl(fetchedPhoto.toString().trim());
            } else {
              _photoUrl = _getDiceBearAvatar(_userName);
            }

            _isLoadingUser = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingUser = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  // Refresh handler
  Future<void> _handleRefresh() async {
    setState(() => _isLoadingUser = true);
    await _loadUserProfile();
  }

  // --- Dynamic App Theme Toggle ---
  void _toggleDarkMode(bool value) {
    if (value) {
      AdaptiveTheme.of(context).setDark();
    } else {
      AdaptiveTheme.of(context).setLight();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? "Dark Mode Enabled" : "Light Mode Enabled"),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<DocumentReference<Map<String, dynamic>>> _resolveCitizenProfileReference(
      User user) async {
    final citizens = FirebaseFirestore.instance.collection('citizens');

    final directReference = citizens.doc(user.uid);
    final directSnapshot = await directReference.get();
    if (directSnapshot.exists) return directReference;

    final authUidQuery = await citizens
        .where('authUid', isEqualTo: user.uid)
        .limit(1)
        .get();
    if (authUidQuery.docs.isNotEmpty) {
      return authUidQuery.docs.first.reference;
    }

    final legacyUidQuery = await citizens
        .where('uid', isEqualTo: user.uid)
        .limit(1)
        .get();
    if (legacyUidQuery.docs.isNotEmpty) {
      return legacyUidQuery.docs.first.reference;
    }

    return directReference;
  }

  Future<void> _toggleNotifications(bool value) async {
    final previousValue = _notificationsEnabled;
    setState(() => _notificationsEnabled = value);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('No signed-in user found.');

      final profileReference =
      await _resolveCitizenProfileReference(user);

      await profileReference.set({
        'notificationsEnabled': value,
        'notificationsPreferenceUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (value) {
        try {
          final token = await NotificationService.instance.getFcmToken();
          if (token != null) {
            await ApiService.registerFcmToken(token);
          }
        } catch (error) {
          debugPrint('⚠️ FCM re-registration warning: $error');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'Notifications Turned On' : 'Notifications Turned Off'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _notificationsEnabled = previousValue);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update notification setting: $error'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // 🔑 Fixed Logout Dialog and Session Disposal Flow
  void _showLogoutDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Log Out"),
        content: const Text("Are you sure you want to log out?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              // Close confirmation dialog
              Navigator.of(dialogContext).pop();

              try {
                // 1. Notify backend of user status update
                await ApiService.updateUserPresence(isActive: false);

                // 2. Disconnect Sockets
                SocketService.disconnect();

                // 3. Clear Cache Manager instances
                await CustomUnsecureCacheManager.instance.emptyCache();

                // 4. Sign out from Firebase Auth
                await FirebaseAuth.instance.signOut();

                // 5. Navigate to root/wrapper screen
                if (mounted) {
                  Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
                    '/',
                        (route) => false,
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Logout error: ${e.toString()}")),
                  );
                }
              }
            },
            child: const Text("Log Out", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.of(context).size.height;
    final String fallbackAvatarUrl = _getDiceBearAvatar(_userName);

    final theme = Theme.of(context);
    final isDark = AdaptiveTheme.of(context).mode.isDark;

    final List<OptionItem> accountOptions = [
      OptionItem(
        icon: LucideIcons.user,
        color: const Color(0xff5ca6d0),
        label: "Profile Management",
        onClick: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ProfileManagementPage(),
            ),
          ).then((_) => _loadUserProfile());
        },
      ),
      OptionItem(
        icon: LucideIcons.phoneCall,
        color: const Color(0xffe29578),
        label: "Emergency Contacts",
        onClick: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const EmergencyContactsUpdatePage(),
            ),
          ).then((_) => _loadUserProfile());
        },
      ),
      OptionItem(
        icon: LucideIcons.bell,
        color: const Color(0xfff4a261),
        label: "Notifications",
        trailing: CupertinoSwitch(
          activeColor: theme.colorScheme.primary,
          value: _notificationsEnabled,
          onChanged: _toggleNotifications,
        ),
        onClick: () => _toggleNotifications(!_notificationsEnabled),
      ),
    ];

    final List<OptionItem> appOptions = [
      OptionItem(
        icon: LucideIcons.moon,
        color: const Color(0xff8860d0),
        label: "Dark Mode",
        trailing: CupertinoSwitch(
          activeColor: theme.colorScheme.primary,
          value: isDark,
          onChanged: _toggleDarkMode,
        ),
        onClick: () => _toggleDarkMode(!isDark),
      ),
      OptionItem(
        icon: LucideIcons.bot,
        color: const Color(0xff2a9d8f),
        label: "AlertU Chatbot",
        onClick: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AlertUChatbotPage(),
            ),
          );
        },
      ),
      OptionItem(
        icon: LucideIcons.fileText,
        color: const Color(0xff457b9d),
        label: "About App",
        onClick: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AboutAppPage(),
            ),
          );
        },
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox(
        width: double.infinity,
        child: Stack(
          children: [
            // ==================== TOP HERO HEADER ====================
            Container(
              height: height * userDetailFraction,
              decoration: const BoxDecoration(
                color: Colors.black,
                image: DecorationImage(
                  image: AssetImage("images/background.png"),
                  fit: BoxFit.cover,
                  opacity: 0.8,
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: basePadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Settings",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontSize: 26,
                        ),
                      ),
                      const Spacer(),
                      Center(
                        child: Column(
                          children: [
                            _isLoadingUser
                                ? Shimmer.fromColors(
                              baseColor: Colors.grey[800]!,
                              highlightColor: Colors.grey[600]!,
                              child: const CircleAvatar(radius: 44),
                            )
                                : Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24, width: 2),
                              ),
                              child: ClipOval(
                                child: CachedNetworkImage(
                                  key: ValueKey(_photoUrl),
                                  imageUrl: _photoUrl ?? fallbackAvatarUrl,
                                  cacheManager: CustomUnsecureCacheManager.instance,
                                  httpHeaders: {
                                    if (_idToken != null && _idToken!.isNotEmpty)
                                      'Authorization': 'Bearer $_idToken',
                                  },
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Shimmer.fromColors(
                                    baseColor: Colors.grey[800]!,
                                    highlightColor: Colors.grey[600]!,
                                    child: Container(color: Colors.white24),
                                  ),
                                  errorWidget: (context, url, error) => CachedNetworkImage(
                                    imageUrl: fallbackAvatarUrl,
                                    cacheManager: CustomUnsecureCacheManager.instance,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _isLoadingUser
                                ? Shimmer.fromColors(
                              baseColor: Colors.grey[800]!,
                              highlightColor: Colors.grey[600]!,
                              child: Container(
                                width: 140,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            )
                                : Text(
                              _userName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontSize: 20,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _isLoadingUser
                                ? Shimmer.fromColors(
                              baseColor: Colors.grey[800]!,
                              highlightColor: Colors.grey[600]!,
                              child: Container(
                                margin: const EdgeInsets.only(top: 4),
                                width: 180,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            )
                                : Text(
                              _userEmail,
                              style: const TextStyle(
                                fontWeight: FontWeight.w400,
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: height * offset),
                    ],
                  ),
                ),
              ),
            ),

            // ==================== FOREGROUND CARD WITH REFRESH ====================
            Column(
              children: [
                SizedBox(height: height * contentFraction),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      child: RefreshIndicator(
                        onRefresh: _handleRefresh,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
                          children: [
                            _buildSectionTitle("Account", theme),
                            ...accountOptions.map((opt) => _buildOptionRow(opt, theme)),

                            const SizedBox(height: 16),
                            _buildSectionTitle("App Settings", theme),
                            ...appOptions.map((opt) => _buildOptionRow(opt, theme)),

                            const SizedBox(height: 24),

                            // Logout Button
                            _buildLogoutButton(),

                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.primary,
          fontSize: 11,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildOptionRow(OptionItem option, ThemeData theme) {
    return GestureDetector(
      onTap: option.onClick,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        color: Colors.transparent,
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              alignment: Alignment.center,
              margin: const EdgeInsets.only(right: 14),
              decoration: BoxDecoration(
                color: option.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                option.icon,
                color: option.color,
                size: 20,
              ),
            ),
            Expanded(
              child: Text(
                option.label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: theme.textTheme.bodyLarge?.color ?? Colors.black87,
                ),
              ),
            ),
            if (option.trailing != null)
              option.trailing!
            else
              Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: theme.hintColor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE53935),
        elevation: 3,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      onPressed: _showLogoutDialog,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.logOut,
            color: Colors.white,
            size: 20,
          ),
          SizedBox(width: 10),
          Text(
            "Log Out",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}