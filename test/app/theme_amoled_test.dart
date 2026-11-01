import 'package:bilisail/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('amoled keeps the dark hues over a pure black base', () {
    final amoled = BiliTheme.amoled();
    expect(amoled.brightness, Brightness.dark);
    expect(amoled.scaffoldBackgroundColor, const Color(0xFF000000));
    expect(amoled.colorScheme.surface, const Color(0xFF000000));
    expect(amoled.colorScheme.surfaceContainerLowest, const Color(0xFF000000));
    expect(amoled.appBarTheme.backgroundColor, const Color(0xFF000000));

    final dark = BiliTheme.dark();
    expect(amoled.colorScheme.primary, dark.colorScheme.primary);
    expect(amoled.colorScheme.onSurface, dark.colorScheme.onSurface);
    expect(amoled.colorScheme.outline, dark.colorScheme.outline);
    expect(
      amoled.colorScheme.onSurfaceVariant,
      dark.colorScheme.onSurfaceVariant,
    );
  });

  test('amoled containers stay lifted above the black scaffold', () {
    final scheme = BiliTheme.amoled().colorScheme;
    final luminances = <int>[
      scheme.surface.toARGB32(),
      scheme.surfaceContainerLow.toARGB32(),
      scheme.surfaceContainerHigh.toARGB32(),
      scheme.surfaceContainerHighest.toARGB32(),
    ];
    for (var index = 1; index < luminances.length; index++) {
      expect(
        luminances[index],
        greaterThan(luminances[index - 1]),
        reason: 'container $index should read above the previous layer',
      );
    }
    expect(
      scheme.outlineVariant.toARGB32(),
      greaterThan(scheme.surface.toARGB32()),
    );
    expect(
      scheme.primaryContainer.toARGB32(),
      greaterThan(scheme.surface.toARGB32()),
    );
    expect(
      scheme.onPrimaryContainer.toARGB32(),
      greaterThan(scheme.primaryContainer.toARGB32()),
    );
  });

  test('regular dark theme keeps its tinted surfaces', () {
    final dark = BiliTheme.dark();
    expect(dark.colorScheme.surface, const Color(0xFF1C2530));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF141D27));
    expect(dark.colorScheme.surfaceContainer, const Color(0xFF232F3D));
  });
}
