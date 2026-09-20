import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 1. Stream provider listening to user state changes
final authUserProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.userChanges();
});

/// 2. Synchronous Map provider watching authUserProvider
final userProfileProvider = Provider<Map<String, String>>((ref) {
  // Use .asData?.value to extract the synchronous snapshot from AsyncValue in Riverpod 3
  final user = ref.watch(authUserProvider).asData?.value ?? FirebaseAuth.instance.currentUser;

  if (user == null) {
    return {
      "name": "Anonymous",
      "email": "Not Provided",
      "phone": "Not Provided",
    };
  }

  String name = user.displayName?.trim() ?? "Anonymous";
  String phone = user.phoneNumber?.trim() ?? "Not Provided";

  // Delimiter handler for embedded name/phone combinations
  if (name.contains('||')) {
    final parts = name.split('||');
    name = parts[0].trim();
    if (parts.length > 1 && parts[1].trim().isNotEmpty) {
      phone = parts[1].trim();
    }
  }

  return {
    "name": name.isEmpty ? "Anonymous" : name,
    "email": user.email ?? "Not Provided",
    "phone": phone.isEmpty ? "Not Provided" : phone,
  };
});