import 'package:alertu_flutter/wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:intl_phone_field/intl_phone_field.dart';

import 'homepage.dart';

final completeProfileLoadingProvider = StateProvider<bool>((ref) => false);

class CompleteProfile extends ConsumerStatefulWidget {
  final User user;
  const CompleteProfile({super.key, required this.user});

  @override
  ConsumerState<CompleteProfile> createState() => _CompleteProfileState();
}

class _CompleteProfileState extends ConsumerState<CompleteProfile> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController name;
  final TextEditingController address = TextEditingController();
  final TextEditingController email = TextEditingController();
  final TextEditingController password = TextEditingController();
  final TextEditingController confirmPassword = TextEditingController();

  String completePhoneNumber = "";
  bool _isPhoneValid = false;
  bool _isDpaAccepted = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final List<_SignupEmergencyContact> _emergencyContacts = <_SignupEmergencyContact>[];
  bool _contactsCompleted = false;

  String _strengthText = 'Weak';
  Color _strengthColor = Colors.red;
  double _strengthProgress = 0.33;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.user.displayName);
    email.text = widget.user.email ?? '';
    password.addListener(_evaluatePasswordStrength);
  }

  @override
  void dispose() {
    name.dispose();
    address.dispose();
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    password.removeListener(_evaluatePasswordStrength);
    super.dispose();
  }

  void _evaluatePasswordStrength() {
    final text = password.text;
    final uppercaseCount = text.replaceAll(RegExp(r'[^A-Z]'), '').length;
    final specialCharCount = text.replaceAll(RegExp(r'[a-zA-Z0-9\s]'), '').length;

    if (text.length < 12) {
      setState(() {
        _strengthText = 'Weak';
        _strengthColor = Colors.red;
        _strengthProgress = 0.33;
      });
    } else if (text.length >= 15 && uppercaseCount == 1 && specialCharCount == 1) {
      setState(() {
        _strengthText = 'Strong';
        _strengthColor = Colors.green;
        _strengthProgress = 1.0;
      });
    } else {
      setState(() {
        _strengthText = 'Moderate';
        _strengthColor = Colors.amber;
        _strengthProgress = 0.66;
      });
    }
  }

  void _showSnackBar(String title, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xff0d47a1),
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

  Future<void> saveProfile() async {
    if (!_formKey.currentState!.validate() || !_isPhoneValid || completePhoneNumber.isEmpty) {
      _showSnackBar("Incomplete Form", "Please fix the errors in the form before submitting.");
      return;
    }

    if (!_contactsCompleted) {
      _showSnackBar("Emergency Contacts Required", "Please add at least one emergency contact before finishing setup.");
      return;
    }

    if (!_isDpaAccepted) {
      _showSnackBar("Consent Required", "Please check the consent box to complete your registration.");
      return;
    }

    ref.read(completeProfileLoadingProvider.notifier).state = true;

    try {
      String customProfileData = "${name.text.trim()}||$completePhoneNumber||${address.text.trim()}";
      await widget.user.updateDisplayName(customProfileData);
      await widget.user.reload();

      await FirebaseFirestore.instance.collection('citizens').doc(widget.user.uid).set({
        'id': widget.user.uid,
        'fullName': name.text.trim(),
        'email': widget.user.email?.trim() ?? '',
        'phoneNumber': completePhoneNumber,
        'zone': address.text.trim(),
        'status': 'Active',
        'dpaAccepted': true,
        'dpaAcceptedAt': FieldValue.serverTimestamp(),
        'emailVerified': true,
        'emergencyContacts': _emergencyContacts.map((contact) => {'name': contact.name.trim(), 'phone': contact.phone.trim(), 'relation': contact.relation}).toList(),
        'legacyContactPayload': _emergencyContacts.map((contact) => '${contact.name.trim()}|${contact.phone.trim()}|${contact.relation}').join('##'),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const Homepage()),
              (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("Error", "Could not save your profile. Please try again.");
      }
    } finally {
      if (mounted) {
        ref.read(completeProfileLoadingProvider.notifier).state = false;
      }
    }
  }

  Future<List<Map<String, String>>?> _showEmergencyContactsSheet() async {
    final contacts = _emergencyContacts.isEmpty
        ? <_SignupEmergencyContact>[_SignupEmergencyContact()]
        : _emergencyContacts.map((contact) => _SignupEmergencyContact.from(contact)).toList();
    final formKey = GlobalKey<FormState>();

    return showModalBottomSheet<List<Map<String, String>>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Container(
                height: MediaQuery.of(context).size.height * 0.9,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text('Emergency Contacts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xff0d47a1))),
                            ),
                            IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close)),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Add at least one trusted person to contact during emergencies. You may add up to three.', style: TextStyle(color: Colors.black54, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          children: [
                            ...List.generate(contacts.length, (index) {
                              final contact = contacts[index];
                              return Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(child: Text('Contact #${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xff0d47a1)))),
                                        if (contacts.length > 1)
                                          IconButton(onPressed: () => setSheetState(() => contacts.removeAt(index)), icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
                                      ],
                                    ),
                                    TextFormField(
                                      initialValue: contact.name,
                                      decoration: const InputDecoration(labelText: 'Full Name'),
                                      validator: (value) => value == null || value.trim().length < 2 ? 'Enter a valid name' : null,
                                      onChanged: (value) => contact.name = value,
                                    ),
                                    const SizedBox(height: 10),
                                    IntlPhoneField(
                                      style: const TextStyle(color: Colors.black87),
                                      dropdownTextStyle: const TextStyle(color: Colors.black87),
                                      decoration: InputDecoration(
                                        hintText: 'Phone Number',
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.grey.shade300),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.grey.shade300),
                                        ),
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
                                    const SizedBox(height: 10),
                                    DropdownButtonFormField<String>(
                                      value: contact.relation,
                                      decoration: const InputDecoration(labelText: 'Relationship'),
                                      items: const ['Parent', 'Guardian', 'Spouse', 'Sibling', 'Friend', 'Other'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                                      onChanged: (value) => setSheetState(() => contact.relation = value ?? 'Parent'),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            if (contacts.length < 3)
                              OutlinedButton.icon(
                                onPressed: () => setSheetState(() => contacts.add(_SignupEmergencyContact())),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Another Contact'),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              if (!formKey.currentState!.validate()) return;
                              if (contacts.any((contact) => !contact.isPhoneValid || contact.phone.isEmpty)) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid phone number for every contact.')));
                                return;
                              }
                              Navigator.pop(sheetContext, contacts.map((contact) => {'name': contact.name.trim(), 'phone': contact.phone.trim(), 'relation': contact.relation}).toList());
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff0d47a1), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15)),
                            child: const Text('Save Emergency Contacts', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _showTermsSheet() async {
    final scrollController = ScrollController();
    bool reachedBottom = false;
    bool accepted = false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            scrollController.addListener(() {
              if (scrollController.hasClients && scrollController.position.pixels >= scrollController.position.maxScrollExtent - 24 && !reachedBottom) {
                setSheetState(() => reachedBottom = true);
              }
            });
            final terms = <String>[
              '1. General\n1.1. These Terms and Conditions govern the access to and use of the AlertU: Mobile and Web Based Disaster Alert and Incident Reporting System (the “system”), including all features, services, and functionalities which are available through its mobile application and web platform.\n\n1.2. By accessing or using the AlertU, the user agrees to be bound by these Terms and Conditions in full. The user\'s personal data shall be collected, processed, and protected in connection with the use of AlertU shall be governed by the Data Privacy Act of 2012 (R.A. No. 10173), its Implementing Rules and Regulations, and other applicable laws.\n\n1.3. For purposes of these Terms, AlertU refers to the Mobile and Web Based Disaster Alert and Incident Reporting System which is developed for the Municipality of Paombong, Bulacan, while our System Administrator refers to the local authorized Municipal Disaster Risk Reduction and Management Office (MDRRMO) personnel for managing, maintaining, and monitoring the system.',
              '2. Basic Terms\n2.1. The App shall be made available to the users which must be at least eighteen (18) years of age or a minor, subject to the requirements below:\n\n• The user must be at least eighteen (18) years of age to register for an account. By registering, the user represents and warrants that the information is factual, complete, and accurate. Users who are at least eighteen (18) years of age have the legal capacity to agree with these Terms and Conditions.\n\n• If the user is below eighteen (18) years old, parental consent or legal guardian consent will be required from them for their use of AlertU. It shall be the parent, legal guardian, or other person exercising parental authority over the minor who allows, authorizes, and consents to the opening of the AlertU account, and who shall be principally responsible over the account. System owners assume no responsibility or liability for any misrepresentation of the user\'s age.',
              '3. Warranties\n3.1. By registering in AlertU, the user warrants that the information provided is factual, complete, and accurate. The user also warrants that they are authorized to create and use their account or, if they are below eighteen (18) years old, they have consent of their parent or legal guardian.\n\n3.2. By providing the requested information for verification of the user\'s account, the user understands and agrees that their personal information will be collected and processed only for legitimate purposes, which includes account verification, incident reporting, emergency notification, and other features of the AlertU System, in accordance with Data Privacy Act of 2012 (Republic Act No. 10173).\n\n3.3. The user also warrants that all information including incident reports, locations, uploaded media, and other information presented through AlertU are factual and accurate to the best of his or her knowledge. Any act of false submission, misleading, malicious, or fraudulent reports is strictly prohibited and may result in suspension or termination of the user\'s account, while also being subjected to the applied laws.',
              '4. Use of the App\nThrough registration and by having access to the AlertU, the user hereby warrants that the App shall only be used for the following purposes:\n\n• Registration and managing an AlertU personal account;\n• Reporting disaster, emergencies, and other incidents within the Municipality of Paombong;\n• Obtaining disaster alerts, and emergency notifications from authorized MDRRMO personnel;\n• Monitoring the status and updates of submitted reports;\n• Accessing other disaster management services and features that may be added to the AlertU System in the future.',
              '5. Restrictions\n5.1. The user is expressly and emphatically restricted from all of the following:\n\n• 5.1.1. Using the AlertU System for any illegal or unlawful activities;\n• 5.1.2. Submission of false, misleading, malicious, or fraudulent reports or information;\n• 5.1.3. Attempting to gain unauthorized access to the System or other user accounts;\n• 5.1.4. Interfering with, damaging, or disrupting the system\'s operation, security, or functionality;\n• 5.1.5. Interfering with or restricting other users\' access to the System;\n• 5.1.6. Engaging in any data mining, data harvesting, data extracting, or any other similar activity;\n• 5.1.7. Using this App on behalf of another person without proper authority;\n• 5.1.8. Failing to keep account credentials confidential and secure.',
              '6. Profile & Privacy\n6.1. All information gathered by the AlertU System shall be treated as confidential under Section 3 of the Data Privacy Act of 2012.\n\n6.2. When required by the AlertU Privacy Notice and applicable laws, the System will secure explicit consent prior to data processing under Sections 12 and 13 of R.A. 10173.\n\n6.3. Personal information is only disclosed to authorized MDRRMO personnel or local government agencies when required by law or legal process.\n\n6.4. Users may request access to, correction of, or deletion of their personal information, subject to operational requirements.',
              '7. Limitation of Liability\n7.1. AlertU does not guarantee that the system will always function without interruption, delay, or error, although reasonable efforts are made to ensure reliability.\n\n7.2. The Municipality of Paombong, System Administrators, and developers are not liable for losses caused by user improper use, inaccurate submissions, or internet disruptions.\n\n7.3. AlertU is a reporting tool and does not replace official emergency response hotlines. Users should contact emergency hotlines directly for immediate assistance.\n\n7.4. Users agree that system owners are not liable for direct, indirect, or consequential damages resulting from breaches of these terms.',
              '8. Update in Terms\nThe System Owners reserve the right to amend or revise these Terms and Conditions at any time. Users are expected to review these terms regularly.',
            ];
            return SafeArea(
              child: Container(
                height: MediaQuery.of(context).size.height * 0.9,
                decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                      child: Row(
                        children: [
                          const Expanded(child: Text('Terms and Conditions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xff0d47a1)))),
                          IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: terms.map((text) => Padding(padding: const EdgeInsets.only(bottom: 18), child: Text(text, style: const TextStyle(color: Colors.black87, fontSize: 13, height: 1.45)))).toList(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Checkbox(value: accepted, onChanged: reachedBottom ? (value) => setSheetState(() => accepted = value ?? false) : null),
                              const Expanded(child: Text('I have fully read and accept all rules written above.', style: TextStyle(fontSize: 13))),
                            ],
                          ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: reachedBottom && accepted ? () => Navigator.pop(sheetContext, true) : null,
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff0d47a1), foregroundColor: Colors.white),
                              child: const Text('Accept Terms & Conditions'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!scrollController.hasClients) {
      scrollController.dispose();
    }
    return result == true;
  }

  Future<void> _openEmergencyContacts() async {
    final result = await _showEmergencyContactsSheet();
    if (!mounted || result == null) return;
    setState(() {
      _emergencyContacts
        ..clear()
        ..addAll(result.map(_SignupEmergencyContact.fromMap));
      _contactsCompleted = true;
    });
  }

  Future<void> _openTerms() async {
    final accepted = await _showTermsSheet();
    if (mounted && accepted) setState(() => _isDpaAccepted = true);
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(completeProfileLoadingProvider);

    return Theme(
      data: ThemeData.light().copyWith(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Color(0xff0d47a1),
          surface: Colors.white,
          onSurface: Colors.black87,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: TextStyle(color: Colors.grey.shade500),
          labelStyle: const TextStyle(color: Colors.black87),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xff0d47a1), width: 1.5),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Color(0xff0d47a1)),
        ),
        body: SafeArea(
          child: isLoading
              ? const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xff0d47a1)),
            ),
          )
              : LayoutBuilder(
            builder: (context, constraints) {
              double horizontalPadding = constraints.maxWidth > 600 ? 40.0 : 24.0;

              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Create Account',
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xff0d47a1)),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: name,
                            style: const TextStyle(color: Colors.black87),
                            decoration: const InputDecoration(hintText: 'Full Name'),
                            validator: (v) => (v == null || v.trim().length < 2) ? 'Provide a valid name' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: email,
                            readOnly: true,
                            showCursor: false,
                            style: const TextStyle(color: Colors.black87),
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              hintText: 'Email Address',
                              prefixIcon: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Image.asset('images/emailicon.png', height: 20, width: 20),
                              ),
                            ),
                            validator: (v) => (v == null || !v.contains('@')) ? 'Provide a valid email address' : null,
                          ),
                          const SizedBox(height: 14),
                          IntlPhoneField(
                            style: const TextStyle(color: Colors.black87),
                            dropdownTextStyle: const TextStyle(color: Colors.black87),
                            decoration: InputDecoration(
                              hintText: 'Phone Number',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Colors.grey.shade300),
                              ),
                            ),
                            initialCountryCode: 'PH',
                            onChanged: (phone) {
                              completePhoneNumber = phone.completeNumber;
                              try {
                                _isPhoneValid = phone.isValidNumber();
                              } catch (_) {
                                _isPhoneValid = false;
                              }
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: address,
                            style: const TextStyle(color: Colors.black87),
                            decoration: const InputDecoration(hintText: 'Home Address'),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Home address is required' : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: password,
                            style: const TextStyle(color: Colors.black87),
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              hintText: 'Password',
                              prefixIcon: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Image.asset('images/passwordicon.png', height: 20, width: 20),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: const Color(0xff0d47a1)),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Password cannot be empty';
                              if (v.length < 15) return 'Password must be at least 15 characters total';
                              final uppercaseCount = v.replaceAll(RegExp(r'[^A-Z]'), '').length;
                              if (uppercaseCount != 1) return 'Must contain exactly 1 uppercase letter';
                              final specialCharCount = v.replaceAll(RegExp(r'[a-zA-Z0-9\s]'), '').length;
                              if (specialCharCount != 1) return 'Must contain exactly 1 special character';
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Password Strength:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text(
                                    _strengthText,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _strengthColor),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: _strengthProgress,
                                backgroundColor: Colors.grey.shade200,
                                valueColor: AlwaysStoppedAnimation<Color>(_strengthColor),
                                minHeight: 5,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: confirmPassword,
                            style: const TextStyle(color: Colors.black87),
                            obscureText: _obscureConfirmPassword,
                            decoration: InputDecoration(
                              hintText: 'Confirm Password',
                              prefixIcon: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Image.asset('images/passwordicon.png', height: 20, width: 20),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: const Color(0xff0d47a1)),
                                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Please confirm your password';
                              if (v != password.text) return 'Passwords do not match';
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: isLoading ? null : _openEmergencyContacts,
                            icon: Icon(_contactsCompleted ? Icons.check_circle : Icons.contact_phone_outlined),
                            label: Text(_contactsCompleted ? 'Emergency Contacts Saved' : 'Add Emergency Contacts (Required)'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _contactsCompleted ? Colors.green.shade700 : const Color(0xff0d47a1),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: _contactsCompleted ? Colors.green.shade700 : const Color(0xff0d47a1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FormField<bool>(
                            initialValue: _isDpaAccepted,
                            validator: (_) => _isDpaAccepted ? null : 'Required',
                            builder: (formFieldState) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(value: _isDpaAccepted, onChanged: isLoading ? null : (_) => _openTerms()),
                                      const Expanded(child: Text('I agree to the Terms and Conditions and data privacy requirements.', style: TextStyle(color: Colors.black87, fontSize: 13))),
                                      IconButton(onPressed: isLoading ? null : _openTerms, icon: const Icon(Icons.open_in_new, color: Color(0xff0d47a1)), tooltip: 'Read Terms and Conditions'),
                                    ],
                                  ),
                                  if (formFieldState.hasError)
                                    Padding(padding: const EdgeInsets.only(left: 12), child: Text(formFieldState.errorText ?? '', style: TextStyle(color: Colors.red.shade700, fontSize: 12))),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 28),
                          ElevatedButton(
                            onPressed: saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xff0d47a1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              "Finish Setup",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton(
                            onPressed: () => FirebaseAuth.instance.signOut(),
                            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SignupEmergencyContact {
  String name = '';
  String phone = '';
  String relation = 'Parent';
  bool isPhoneValid = false;

  _SignupEmergencyContact();

  _SignupEmergencyContact.from(_SignupEmergencyContact other)
      : name = other.name,
        phone = other.phone,
        relation = other.relation,
        isPhoneValid = other.isPhoneValid;

  _SignupEmergencyContact.fromMap(Map<String, String> data)
      : name = data['name'] ?? '',
        phone = data['phone'] ?? '',
        relation = data['relation'] ?? 'Parent',
        isPhoneValid = true;
}