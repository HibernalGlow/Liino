part of 'welcome_screen.dart';

class _ScanningLottieAnimation extends StatelessWidget {
  const _ScanningLottieAnimation();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 400.s,
        height: 300.s,
        child: Lottie.asset(
          AppAssets.loadingAnimation,
          fit: BoxFit.contain,
          repeat: true,
        ),
      ),
    );
  }
}
