import 'package:flutter/material.dart';

/// Compact, keyboard-accessible list actions that stay outside the scroll area.
final class ScrollFloatingActions extends StatelessWidget {
  const ScrollFloatingActions({
    super.key,
    this.onRefresh,
    this.refreshTooltip = '刷新列表',
    this.onToTop,
  });

  /// Null hides the refresh action, e.g. when the user turned the floating
  /// refresh button off in settings.
  final VoidCallback? onRefresh;
  final String refreshTooltip;
  final VoidCallback? onToTop;

  @override
  Widget build(BuildContext context) {
    final refresh = onRefresh;
    if (refresh == null && onToTop == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final style = ButtonStyle(
      fixedSize: const WidgetStatePropertyAll(Size.square(48)),
      minimumSize: const WidgetStatePropertyAll(Size.square(48)),
      maximumSize: const WidgetStatePropertyAll(Size.square(48)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      backgroundColor: WidgetStatePropertyAll(colors.surface),
      foregroundColor: WidgetStatePropertyAll(colors.onSurfaceVariant),
      side: WidgetStatePropertyAll(BorderSide(color: colors.outlineVariant)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      elevation: const WidgetStatePropertyAll(1),
      shadowColor: WidgetStatePropertyAll(
        colors.shadow.withValues(alpha: 0.15),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (refresh != null)
          IconButton(
            tooltip: refreshTooltip,
            onPressed: refresh,
            style: style,
            icon: const Icon(Icons.refresh_rounded, size: 22),
          )
        else
          const SizedBox.shrink(),
        if (onToTop != null) ...[
          if (refresh != null) const SizedBox(height: 8),
          Tooltip(
            message: '回到顶部',
            child: TextButton(
              onPressed: onToTop,
              style: style,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.arrow_upward_rounded, size: 20),
                  Text(
                    '顶部',
                    textScaler: MediaQuery.textScalerOf(context)
                        .clamp(maxScaleFactor: 1.3),
                    style: const TextStyle(fontSize: 10, height: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
