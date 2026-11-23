import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/theme/app_theme.dart';
import 'package:sakuin/features/home/navigation_shell.dart';
import 'package:sakuin/features/onboarding/onboarding_screen.dart';
import 'package:sakuin/features/settings/pin_lock_screen.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

class SakuinApp extends ConsumerStatefulWidget {
  const SakuinApp({super.key});

  @override
  ConsumerState<SakuinApp> createState() => _SakuinAppState();
}

class _SakuinAppState extends ConsumerState<SakuinApp>
    with WidgetsBindingObserver {
  bool _unlocked = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = ref.read(settingsProvider);
    if (!settings.pinEnabled) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pausedAt = DateTime.now();
      if (settings.autoLockSeconds == 0) {
        setState(() => _unlocked = false);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedAt != null && settings.autoLockSeconds > 0) {
        final elapsed = DateTime.now().difference(_pausedAt!).inSeconds;
        if (elapsed >= settings.autoLockSeconds) {
          setState(() => _unlocked = false);
        }
      }
      _pausedAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final pinEnabled = ref.watch(settingsProvider.select((s) => s.pinEnabled));
    final onboardingDone = ref.watch(
      settingsProvider.select((s) => s.onboardingCompleted),
    );
    final walletsAsync = ref.watch(allWalletsWithBalancesProvider);

    Widget homeWidget;
    if (pinEnabled && !_unlocked) {
      homeWidget = PinLockScreen(
        mode: PinScreenMode.unlock,
        onUnlocked: () => setState(() => _unlocked = true),
      );
    } else if (!onboardingDone &&
        walletsAsync.hasValue &&
        (walletsAsync.value?.isEmpty ?? true)) {
      homeWidget = const OnboardingScreen();
    } else {
      homeWidget = const NavigationShell();
    }

    return MaterialApp(
      title: 'Sakuin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: homeWidget,
    );
  }
}
