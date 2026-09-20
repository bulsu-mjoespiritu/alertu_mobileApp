import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:google_fonts/google_fonts.dart';

import 'homepage.dart';
import 'splash_screen.dart';

class TermsAndConditionsScreen extends StatefulWidget {
  final String? fullName;
  final String? phoneNumber;
  final String? zone;

  const TermsAndConditionsScreen({
    super.key,
    this.fullName,
    this.phoneNumber,
    this.zone,
  });

  @override
  State<TermsAndConditionsScreen> createState() => _TermsAndConditionsScreenState();
}

class _TermsAndConditionsScreenState extends State<TermsAndConditionsScreen> {
  final Color primaryColor = const Color(0xff0d47a1);
  final ScrollController _scrollController = ScrollController();

  bool _hasScrolledToBottom = false;
  bool _isCheckboxChecked = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 30) {
        if (!_hasScrolledToBottom) {
          setState(() {
            _hasScrolledToBottom = true;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }

  /// Atomically increments the counters/citizens counter document in Firestore
  /// Guarantees formatted output: CID00000001, CID00000002, etc.
  Future<String> _getNextCitizenID() async {
    final counterRef = FirebaseFirestore.instance.collection('counters').doc('citizens');

    return FirebaseFirestore.instance.runTransaction((transaction) async {
      final counterDoc = await transaction.get(counterRef);

      int currentCount = 0;

      if (counterDoc.exists && counterDoc.data() != null) {
        final data = counterDoc.data()!;

        // Checks both 'currentCount' and 'count' in case your React backend uses 'count'
        if (data.containsKey('currentCount')) {
          currentCount = (data['currentCount'] as num).toInt();
        } else if (data.containsKey('count')) {
          currentCount = (data['count'] as num).toInt();
        }
      }

      final nextCount = currentCount + 1;
      final formattedID = 'CID${nextCount.toString().padLeft(8, '0')}';

      if (counterDoc.exists) {
        // Use update for existing documents to prevent total document structure resets
        transaction.update(counterRef, {
          'currentCount': nextCount,
          'count': nextCount, // Keeps sync compatibility if React uses 'count'
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Create document if it doesn't exist
        transaction.set(counterRef, {
          'currentCount': nextCount,
          'count': nextCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return formattedID;
    });
  }

  /// Writes or updates user citizen profile record into Firestore
  Future<bool> _saveUserToFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      await user.reload();

      final citizenRef = FirebaseFirestore.instance.collection('citizens').doc(user.uid);
      final existingDoc = await citizenRef.get();

      // CASE 1: Document already exists -> Just update terms/DPA and active flags
      if (existingDoc.exists) {
        await citizenRef.update({
          'dpaAccepted': true,
          'termsAcceptedAt': FieldValue.serverTimestamp(),
          'isActive': true,
          'lastActiveAt': FieldValue.serverTimestamp(),
        });

        return true;
      }

      // CASE 2: Document does NOT exist in 'citizens' -> Check 'admin_citizens' for pre-assigned ID
      String citizenID = '';

      final adminQuery = await FirebaseFirestore.instance
          .collection('admin_citizens')
          .where('authUid', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (adminQuery.docs.isNotEmpty) {
        final adminData = adminQuery.docs.first.data();
        final rawAdminID = adminData['citizenID']?.toString() ?? '';
        if (RegExp(r'^CID\d{8}$').hasMatch(rawAdminID)) {
          citizenID = rawAdminID;
        }
      }

      // CASE 3: Brand new user -> Generate next sequential Citizen ID
      if (citizenID.isEmpty) {
        citizenID = await _getNextCitizenID();
      }

      // Unpack raw string if passed in concatenated format ("Name||Phone||Zone")
      String parsedName = widget.fullName ?? user.displayName ?? 'No Name Provided';
      String parsedPhone = widget.phoneNumber ?? user.phoneNumber ?? '';
      String parsedZone = widget.zone ?? 'Global / Unassigned';

      if (parsedName.contains('||')) {
        final parts = parsedName.split('||');
        if (parts.isNotEmpty) parsedName = parts[0].trim();
        if (parts.length > 1 && parts[1].trim().isNotEmpty) {
          parsedPhone = parts[1].trim();
        }
        if (parts.length > 2 && parts[2].trim().isNotEmpty) {
          parsedZone = parts[2].trim();
        }
      }

      if (parsedPhone.isEmpty) {
        parsedPhone = user.phoneNumber ?? 'No Phone Record';
      }

      final email = user.email ?? 'N/A';

      // Create new Citizen Document
      await citizenRef.set({
        'citizenID': citizenID,
        'authUid': user.uid,
        'fullName': parsedName,
        'email': email,
        'phoneNumber': parsedPhone,
        'zone': parsedZone,
        'status': 'Active',
        'isActive': true,
        'isDisabled': false,
        'isArchived': false,
        'dpaAccepted': true,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      debugPrint("Error writing profile to Firestore: $e");
      return false;
    }
  }

  Future<void> _handleAcceptTerms() async {
    if (!_hasScrolledToBottom || !_isCheckboxChecked || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    // 1. Await Firestore profile creation before navigating
    final success = await _saveUserToFirestore();

    if (!mounted) return;

    if (!success) {
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to complete registration. Please check your network connection.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 2. Transition to Homepage via Splash Screen
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const AnimatedSplashScreen(
          destination: Homepage(),
        ),
      ),
          (route) => false,
    );
  }

  Future<void> _handleDeclineAndExit() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => FTheme(
        data: FTheme.neutral.light.touch,
        child: Theme(
          data: ThemeData.light().copyWith(
            scaffoldBackgroundColor: const Color(0xfff8fafc),
            colorScheme: const ColorScheme.light(
              primary: Color(0xff0d47a1),
              surface: Colors.white,
              onSurface: Color(0xff0f172a),
            ),
          ),
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              'Decline Terms?',
              style: GoogleFonts.roboto(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: const Color(0xff0f172a),
              ),
            ),
            content: Text(
              'Declining the terms will permanently remove your registration profile and terminate the application setup session. Proceed?',
              style: GoogleFonts.roboto(
                color: const Color(0xff334155),
                height: 1.5,
                fontSize: 14,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.roboto(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  try {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user != null) {
                      // Mark offline status prior to deletion if record exists
                      await FirebaseFirestore.instance
                          .collection('citizens')
                          .doc(user.uid)
                          .set({'isActive': false}, SetOptions(merge: true));

                      await user.delete();
                    }
                  } catch (e) {
                    debugPrint("Error dropping user record: $e");
                  } finally {
                    await FirebaseAuth.instance.signOut();
                    if (mounted) {
                      await SystemNavigator.pop();
                    }
                  }
                },
                child: Text(
                  'Delete & Exit',
                  style: GoogleFonts.roboto(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isButtonEnabled = _hasScrolledToBottom && _isCheckboxChecked && !_isProcessing;

    return FTheme(
      data: FTheme.neutral.light.touch,
      child: Theme(
        data: ThemeData.light().copyWith(
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xfff8fafc),
          colorScheme: ColorScheme.light(
            primary: primaryColor,
            surface: Colors.white,
            onSurface: const Color(0xff0f172a),
          ),
        ),
        child: Scaffold(
          backgroundColor: const Color(0xfff8fafc),
          appBar: AppBar(
            title: Text(
              'Terms of Service',
              style: GoogleFonts.roboto(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: const Color(0xff0f172a),
              ),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            automaticallyImplyLeading: false,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1.0),
              child: Container(color: const Color(0xffe2e8f0), height: 1.0),
            ),
          ),
          body: SafeArea(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Header Card
                    FCard(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Image.asset(
                              'images/logo1.png',
                              width: 48,
                              height: 48,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AlertU Platform Policy',
                                    style: GoogleFonts.roboto(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xff0f172a),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'MDRRMO • Municipality of Paombong, Bulacan',
                                    style: GoogleFonts.roboto(
                                      fontSize: 12,
                                      color: const Color(0xff64748b),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Scrollable Document Box
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xffe2e8f0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          radius: const Radius.circular(6),
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionHeader('1. General'),
                                  _buildParagraph(
                                      '1.1. These Terms and Conditions govern the access to and use of the AlertU: Mobile and Web Based Disaster Alert and Incident Reporting System (the “system”), including all features, services, and functionalities which are available through its mobile application and web platform.'),
                                  _buildParagraph(
                                      '1.2. By accessing or using the AlertU, the user agrees to be bound by these Terms and Conditions in full. The user\'s personal data shall be collected, processed, and protected in connection with the use of AlertU shall be governed by the Data Privacy Act of 2012 (R.A. No. 10173), its Implementing Rules and Regulations, and other applicable laws.'),
                                  _buildParagraph(
                                      '1.3. For purposes of these Terms, AlertU refers to the Mobile and Web Based Disaster Alert and Incident Reporting System which is developed for the Municipality of Paombong, Bulacan, while our System Administrator refers to the local authorized Municipal Disaster Risk Reduction and Management Office (MDRRMO) personnel for managing, maintaining, and monitoring the system.'),

                                  _buildSectionHeader('2. Basic Terms'),
                                  _buildParagraph(
                                      '2.1. The App shall be made available to the users which must be at least eighteen (18) years of age or a minor, subject to the requirements below:\n\n'
                                          '• The user must be at least eighteen (18) years of age to register for an account. By registering, the user represents and warrants that the information is factual, complete, and accurate. Users who are at least eighteen (18) years of age have the legal capacity to agree with these Terms and Conditions.\n\n'
                                          '• If the user is below eighteen (18) years old, parental consent or legal guardian consent will be required from them for their use of AlertU. It shall be the parent, legal guardian, or other person exercising parental authority over the minor who allows, authorizes, and consents to the opening of the AlertU account, and who shall be principally responsible over the account. System owners assume no responsibility or liability for any misrepresentation of the user\'s age.'),

                                  _buildSectionHeader('3. Warranties'),
                                  _buildParagraph(
                                      '3.1. By registering in AlertU, the user warrants that the information provided is factual, complete, and accurate. The user also warrants that they are authorized to create and use their account or, if they are below eighteen (18) years old, they have consent of their parent or legal guardian.'),
                                  _buildParagraph(
                                      '3.2. By providing the requested information for verification of the user\'s account, the user understands and agrees that their personal information will be collected and processed only for legitimate purposes, which includes account verification, incident reporting, emergency notification, and other features of the AlertU System, in accordance with Data Privacy Act of 2012 (Republic Act No. 10173).'),
                                  _buildParagraph(
                                      '3.3. The user also warrants that all information including incident reports, locations, uploaded media, and other information presented through AlertU are factual and accurate to the best of his or her knowledge. Any act of false submission, misleading, malicious, or fraudulent reports is strictly prohibited and may result in suspension or termination of the user\'s account, while also being subjected to the applied laws.'),

                                  _buildSectionHeader('4. Use of the App'),
                                  _buildParagraph(
                                      'Through registration and by having access to the AlertU, the user hereby warrants that the App shall only be used for the following purposes:\n\n'
                                          '• Registration and managing an AlertU personal account;\n'
                                          '• Reporting disaster, emergencies, and other incidents within the Municipality of Paombong;\n'
                                          '• Obtaining disaster alerts, and emergency notifications from authorized MDRRMO personnel;\n'
                                          '• Monitoring the status and updates of submitted reports;\n'
                                          '• Accessing other disaster management services and features that may be added to the AlertU System in the future.'),

                                  _buildSectionHeader('5. Restrictions'),
                                  _buildParagraph(
                                      '5.1. The user is expressly and emphatically restricted from all of the following:\n\n'
                                          '• 5.1.1. Using the AlertU System for any illegal or unlawful activities;\n'
                                          '• 5.1.2. Submission of false, misleading, malicious, or fraudulent reports or information;\n'
                                          '• 5.1.3. Attempting to gain unauthorized access to the System or other user accounts;\n'
                                          '• 5.1.4. Interfering with, damaging, or disrupting the system\'s operation, security, or functionality;\n'
                                          '• 5.1.5. Interfering with or restricting other users\' access to the System;\n'
                                          '• 5.1.6. Engaging in any data mining, data harvesting, data extracting, or any other similar activity;\n'
                                          '• 5.1.7. Using this App on behalf of another person without proper authority;\n'
                                          '• 5.1.8. Failing to keep account credentials confidential and secure.'),

                                  _buildSectionHeader('6. Profile & Privacy'),
                                  _buildParagraph(
                                      '6.1. All information gathered by the AlertU System shall be treated as confidential under Section 3 of the Data Privacy Act of 2012.'),
                                  _buildParagraph(
                                      '6.2. When required by the AlertU Privacy Notice and applicable laws, the System will secure explicit consent prior to data processing under Sections 12 and 13 of R.A. 10173.'),
                                  _buildParagraph(
                                      '6.3. Personal information is only disclosed to authorized MDRRMO personnel or local government agencies when required by law or legal process.'),
                                  _buildParagraph(
                                      '6.4. Users may request access to, correction of, or deletion of their personal information, subject to operational requirements.'),

                                  _buildSectionHeader('7. Limitation of Liability'),
                                  _buildParagraph(
                                      '7.1. AlertU does not guarantee that the system will always function without interruption, delay, or error, although reasonable efforts are made to ensure reliability.'),
                                  _buildParagraph(
                                      '7.2. The Municipality of Paombong, System Administrators, and developers are not liable for losses caused by user improper use, inaccurate submissions, or internet disruptions.'),
                                  _buildParagraph(
                                      '7.3. AlertU is a reporting tool and does not replace official emergency response hotlines. Users should contact emergency hotlines directly for immediate assistance.'),
                                  _buildParagraph(
                                      '7.4. Users agree that system owners are not liable for direct, indirect, or consequential damages resulting from breaches of these terms.'),

                                  _buildSectionHeader('8. Update in Terms'),
                                  _buildParagraph(
                                      'The System Owners reserve the right to amend or revise these Terms and Conditions at any time. Users are expected to review these terms regularly.'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    if (!_hasScrolledToBottom)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.arrow_downward_rounded, size: 14, color: Color(0xff64748b)),
                            const SizedBox(width: 6),
                            Text(
                              'Please scroll to the bottom to unlock agreement',
                              style: GoogleFonts.roboto(
                                fontSize: 12,
                                color: const Color(0xff64748b),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Checkbox Row
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          FCheckbox(
                            value: _isCheckboxChecked,
                            onChange: (_hasScrolledToBottom && !_isProcessing)
                                ? (bool value) {
                              setState(() {
                                _isCheckboxChecked = value;
                              });
                            }
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'I have fully read and accept all rules written above.',
                              style: GoogleFonts.roboto(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _hasScrolledToBottom ? const Color(0xff0f172a) : Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Action Buttons
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            disabledBackgroundColor: primaryColor.withOpacity(0.5),
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white.withOpacity(0.8),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: isButtonEnabled ? _handleAcceptTerms : null,
                          child: _isProcessing
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : Text(
                            'I Agree & Continue',
                            style: GoogleFonts.roboto(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FButton(
                          variant: FButtonVariant.outline,
                          onPress: _isProcessing ? null : _handleDeclineAndExit,
                          child: Text(
                            'Decline & Terminate Account',
                            style: GoogleFonts.roboto(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18.0, bottom: 6.0),
      child: Text(
        title,
        style: GoogleFonts.roboto(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: primaryColor,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: GoogleFonts.roboto(
          fontSize: 13,
          color: const Color(0xff334155),
          height: 1.5,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}