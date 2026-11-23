import 'package:flutter/services.dart';

class AppHaptics {
  AppHaptics._();

  static void light(bool enabled) {
    if (enabled) HapticFeedback.lightImpact();
  }

  static void medium(bool enabled) {
    if (enabled) HapticFeedback.mediumImpact();
  }

  static void selection(bool enabled) {
    if (enabled) HapticFeedback.selectionClick();
  }
}
