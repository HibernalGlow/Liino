import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:looper_player/core/theme/app_assets.dart';

class AppLoadingIndicator extends StatelessWidget {
  final double size;
  const AppLoadingIndicator({super.key, this.size = 120.0});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Lottie.asset(AppAssets.loadingAnimation, fit: BoxFit.contain),
      ),
    );
  }
}
