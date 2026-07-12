import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'providers/app_locale_controller.dart';
import 'services/file_storage_service.dart';
import 'services/model_download_source_policy.dart';
import 'widgets/brand_mark.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  } catch (_) {
    runApp(const _InitializationFailureApp());
    return;
  }
  runApp(const FkNotesApp());
}

class _InitializationFailureApp extends StatelessWidget {
  const _InitializationFailureApp();
  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: '非空笔记',
    debugShowCheckedModeBanner: false,
    home: _BrandLaunchScreen(error: true),
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
            const Positioned(
              left: 0,
              right: 0,
              bottom: 42,
              child: Center(
                child: Text(
                  '本地存储初始化失败',
                  style: TextStyle(color: AppColors.coral, fontSize: 12),
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
      const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '非空笔记',
            style: TextStyle(
              color: AppColors.ink,
              fontFamily: 'serif',
              fontSize: 31,
              height: 1.18,
              fontWeight: FontWeight.w700,
              letterSpacing: .4,
            ),
          ),
          SizedBox(height: 5),
          Text(
            '本地优先 · 私密可靠',
            style: TextStyle(
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
