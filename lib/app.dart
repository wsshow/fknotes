import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import 'pages/quill_home_page.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/l10n.dart';
import 'providers/app_lock_controller.dart';
import 'providers/app_locale_controller.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/app_feedback_navigator_observer.dart';
import 'debug/debug_navigation.dart';

class AppColors {
  static const ink = Color(0xFF202124);
  static const muted = Color(0xFF74777D);
  static const subtle = Color(0xFFA7A9AE);
  static const canvas = Color(0xFFF7F7F6);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF1F2F2);
  static const line = Color(0xFFE7E7E5);
  static const accent = Color(0xFFD85C3B);
  static const accentPressed = Color(0xFFBC492C);
  static const accentSoft = Color(0xFFFBEDE8);
  static const success = Color(0xFF39735C);
  static const successSoft = Color(0xFFEAF4EF);
  static const warning = Color(0xFFA56A22);
  static const warningSoft = Color(0xFFF8F0E4);
  static const danger = Color(0xFFC7473E);
  static const dangerSoft = Color(0xFFFBEAE8);
  static const scrim = Color(0x52202124);

  // Compatibility names used by feature surfaces while they migrate to the
  // semantic palette above.
  static const moss = accent;
  static const coral = danger;
  static const lime = surfaceMuted;
  static const softGreen = accentSoft;
  static const softBlue = surfaceMuted;
  static const softAmber = warningSoft;
  static const softLavender = surfaceMuted;
  static const softCoral = dangerSoft;
}

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class AppRadius {
  static const small = 12.0;
  static const medium = 16.0;
  static const large = 20.0;
  static const extraLarge = 26.0;
  static const pill = 999.0;
}

abstract final class AppShadows {
  static const low = <BoxShadow>[
    BoxShadow(color: Color(0x0A202124), blurRadius: 16, offset: Offset(0, 4)),
  ];

  static const floating = <BoxShadow>[
    BoxShadow(color: Color(0x12202124), blurRadius: 28, offset: Offset(0, 10)),
  ];
}

class FkNotesApp extends StatelessWidget {
  const FkNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    const scheme = ColorScheme.light(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      primaryContainer: AppColors.accentSoft,
      onPrimaryContainer: AppColors.ink,
      primaryFixed: AppColors.accentSoft,
      primaryFixedDim: AppColors.surfaceMuted,
      onPrimaryFixed: AppColors.ink,
      onPrimaryFixedVariant: AppColors.accent,
      secondary: AppColors.muted,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.surfaceMuted,
      onSecondaryContainer: AppColors.ink,
      secondaryFixed: AppColors.surfaceMuted,
      secondaryFixedDim: AppColors.warningSoft,
      onSecondaryFixed: AppColors.ink,
      onSecondaryFixedVariant: AppColors.muted,
      tertiary: AppColors.muted,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.surfaceMuted,
      onTertiaryContainer: AppColors.ink,
      tertiaryFixed: AppColors.surfaceMuted,
      tertiaryFixedDim: AppColors.surfaceMuted,
      onTertiaryFixed: AppColors.ink,
      onTertiaryFixedVariant: AppColors.muted,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: AppColors.dangerSoft,
      onErrorContainer: AppColors.danger,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      surfaceDim: AppColors.surfaceMuted,
      surfaceBright: AppColors.surface,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.canvas,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surfaceMuted,
      surfaceContainerHighest: AppColors.line,
      onSurfaceVariant: AppColors.muted,
      outline: AppColors.muted,
      outlineVariant: AppColors.line,
      shadow: AppColors.ink,
      scrim: AppColors.ink,
      inverseSurface: AppColors.ink,
      onInverseSurface: AppColors.surface,
      inversePrimary: AppColors.lime,
      surfaceTint: Colors.transparent,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AppLocaleController.instance),
        ChangeNotifierProvider(
          create: (_) => AppLockController()..initialize(),
        ),
      ],
      child: Consumer<AppLocaleController>(
        builder: (context, localeController, _) => MaterialApp(
          onGenerateTitle: (context) => context.l10n.appTitle,
          locale: localeController.locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            FlutterQuillLocalizations.delegate,
          ],
          debugShowCheckedModeBanner: false,
          navigatorObservers: [
            AppFeedbackNavigatorObserver(),
            if (kDebugMode) ...createDebugNavigatorObservers(),
          ],
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: scheme,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
                TargetPlatform.windows: ZoomPageTransitionsBuilder(),
                TargetPlatform.linux: ZoomPageTransitionsBuilder(),
              },
            ),
            scaffoldBackgroundColor: AppColors.canvas,
            fontFamilyFallback: const [
              'PingFang SC',
              'Noto Sans CJK SC',
              'sans-serif',
            ],
            textTheme: ThemeData.light().textTheme
                .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
                .copyWith(
                  headlineLarge: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 30,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.55,
                  ),
                  headlineMedium: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 26,
                    height: 1.24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.4,
                  ),
                  headlineSmall: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 22,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.2,
                  ),
                  titleLarge: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 20,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.15,
                  ),
                  titleMedium: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                  bodyLarge: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 16,
                    height: 1.6,
                    fontWeight: FontWeight.w400,
                  ),
                  bodyMedium: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 14,
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            appBarTheme: const AppBarTheme(
              elevation: 0,
              scrolledUnderElevation: 0,
              toolbarHeight: 64,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              foregroundColor: AppColors.ink,
              titleTextStyle: TextStyle(
                color: AppColors.ink,
                fontSize: 20,
                height: 1.35,
                fontWeight: FontWeight.w700,
                letterSpacing: -.15,
              ),
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness: Brightness.dark,
                systemNavigationBarContrastEnforced: false,
              ),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              color: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.large),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: AppColors.surfaceMuted,
              hintStyle: const TextStyle(color: AppColors.muted),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 15,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.medium),
                borderSide: const BorderSide(
                  color: AppColors.accent,
                  width: 1.5,
                ),
              ),
            ),
            navigationBarTheme: NavigationBarThemeData(
              height: 64,
              elevation: 0,
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              indicatorColor: AppColors.accentSoft,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              indicatorShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.small),
              ),
              iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
                  size: 22,
                  color: states.contains(WidgetState.selected)
                      ? AppColors.accent
                      : AppColors.muted,
                ),
              ),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  fontSize: 11,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: states.contains(WidgetState.selected)
                      ? AppColors.accent
                      : AppColors.muted,
                ),
              ),
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              focusElevation: 0,
              hoverElevation: 1,
              highlightElevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                side: const BorderSide(color: AppColors.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.small),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            chipTheme: ChipThemeData(
              backgroundColor: AppColors.surface,
              disabledColor: AppColors.softBlue,
              selectedColor: AppColors.softGreen,
              secondarySelectedColor: AppColors.softGreen,
              surfaceTintColor: Colors.transparent,
              checkmarkColor: AppColors.coral,
              deleteIconColor: AppColors.muted,
              iconTheme: const IconThemeData(color: AppColors.muted, size: 18),
              side: const BorderSide(color: AppColors.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              labelStyle: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
              ),
              secondaryLabelStyle: const TextStyle(
                color: AppColors.moss,
                fontWeight: FontWeight.w600,
              ),
            ),
            listTileTheme: ListTileThemeData(
              textColor: AppColors.ink,
              iconColor: AppColors.muted,
              selectedColor: AppColors.moss,
              selectedTileColor: AppColors.softGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            searchBarTheme: SearchBarThemeData(
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: const WidgetStatePropertyAll(
                AppColors.surfaceMuted,
              ),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              hintStyle: const WidgetStatePropertyAll(
                TextStyle(color: AppColors.muted),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
              ),
            ),
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.surface
                    : AppColors.muted,
              ),
              trackColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.accent
                    : AppColors.line,
              ),
              trackOutlineColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
            ),
            segmentedButtonTheme: SegmentedButtonThemeData(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? AppColors.accentSoft
                      : AppColors.surface,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? AppColors.accent
                      : AppColors.muted,
                ),
                side: const WidgetStatePropertyAll(
                  BorderSide(color: AppColors.line),
                ),
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: AppColors.surface,
              modalBackgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              modalElevation: 5,
              shadowColor: AppColors.ink,
              modalBarrierColor: AppColors.scrim,
              showDragHandle: true,
              dragHandleColor: AppColors.line,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: AppColors.line),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 5,
              shadowColor: AppColors.ink.withValues(alpha: .12),
              barrierColor: AppColors.scrim,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppColors.line),
              ),
              clipBehavior: Clip.antiAlias,
            ),
            popupMenuTheme: PopupMenuThemeData(
              color: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 5,
              shadowColor: AppColors.ink.withValues(alpha: .12),
              menuPadding: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.line),
              ),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  color: states.contains(WidgetState.disabled)
                      ? AppColors.muted.withValues(alpha: .55)
                      : AppColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              iconColor: AppColors.muted,
              iconSize: 22,
            ),
            tooltipTheme: TooltipThemeData(
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                color: AppColors.surface,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: AppColors.coral,
              selectionColor: AppColors.moss.withValues(alpha: .18),
              selectionHandleColor: AppColors.coral,
            ),
            snackBarTheme: SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            dividerTheme: const DividerThemeData(
              color: AppColors.line,
              thickness: 1,
              space: 1,
            ),
          ),
          builder: (context, child) =>
              AppLockGate(child: child ?? const SizedBox.shrink()),
          home: const QuillHomePage(),
        ),
      ),
    );
  }
}
