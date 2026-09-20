import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Representation of a single chat message
class ChatMessage {
  final String text;
  final bool isUser;
  final List<ChatOption>? options;
  final bool isMainResponse;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.options,
    this.isMainResponse = false,
  });
}

/// Representation of an interactive decision tree option
class ChatOption {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  ChatOption({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class AlertUChatbotPage extends StatefulWidget {
  const AlertUChatbotPage({super.key});

  @override
  State<AlertUChatbotPage> createState() => _AlertUChatbotPageState();
}

class _AlertUChatbotPageState extends State<AlertUChatbotPage> {
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _showMainMenu();
  }

  /// Automatically scrolls to the bottom when new messages arrive
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Reset or initial load: Main Menu Options
  void _showMainMenu({bool isReset = false}) {
    final mainMenuOptions = [
      ChatOption(
        label: "How do I report an incident?",
        icon: LucideIcons.camera,
        onTap: () => _handleOptionA(),
      ),
      ChatOption(
        label: "How do I get immediate help? (SOS / Call)",
        icon: LucideIcons.shieldAlert,
        onTap: () => _handleOptionB(),
      ),
      ChatOption(
        label: "Where can I view reports & map legends?",
        icon: LucideIcons.mapPin,
        onTap: () => _handleOptionC(),
      ),
      ChatOption(
        label: "How do notifications work?",
        icon: LucideIcons.bell,
        onTap: () => _handleOptionD(),
      ),
    ];

    setState(() {
      if (isReset) {
        _messages.add(
          ChatMessage(
            text: "Main Menu\nHow else can I help you today?",
            isUser: false,
            options: mainMenuOptions,
          ),
        );
      } else {
        _messages.add(
          ChatMessage(
            text: "Hi! How can I help you today? Please choose an option below:",
            isUser: false,
            options: mainMenuOptions,
          ),
        );
      }
    });

    _scrollToBottom();
  }

  /// Helper to return back to Main Menu button
  List<ChatOption> _getBackToMenuOption() {
    return [
      ChatOption(
        label: "Go Back to Main Menu",
        icon: LucideIcons.arrowLeft,
        onTap: () {
          _addUserMessage("Go Back to Main Menu");
          _showMainMenu(isReset: true);
        },
      )
    ];
  }

  void _addUserMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
    });
    _scrollToBottom();
  }

  // --- Decision Tree Handlers ---

  // Option A: Reporting an Incident
  void _handleOptionA() {
    _addUserMessage("How do I report an incident?");
    setState(() {
      _messages.add(
        ChatMessage(
          text: "To report an incident, follow these simple steps:\n\n"
              "1️⃣ Tap the '+' (Report) icon on the navigation bar at the bottom.\n"
              "2️⃣ Take a clear photo of the incident as real proof.\n"
              "3️⃣ Fill out the required details.\n"
              "4️⃣ Tap Submit.\n\n"
              "💡 Tip: Clear photos help admins review and verify your report quickly!",
          isUser: false,
          options: _getBackToMenuOption(),
          isMainResponse: true,
        ),
      );
    });
    _scrollToBottom();
  }

  // Option B: Getting Emergency Help Submenu
  void _handleOptionB() {
    _addUserMessage("How do I get immediate help? (SOS / Emergency Call)");
    setState(() {
      _messages.add(
        ChatMessage(
          text: "What kind of help do you need right now?",
          isUser: false,
          options: [
            ChatOption(
              label: "B1. Use the SOS Button",
              icon: LucideIcons.siren,
              onTap: () => _handleOptionB1(),
            ),
            ChatOption(
              label: "B2. Make an Emergency Call",
              icon: LucideIcons.phoneCall,
              onTap: () => _handleOptionB2(),
            ),
            ..._getBackToMenuOption(),
          ],
        ),
      );
    });
    _scrollToBottom();
  }

  void _handleOptionB1() {
    _addUserMessage("Use the SOS Button");
    setState(() {
      _messages.add(
        ChatMessage(
          text: "🚨 SOS Button:\n\n"
              "Press the SOS Button if you are in danger. This instantly sends your live location to the admins.\n\n"
              "The admins will then contact your saved emergency contacts for you.",
          isUser: false,
          options: _getBackToMenuOption(),
          isMainResponse: true,
        ),
      );
    });
    _scrollToBottom();
  }

  void _handleOptionB2() {
    _addUserMessage("Make an Emergency Call");
    setState(() {
      _messages.add(
        ChatMessage(
          text: "📞 Emergency Call:\n\n"
              "Tap Emergency Call to directly phone the admins right away for immediate assistance.",
          isUser: false,
          options: _getBackToMenuOption(),
          isMainResponse: true,
        ),
      );
    });
    _scrollToBottom();
  }

  // Option C: Viewing Reports & Map Legends Submenu
  void _handleOptionC() {
    _addUserMessage("Where can I view reports and map legends?");
    setState(() {
      _messages.add(
        ChatMessage(
          text: "What would you like to view?",
          isUser: false,
          options: [
            ChatOption(
              label: "C1. Map Legends",
              icon: LucideIcons.map,
              onTap: () => _handleOptionC1(),
            ),
            ChatOption(
              label: "C2. List of Reports",
              icon: LucideIcons.fileText,
              onTap: () => _handleOptionC2(),
            ),
            ..._getBackToMenuOption(),
          ],
        ),
      );
    });
    _scrollToBottom();
  }

  void _handleOptionC1() {
    _addUserMessage("Map Legends");
    setState(() {
      _messages.add(
        ChatMessage(
          text: "🗺️ Map Legends:\n\n"
              "Tap the Map Legends button on the Home Page. This shows what the different icons and colors on the map mean.",
          isUser: false,
          options: _getBackToMenuOption(),
          isMainResponse: true,
        ),
      );
    });
    _scrollToBottom();
  }

  void _handleOptionC2() {
    _addUserMessage("List of Reports");
    setState(() {
      _messages.add(
        ChatMessage(
          text: "📋 List of Reports:\n\n"
              "Tap the Reports icon on the navigation bar to browse and check different reported incidents.",
          isUser: false,
          options: _getBackToMenuOption(),
          isMainResponse: true,
        ),
      );
    });
    _scrollToBottom();
  }

  // Option D: Notifications & Status Checks
  void _handleOptionD() {
    _addUserMessage("How do notifications work?");
    setState(() {
      _messages.add(
        ChatMessage(
          text: "🔔 Notifications & Status Checks:\n\n"
              "Check your Notifications tab to see the status of your reported incident:\n\n"
              "✅ Accepted: The admin verified your report.\n"
              "❌ Rejected: The admin declined the report (for example, if it was a duplicate report).",
          isUser: false,
          options: _getBackToMenuOption(),
          isMainResponse: true,
        ),
      );
    });
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Adaptive Theme Colors
    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xFF0D47A1);
    final scaffoldBg = isDark ? theme.colorScheme.surface : const Color(0xFFF4F6F9);
    final appBarBg = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final titleColor = isDark ? theme.colorScheme.onSurface : Colors.black87;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.bot, color: primaryColor, size: 22),
            ),
            const SizedBox(width: 10),
            Text(
              "AlertU Guide Bot",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: titleColor,
              ),
            ),
          ],
        ),
        backgroundColor: appBarBg,
        foregroundColor: primaryColor,
        elevation: isDark ? 0 : 0.5,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720), // Responsive desktop containment
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return _buildAnimatedMessageBubble(message);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Renders an animated chat bubble with message content and action cards
  Widget _buildAnimatedMessageBubble(ChatMessage message) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Theme values
    final primaryColor = isDark ? theme.colorScheme.primary : const Color(0xFF0D47A1);
    final botBubbleBg = isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    final botTextColor = isDark ? theme.colorScheme.onSurface : Colors.black87;
    final backMenuBg = isDark ? theme.colorScheme.surfaceContainerHighest : Colors.grey.shade200;
    final backMenuBorder = isDark ? Colors.white12 : Colors.grey.shade300;
    final backMenuTextColor = isDark ? theme.colorScheme.onSurfaceVariant : Colors.grey.shade800;
    final cardBg = isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 15),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment:
          message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment:
              message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!message.isUser)
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: primaryColor,
                    child: const Icon(LucideIcons.bot, color: Colors.white, size: 18),
                  ),
                if (!message.isUser) const SizedBox(width: 8),

                Flexible(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: message.isUser ? primaryColor : botBubbleBg,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(message.isUser ? 16 : 4),
                        bottomRight: Radius.circular(message.isUser ? 4 : 16),
                      ),
                      border: Border.all(
                        color: message.isUser
                            ? Colors.transparent
                            : (isDark ? Colors.white10 : Colors.black.withOpacity(0.04)),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withOpacity(0.2)
                              : Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ],
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: message.isUser ? Colors.white : botTextColor,
                        fontWeight: message.isUser ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Options List (Decision Cards)
            if (message.options != null && message.options!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, left: 40),
                child: Column(
                  children: message.options!.map((option) {
                    final bool isBackMenu = option.label.contains("Main Menu");

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: isBackMenu ? backMenuBg : cardBg,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: option.onTap,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isBackMenu
                                    ? backMenuBorder
                                    : primaryColor.withOpacity(isDark ? 0.5 : 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  option.icon,
                                  size: 18,
                                  color: isBackMenu ? backMenuTextColor : primaryColor,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    option.label,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isBackMenu ? backMenuTextColor : primaryColor,
                                    ),
                                  ),
                                ),
                                Icon(
                                  LucideIcons.chevronRight,
                                  size: 16,
                                  color: isBackMenu
                                      ? backMenuTextColor.withOpacity(0.6)
                                      : primaryColor.withOpacity(0.6),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}