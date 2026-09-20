import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class EmergencyContactModel {
  String name;
  String phone;
  String relation;
  bool isPhoneValid;

  EmergencyContactModel({
    this.name = '',
    this.phone = '',
    this.relation = 'Parent',
    this.isPhoneValid = true,
  });
}

class EmergencyContactsUpdatePage extends ConsumerStatefulWidget {
  const EmergencyContactsUpdatePage({super.key});

  @override
  ConsumerState<EmergencyContactsUpdatePage> createState() =>
      _EmergencyContactsUpdatePageState();
}

class _EmergencyContactsUpdatePageState
    extends ConsumerState<EmergencyContactsUpdatePage> {
  final _formKey = GlobalKey<FormState>();

  List<EmergencyContactModel> _contacts = [];
  final List<String> _relations = [
    'Parent',
    'Guardian',
    'Spouse',
    'Sibling',
    'Friend',
    'Other'
  ];

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchExistingContacts();
  }

  /// Helper to extract country ISOCode and national number from stored complete phone number
  Map<String, String> _parsePhoneNumber(String fullPhone) {
    String cleanPhone = fullPhone.trim();
    if (cleanPhone.startsWith('+63')) {
      return {
        'countryCode': 'PH',
        'nationalNumber': cleanPhone.replaceFirst('+63', ''),
      };
    } else if (cleanPhone.startsWith('+1')) {
      return {
        'countryCode': 'US',
        'nationalNumber': cleanPhone.replaceFirst('+1', ''),
      };
    }
    // Fallback if no country code prefix is attached
    return {
      'countryCode': 'PH',
      'nationalNumber': cleanPhone.replaceFirst('+', ''),
    };
  }

  /// Fetch existing contacts from Firestore 'citizens' collection
  Future<void> _fetchExistingContacts() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('citizens')
            .doc(user.uid)
            .get();

        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final List<dynamic>? rawContacts = data['emergencyContacts'];

          if (rawContacts != null && rawContacts.isNotEmpty) {
            final List<EmergencyContactModel> loaded = [];
            for (var item in rawContacts) {
              if (item is Map<String, dynamic>) {
                String phone = (item['phone'] ?? '').toString();
                loaded.add(
                  EmergencyContactModel(
                    name: item['name'] ?? '',
                    phone: phone,
                    relation: _relations.contains(item['relation'])
                        ? item['relation']
                        : 'Other',
                    isPhoneValid: phone.isNotEmpty,
                  ),
                );
              }
            }
            if (loaded.isNotEmpty) {
              _contacts = loaded;
            }
          }
        }
      }
    } catch (e) {
      _showSnackBar("Loading Error", "Failed to fetch existing contacts: $e",
          backgroundColor: Colors.redAccent);
    } finally {
      if (_contacts.isEmpty) {
        _contacts = [EmergencyContactModel()];
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSnackBar(String title, String message, {Color? backgroundColor}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final defaultBg = isDark ? theme.colorScheme.surfaceContainerHigh : const Color(0xFF0D47A1);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: backgroundColor ?? defaultBg,
        behavior: SnackBarBehavior.floating,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            Text(
              message,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
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
      _showSnackBar(
        "Required Contact",
        "At least 1 emergency contact is strictly required.",
        backgroundColor: Colors.orange.shade800,
      );
    }
  }

  Future<void> _saveContacts() async {
    if (!_formKey.currentState!.validate()) return;

    for (int i = 0; i < _contacts.length; i++) {
      if (!_contacts[i].isPhoneValid || _contacts[i].phone.trim().isEmpty) {
        _showSnackBar(
          "Invalid Phone",
          "Contact #${i + 1} has an invalid or incomplete phone number.",
          backgroundColor: Colors.orange.shade800,
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar("Auth Error", "No logged in user found.",
            backgroundColor: Colors.redAccent);
        return;
      }

      // Legacy string formatting payload (e.g., Name|Phone|Relation##Name2|Phone2|Relation2)
      String contactPayload = _contacts
          .map((c) => "${c.name.trim()}|${c.phone.trim()}|${c.relation}")
          .join("##");

      // Firestore Map Array payload
      List<Map<String, dynamic>> contactsListMap = _contacts
          .map((c) => {
        'name': c.name.trim(),
        'phone': c.phone.trim(),
        'relation': c.relation,
      })
          .toList();

      // Update Firestore document
      await FirebaseFirestore.instance
          .collection('citizens')
          .doc(user.uid)
          .set({
        'emergencyContacts': contactsListMap,
        'legacyContactPayload': contactPayload,
      }, SetOptions(merge: true));

      if (mounted) {
        _showSnackBar("Success", "Emergency contacts updated successfully!",
            backgroundColor: Colors.green.shade700);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("Error", "Could not save emergency contacts: $e",
            backgroundColor: Colors.redAccent);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Theme adaptive colors
    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xFF0D47A1);
    final scaffoldBg = isDark ? theme.colorScheme.surface : Colors.grey.shade50;
    final cardBg = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final inputBg = isDark ? theme.colorScheme.surfaceContainerHigh : Colors.grey.shade50;
    final borderColor = isDark ? Colors.white12 : Colors.grey.shade300;
    final cardBorderColor = isDark ? Colors.white10 : Colors.grey.shade200;
    final subtextColor = isDark ? theme.colorScheme.onSurfaceVariant : Colors.black54;

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: borderColor),
    );

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: const Text('Emergency Contacts',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: cardBg,
        foregroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                horizontal: 24.0, vertical: 16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Safety Network Settings",
                      style: TextStyle(
                          color: primaryColor,
                          fontSize: 24,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Manage your primary emergency contacts. You can store 1 to 3 designated contacts.",
                      style: TextStyle(color: subtextColor, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    ...List.generate(_contacts.length, (index) {
                      final contact = _contacts[index];
                      final parsedPhone = _parsePhoneNumber(contact.phone);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cardBorderColor),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.black.withOpacity(0.2)
                                  : Colors.black.withOpacity(0.02),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Contact #${index + 1}",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: primaryColor),
                                ),
                                if (_contacts.length > 1)
                                  IconButton(
                                    icon: const Icon(LucideIcons.trash2,
                                        color: Colors.redAccent, size: 20),
                                    onPressed: () =>
                                        _removeContactField(index),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Name Input
                            TextFormField(
                              initialValue: contact.name,
                              style: TextStyle(color: theme.colorScheme.onSurface),
                              decoration: InputDecoration(
                                hintText: 'Full Name',
                                hintStyle: TextStyle(color: subtextColor),
                                filled: true,
                                fillColor: inputBg,
                                border: inputBorder,
                                enabledBorder: inputBorder,
                                focusedBorder: inputBorder.copyWith(
                                  borderSide: BorderSide(color: primaryColor),
                                ),
                              ),
                              validator: (v) =>
                              (v == null || v.trim().length < 2)
                                  ? 'Enter a valid name'
                                  : null,
                              onChanged: (val) => contact.name = val,
                            ),
                            const SizedBox(height: 16),

                            // Phone Input with theme inherited popup dialog
                            IntlPhoneField(
                              initialValue: parsedPhone['nationalNumber'],
                              initialCountryCode:
                              parsedPhone['countryCode'],
                              style: TextStyle(color: theme.colorScheme.onSurface),
                              dropdownTextStyle: TextStyle(color: theme.colorScheme.onSurface),
                              decoration: InputDecoration(
                                hintText: 'Phone Number',
                                hintStyle: TextStyle(color: subtextColor),
                                filled: true,
                                fillColor: inputBg,
                                border: inputBorder,
                                enabledBorder: inputBorder,
                                focusedBorder: inputBorder.copyWith(
                                  borderSide: BorderSide(color: primaryColor),
                                ),
                              ),
                              onChanged: (phone) {
                                contact.phone = phone.completeNumber;
                                try {
                                  contact.isPhoneValid =
                                      phone.isValidNumber();
                                } catch (_) {
                                  contact.isPhoneValid = false;
                                }
                              },
                            ),
                            const SizedBox(height: 16),

                            // Relationship Dropdown
                            DropdownButtonFormField<String>(
                              value: contact.relation,
                              dropdownColor: cardBg,
                              style: TextStyle(color: theme.colorScheme.onSurface),
                              decoration: InputDecoration(
                                hintText: 'Relationship',
                                hintStyle: TextStyle(color: subtextColor),
                                filled: true,
                                fillColor: inputBg,
                                border: inputBorder,
                                enabledBorder: inputBorder,
                                focusedBorder: inputBorder.copyWith(
                                  borderSide: BorderSide(color: primaryColor),
                                ),
                              ),
                              items: _relations.map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(
                                    value,
                                    style: TextStyle(color: theme.colorScheme.onSurface),
                                  ),
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

                    // Add Contact Button
                    if (_contacts.length < 3)
                      OutlinedButton.icon(
                        onPressed: _addNewContactField,
                        icon: const Icon(LucideIcons.plus, size: 18),
                        label: const Text("Add Another Contact"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(
                              vertical: 16),
                          side: BorderSide(
                              color: primaryColor, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),

                    const SizedBox(height: 32),

                    // Save Action Button
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveContacts,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2),
                      )
                          : const Text(
                        "Save Changes",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}