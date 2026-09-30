import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/shared/theme.dart';
import 'package:hris_mobile/shared/tokens.dart';
import 'package:hris_mobile/shared/widgets/kit.dart';
import 'package:hris_mobile/shared/widgets/status_badge.dart';

Future<void> mount(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: SingleChildScrollView(child: child))));

void main() {
  testWidgets('the quiet badge has no fill and no border, and muted text', (tester) async {
    await mount(tester, const StatusBadge('Rest day', tone: StatusTone.quiet));
    final box = tester.widget<Container>(find.byType(Container).first).decoration! as BoxDecoration;
    expect(box.color, Colors.transparent);
    expect(tester.widget<Text>(find.text('Rest day')).style!.color, HrisTokens.light.muted);
  });

  testWidgets('StatePanel shows only the caller\'s text and action', (tester) async {
    var tapped = 0;
    await mount(
      tester,
      StatePanel(
        title: 'Title here',
        message: 'Message here',
        error: true,
        action: TextButton(onPressed: () => tapped++, child: const Text('Act')),
      ),
    );
    expect(find.text('Title here'), findsOneWidget);
    expect(find.text('Message here'), findsOneWidget);
    await tester.tap(find.text('Act'));
    expect(tapped, 1);
  });

  testWidgets('RuledList draws one rule between rows and rows keep a 48dp minimum', (tester) async {
    await mount(tester, const RuledList(children: [RuledRow(child: Text('A')), RuledRow(child: Text('B')), RuledRow(child: Text('C'))]));
    expect(find.byType(Divider), findsNWidgets(2));
    expect(tester.getSize(find.byType(RuledRow).first).height, greaterThanOrEqualTo(HrisSize.touch));
  });
}
