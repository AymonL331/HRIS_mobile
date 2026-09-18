import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/shared/theme.dart';
import 'package:hris_mobile/shared/tokens.dart';
import 'package:hris_mobile/shared/widgets/brand_mark.dart';
import 'package:hris_mobile/shared/widgets/message_banner.dart';
import 'package:hris_mobile/shared/widgets/status_badge.dart';
import 'package:hris_mobile/shared/widgets/user_avatar.dart';

Future<void> mount(WidgetTester tester, Widget child, {Brightness brightness = Brightness.light}) =>
    tester.pumpWidget(MaterialApp(theme: buildTheme(brightness), home: Scaffold(body: Center(child: child))));

Color badgeBg(WidgetTester tester) =>
    (tester.widget<Container>(find.byType(Container).first).decoration! as BoxDecoration).color!;

void main() {
  group('StatusBadge', () {
    testWidgets('each tone draws the web colour set', (tester) async {
      final t = HrisTokens.light;
      await mount(tester, const StatusBadge('Late', tone: StatusTone.warning));
      expect(find.text('Late'), findsOneWidget);
      expect(badgeBg(tester), t.warning.bg);
      expect(tester.widget<Text>(find.text('Late')).style!.color, t.warning.text);

      await mount(tester, const StatusBadge('Present', tone: StatusTone.success));
      expect(badgeBg(tester), t.success.bg);
      await mount(tester, const StatusBadge('Absent', tone: StatusTone.danger));
      expect(badgeBg(tester), t.danger.bg);
      await mount(tester, const StatusBadge('OB', tone: StatusTone.info));
      expect(badgeBg(tester), t.info.bg);
      await mount(tester, const StatusBadge('No record'));
      expect(tester.widget<Text>(find.text('No record')).style!.color, t.muted);
    });

    testWidgets('dark mode uses the dark set', (tester) async {
      await mount(tester, const StatusBadge('Late', tone: StatusTone.warning), brightness: Brightness.dark);
      expect(badgeBg(tester), HrisTokens.dark.warning.bg);
    });

    test('the DTR tone mapping is the web\'s', () {
      expect(dtrDayTone('worked', 'present'), StatusTone.success);
      expect(dtrDayTone('worked', 'late'), StatusTone.warning);
      expect(dtrDayTone('worked', 'official_business'), StatusTone.info);
      expect(dtrDayTone('absent', 'absent'), StatusTone.danger);
      expect(dtrDayTone('on_leave', null), StatusTone.success);
      expect(dtrDayTone('holiday', null), StatusTone.info);
      expect(dtrDayTone('rest_day', null), StatusTone.neutral);
      expect(dtrDayTone('no_record', null), StatusTone.neutral);
      expect(dtrFlagTone('undertime'), StatusTone.warning);
      expect(dtrFlagTone('half_day'), StatusTone.info);
      expect(captureMethodTone('mobile'), StatusTone.info);
      expect(captureMethodTone('system'), StatusTone.warning);
      expect(captureMethodTone('manual'), StatusTone.neutral);
    });
  });

  group('BrandMark / UserAvatar', () {
    testWidgets('the brand renders the word once, at either size', (tester) async {
      await mount(tester, const BrandMark());
      expect(find.text('HRIS'), findsOneWidget);
      await mount(tester, const BrandMark(size: BrandMarkSize.auth));
      expect(find.text('HRIS'), findsOneWidget);
      expect(tester.widget<Text>(find.text('HRIS')).style!.fontSize, HrisType.xl);
    });

    testWidgets('the mark sits LEFT of the word, and follows the theme (light / dark artwork)', (tester) async {
      String asset() => (tester.widget<Image>(find.byType(Image)).image as AssetImage).assetName;
      await mount(tester, const BrandMark());
      expect(asset(), BrandMark.lightAsset);
      expect(tester.getTopLeft(find.byType(Image)).dx, lessThan(tester.getTopLeft(find.text('HRIS')).dx));
      expect(tester.getSize(find.byType(Image)), const Size(HrisSize.brandMark, HrisSize.brandMark));
      await mount(tester, const BrandMark(size: BrandMarkSize.auth), brightness: Brightness.dark);
      await tester.pumpAndSettle(); // the theme change animates; read the settled theme
      expect(asset(), BrandMark.darkAsset);
      expect(tester.getSize(find.byType(Image)), const Size(HrisSize.brandMarkAuth, HrisSize.brandMarkAuth));
    });

    testWidgets('the avatar shows the upper-cased first initial, ? when empty', (tester) async {
      await mount(tester, const UserAvatar('olive'));
      expect(find.text('O'), findsOneWidget);
      await mount(tester, const UserAvatar('  '));
      expect(find.text('?'), findsOneWidget);
    });
  });

  group('MessageBanner', () {
    testWidgets('four tones, and Dismiss fires onClose', (tester) async {
      var closed = 0;
      await mount(tester, MessageBanner.error('Bad', onClose: () => closed++));
      expect(find.text('Bad'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      expect(closed, 1);

      await mount(tester, const MessageBanner.success('Good'));
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byTooltip('Dismiss'), findsNothing);
      await mount(tester, const MessageBanner.warning('Careful'));
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
      await mount(tester, const MessageBanner.info('Note'));
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  });
}
