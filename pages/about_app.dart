import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AboutAppPage extends StatelessWidget {
  const AboutAppPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Dynamic Theme Colors
    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xff0d47a1);
    final bgCanvas = isDark ? theme.colorScheme.surface : const Color(0xfff8fafc);
    final textDark = isDark ? theme.colorScheme.onSurface : const Color(0xff0f172a);
    final textMuted = isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xff64748b);
    final cardBg = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final borderColor = isDark ? Colors.white12 : const Color(0xffe2e8f0);

    return Scaffold(
      backgroundColor: bgCanvas,
      appBar: AppBar(
        title: Text(
          'About App',
          style: GoogleFonts.roboto(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: textDark,
          ),
        ),
        backgroundColor: cardBg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textDark),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: borderColor, height: 1.0),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- 1. BRANDING HEADER ---
                  _buildBrandingHeader(context),

                  const SizedBox(height: 24),

                  // --- 2. CORE PURPOSE / ABOUT CARD ---
                  _buildSectionCard(
                    context: context,
                    title: "About AlertU",
                    icon: LucideIcons.info,
                    child: Text(
                      "AlertU is a disaster risk and incident reporting system designed to connect communities with emergency responders in real time. Our goal is to help citizens report incidents quickly, track local safety updates, and access immediate help during emergencies.",
                      style: GoogleFonts.roboto(
                        fontSize: 14,
                        color: isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xff334155),
                        height: 1.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- 3. KEY FEATURES OVERVIEW ---
                  _buildSectionCard(
                    context: context,
                    title: "Key Features",
                    icon: LucideIcons.sparkles,
                    child: Column(
                      children: const [
                        _FeatureItem(
                          icon: LucideIcons.camera,
                          title: "Instant Incident Reporting",
                          subtitle: "Submit real-time photo evidence and descriptions.",
                        ),
                        _FeatureItem(
                          icon: LucideIcons.mapPin,
                          title: "Live Incident Map",
                          subtitle: "View active local hazards and verified reports.",
                        ),
                        _FeatureItem(
                          icon: LucideIcons.siren,
                          title: "SOS & Direct Call",
                          subtitle: "Send your live location to emergency contacts or contact admins immediately.",
                        ),
                        _FeatureItem(
                          icon: LucideIcons.bellRing,
                          title: "Real-time Alerts",
                          subtitle: "Stay informed on report approvals, status updates, and emergency warnings.",
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- 4. TECHNICAL / EMERGENCY DETAILS ---
                  _buildSectionCard(
                    context: context,
                    title: "Emergency & System Details",
                    icon: LucideIcons.shieldCheck,
                    child: Column(
                      children: [
                        _buildDetailRow(
                          context: context,
                          icon: LucideIcons.phoneCall,
                          label: "Emergency Hotline",
                          value: "MDRRMO Paombong Direct Hotline",
                        ),
                        Divider(height: 20, color: borderColor),
                        _buildDetailRow(
                          context: context,
                          icon: LucideIcons.activity,
                          label: "System Status",
                          value: "Servers Operational • Online",
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- 5. LEGAL & SAFETY GUIDELINES ---
                  _buildSectionCard(
                    context: context,
                    title: "Legal & Responsible Use",
                    icon: LucideIcons.scale,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Responsible Reporting Notice
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xff422006) : const Color(0xfffffbe2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isDark ? const Color(0xff854d0e) : const Color(0xfffde047)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.triangleAlert,
                                color: isDark ? const Color(0xfffde047) : const Color(0xffa16207),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Notice: Submitting false or fake emergency reports is strictly prohibited and subject to legal action.",
                                  style: GoogleFonts.roboto(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? const Color(0xfffef08a) : const Color(0xff854d0e),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Button to open Terms Modal
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            side: BorderSide(color: primaryColor, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Icon(LucideIcons.fileText, color: primaryColor, size: 18),
                          label: Text(
                            "View Terms of Service & Privacy Policy",
                            style: GoogleFonts.roboto(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                          onPressed: () => _showTermsModal(context),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Footer Copyright
                  Center(
                    child: Text(
                      "© 2026 MDRRMO • Municipality of Paombong, Bulacan",
                      style: GoogleFonts.roboto(
                        fontSize: 11,
                        color: textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- BRANDING HEADER WIDGET ---
  Widget _buildBrandingHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xff0d47a1);
    final cardBg = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final textDark = isDark ? theme.colorScheme.onSurface : const Color(0xff0f172a);
    final textMuted = isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xff64748b);
    final borderColor = isDark ? Colors.white12 : const Color(0xffe2e8f0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('images/logo1.png', height: 80, width: 80, fit: BoxFit.contain),
              const SizedBox(width: 8),
              Image.asset('images/AlertU.png', height: 80, width: 80, fit: BoxFit.contain),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "AlertU",
            style: GoogleFonts.roboto(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: textDark,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "Version 1.0.0",
              style: GoogleFonts.roboto(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Fast, Reliable Disaster Risk & Incident Reporting",
            textAlign: TextAlign.center,
            style: GoogleFonts.roboto(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textMuted,
            ),
          ),
        ],
      ),
    );
  }

  // --- SECTION CARD HELPER ---
  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xff0d47a1);
    final cardBg = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final textDark = isDark ? theme.colorScheme.onSurface : const Color(0xff0f172a);
    final borderColor = isDark ? Colors.white12 : const Color(0xffe2e8f0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.2) : Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.roboto(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // --- DETAIL ROW HELPER ---
  Widget _buildDetailRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final textDark = isDark ? theme.colorScheme.onSurface : const Color(0xff0f172a);
    final textMuted = isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xff64748b);

    return Row(
      children: [
        Icon(icon, size: 20, color: textMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.roboto(fontSize: 12, color: textMuted, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.roboto(fontSize: 13, fontWeight: FontWeight.w600, color: textDark),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- TERMS AND CONDITIONS MODAL BOTTOM SHEET ---
  void _showTermsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return const _TermsModalSheet();
      },
    );
  }
}

// --- FEATURE ITEM WIDGET ---
class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xff0d47a1);
    final iconBg = isDark ? theme.colorScheme.surfaceContainerHighest : const Color(0xfff1f5f9);
    final titleColor = isDark ? theme.colorScheme.onSurface : const Color(0xff0f172a);
    final subtitleColor = isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xff64748b);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.roboto(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.roboto(
                    fontSize: 12,
                    color: subtitleColor,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- FULL TERMS & CONDITIONS MODAL SHEET ---
class _TermsModalSheet extends StatefulWidget {
  const _TermsModalSheet();

  @override
  State<_TermsModalSheet> createState() => _TermsModalSheetState();
}

class _TermsModalSheetState extends State<_TermsModalSheet> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xff0d47a1);
    final modalBg = isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white;
    final textDark = isDark ? theme.colorScheme.onSurface : const Color(0xff0f172a);
    final borderColor = isDark ? Colors.white12 : const Color(0xffe2e8f0);
    final handleColor = isDark ? Colors.grey.shade700 : Colors.grey.shade300;

    final double screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.88,
      decoration: BoxDecoration(
        color: modalBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle & Header
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Terms of Service & Privacy',
                  style: GoogleFonts.roboto(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: textDark,
                  ),
                ),
                IconButton(
                  icon: Icon(LucideIcons.x, size: 20, color: textDark),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: borderColor),

          // Exact Scrollable Terms Text
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('1. General', primaryColor),
                  _buildParagraph(
                      '1.1. These Terms and Conditions govern the access to and use of the AlertU: Mobile and Web Based Disaster Alert and Incident Reporting System (the “system”), including all features, services, and functionalities which are available through its mobile application and web platform.',
                      context),
                  _buildParagraph(
                      '1.2. By accessing or using the AlertU, the user agrees to be bound by these Terms and Conditions in full. The user\'s personal data shall be collected, processed, and protected in connection with the use of AlertU shall be governed by the Data Privacy Act of 2012 (R.A. No. 10173), its Implementing Rules and Regulations, and other applicable laws.',
                      context),
                  _buildParagraph(
                      '1.3. For purposes of these Terms, AlertU refers to the Mobile and Web Based Disaster Alert and Incident Reporting System which is developed for the Municipality of Paombong, Bulacan, while our System Administrator refers to the local authorized Municipal Disaster Risk Reduction and Management Office (MDRRMO) personnel for managing, maintaining, and monitoring the system.',
                      context),

                  _buildSectionHeader('2. Basic Terms', primaryColor),
                  _buildParagraph(
                      '2.1. The App shall be made available to the users which must be at least eighteen (18) years of age or a minor, subject to the requirements below:\n\n'
                          '• The user must be at least eighteen (18) years of age to register for an account. By registering, the user represents and warrants that the information is factual, complete, and accurate. Users who are at least eighteen (18) years of age have the legal capacity to agree with these Terms and Conditions.\n\n'
                          '• If the user is below eighteen (18) years old, parental consent or legal guardian consent will be required from them for their use of AlertU. It shall be the parent, legal guardian, or other person exercising parental authority over the minor who allows, authorizes, and consents to the opening of the AlertU account, and who shall be principally responsible over the account. System owners assume no responsibility or liability for any misrepresentation of the user\'s age.',
                      context),

                  _buildSectionHeader('3. Warranties', primaryColor),
                  _buildParagraph(
                      '3.1. By registering in AlertU, the user warrants that the information provided is factual, complete, and accurate. The user also warrants that they are authorized to create and use their account or, if they are below eighteen (18) years old, they have consent of their parent or legal guardian.',
                      context),
                  _buildParagraph(
                      '3.2. By providing the requested information for verification of the user\'s account, the user understands and agrees that their personal information will be collected and processed only for legitimate purposes, which includes account verification, incident reporting, emergency notification, and other features of the AlertU System, in accordance with Data Privacy Act of 2012 (Republic Act No. 10173).',
                      context),
                  _buildParagraph(
                      '3.3. The user also warrants that all information including incident reports, locations, uploaded media, and other information presented through AlertU are factual and accurate to the best of his or her knowledge. Any act of false submission, misleading, malicious, or fraudulent reports is strictly prohibited and may result in suspension or termination of the user\'s account, while also being subjected to the applied laws.',
                      context),

                  _buildSectionHeader('4. Use of the App', primaryColor),
                  _buildParagraph(
                      'Through registration and by having access to the AlertU, the user hereby warrants that the App shall only be used for the following purposes:\n\n'
                          '• Registration and managing an AlertU personal account;\n'
                          '• Reporting disaster, emergencies, and other incidents within the Municipality of Paombong;\n'
                          '• Obtaining disaster alerts, and emergency notifications from authorized MDRRMO personnel;\n'
                          '• Monitoring the status and updates of submitted reports;\n'
                          '• Accessing other disaster management services and features that may be added to the AlertU System in the future.',
                      context),

                  _buildSectionHeader('5. Restrictions', primaryColor),
                  _buildParagraph(
                      '5.1. The user is expressly and emphatically restricted from all of the following:\n\n'
                          '• 5.1.1. Using the AlertU System for any illegal or unlawful activities;\n'
                          '• 5.1.2. Submission of false, misleading, malicious, or fraudulent reports or information;\n'
                          '• 5.1.3. Attempting to gain unauthorized access to the System or other user accounts;\n'
                          '• 5.1.4. Interfering with, damaging, or disrupting the system\'s operation, security, or functionality;\n'
                          '• 5.1.5. Interfering with or restricting other users\' access to the System;\n'
                          '• 5.1.6. Engaging in any data mining, data harvesting, data extracting, or any other similar activity;\n'
                          '• 5.1.7. Using this App on behalf of another person without proper authority;\n'
                          '• 5.1.8. Failing to keep account credentials confidential and secure.',
                      context),

                  _buildSectionHeader('6. Profile & Privacy', primaryColor),
                  _buildParagraph(
                      '6.1. All information gathered by the AlertU System shall be treated as confidential under Section 3 of the Data Privacy Act of 2012.',
                      context),
                  _buildParagraph(
                      '6.2. When required by the AlertU Privacy Notice and applicable laws, the System will secure explicit consent prior to data processing under Sections 12 and 13 of R.A. 10173.',
                      context),
                  _buildParagraph(
                      '6.3. Personal information is only disclosed to authorized MDRRMO personnel or local government agencies when required by law or legal process.',
                      context),
                  _buildParagraph(
                      '6.4. Users may request access to, correction of, or deletion of their personal information, subject to operational requirements.',
                      context),

                  _buildSectionHeader('7. Limitation of Liability', primaryColor),
                  _buildParagraph(
                      '7.1. AlertU does not guarantee that the system will always function without interruption, delay, or error, although reasonable efforts are made to ensure reliability.',
                      context),
                  _buildParagraph(
                      '7.2. The Municipality of Paombong, System Administrators, and developers are not liable for losses caused by user improper use, inaccurate submissions, or internet disruptions.',
                      context),
                  _buildParagraph(
                      '7.3. AlertU is a reporting tool and does not replace official emergency response hotlines. Users should contact emergency hotlines directly for immediate assistance.',
                      context),
                  _buildParagraph(
                      '7.4. Users agree that system owners are not liable for direct, indirect, or consequential damages resulting from breaches of these terms.',
                      context),

                  _buildSectionHeader('8. Update in Terms', primaryColor),
                  _buildParagraph(
                      'The System Owners reserve the right to amend or revise these Terms and Conditions at any time. Users are expected to review these terms regularly.',
                      context),
                ],
              ),
            ),
          ),

          // Close Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Close',
                  style: GoogleFonts.roboto(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 6.0),
      child: Text(
        title,
        style: GoogleFonts.roboto(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: primaryColor,
        ),
      ),
    );
  }

  Widget _buildParagraph(String text, BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final paragraphColor = isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xff334155);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: GoogleFonts.roboto(
          fontSize: 13,
          color: paragraphColor,
          height: 1.5,
        ),
      ),
    );
  }
}