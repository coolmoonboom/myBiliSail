import 'package:flutter/widgets.dart';

/// Shares the floating refresh button preference with list viewports.
/// Widgets outside the scope keep the button, matching the saved default.
final class FloatingActionsScope extends InheritedWidget {
  const FloatingActionsScope({
    super.key,
    required this.refreshButtonVisible,
    required super.child,
  });

  final bool refreshButtonVisible;

  static bool refreshButtonVisibleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FloatingActionsScope>()
          ?.refreshButtonVisible ??
      true;

  @override
  bool updateShouldNotify(FloatingActionsScope oldWidget) =>
      refreshButtonVisible != oldWidget.refreshButtonVisible;
}
