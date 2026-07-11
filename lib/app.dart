import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'providers/app_lock_controller.dart';
import 'providers/note_provider.dart';
import 'widgets/app_lock_gate.dart';

class AppColors {
  static const ink = Color(0xFF28231F);
  static const muted = Color(0xFF7B726B);
  static const canvas = Color(0xFFFAF7F2);
  static const surface = Color(0xFFFFFDFC);
  static const line = Color(0xFFEAE2DA);
  static const moss = Color(0xFFB9573D);
  static const lime = Color(0xFFF1E5D8);
  static const softGreen = Color(0xFFF8EEE7);
  static const softBlue = Color(0xFFF1ECE6);
  static const softAmber = Color(0xFFF5E9DA);
  static const softLavender = Color(0xFFF2ECE8);
  static const softCoral = Color(0xFFFBEAE6);
  static const coral = Color(0xFFC1493F);
  static const scrim = Color(0x3D28231F);
}

class FkNotesApp extends StatelessWidget {
  const FkNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    const scheme = ColorScheme.light(
      primary: AppColors.moss,
      onPrimary: Colors.white,
      primaryContainer: AppColors.softGreen,
      onPrimaryContainer: AppColors.ink,
      primaryFixed: AppColors.softGreen,
      primaryFixedDim: AppColors.lime,
      onPrimaryFixed: AppColors.ink,
      onPrimaryFixedVariant: AppColors.moss,
      secondary: AppColors.muted,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.lime,
      onSecondaryContainer: AppColors.ink,
      secondaryFixed: AppColors.lime,
      secondaryFixedDim: AppColors.softAmber,
      onSecondaryFixed: AppColors.ink,
      onSecondaryFixedVariant: AppColors.muted,
      tertiary: AppColors.muted,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.softLavender,
      onTertiaryContainer: AppColors.ink,
      tertiaryFixed: AppColors.softLavender,
      tertiaryFixedDim: AppColors.softBlue,
      onTertiaryFixed: AppColors.ink,
      onTertiaryFixedVariant: AppColors.muted,
      error: AppColors.coral,
      onError: Colors.white,
      errorContainer: AppColors.softCoral,
      onErrorContainer: AppColors.coral,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      surfaceDim: AppColors.softBlue,
      surfaceBright: AppColors.surface,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.canvas,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.softLavender,
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
        ChangeNotifierProvider(
          create: (_) => AppLockController()..initialize(),
        ),
        ChangeNotifierProvider(create: (_) => NoteProvider()..loadEntries()),
      ],
      child: MaterialApp(
        title: '非空笔记',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
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
                  fontFamily: 'serif',
                  fontSize: 30,
                  height: 1.18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.7,
                ),
                headlineMedium: const TextStyle(
                  color: AppColors.ink,
                  fontFamily: 'serif',
                  fontSize: 26,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.5,
                ),
                headlineSmall: const TextStyle(
                  color: AppColors.ink,
                  fontFamily: 'serif',
                  fontSize: 22,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.25,
                ),
                titleLarge: const TextStyle(
                  color: AppColors.ink,
                  fontFamily: 'serif',
                  fontSize: 19,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                ),
                titleMedium: const TextStyle(
                  color: AppColors.ink,
                  fontFamily: 'serif',
                  fontSize: 16,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
                bodyLarge: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 16,
                  height: 1.55,
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
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            foregroundColor: AppColors.ink,
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
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: AppColors.line),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppColors.surface,
            hintStyle: const TextStyle(color: AppColors.muted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: AppColors.moss),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            height: 66,
            elevation: 0,
            backgroundColor: AppColors.surface,
            surfaceTintColor: Colors.transparent,
            indicatorColor: Colors.transparent,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
                size: 23,
                color: states.contains(WidgetState.selected)
                    ? AppColors.moss
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
                    ? AppColors.moss
                    : AppColors.muted,
              ),
            ),
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData(
            backgroundColor: AppColors.moss,
            foregroundColor: Colors.white,
            elevation: 2,
            focusElevation: 2,
            hoverElevation: 3,
            highlightElevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              side: const BorderSide(color: AppColors.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
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
        home: const HomePage(),
      ),
    );
  }
}
