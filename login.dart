import 'package:alertu_flutter/signup.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:alertu_flutter/email_sending.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'forgot.dart';

final loginLoadingProvider = StateProvider<bool>((ref) => false);

class Login extends ConsumerStatefulWidget {
  const Login({super.key});

  @override
  ConsumerState<Login> createState() => _LoginState();
}

class _LoginState extends ConsumerState<Login> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  /// 🔹 Generates the next atomic Citizen ID (e.g., CID00000008) matching Web & App schemas
  Future<String> _generateNextCitizenId() async {
    final counterRef = FirebaseFirestore.instance.collection('counters').doc('citizens');

    return FirebaseFirestore.instance.runTransaction((transaction) async {
      final counterDoc = await transaction.get(counterRef);

      int currentCount = 0;
      if (counterDoc.exists && counterDoc.data() != null) {
        final data = counterDoc.data()!;
        if (data.containsKey('currentCount')) {
          currentCount = (data['currentCount'] as num).toInt();
        } else if (data.containsKey('count')) {
          currentCount = (data['count'] as num).toInt();
        }
      }

      final int nextCount = currentCount + 1;
      final String formattedCid = 'CID${nextCount.toString().padLeft(8, '0')}';

      // Keep both currentCount and count in sync to avoid counter conflicts
      transaction.set(
        counterRef,
        {
          'currentCount': nextCount,
          'count': nextCount,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return formattedCid;
    });
  }

  /// 🔹 Ensures user document exists in Firestore with matching CID structure
  Future<void> _ensureCitizenProfileExists(User user) async {
    final citizenRef = FirebaseFirestore.instance.collection('citizens').doc(user.uid);
    final docSnapshot = await citizenRef.get();

    if (!docSnapshot.exists) {
      final String generatedCid = await _generateNextCitizenId();

      await citizenRef.set({
        'id': generatedCid,
        'citizenId': generatedCid,
        'citizenID': generatedCid,
        'cid': generatedCid,
        'uid': user.uid,
        'authUid': user.uid,
        'fullName': user.displayName ?? email.text.split('@').first,
        'email': user.email ?? email.text.trim(),
        'phoneNumber': user.phoneNumber ?? '',
        'zone': '',
        'status': 'Active',
        'isDisabled': false,
        'isOnline': true,
        'isActive': true,
        'isArchived': false,
        'dpaAccepted': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> loginWithGoogle() async {
    ref.read(loginLoadingProvider.notifier).state = true;
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn.instance.authenticate();
      if (googleUser == null) {
        if (mounted) ref.read(loginLoadingProvider.notifier).state = false;
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final List<String> scopes = ['email', 'profile'];
      final clientAuth = await googleUser.authorizationClient.authorizeScopes(scopes);

      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: clientAuth.accessToken,
      );

      // Authenticate with Firebase
      final UserCredential userCredential =
      await FirebaseAuth.instance.signInWithCredential(credential);

      if (userCredential.user != null) {
        await _ensureCitizenProfileExists(userCredential.user!);
      }
    } catch (e) {
      try { await GoogleSignIn.instance.signOut(); } catch (_) {}
      if (mounted) {
        _showFeedback("Google Login Cancelled or Failed", type: 'error');
      }
      debugPrint("Google Sync Exception Tracker: $e");
    } finally {
      if (mounted) {
        ref.read(loginLoadingProvider.notifier).state = false;
      }
    }
  }

  Future<void> signInWithEmail() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      _showFeedback("Please fill out the form correctly.", type: 'warning');
      return;
    }

    ref.read(loginLoadingProvider.notifier).state = true;
    try {
      final UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );

      final signedInUser = userCredential.user;
      if (signedInUser != null) {
        await signedInUser.reload();
        final refreshedUser = FirebaseAuth.instance.currentUser;
        final citizenSnapshot = await FirebaseFirestore.instance
            .collection('citizens')
            .doc((refreshedUser ?? signedInUser).uid)
            .get();
        final firestoreEmailVerified = citizenSnapshot.data()?['emailVerified'] == true;

        // Email/password accounts must verify before profile creation or app access.
        if (refreshedUser != null && !refreshedUser.emailVerified && !firestoreEmailVerified) {
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const EmailSendingScreen()),
                  (route) => false,
            );
          }
          return;
        }

        await _ensureCitizenProfileExists(refreshedUser ?? signedInUser);
      }

      _showFeedback("Login successful!", type: 'success');
    } on FirebaseAuthException catch (e) {
      String errorMessage = "Authorization failed. Please try again.";
      if (e.code == 'user-not-found') errorMessage = "No user found for that email.";
      if (e.code == 'wrong-password') errorMessage = "Incorrect password.";
      if (e.code == 'network-request-failed') errorMessage = "Network error. Check your connection.";

      _showFeedback(errorMessage, type: 'error');
    } catch (e) {
      _showFeedback("An unexpected error occurred.", type: 'error');
    } finally {
      if (mounted) ref.read(loginLoadingProvider.notifier).state = false;
    }
  }

  Widget _buildBrandingHeader() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 384),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('images/logo1.png', height: 130, width: 130, fit: BoxFit.contain),
          Image.asset('images/AlertU.png', height: 130, width: 130, fit: BoxFit.contain),
        ],
      ),
    );
  }

  void _showFeedback(String message, {String type = 'error'}) {
    if (!mounted) return;

    Color bgColor;
    IconData icon;

    switch (type) {
      case 'success':
        bgColor = Colors.green.shade700;
        icon = Icons.check_circle_outline;
        break;
      case 'warning':
        bgColor = Colors.orange.shade800;
        icon = Icons.warning_amber_rounded;
        break;
      case 'error':
      default:
        bgColor = Colors.red.shade700;
        icon = Icons.error_outline;
        break;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'DISMISS', textColor: Colors.white, onPressed: () {}),
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  Widget _buildFormFields() {
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    );

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Email", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
          const SizedBox(height: 8),
          TextFormField(
            controller: email,
            style: const TextStyle(color: Colors.black87),
            validator: (value) => (value == null || !value.contains('@')) ? 'Enter a valid email' : null,
            decoration: inputDecoration.copyWith(hintText: 'Enter your email'),
          ),
          const SizedBox(height: 20),
          const Text("Password", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
          const SizedBox(height: 8),
          TextFormField(
            controller: password,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Colors.black87),
            validator: (value) => (value == null || value.length < 6) ? 'Password too short' : null,
            decoration: inputDecoration.copyWith(
              hintText: 'Enter your password',
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const Forgot())),
              child: const Text("Forgot password?", style: TextStyle(color: Color(0xff0d47a1), fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: signInWithEmail,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff0d47a1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Login", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward)
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey[300])),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text("OR", style: TextStyle(color: Colors.grey[600])),
              ),
              Expanded(child: Divider(color: Colors.grey[300])),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: loginWithGoogle,
            icon: Image.asset('images/googleicon.png', height: 20),
            label: const Text("Sign in with Google", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: Colors.grey[300]!),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
          ),
          const SizedBox(height: 30),
          Center(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account? ", style: TextStyle(color: Colors.black87)),
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUp())),
                      child: const Text("Register", style: TextStyle(color: Color(0xff0d47a1), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Privacy Policy", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.circle, size: 6, color: Color(0xff0d47a1))),
                    Text("Terms of Service", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 384),
                  child: _buildBrandingHeader(),
                ),
                const SizedBox(height: 20),
                Container(
                  constraints: const BoxConstraints(maxWidth: 384),
                  width: double.infinity,
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      )
                    ],
                  ),
                  child: _buildFormFields(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}