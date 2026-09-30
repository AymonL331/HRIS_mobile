import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/shared/theme.dart';
import 'package:hris_mobile/shared/tokens.dart';

void main() {
  group('buildTheme', () {
    test('light carries the web light tokens', () {
      final theme = buildTheme(Brightness.light);
      final t = theme.extension<HrisTokens>()!;
      expect(t.bg, const Color(0xFFF7F7F6));
      expect(t.surface, const Color(0xFFFFFFFF));
      expect(t.primary, const Color(0xFF0B5563));
      expect(theme.scaffoldBackgroundColor, t.bg);
      expect(theme.colorScheme.primary, t.primary);
      expect(theme.colorScheme.error, t.danger.solid);
      expect(theme.colorScheme.surfaceTint, Colors.transparent);
    });

    test('dark carries the web dark tokens', () {
      final theme = buildTheme(Brightness.dark);
      final t = theme.extension<HrisTokens>()!;
      expect(theme.brightness, Brightness.dark);
      expect(t.bg, const Color(0xFF0F1416));
      expect(t.surface, const Color(0xFF171C1E));
      expect(t.primary, const Color(0xFF137A8C));
      expect(theme.scaffoldBackgroundColor, t.bg);
    });

    test('the type scale is the web scale', () {
      final text = buildTheme().textTheme;
      expect(text.bodyMedium!.fontSize, 14.0);
      expect(text.bodyLarge!.fontSize, 16.0);
      expect(text.headlineSmall!.fontSize, 24.0);
      expect(text.headlineSmall!.fontWeight, FontWeight.w600);
      expect(text.labelSmall!.fontSize, 12.0);
      expect(text.displaySmall!.fontSize, 24.0);
    });

    test('the no-arg call is the light theme', () {
      expect(buildTheme().brightness, Brightness.light);
    });
  });

  group('HrisTokens.of', () {
    testWidgets('falls back by brightness under a bare MaterialApp', (tester) async {
      late HrisTokens light;
      late HrisTokens dark;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        light = HrisTokens.of(c);
        return const SizedBox();
      })));
      await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Builder(builder: (c) {
        dark = HrisTokens.of(c);
        return const SizedBox();
      })));
      // MaterialApp animates a theme change; settle so the dark theme is in force.
      await tester.pumpAndSettle();
      expect(light.bg, HrisTokens.light.bg);
      expect(dark.bg, HrisTokens.dark.bg);
    });

    test('lerp interpolates every colour', () {
      final mid = HrisTokens.light.lerp(HrisTokens.dark, 0.5);
      expect(mid.bg, Color.lerp(HrisTokens.light.bg, HrisTokens.dark.bg, 0.5));
      expect(mid.danger.text, Color.lerp(HrisTokens.light.danger.text, HrisTokens.dark.danger.text, 0.5));
    });
  });
}
