import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/io_client.dart';
import '../services/socket.dart';
import '../services/api_service.dart';

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

class ProfileManagementPage extends StatefulWidget {
  const ProfileManagementPage({super.key});

  @override
  State<ProfileManagementPage> createState() => _ProfileManagementPageState();
}

class _ProfileManagementPageState extends State<ProfileManagementPage> {
  final _formKey = GlobalKey<FormState>();

  // Page View Mode (Toggle between View and Edit)
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  bool _isPhoneValid = true;

  // Form Controllers
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _zoneAddressController = TextEditingController();

  String _completePhoneNumber = "";

  // User Profile Data & Auth Token
  String _uid = '';
  String _photoUrl = '';
  String _savedPhotoUrl = '';
  XFile? _pendingAvatarFile;
  bool _pendingAvatarRemoval = false;
  String _initialEmail = '';
  String? _idToken;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    SocketService.off('citizen_updated');
    SocketService.off('profile_updated');
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _zoneAddressController.dispose();
    super.dispose();
  }

  // --- Helper to generate a reliable DiceBear fallback avatar URL ---
  String _getDiceBearAvatar(String name) {
    final cleanName = name.trim().isNotEmpty ? name.trim() : 'Citizen User';
    return "https://api.dicebear.com/7.x/initials/png?seed=${Uri.encodeComponent(cleanName)}&backgroundColor=0D47A1&textColor=ffffff";
  }

  // --- Helper to resolve relative and dynamic base URLs without path duplication ---
  String _resolveFullUrl(String rawUrl) {
    if (rawUrl.isEmpty) return '';

    String finalUrl = rawUrl;

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

  // --- Fetch latest Firebase ID Token ---
  Future<String?> _fetchFreshToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken();
        if (mounted) {
          setState(() {
            _idToken = token;
          });
        }
        return token;
      }
    } catch (e) {
      debugPrint('Error fetching ID token: $e');
    }
    return null;
  }

  // --- Socket.IO Listener Setup via SocketService ---
  Future<void> _setupSocketListeners(String uid) async {
    await SocketService.initSocket();

    SocketService.registerUserRoom(uid);

    SocketService.off('citizen_updated');
    SocketService.off('profile_updated');

    SocketService.on('citizen_updated', _handleLiveProfileUpdate);
    SocketService.on('profile_updated', _handleLiveProfileUpdate);
  }

  void _handleLiveProfileUpdate(dynamic data) {
    if (data != null && mounted) {
      final String? updatedUid = data['uid'] ?? data['authUid'] ?? data['id'];
      if (updatedUid == _uid || updatedUid == null) {
        final String? newAvatar = data['avatar'] ?? data['photoUrl'] ?? data['photoURL'];
        if (newAvatar != null && newAvatar.isNotEmpty) {
          final fullUrl = _resolveFullUrl(newAvatar);
          setState(() {
            _photoUrl = '$fullUrl?v=${DateTime.now().millisecondsSinceEpoch}';
          });
        } else {
          setState(() {
            _photoUrl = '';
          });
        }
      }
    }
  }

  // --- Fetch User Data from Firebase ---
  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _uid = user.uid;
        _initialEmail = user.email ?? '';

        await _fetchFreshToken();

        if (user.photoURL != null && user.photoURL!.isNotEmpty) {
          _photoUrl = _resolveFullUrl(user.photoURL!);
        }
        _savedPhotoUrl = _photoUrl;

        _setupSocketListeners(_uid);

        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('citizens')
            .doc(_uid)
            .get();

        if (!doc.exists) {
          final querySnap = await FirebaseFirestore.instance
              .collection('citizens')
              .where('authUid', isEqualTo: _uid)
              .limit(1)
              .get();

          if (querySnap.docs.isNotEmpty) {
            doc = querySnap.docs.first;
          }
        }

        if (doc.exists && mounted) {
          final data = doc.data() as Map<String, dynamic>?;
          final fetchedPhoto = data?['avatar'] ?? data?['photoUrl'] ?? data?['photoURL'];

          setState(() {
            if (fetchedPhoto != null && fetchedPhoto.toString().isNotEmpty) {
              _photoUrl = _resolveFullUrl(fetchedPhoto.toString());
            } else {
              _photoUrl = '';
            }
            _emailController.text = data?['email'] ?? _initialEmail;
            _fullNameController.text = data?['fullName'] ?? user.displayName ?? '';
            _phoneController.text = data?['phoneNumber'] ?? data?['mobile'] ?? '';
            _completePhoneNumber = _phoneController.text;
            _zoneAddressController.text =
                data?['zone'] ?? data?['zoneAddress'] ?? data?['location'] ?? 'Zone 1';
            _savedPhotoUrl = _photoUrl;
            _pendingAvatarFile = null;
            _pendingAvatarRemoval = false;
            _isLoading = false;
          });
        } else if (mounted) {
          setState(() {
            _emailController.text = _initialEmail;
            _fullNameController.text = user.displayName ?? '';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Modal Bottom Sheet Options for Avatar ---
  void _showAvatarOptions() {
    if (!_isEditing || _isUploadingAvatar || _isSaving) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Wrap(
              children: [
                ListTile(
                  leading: Icon(
                    LucideIcons.image,
                    color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF0D47A1),
                  ),
                  title: Text(
                    'Upload New Photo',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadAvatar();
                  },
                ),
                if (_photoUrl.isNotEmpty || _pendingAvatarFile != null)
                  ListTile(
                    leading: const Icon(LucideIcons.trash2, color: Colors.redAccent),
                    title: const Text(
                      'Remove Profile Picture',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _deleteAvatar();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Mark avatar for removal; the server changes only after Save Changes ---
  void _deleteAvatar() {
    if (!_isEditing || _isUploadingAvatar || _isSaving) return;
    setState(() {
      _pendingAvatarFile = null;
      _pendingAvatarRemoval = true;
      _photoUrl = '';
    });
    _showSnackBar('Preview Updated', 'Profile picture will be removed when you press Save Changes.');
  }

  // --- Delete Profile Picture Route Call ---
  Future<void> _deleteAvatarOnServer() async {
    try {
      setState(() => _isUploadingAvatar = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Session expired.");

      final idToken = await user.getIdToken(true);
      _idToken = idToken;

      if (ApiService.baseUrl == null) {
        await ApiService.initBackend();
      }

      final Uri deleteEndpoint = Uri.parse('${ApiService.baseUrl}/citizens/delete-avatar');

      final response = await http.delete(
        deleteEndpoint,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 204 || response.statusCode == 404) {
        if (_photoUrl.isNotEmpty) {
          await CustomUnsecureCacheManager.instance.removeFile(_photoUrl);
        }

        await FirebaseFirestore.instance.collection('citizens').doc(_uid).set({
          'avatar': '',
          'photoUrl': '',
          'photoURL': '',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (mounted) {
          setState(() {
            _photoUrl = '';
            _isUploadingAvatar = false;
          });

          _showSnackBar(
            "Avatar Removed",
            "Profile photo reverted to default successfully.",
            backgroundColor: const Color(0xFF2E7D32),
          );
        }
      } else {
        final resData = jsonDecode(response.body);
        final errorMsg = resData['message'] ?? response.body;
        throw Exception(errorMsg);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        _showSnackBar(
          "Action Failed",
          e.toString().replaceAll("Exception: ", ""),
          backgroundColor: const Color(0xFFC62828),
        );
      }
      rethrow;
    }
  }

  // --- Image Picker: local preview only; server commit happens on Save Changes ---
  Future<void> _pickAndUploadAvatar() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (image == null || !mounted) return;
      setState(() {
        _pendingAvatarFile = image;
        _pendingAvatarRemoval = false;
      });
      _showSnackBar('Preview Updated', 'Press Save Changes to apply the new profile picture.');
    } catch (e) {
      if (mounted) {
        _showSnackBar('Preview Failed', e.toString().replaceAll('Exception: ', ''), backgroundColor: const Color(0xFFC62828));
      }
    }
  }

  // --- Upload the pending avatar only during Save Changes ---
  Future<void> _uploadPendingAvatar() async {
    final image = _pendingAvatarFile;
    if (image == null) return;
    try {

      setState(() => _isUploadingAvatar = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception("Session expired. Please log in again.");
      }

      final idToken = await user.getIdToken(true);
      _idToken = idToken;

      if (ApiService.baseUrl == null) {
        await ApiService.initBackend();
      }

      final Uri uploadEndpoint = Uri.parse('${ApiService.baseUrl}/citizens/upload-avatar');

      final String extension = image.path.split('.').last.toLowerCase();
      final String subType = (extension == 'jpg' || extension == 'jpeg') ? 'jpeg' : extension;

      final request = http.MultipartRequest('POST', uploadEndpoint)
        ..headers['Authorization'] = 'Bearer $idToken'
        ..files.add(
          await http.MultipartFile.fromPath(
            'avatar',
            image.path,
            contentType: MediaType('image', subType),
          ),
        );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final resData = jsonDecode(response.body);
        final rawAvatarUrl = resData['avatar'] ?? resData['photoUrl'] ?? resData['avatarUrl'];

        if (rawAvatarUrl != null && rawAvatarUrl.toString().isNotEmpty) {
          final resolvedUrl = _resolveFullUrl(rawAvatarUrl.toString());

          await CustomUnsecureCacheManager.instance.removeFile(resolvedUrl);
          if (_photoUrl.isNotEmpty) {
            await CustomUnsecureCacheManager.instance.removeFile(_photoUrl);
          }

          final updatePayload = {
            'avatar': rawAvatarUrl,
            'photoURL': rawAvatarUrl,
            'photoUrl': rawAvatarUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          };

          final docRef = FirebaseFirestore.instance.collection('citizens').doc(_uid);
          final docSnap = await docRef.get();
          if (docSnap.exists) {
            await docRef.set(updatePayload, SetOptions(merge: true));
          } else {
            final querySnap = await FirebaseFirestore.instance
                .collection('citizens')
                .where('authUid', isEqualTo: _uid)
                .limit(1)
                .get();

            if (querySnap.docs.isNotEmpty) {
              await querySnap.docs.first.reference.set(updatePayload, SetOptions(merge: true));
            } else {
              await docRef.set(updatePayload, SetOptions(merge: true));
            }
          }

          final cacheBustedUrl = '$resolvedUrl${resolvedUrl.contains('?') ? '&' : '?'}v=${DateTime.now().millisecondsSinceEpoch}';

          if (mounted) {
            setState(() {
              _photoUrl = cacheBustedUrl;
              _isUploadingAvatar = false;
            });

            _showSnackBar(
              "Avatar Updated",
              "Profile photo updated successfully!",
              backgroundColor: const Color(0xFF2E7D32),
            );
          }
        } else {
          _loadUserData();
        }
      } else {
        throw Exception("Server returned code ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
        _showSnackBar(
          "Upload Failed",
          e.toString().replaceAll('Exception: ', ''),
          backgroundColor: const Color(0xFFC62828),
        );
      }
      rethrow;
    }
  }

  // --- Save / Update Profile ---
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate() || !_isPhoneValid) {
      _showSnackBar(
        "Validation Error",
        "Please review and fix form errors before saving.",
        backgroundColor: const Color(0xFFC62828),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception("User session not found. Please log in again.");
      }

      final newFullName = _fullNameController.text.trim();
      if (user.displayName != newFullName) {
        await user.updateDisplayName(newFullName);
      }

      final finalPhoneNumber = _completePhoneNumber.isNotEmpty
          ? _completePhoneNumber
          : _phoneController.text.trim();
      final finalZone = _zoneAddressController.text.trim();

      final firestorePayload = {
        'fullName': newFullName,
        'phoneNumber': finalPhoneNumber,
        'mobile': finalPhoneNumber,
        'zone': finalZone,
        'zoneAddress': finalZone,
        'authUid': _uid,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final directDocRef = FirebaseFirestore.instance.collection('citizens').doc(_uid);
      final docSnap = await directDocRef.get();

      if (docSnap.exists) {
        await directDocRef.set(firestorePayload, SetOptions(merge: true));
      } else {
        final querySnap = await FirebaseFirestore.instance
            .collection('citizens')
            .where('authUid', isEqualTo: _uid)
            .limit(1)
            .get();

        if (querySnap.docs.isNotEmpty) {
          await querySnap.docs.first.reference.set(firestorePayload, SetOptions(merge: true));
        } else {
          await directDocRef.set(firestorePayload, SetOptions(merge: true));
        }
      }

      try {
        final idToken = await user.getIdToken(true);
        _idToken = idToken;

        if (ApiService.baseUrl == null) {
          await ApiService.initBackend();
        }

        final Uri generalEndpoint = Uri.parse('${ApiService.baseUrl}/citizens/$_uid');

        await http.put(
          generalEndpoint,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
          body: jsonEncode({
            'fullName': newFullName,
            'phoneNumber': finalPhoneNumber,
            'zone': finalZone,
          }),
        );
      } catch (backendErr) {
        debugPrint('⚠️ Backend API sync warning: $backendErr');
      }

      if (_pendingAvatarRemoval) {
        await _deleteAvatarOnServer();
      } else if (_pendingAvatarFile != null) {
        await _uploadPendingAvatar();
      }

      try {
        await user.reload();
      } catch (reloadErr) {
        debugPrint('⚠️ User session reload warning: $reloadErr');
      }

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isEditing = false;
          _savedPhotoUrl = _photoUrl;
          _pendingAvatarFile = null;
          _pendingAvatarRemoval = false;
        });

        _showSnackBar(
          "Success",
          "Profile updated successfully!",
          backgroundColor: const Color(0xFF2E7D32),
        );
      }
    } on FirebaseAuthException catch (authErr) {
      if (mounted) {
        setState(() => _isSaving = false);
        String message = authErr.message ?? "Authentication failed.";
        _showSnackBar("Update Failed", message, backgroundColor: const Color(0xFFC62828));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnackBar(
          "Update Failed",
          e.toString().replaceAll("Exception: ", ""),
          backgroundColor: const Color(0xFFC62828),
        );
      }
    }
  }

  void _showSnackBar(String title, String message, {Color? backgroundColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: backgroundColor ?? (isDark ? const Color(0xFF1E3A8A) : const Color(0xFF0D47A1)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 2),
            Text(message, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8F9FA);
    final appBarBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final primaryColor = isDark ? const Color(0xFF60A5FA) : const Color(0xFF0D47A1);
    final titleColor = isDark ? Colors.white : const Color(0xFF1E293B);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: bgColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: appBarBg,
        foregroundColor: primaryColor,
        title: Text(
          _isEditing ? "Edit Profile" : "Profile Management",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: titleColor,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: Icon(
                _isEditing ? LucideIcons.x : LucideIcons.pencil,
                color: primaryColor,
              ),
              onPressed: _isSaving ? null : () {
                setState(() {
                  if (_isEditing) {
                    _isEditing = false;
                    _photoUrl = _savedPhotoUrl;
                    _pendingAvatarFile = null;
                    _pendingAvatarRemoval = false;
                  } else {
                    _isEditing = true;
                    _pendingAvatarFile = null;
                    _pendingAvatarRemoval = false;
                    _photoUrl = _savedPhotoUrl;
                  }
                });
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? _buildShimmerLoading(isDark)
            : LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 550),
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    20 + MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  child: Column(
                    children: [
                      _buildAvatarHeader(isDark),
                      const SizedBox(height: 24),
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 300),
                        crossFadeState: _isEditing
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: _buildProfileView(isDark),
                        secondChild: _buildProfileEditForm(isDark),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // --- Avatar Header Widget with Option Modal Trigger ---
  Widget _buildAvatarHeader(bool isDark) {
    final String fallbackAvatar = _getDiceBearAvatar(
      _fullNameController.text.isNotEmpty
          ? _fullNameController.text
          : 'Citizen User',
    );

    final titleColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : Colors.grey[600];
    final avatarButtonBg = isDark ? const Color(0xFF3B82F6) : const Color(0xFF0D47A1);

    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? Colors.blue.shade900 : const Color(0xFF0D47A1)).withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: _pendingAvatarFile != null
                        ? Image.file(
                      File(_pendingAvatarFile!.path),
                      key: ValueKey(_pendingAvatarFile!.path),
                      fit: BoxFit.cover,
                    )
                        : CachedNetworkImage(
                      key: ValueKey(_photoUrl),
                      imageUrl: _photoUrl.isNotEmpty ? _photoUrl : fallbackAvatar,
                      cacheManager: CustomUnsecureCacheManager.instance,
                      httpHeaders: {
                        if (_idToken != null && _idToken!.isNotEmpty)
                          'Authorization': 'Bearer $_idToken',
                      },
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Shimmer.fromColors(
                        baseColor: isDark ? const Color(0xFF334155) : Colors.grey[300]!,
                        highlightColor: isDark ? const Color(0xFF475569) : Colors.grey[100]!,
                        child: Container(
                          width: 92,
                          height: 92,
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        ),
                      ),
                      errorWidget: (context, url, error) => CachedNetworkImage(
                        imageUrl: fallbackAvatar,
                        cacheManager: CustomUnsecureCacheManager.instance,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              if (_isUploadingAvatar)
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_isEditing && !_isUploadingAvatar && !_isSaving)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: avatarButtonBg,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(LucideIcons.camera, size: 15, color: Colors.white),
                      onPressed: _showAvatarOptions,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _fullNameController.text.isNotEmpty
                ? _fullNameController.text
                : "Citizen User",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _emailController.text,
            style: TextStyle(fontSize: 13, color: subtitleColor),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileView(bool isDark) {
    final primaryColor = isDark ? const Color(0xFF60A5FA) : const Color(0xFF0D47A1);
    final buttonBg = isDark ? const Color(0xFF2563EB) : const Color(0xFF0D47A1);

    return Column(
      children: [
        _buildInfoCard(
          isDark: isDark,
          icon: LucideIcons.user,
          color: const Color(0xff5ca6d0),
          title: "Full Name",
          value: _fullNameController.text,
        ),
        _buildInfoCard(
          isDark: isDark,
          icon: LucideIcons.mail,
          color: const Color(0xffe29578),
          title: "Email Address",
          value: _emailController.text,
        ),
        _buildInfoCard(
          isDark: isDark,
          icon: LucideIcons.phone,
          color: const Color(0xff62b667),
          title: "Mobile Number",
          value: _phoneController.text.isNotEmpty
              ? _phoneController.text
              : "Not provided",
        ),
        _buildInfoCard(
          isDark: isDark,
          icon: LucideIcons.mapPin,
          color: const Color(0xfff4a261),
          title: "Home Address (Zone)",
          value: _zoneAddressController.text.isNotEmpty
              ? _zoneAddressController.text
              : "Not set",
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonBg,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(LucideIcons.pencil, color: Colors.white, size: 18),
            label: const Text(
              "Edit Profile Details",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            onPressed: () => setState(() => _isEditing = true),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required bool isDark,
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    Widget? trailing,
  }) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final titleColor = isDark ? const Color(0xFF94A3B8) : Colors.grey[600];
    final valueColor = isDark ? Colors.white : const Color(0xFF1E293B);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.black.withOpacity(0.025),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 12, color: titleColor),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildProfileEditForm(bool isDark) {
    final primaryButtonBg = isDark ? const Color(0xFF2563EB) : const Color(0xFF0D47A1);
    final disabledButtonBg = isDark ? const Color(0xFF334155) : Colors.grey.shade300;
    final disabledTextColor = isDark ? const Color(0xFF64748B) : Colors.grey[500];

    final cancelBorderColor = isDark ? const Color(0xFF475569) : Colors.grey.shade300;
    final cancelTextColor = isDark ? const Color(0xFFCBD5E1) : Colors.grey[700];

    final fieldBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final fieldBorder = isDark ? const Color(0xFF334155) : Colors.grey.shade300;
    final focusBorder = isDark ? const Color(0xFF60A5FA) : const Color(0xFF0D47A1);

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFormFieldLabel("Full Name", isDark),
          TextFormField(
            controller: _fullNameController,
            enabled: !_isSaving,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: _buildInputDecoration(
              hint: 'Full Name',
              icon: LucideIcons.user,
              isDark: isDark,
            ),
            validator: (v) =>
            (v == null || v.trim().length < 2) ? 'Provide a valid name' : null,
          ),
          const SizedBox(height: 16),

          _buildFormFieldLabel("Mobile Number", isDark),
          IntlPhoneField(
            enabled: !_isSaving,
            initialValue: _phoneController.text,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            dropdownTextStyle: TextStyle(color: isDark ? Colors.white : Colors.black),
            dropdownIcon: Icon(Icons.arrow_drop_down, color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600),
            decoration: InputDecoration(
              hintText: 'Phone Number',
              hintStyle: TextStyle(color: isDark ? const Color(0xFF64748B) : Colors.grey.shade500),
              filled: true,
              fillColor: fieldBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: fieldBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: fieldBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: focusBorder, width: 1.5),
              ),
            ),
            initialCountryCode: 'PH',
            onChanged: (phone) {
              _completePhoneNumber = phone.completeNumber;
              try {
                _isPhoneValid = phone.isValidNumber();
              } catch (_) {
                _isPhoneValid = false;
              }
            },
          ),
          const SizedBox(height: 12),

          _buildFormFieldLabel("Home Address / Zone", isDark),
          TextFormField(
            controller: _zoneAddressController,
            enabled: !_isSaving,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: _buildInputDecoration(
              hint: 'Home Address',
              icon: LucideIcons.mapPin,
              isDark: isDark,
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Home address is required'
                : null,
          ),
          const SizedBox(height: 16),

          const SizedBox(height: 28),

          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cancelTextColor,
                    side: BorderSide(color: cancelBorderColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _isSaving ? null : () {
                    setState(() {
                      _isEditing = false;
                      _photoUrl = _savedPhotoUrl;
                      _pendingAvatarFile = null;
                      _pendingAvatarRemoval = false;
                    });
                  },
                  child: const Text(
                    "Cancel",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryButtonBg,
                    disabledBackgroundColor: disabledButtonBg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : Icon(
                    LucideIcons.save,
                    color: Colors.white,
                    size: 18,
                  ),
                  label: Text(
                    _isSaving ? "Saving..." : "Save Changes",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: _isSaving ? null : _saveProfile,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormFieldLabel(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, left: 2.0),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hint,
    required IconData icon,
    required bool isDark,
    Widget? suffixIcon,
  }) {
    final fieldBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final fieldBorder = isDark ? const Color(0xFF334155) : Colors.grey.shade300;
    final focusBorder = isDark ? const Color(0xFF60A5FA) : const Color(0xFF0D47A1);
    final iconColor = isDark ? const Color(0xFF60A5FA) : const Color(0xFF0D47A1);
    final hintColor = isDark ? const Color(0xFF64748B) : Colors.grey.shade500;

    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: hintColor),
      prefixIcon: Icon(icon, size: 18, color: iconColor),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: fieldBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: fieldBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: focusBorder, width: 1.5),
      ),
    );
  }

  Widget _buildShimmerLoading(bool isDark) {
    final baseColor = isDark ? const Color(0xFF334155) : Colors.grey[300]!;
    final highlightColor = isDark ? const Color(0xFF475569) : Colors.grey[100]!;
    final itemBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const CircleAvatar(radius: 46),
                const SizedBox(height: 16),
                Container(width: 140, height: 18, color: itemBg),
                const SizedBox(height: 28),
                ...List.generate(
                  5,
                      (index) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    height: 58,
                    decoration: BoxDecoration(
                      color: itemBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}