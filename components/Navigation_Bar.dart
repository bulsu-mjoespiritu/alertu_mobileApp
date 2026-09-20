import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../global/navbarcount.dart';

/// How far the circular "+" action button overflows ABOVE the bar.
///
/// Bug fix (report button): the button used to be a `Positioned(top: -32)`
/// child of a Stack that was only as tall as the bar itself. Flutter does
/// NOT hit-test the part of a child that falls outside its parent's
/// bounds -- `clipBehavior: Clip.none` only affects painting, not touch.
/// So the top ~32px of the blue circle was painted but completely dead to
/// taps, and only the small sliver of the circle overlapping the bar (plus
/// the "Report" label underneath it, which sat fully inside the bar) was
/// actually pressable. That's exactly the reported symptom: "the word
/// Report is the real button, not the circle".
///
/// The bar now reserves this much real height ABOVE the visual bar, so the
/// whole circle lives inside the widget's own bounds and is fully
/// tappable. The reserved strip has no background of its own, so taps that
/// miss the circle still fall through to whatever is behind it (the map).
const double kReportButtonOverflow = 38.0;

/// Total height the navigation bar occupies at the bottom of the screen,
/// excluding the device's system inset. Callers that need to leave room
/// for the bar (e.g. Homepage's page container) should use this.
const double kNavigationBarHeight = 70.0;

class CustomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final VoidCallback onReportPressed;
  final bool isReportLoading;

  const CustomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onReportPressed,
    this.isReportLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Use primary color or accessible blue tint
    final Color primaryColor = theme.colorScheme.primary;
    final Color navBgColor = theme.cardColor; // Dynamic background (white in light mode, dark in dark mode)
    final Color unselectedColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    // Report is a global action available from every tab, not just Home, so
    // it is never visually or functionally disabled based on currentIndex.
    final Color reportColor = primaryColor;

    // Aspect-scoped lookups: `MediaQuery.of(context)` subscribed the nav bar
    // to every MediaQuery change, so it rebuilt on every frame of the
    // keyboard animation. paddingOf/sizeOf only listen to what is actually
    // read here, so the keyboard opening no longer touches this widget.
    final double bottomPadding = MediaQuery.paddingOf(context).bottom;
    final double screenWidth = MediaQuery.sizeOf(context).width;

    return SizedBox(
      // Real height = the bar itself + the strip the circle overflows into.
      height: kNavigationBarHeight + bottomPadding + kReportButtonOverflow,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ---- The bar itself, pinned to the bottom of this SizedBox ----
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: kNavigationBarHeight + bottomPadding,
              padding: EdgeInsets.only(bottom: bottomPadding),
              decoration: BoxDecoration(
                color: navBgColor,
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withOpacity(0.3)
                        : Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  )
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(context, kNavPageHome, 'images/navbaricons/HomeIcon.svg', "Home", primaryColor, unselectedColor),
                  _buildNavItem(context, kNavPageReports, 'images/navbaricons/ReportIcon.svg', "Reports", primaryColor, unselectedColor),
                  const SizedBox(width: 72), // Clean clearance gap for the central overflow button
                  _buildNavItem(context, kNavPageNotifications, 'images/navbaricons/NotifIcon.svg', "Alerts", primaryColor, unselectedColor),
                  _buildNavItem(context, kNavPageSettings, 'images/navbaricons/SettingsIcon.svg', "Settings", primaryColor, unselectedColor),
                ],
              ),
            ),
          ),

          // ---- The circular "+" action button ----
          // Sits entirely INSIDE this widget's bounds now (top: 6 rather
          // than a negative offset on a short Stack), so every pixel of the
          // circle is hit-testable.
          Positioned(
            top: 6,
            left: (screenWidth / 2) - 36,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Only the circle is the tap target. The "Report" caption
                // below is now a plain, non-tappable label -- tapping the
                // word does nothing, exactly as requested.
                GestureDetector(
                  onTap: isReportLoading ? null : onReportPressed,
                  behavior: HitTestBehavior.opaque,
                  child: Opacity(
                    opacity: isReportLoading ? 0.75 : 1.0,
                    child: Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: reportColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: isDark ? Colors.black54 : Colors.black26,
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: isReportLoading
                          ? const SizedBox(
                        width: 32,
                        height: 32,
                        child: Padding(
                          padding: EdgeInsets.all(6.0),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      )
                          : Image.asset(
                        'images/navbaricons/PlusIcon.png',
                        width: 32,
                        height: 32,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Plain caption -- IgnorePointer makes sure it can never
                // swallow (or act as) the report tap.
                IgnorePointer(
                  child: Text(
                    "Report",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: reportColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
      BuildContext context,
      int index,
      String assetPath,
      String label,
      Color activeColor,
      Color inactiveColor,
      ) {
    final bool isSelected = currentIndex == index;
    final Color itemColor = isSelected ? activeColor : inactiveColor;

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(top: 12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              assetPath,
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(itemColor, BlendMode.srcIn),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: itemColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
