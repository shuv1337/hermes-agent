import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hermes_mobile/core/providers.dart';
import 'package:hermes_mobile/core/services/app_lifecycle.dart';
import 'package:hermes_mobile/core/services/result_notifier.dart';
import 'package:hermes_mobile/core/sync/background_sync.dart';
import 'package:hermes_mobile/core/theme/hermes_skins.dart';
import 'package:hermes_mobile/features/connect/connect_screen.dart';
import 'package:hermes_mobile/features/shell/gateway_shell.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

class HermesMobileApp extends StatelessWidget {
  const HermesMobileApp({super.key, this.providerOverrides = const []});

  /// Provider overrides (typed as dynamic for riverpod Override portability).
  final List<dynamic> providerOverrides;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: providerOverrides.cast(),
      child: const _ThemedApp(),
    );
  }
}

class _ThemedApp extends ConsumerWidget {
  const _ThemedApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(appSkinProvider);
    final mode = ref.watch(appThemeModeProvider).value ?? ThemeMode.system;
    final localeOverride = ref.watch(appLocaleProvider).value;
    // Eager-load mute flag so FeedbackService.instance.muted is correct.
    ref.watch(hapticsMutedProvider);

    return MaterialApp(
      onGenerateTitle: (ctx) => ctx.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: buildThemeData(skin, Brightness.light),
      darkTheme: buildThemeData(skin, Brightness.dark),
      locale: localeOverride,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeListResolutionCallback: (deviceLocales, supported) {
        // Prefer exact language match from the device list.
        if (deviceLocales != null) {
          for (final device in deviceLocales) {
            for (final s in supported) {
              if (s.languageCode == device.languageCode) return s;
            }
          }
        }
        return const Locale('en');
      },
      // Tap outside any TextField → dismiss keyboard (iOS UX).
      // Bind L10n for non-context callers (tool status, etc.).
      builder: (context, child) {
        final l10n = AppLocalizations.of(context);
        L10n.bind(l10n);
        // Preserve the platform's accessibility text size. Screens that can
        // grow use scrolling/list layouts; do not silently cap user settings.
        final mq = MediaQuery.of(context);
        // Default status/nav-bar icon style for the whole app, keyed off the
        // *effective* theme brightness (now reliable post-buildThemeData
        // fix). AppBar screens get correct icons automatically from
        // AppBarTheme/ColorScheme; this covers the AppBar-less screens
        // (GatewayShell, ConnectScreen) which would otherwise keep whatever
        // main.dart's launch-time hardcode set. Screens with an AppBar
        // still win locally — Flutter nests their own AnnotatedRegion
        // closer to the leaf.
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final overlayStyle =
            (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: theme.scaffoldBackgroundColor,
                  systemNavigationBarIconBrightness: isDark
                      ? Brightness.light
                      : Brightness.dark,
                );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: MediaQuery(
            data: mq,
            // Do not wrap the entire app in a tap recognizer. On iOS, taps on
            // the system edit menu (Paste/Select All) can reach an ancestor
            // recognizer and unfocus the TextField before the edit completes.
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const _RootGate(),
    );
  }
}

class _RootGate extends ConsumerStatefulWidget {
  const _RootGate();

  @override
  ConsumerState<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<_RootGate>
    with WidgetsBindingObserver {
  /// Ignore lifecycle churn during the first second of cold start (iOS fires
  /// inactive→resumed while plugins are still coming up).
  var _bootGuardUntil = DateTime.now().add(const Duration(seconds: 2));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootGuardUntil = DateTime.now().add(const Duration(seconds: 2));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLifecycle.update(state);
    if (DateTime.now().isBefore(_bootGuardUntil)) {
      return;
    }
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Catch finishes while backgrounded (WS may die; BG sync as backup).
        BackgroundSync.scheduleSoon(delay: const Duration(seconds: 5));
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.resumed:
        // Re-assert notification permission path after returning.
        unawaited(ResultNotifier.instance.init(requestPermission: false));
        BackgroundSync.run(reason: 'resume').then((_) {
          if (!mounted) return;
          ref.read(sessionsProvider.notifier).refresh();
          ref.read(jobsProvider.notifier).refresh();
        });
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(gatewayBookProvider);
    final reauth = ref.watch(needsReauthProvider);
    final l10n = context.l10n;
    return book.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: Center(child: Text(l10n.failedToLoadConnection('$e'))),
      ),
      data: (b) {
        // Expired/kicked session → interactive login (never silent re-auth).
        if (reauth.required) {
          return ConnectScreen(
            reauth: true,
            reauthMessage: reauth.message,
            existingProfile: b.resolved,
          );
        }
        return b.resolved == null
            ? const ConnectScreen()
            : const GatewayShell();
      },
    );
  }
}
