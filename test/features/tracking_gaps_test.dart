import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hris_mobile/features/tracking/tracking_gaps.dart';

import '../fakes/clock_fakes.dart';

/// 2026-11-13: long gaps on the open shift must be explained before clock-out.
class FakeGapsApi implements TrackingGapsApi {
  List<TrackingGap> gaps;
  Object? failWith;
  final submitted = <Map<TrackingGap, String>>[];
  FakeGapsApi(this.gaps);

  @override
  Future<List<TrackingGap>> needingReason(int attendanceLogId) async {
    if (failWith != null) throw failWith!;
    return gaps;
  }

  @override
  Future<void> submit(int attendanceLogId, Map<TrackingGap, String> reasons) async => submitted.add(reasons);
}

final _gap = TrackingGap(
  startAt: DateTime.utc(2026, 11, 13, 1, 0),
  endAt: DateTime.utc(2026, 11, 13, 3, 15),
  minutes: 135,
);

Future<bool?> _run(WidgetTester tester, FakeGapsApi api, {FakeTrackingService? tracking}) async {
  bool? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => result = await explainGapsBeforeClockOut(context, attendanceLogId: 5, api: api, tracking: tracking),
        child: const Text('OUT'),
      ),
    ),
  ));
  await tester.tap(find.text('OUT'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('no gaps: clock-out goes on at once, after sending what the phone holds', (tester) async {
    final tracking = FakeTrackingService();
    expect(await _run(tester, FakeGapsApi([]), tracking: tracking), isTrue);
    expect(tracking.flushes, 1);
  });

  testWidgets('the server cannot be asked: the clock-out is never blocked', (tester) async {
    final api = FakeGapsApi([_gap])..failWith = Exception('offline');
    expect(await _run(tester, api), isTrue);
  });

  testWidgets('a gap: the reason is required, then sent with the clock-out', (tester) async {
    final api = FakeGapsApi([_gap]);
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await explainGapsBeforeClockOut(context, attendanceLogId: 5, api: api),
          child: const Text('OUT'),
        ),
      ),
    ));
    await tester.tap(find.text('OUT'));
    await tester.pumpAndSettle();

    expect(find.text('Explain the time with no location'), findsOneWidget);
    expect(find.textContaining('2 h 15 min'), findsOneWidget);
    final send = find.widgetWithText(FilledButton, 'Send and clock out');
    expect(tester.widget<FilledButton>(send).onPressed, isNull, reason: 'no reason typed yet');

    await tester.enterText(find.byType(TextField), 'Battery died at the client site');
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(api.submitted.single.values.single, 'Battery died at the client site');
  });

  testWidgets('Cancel stops the clock-out and sends nothing', (tester) async {
    final api = FakeGapsApi([_gap]);
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await explainGapsBeforeClockOut(context, attendanceLogId: 5, api: api),
          child: const Text('OUT'),
        ),
      ),
    ));
    await tester.tap(find.text('OUT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(api.submitted, isEmpty);
  });
}
