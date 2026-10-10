import 'package:flutter/material.dart';

extension HapticSnackBar on ScaffoldMessengerState {
  /// Shows [snackBar] at once and plays [haptic] (an `AppHaptics` event)
  /// with it.
  ///
  /// A plain [showSnackBar] queues behind the snackbar already on screen -
  /// the "Searching..." one a lookup opened with, say - so a haptic played
  /// next to it went off seconds before its message appeared. Here whatever
  /// is showing or waiting is dropped first, so the message slides in on
  /// the same frame the haptic plays.
  void showHapticSnackBar(VoidCallback haptic, SnackBar snackBar) {
    clearSnackBars();
    removeCurrentSnackBar();
    showSnackBar(snackBar);
    haptic();
  }
}
