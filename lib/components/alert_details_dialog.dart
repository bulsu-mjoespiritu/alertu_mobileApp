import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Everything the "Alert Details" card needs, in a shape that is safe to
/// store as JSON.
///
/// Alerts sent from the admin dashboard's Alerts tab live in the Firestore
/// `alerts` collection. A raw document can't be persisted with the
/// notification (it holds Firestore `Timestamp`s, which `jsonEncode` can't
/// handle), so [AlertDetails.compactFromFirestore] boils it down to plain
/// strings first. That compact map is what gets saved on
/// `NotificationItem.alertData`.
class AlertDetails {
  final String title;
  final String message;

  /// Raw status from the alert document ("active", "cancelled", ...).
  final String status;
  final String type;
  final String targetLocation;
  final String audienceScope;

  /// Already formatted, e.g. "15,000 recipients". Empty when unknown.
  final String recipients;

  /// Already formatted, e.g. "1 Hour". Empty when unknown.
  final String expiresIn;

  /// ISO-8601 expiry, used to flip the badge to "expired" once it passes.
  final String? expiresAt;

  const AlertDetails({
    required this.title,
    required this.message,
    this.status = 'active',
    this.type = 'General',
    this.targetLocation = 'All Barangays',
    this.audienceScope = '',
    this.recipients = '',
    this.expiresIn = '',
    this.expiresAt,
  });

  // ---------------------------------------------------------------------
  // FIELD NAMES
  //
  // The admin dashboard's alert document is the source of truth. Only
  // title / message / status / expiresAt / recipientScope / barangays /
  // createdAt are known for certain (the Notifications page already reads
  // them). The rest are best guesses at what the admin side calls them --
  // if a value shows up as "—" in the card, add the real Firestore field
  // name to the matching list below.
  // ---------------------------------------------------------------------
  static const _typeKeys = ['type', 'alertType', 'category'];
  static const _locationKeys = ['targetLocation', 'location'];
  static const _audienceKeys = [
    'audienceScope',
    'audience',
    'targetAudience',
    'recipientType',
  ];
  static const _recipientKeys = [
    'recipientCount',
    'recipientsCount',
    'totalRecipients',
    'recipients',
  ];
  static const _expiresInKeys = [
    'expiresInLabel',
    'expiresIn',
    'expiryLabel',
    'duration',
  ];

  /// Builds the JSON-safe map stored on the notification from a raw alert
  /// document (or a socket payload carrying the same fields).
  static Map<String, dynamic> compactFromFirestore(
    Map<String, dynamic> raw,
    String alertId,
  ) {
    String? firstText(List<String> keys) {
      for (final key in keys) {
        final value = raw[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    }

    // Target location: an explicit field wins, then a "Specific
    // barangays" selection, otherwise the alert went to everyone.
    String targetLocation =
        firstText(_locationKeys) ?? 'All Barangays';
    final scope = raw['recipientScope']?.toString() ?? '';
    final barangays = raw['barangays'];
    if (firstText(_locationKeys) == null &&
        scope.contains('Specific') &&
        barangays is List &&
        barangays.isNotEmpty) {
      targetLocation = barangays.map((b) => b.toString()).join(', ');
    }

    // Recipients: number, numeric string, or a list of recipients.
    String recipients = '';
    for (final key in _recipientKeys) {
      final value = raw[key];
      int? count;
      if (value is num) {
        count = value.toInt();
      } else if (value is List) {
        count = value.length;
      } else if (value is String) {
        count = int.tryParse(value.replaceAll(',', '').trim());
        if (count == null && value.trim().isNotEmpty) {
          recipients = value.trim();
          break;
        }
      }
      if (count != null) {
        recipients = '${_thousands(count)} recipient${count == 1 ? '' : 's'}';
        break;
      }
    }

    final createdAt = _toDate(raw['createdAtServer']) ?? _toDate(raw['createdAt']);
    final expiresAt = _toDate(raw['expiresAt']);

    // "Expires in": use the admin's own label when there is one,
    // otherwise work it out from how long the alert was set to last.
    String expiresIn = firstText(_expiresInKeys) ?? '';
    if (expiresIn.isEmpty && createdAt != null && expiresAt != null) {
      expiresIn = _durationLabel(expiresAt.difference(createdAt));
    }

    return <String, dynamic>{
      'id': alertId,
      'title': raw['title']?.toString().trim() ?? '',
      'message': (raw['message'] ?? raw['body'])?.toString().trim() ?? '',
      'status': raw['status']?.toString().trim() ?? 'active',
      'type': firstText(_typeKeys) ?? 'General',
      'targetLocation': targetLocation,
      'audienceScope': firstText(_audienceKeys) ?? '',
      'recipients': recipients,
      'expiresIn': expiresIn,
      if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
    };
  }

  /// Rebuilds details from a compact map. [fallbackTitle] and
  /// [fallbackMessage] (the notification's own text) fill in when the map
  /// is empty -- e.g. an alert that arrived by push while offline.
  factory AlertDetails.fromMap(
    Map<String, dynamic> map, {
    required String fallbackTitle,
    required String fallbackMessage,
  }) {
    String read(String key, [String fallback = '']) {
      final value = map[key]?.toString().trim() ?? '';
      return value.isEmpty ? fallback : value;
    }

    return AlertDetails(
      // The notification title carries a leading siren emoji the admin
      // card doesn't show.
      title: read('title', fallbackTitle.replaceFirst('🚨', '').trim()),
      message: read('message', fallbackMessage),
      status: read('status', 'active'),
      type: read('type', 'General'),
      targetLocation: read('targetLocation', 'All Barangays'),
      audienceScope: read('audienceScope'),
      recipients: read('recipients'),
      expiresIn: read('expiresIn'),
      expiresAt: map['expiresAt']?.toString(),
    );
  }

  /// What the status badge should say right now.
  String get effectiveStatus {
    final s = status.toLowerCase();
    if (s == 'active' && expiresAt != null) {
      final exp = DateTime.tryParse(expiresAt!);
      if (exp != null && exp.isBefore(DateTime.now())) return 'expired';
    }
    return s.isEmpty ? 'active' : s;
  }

  // ------------------------------ helpers ------------------------------

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  static String _thousands(int n) => n.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );

  static String _durationLabel(Duration d) {
    var minutes = (d.inSeconds / 60).round();
    if (minutes <= 0) return '';
    // The expiry is stamped on the admin's device and the creation time by
    // the server, so they differ by a few seconds. Snap to 5 minutes so a
    // 1-hour alert reads "1 Hour" rather than "59 Minutes".
    if (minutes >= 10) minutes = (minutes / 5).round() * 5;

    if (minutes % 1440 == 0) {
      final days = minutes ~/ 1440;
      return '$days Day${days == 1 ? '' : 's'}';
    }
    if (minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return '$hours Hour${hours == 1 ? '' : 's'}';
    }
    return '$minutes Minutes';
  }
}

/// Shows the alert as a card -- same layout as the admin dashboard's
/// "Alert Details" dialog.
Future<void> showAlertDetailsDialog(
  BuildContext context,
  AlertDetails details,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AlertDetailsDialog(details: details),
  );
}

class _AlertDetailsDialog extends StatelessWidget {
  final AlertDetails details;

  const _AlertDetailsDialog({required this.details});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final footerBg = isDark ? const Color(0xFF172033) : const Color(0xFFF8FAFC);
    final divider = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
    const labelColor = Color(0xFF94A3B8);
    final strongText = isDark ? Colors.white : const Color(0xFF0F172A);
    final bodyText = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155);
    final messageBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final messageBorder =
        isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
    final accent = isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);

    return Dialog(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // HEADER
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 14, 14),
              child: Row(
                children: [
                  Icon(LucideIcons.triangleAlert, size: 20, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Alert Details',
                      style: GoogleFonts.montserrat(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: strongText,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(LucideIcons.x, size: 18, color: labelColor),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: divider),

            // BODY
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('TITLE & STATUS', labelColor),
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text(
                          details.title.isEmpty
                              ? 'Emergency Alert'
                              : details.title,
                          style: GoogleFonts.montserrat(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: strongText,
                          ),
                        ),
                        _StatusBadge(status: details.effectiveStatus),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _label('TYPE', labelColor),
                    const SizedBox(height: 6),
                    Text(
                      details.type,
                      style: _value(bodyText, size: 14),
                    ),
                    const SizedBox(height: 18),
                    _label('BROADCAST MESSAGE', labelColor),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: messageBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: messageBorder),
                      ),
                      child: Text(
                        details.message.isEmpty ? '—' : details.message,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.5,
                          color: bodyText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _field('TARGET LOCATION',
                              details.targetLocation, labelColor, bodyText),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _field('RECIPIENTS', details.recipients,
                              labelColor, bodyText),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _field('AUDIENCE SCOPE', details.audienceScope,
                              labelColor, bodyText),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _field('EXPIRES IN', details.expiresIn,
                              labelColor, bodyText),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // FOOTER
            Container(
              color: footerBg,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: strongText,
                    backgroundColor: bg,
                    side: BorderSide(
                      color: isDark
                          ? const Color(0xFF475569)
                          : const Color(0xFFE2E8F0),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 12),
                  ),
                  child: Text(
                    'Close',
                    style: GoogleFonts.montserrat(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _label(String text, Color color) => Text(
        text,
        style: GoogleFonts.montserrat(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: color,
        ),
      );

  static TextStyle _value(Color color, {double size = 13}) =>
      GoogleFonts.montserrat(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static Widget _field(
      String label, String value, Color labelColor, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label, labelColor),
        const SizedBox(height: 6),
        Text(value.isEmpty ? '—' : value, style: _value(textColor)),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = status == 'active';

    final Color bg = isActive
        ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5))
        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));
    final Color fg = isActive
        ? (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857))
        : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: GoogleFonts.montserrat(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
