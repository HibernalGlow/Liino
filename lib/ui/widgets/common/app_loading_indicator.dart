import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:looper_player/core/theme/app_assets.dart';
import 'package:looper_player/core/utils/ui_utils.dart';

class AppLoadingIndicator extends StatelessWidget {
  /// Null uses the page-loader default: 120, or 200 in a desktop window.
  final double? size;
  const AppLoadingIndicator({super.key, this.size});

  @override
  Widget build(BuildContext context) {
    final size = this.size ?? (UiUtils.isDesktop ? 200.0 : 120.0);
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Lottie.asset(AppAssets.loadingAnimation, fit: BoxFit.contain),
      ),
    );
  }
}
