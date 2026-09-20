import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackPage extends StatefulWidget {
  final String? reportId;

  const FeedbackPage({super.key, this.reportId});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int _selectedStars = 0;
  final TextEditingController _improvementController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _improvementController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedbackAndGoHome() async {
    if (widget.reportId == null) {
      debugPrint("Warning: Missing report reference index pointer. Swiping back home.");
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('reports')
          .doc(widget.reportId)
          .update({
        "feedback": {
          "starRating": _selectedStars,
          "improvementNotes": _improvementController.text.trim(),
          "submittedAt": FieldValue.serverTimestamp(),
        }
      });

      debugPrint('Feedback parameters merged cleanly into report ID: ${widget.reportId}');
    } catch (error) {
      debugPrint("Failed to append feedback data payload: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFDC2626),
            content: Text('Error updating report file: $error'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Dynamic Ecosystem Color Mapping
    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xFF0D47A1);
    final surfaceBg = isDark ? theme.colorScheme.surface : const Color(0xFFF8FAFC);
    final cardBg = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final cardBorder = isDark
        ? theme.colorScheme.outline.withOpacity(0.3)
        : const Color(0xFFE2E8F0);
    final textMain = isDark ? theme.colorScheme.onSurface : const Color(0xFF0F172A);
    final textMuted = isDark ? theme.colorScheme.onSurfaceVariant : const Color(0xFF64748B);
    final dividerColor = isDark
        ? theme.colorScheme.outline.withOpacity(0.2)
        : const Color(0xFFE2E8F0);
    final fallbackBg = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : const Color(0xFFF1F5F9);
    final starUnselected = isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1);

    final double screenWidth = MediaQuery.of(context).size.width;
    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    final double contentPadding = screenWidth > 600 ? 28.0 : 20.0;
    final double visualCardHeight = screenWidth > 600 ? 160.0 : 130.0;

    return Scaffold(
      backgroundColor: surfaceBg,
      appBar: AppBar(
        title: Text(
          'App Experience Feedback',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            letterSpacing: -0.3,
            color: textMain,
          ),
        ),
        backgroundColor: cardBg,
        foregroundColor: textMain,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false, // Prevents backing into stale subpages
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: dividerColor, height: 1),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              contentPadding,
              16.0,
              contentPadding,
              bottomPadding > 0 ? bottomPadding + 16.0 : 24.0,
            ),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),

                    // Visual Feedback Header Image/Icon Asset Wrapper
                    Container(
                      height: visualCardHeight,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: fallbackBg,
                        border: Border.all(color: cardBorder),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'images/visualfeedback.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Icon(
                              Icons.rate_review_rounded,
                              size: screenWidth > 600 ? 54 : 44,
                              color: primaryColor.withOpacity(0.8),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'How was your dispatch experience?',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: textMain,
                        letterSpacing: -0.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'Your response helps optimize active emergency response performance pipelines.',
                        style: TextStyle(fontSize: 13, color: textMuted, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ⭐ 1-5 INTERACTIVE STAR SELECTOR ROW
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starPosition = index + 1;
                        final isSelected = starPosition <= _selectedStars;

                        return InkWell(
                          onTap: _isSaving ? null : () => setState(() => _selectedStars = starPosition),
                          borderRadius: BorderRadius.circular(100),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              child: Icon(
                                isSelected ? Icons.star_rounded : Icons.star_border_rounded,
                                color: isSelected ? const Color(0xFFF59E0B) : starUnselected,
                                size: screenWidth > 600 ? 52 : 44,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 32),

                    // IMPROVEMENT TEXT INPUT HEADER
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'What features or flows can we improve?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    TextField(
                      controller: _improvementController,
                      maxLines: 4,
                      enabled: !_isSaving,
                      style: TextStyle(fontSize: 14, color: textMain),
                      decoration: InputDecoration(
                        hintText: 'Type any recommendations regarding local latency, UI visibility, or hardware sensor mapping...',
                        hintStyle: TextStyle(color: textMuted.withOpacity(0.7), fontSize: 13, height: 1.4),
                        filled: true,
                        fillColor: cardBg,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cardBorder),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cardBorder.withOpacity(0.5)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: primaryColor, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),

                    // 🚀 MAIN ACTION DISPATCH SUBMIT OVERLAY CONTROL BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedStars == 0 || _isSaving
                              ? (isDark ? cardBorder : const Color(0xFFE2E8F0))
                              : primaryColor,
                          foregroundColor: _selectedStars == 0 || _isSaving
                              ? (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8))
                              : Colors.white,
                          elevation: 0,
                          disabledBackgroundColor: isDark ? cardBorder : const Color(0xFFE2E8F0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _selectedStars == 0 || _isSaving ? null : _submitFeedbackAndGoHome,
                        child: _isSaving
                            ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: textMuted,
                          ),
                        )
                            : const Text(
                          'COMPLETE & RETURN TO HOME',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}