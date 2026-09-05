import 'dart:async';
import 'dart:io';

import 'package:alertu_flutter/wrapper.dart';
import 'package:alertu_flutter/services/api_service.dart';
import 'package:alertu_flutter/services/socket.dart';
import 'package:alertu_flutter/services/notification_service.dart';
import 'package:alertu_flutter/services/reportnotifs.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:forui/forui.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 🛡️ Custom HttpOverrides class to handle SSL Certificate verification
/// for Railway endpoints and Backblaze B2 storage on devices/emulators missing root CAs.
class AppHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // Automatically trust SSL handshakes from Railway, Backblaze, Render, or internal domains
        if (host.contains('up.railway.app') ||
            host.contains('onrender.com') ||
            host.contains('backblazeb2.com') ||
            host.contains('alertu')) {
          return true;
        }
        return false;
      };
  }
}

void main() async {
  // 🔒 1. Apply global HTTP Overrides FIRST before any initialization
  HttpOverrides.global = AppHttpOverrides();

  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 2. Fetch saved theme mode before app loads
  final savedThemeMode = await AdaptiveTheme.getThemeMode();

  // 3. Initialize Firebase Core
  await Firebase.initializeApp();

  // 4. Initialize Notification Service & Google Auth
  try {
    await ReportNotifService.instance.initializeAndStart();
    await GoogleSignIn.instance.initialize();
  } catch (e) {
    debugPrint("Auth/Notification services initialization warning: $e");
  }

  // 5. Run App immediately so UI renders without waiting for network timeouts
  runApp(
    ProviderScope(
      child: MyApp(savedThemeMode: savedThemeMode),
    ),
  );

  // 6. Asynchronous Background Network Initialization
  _initServicesInBackground();
}

/// Runs socket and backend initialization in the background without freezing app startup
Future<void> _initServicesInBackground() async {
  try {
    await ApiService.initBackend();
    await SocketService.initSocket();

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final fcmToken = await NotificationService.instance.getFcmToken();
      if (fcmToken != null) {
        await ApiService.registerFcmToken(fcmToken);
      }
    }
  } catch (e) {
    debugPrint("Background Backend or Socket connection warning: $e");
  }
}

class MyApp extends StatefulWidget {
  final AdaptiveThemeMode? savedThemeMode;

  const MyApp({super.key, this.savedThemeMode});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setWakelockEnabled(true);
  }

  Future<void> _setWakelockEnabled(bool enabled) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
      debugPrint('🔒 Wakelock ${enabled ? 'enabled' : 'disabled'}');
    } catch (error) {
      // Wakelock must never prevent the app, GPS, or sockets from working.
      debugPrint('⚠️ Wakelock update skipped: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      _setWakelockEnabled(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setWakelockEnabled(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_setWakelockEnabled(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveTheme(
      // --- Light Theme Setup ---
      light: FlexThemeData.light(
        scheme: FlexScheme.blue,
        useMaterial3: true,
        surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
        blendLevel: 7,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 10,
          blendOnColors: false,
          useTextTheme: true,
          useM2StyleDividerInM3: true,
          alignedDropdown: true,
          defaultRadius: 12.0,
        ),
      ),

      // --- Dark Theme Setup ---
      dark: FlexThemeData.dark(
        scheme: FlexScheme.blue,
        useMaterial3: true,
        surfaceMode: FlexSurfaceMode.highScaffoldLowSurface,
        blendLevel: 13,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 20,
          useTextTheme: true,
          useM2StyleDividerInM3: true,
          alignedDropdown: true,
          defaultRadius: 12.0,
        ),
      ),

      initial: widget.savedThemeMode ?? AdaptiveThemeMode.light,

      // --- Builder integrating adaptive Material themes with ForUI ---
      builder: (theme, darkTheme) => MaterialApp(
        title: 'Alert U',
        theme: theme,
        darkTheme: darkTheme,
        builder: (context, child) {
          final isDark = AdaptiveTheme.of(context).mode.isDark;
          return FTheme(
            data: isDark ? FTheme.neutral.dark.touch : FTheme.neutral.light.touch,
            // Preserve Flutter's real MediaQuery.viewInsets so form screens
            // can resize and scroll focused fields above the keyboard.
            child: child!,
          );
        },
        debugShowCheckedModeBanner: false,
        home: const AnimatedSplashScreen(),
      ),
    );
  }
}

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _startTransition();
  }

  Future<void> _startTransition() async {
    FlutterNativeSplash.remove();

    await _controller.forward();
    await Future.delayed(const Duration(milliseconds: 200));

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) => const Wrapper(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: child,
              ),
            );
          },
          child: Image.asset(
            'images/logo1.png',
            width: 140,
          ),
        ),
      ),
    );
  }
}