import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../global/navbarcount.dart';

class CustomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final VoidCallback onReportPressed;

  const CustomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onReportPressed,
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

    final double bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      // Accommodate the default bar height plus device system notch space smoothly
      height: 70 + bottomPadding,
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        color: navBgColor,
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          )
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none, // Allows the large center action button to overflow upward cleanly
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(context, kNavPageHome, 'images/navbaricons/HomeIcon.svg', "Home", primaryColor, unselectedColor),
              _buildNavItem(context, kNavPageReports, 'images/navbaricons/ReportIcon.svg', "Reports", primaryColor, unselectedColor),
              const SizedBox(width: 72), // Clean clearance gap for the central overflow button
              _buildNavItem(context, kNavPageNotifications, 'images/navbaricons/NotifIcon.svg', "Alerts", primaryColor, unselectedColor),
              _buildNavItem(context, kNavPageSettings, 'images/navbaricons/SettingsIcon.svg', "Settings", primaryColor, unselectedColor),
            ],
          ),
          Positioned(
            top: -32, // Offsets the FAB button cleanly above the header line of the bar
            left: (MediaQuery.of(context).size.width / 2) - 36,
            child: GestureDetector(
              onTap: onReportPressed,
              behavior: HitTestBehavior.opaque,
              child: Opacity(
                opacity: 1.0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
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
                      child: Image.asset('images/navbaricons/PlusIcon.png', width: 32, height: 32),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Report",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: reportColor,
                      ),
                    ),
                  ],
                ),
              ),
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