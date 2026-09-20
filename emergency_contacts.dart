import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:alertu_flutter/terms_conditions.dart';
import 'package:alertu_flutter/wrapper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

class EmergencyContactModel {
  String name = '';
  String phone = '';
  String relation = 'Parent';
  bool isPhoneValid = false;
}

class EmergencyContactsScreen extends ConsumerStatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  ConsumerState<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends ConsumerState<EmergencyContactsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Track our contacts list
  final List<EmergencyContactModel> _contacts = [EmergencyContactModel()];
  final List<String> _relations = ['Parent', 'Guardian', 'Spouse', 'Sibling', 'Friend', 'Other'];

  final Color primaryColor = const Color(0xff0d47a1);

  // Reusable design-compliant custom floating system SnackBar helper
  void _showSnackBar(String title, String message, {Color? backgroundColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: backgroundColor ?? primaryColor,
        behavior: SnackBarBehavior.floating,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            Text(message, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  void _addNewContactField() {
    if (_contacts.length < 3) {
      setState(() {
        _contacts.add(EmergencyContactModel());
      });
    } else {
      _showSnackBar("Limit Reached", "You can add a maximum of 3 emergency contacts.");
    }
  }

  void _removeContactField(int index) {
    if (_contacts.length > 1) {
      setState(() {
        _contacts.removeAt(index);
      });
    } else {
      _showSnackBar("Required Contact", "At least 1 emergency contact is strictly required.", backgroundColor: Colors.orange.shade800);
    }
  }

  Future<void> saveAndContinue() async {
    if (!_formKey.currentState!.validate()) return;

    for (int i = 0; i < _contacts.length; i++) {
      if (!_contacts[i].isPhoneValid || _contacts[i].phone.isEmpty) {
        _showSnackBar("Invalid Phone", "Contact #${i + 1} has an invalid or incomplete phone number.", backgroundColor: Colors.orange.shade800);
        return;
      }
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Serialization formatting string payload
      String contactPayload = _contacts.map((c) => "${c.name.trim()}|${c.phone}|${c.relation}").join("##");

      // Convert Dart custom model list objects into clean Firestore Maps array
      List<Map<String, dynamic>> contactsListMap = _contacts.map((c) => {
        'name': c.name.trim(),
        'phone': c.phone.trim(),
        'relation': c.relation,
      }).toList();

      // Update the document in the 'citizens' collection with the contact array
      await FirebaseFirestore.instance.collection('citizens').doc(user.uid).update({
        'emergencyContacts': contactsListMap,
        'legacyContactPayload': contactPayload
      });

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const TermsAndConditionsScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("Error", "Could not save contacts setup: $e", backgroundColor: Colors.redAccent);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade300),
    );

    return Theme(
      data: ThemeData.light().copyWith(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.grey.shade50,
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          surface: Colors.white,
          onSurface: Colors.black87,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          hintStyle: TextStyle(color: Colors.grey.shade500),
          labelStyle: const TextStyle(color: Colors.black87),
          border: inputBorder,
          enabledBorder: inputBorder,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primaryColor, width: 1.5),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text('Emergency Contacts', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: primaryColor,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        "Set up your safety network",
                        style: TextStyle(color: primaryColor, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Add who to reach out to during emergencies. You must add at least 1, up to a maximum of 3 individuals.",
                        style: TextStyle(color: Colors.black54, fontSize: 14),
                      ),
                      const SizedBox(height: 24),

                      ...List.generate(_contacts.length, (index) {
                        final contact = _contacts[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "Contact #${index + 1}",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: primaryColor),
                                  ),
                                  if (_contacts.length > 1)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                      onPressed: () => _removeContactField(index),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Name Input
                              TextFormField(
                                initialValue: contact.name,
                                style: const TextStyle(color: Colors.black87),
                                decoration: InputDecoration(
                                  hintText: 'Full Name',
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  border: inputBorder,
                                  enabledBorder: inputBorder,
                                ),
                                validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a valid name' : null,
                                onChanged: (val) => contact.name = val,
                              ),
                              const SizedBox(height: 16),

                              // International Phone Input
                              IntlPhoneField(
                                style: const TextStyle(color: Colors.black87),
                                dropdownTextStyle: const TextStyle(color: Colors.black87),
                                decoration: InputDecoration(
                                  hintText: 'Phone Number',
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  border: inputBorder,
                                  enabledBorder: inputBorder,
                                ),
                                initialCountryCode: 'PH',
                                onChanged: (phone) {
                                  contact.phone = phone.completeNumber;
                                  try {
                                    contact.isPhoneValid = phone.isValidNumber();
                                  } catch (_) {
                                    contact.isPhoneValid = false;
                                  }
                                },
                              ),
                              const SizedBox(height: 16),

                              // Relationship Dropdown
                              DropdownButtonFormField<String>(
                                value: contact.relation,
                                style: const TextStyle(color: Colors.black87),
                                dropdownColor: Colors.white,
                                decoration: InputDecoration(
                                  hintText: 'Relationship',
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  border: inputBorder,
                                  enabledBorder: inputBorder,
                                ),
                                items: _relations.map((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value, style: const TextStyle(color: Colors.black87)),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      contact.relation = val;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      }),

                      // Add Action Button
                      if (_contacts.length < 3)
                        OutlinedButton.icon(
                          onPressed: _addNewContactField,
                          icon: const Icon(Icons.add),
                          label: const Text("Add Another Contact"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: primaryColor, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),

                      const SizedBox(height: 32),

                      // Submit Action Button
                      ElevatedButton(
                        onPressed: saveAndContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Text("Save & Finish Registration", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}