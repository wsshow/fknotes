import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'debug/app_diagnostics.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/l10n.dart';
import 'providers/app_locale_controller.dart';
import 'services/file_storage_service.dart';
import 'services/model_download_source_policy.dart';
import 'widgets/brand_mark.dart';
import 'app.dart';

void main() {
  runZonedGuarded(_startApplication, (error, stackTrace) {
    if (kDebugMode) {
      AppDiagnostics.error(
        AppLogCategory.application,
        'uncaught_zone_error',
        error: error,
        stackTrace: stackTrace,
        fatal: true,
      );
    }
  });
}

Future<void> _startApplication() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    await AppDiagnostics.instance.initialize();
    _installDebugErrorHandlers();
    AppDiagnostics.info(
      AppLogCategory.application,
      'startup_started',
      data: {
        'buildMode': 'debug',
        'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
      },
    );
  }
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  try {
    // Do all required startup work before Flutter draws its first frame. The
    // native splash remains visible, so there is no second loading screen.
    await FileStorageService.instance.init();
    await ModelDownloadSourcePolicy.instance.load();
    await AppLocaleController.instance.initialize();
  } catch (error, stackTrace) {
    if (kDebugMode) {
      AppDiagnostics.error(
        AppLogCategory.application,
        'startup_initialization_failed',
        error: error,
        stackTrace: stackTrace,
        fatal: true,
      );
    }
    runApp(const _InitializationFailureApp());
    return;
  }
  if (kDebugMode) {
    AppDiagnostics.info(AppLogCategory.application, 'startup_completed');
  }
  runApp(const FkNotesApp());
}

void _installDebugErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppDiagnostics.error(
      AppLogCategory.application,
      'flutter_framework_error',
      data: {
        'library': details.library,
        'context': details.context?.toDescription(),
        'silent': details.silent,
      },
      error: details.exception,
      stackTrace: details.stack,
      fatal: false,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppDiagnostics.error(
      AppLogCategory.application,
      'platform_dispatcher_error',
      error: error,
      stackTrace: stackTrace,
      fatal: true,
    );
    return true;
  };
}

class _InitializationFailureApp extends StatelessWidget {
  const _InitializationFailureApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => context.l10n.appTitle,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    debugShowCheckedModeBanner: false,
    home: const _BrandLaunchScreen(error: true),
  );
}

// Retained as a branded failure state and as the source for future launch
// experiments. It is intentionally not part of the normal startup path.
class _BrandLaunchScreen extends StatelessWidget {
  final bool error;
  const _BrandLaunchScreen({required this.error});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.canvas,
    body: SafeArea(
      child: Stack(
        children: [
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 8 * (1 - value)),
                  child: child,
                ),
              ),
              child: const _BrandWordmark(),
            ),
          ),
          if (error)
            Positioned(
              left: 0,
              right: 0,
              bottom: 42,
              child: Center(
                child: Text(
                  context.l10n.localStorageInitializationFailed,
                  style: const TextStyle(color: AppColors.coral, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const BrandMark(size: 68),
      const SizedBox(width: 18),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.appTitle,
            style: const TextStyle(
              color: AppColors.ink,
              fontFamily: 'serif',
              fontSize: 31,
              height: 1.18,
              fontWeight: FontWeight.w700,
              letterSpacing: .4,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            context.l10n.appTagline,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12.5,
              height: 1.2,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.15,
            ),
          ),
        ],
      ),
    ],
  );
}
