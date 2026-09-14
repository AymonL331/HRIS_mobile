import 'package:flutter/material.dart';

import '../../shared/tokens.dart';

/// Drawings of the Android screens the setup wizard sends the employee to, with
/// the choice to make marked "Tap" and the wrong ones struck through.
///
/// Drawn rather than bundled as screenshots on purpose: the real screens differ
/// by Android version and phone brand, so a screenshot is always slightly wrong
/// for someone, while a diagram only has to carry the WORDS they will see — and
/// Android keeps those the same. It also follows light/dark for free.
enum MockMark { pick, avoid, plain }

TextStyle _label(HrisTokens t, MockMark mark) => TextStyle(
  fontSize: HrisType.xs,
  color: t.text,
  fontWeight: mark == MockMark.pick ? HrisType.semibold : FontWeight.w400,
  decoration: mark == MockMark.avoid ? TextDecoration.lineThrough : null,
);

class _Frame extends StatelessWidget {
  final List<Widget> children;

  const _Frame({required this.children});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Container(
        padding: const EdgeInsets.all(HrisSpace.s3 + 2),
        decoration: BoxDecoration(
          color: t.bg,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// One row of a mock screen, marked as the one to tap, one to avoid, or plain.
class _Marked extends StatelessWidget {
  final MockMark mark;
  final Widget child;
  final bool center;

  const _Marked({required this.mark, required this.child, this.center = false});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final pick = mark == MockMark.pick;
    final row = Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: 9),
      decoration: BoxDecoration(
        color: pick ? t.primarySoft : t.surface,
        border: Border.all(color: pick ? t.primary : t.border, width: pick ? 2 : 1),
        borderRadius: BorderRadius.circular(HrisRadius.sm + 2),
      ),
      child: Row(
        children: [
          Expanded(child: center ? Center(child: child) : child),
          if (pick) ...[const SizedBox(width: 6), const _TapPill()],
          if (mark == MockMark.avoid) Icon(Icons.close, size: 16, color: t.danger.text),
        ],
      ),
    );
    return mark == MockMark.avoid ? Opacity(opacity: 0.5, child: row) : row;
  }
}

class _TapPill extends StatelessWidget {
  const _TapPill();

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(HrisRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app, size: 12, color: t.primaryContrast),
          const SizedBox(width: 2),
          Text(
            'Tap',
            style: TextStyle(fontSize: 10.5, fontWeight: HrisType.semibold, color: t.primaryContrast),
          ),
        ],
      ),
    );
  }
}

/// Android's first location dialog: Precise vs Approximate, then three buttons.
class PermissionDialogMock extends StatelessWidget {
  const PermissionDialogMock({super.key});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return _Frame(
      children: [
        Icon(Icons.location_on_outlined, size: 22, color: t.primary),
        const SizedBox(height: 6),
        Text(
          'Allow HRIS to access this device’s location?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, color: t.text),
        ),
        const SizedBox(height: HrisSpace.s3),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _AccuracyChoice(icon: Icons.my_location, label: 'Precise', picked: true),
            ),
            Expanded(
              child: _AccuracyChoice(icon: Icons.map_outlined, label: 'Approximate', picked: false),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // BOTH grant location for now, and the next step turns either one into
        // "Allow all the time" in Settings (user, 2026-09-14) — so both are marked
        // as a right tap. Only "Don't allow" leads nowhere.
        _Marked(
          mark: MockMark.pick,
          center: true,
          child: Text('While using the app', style: _label(t, MockMark.pick)),
        ),
        _Marked(
          mark: MockMark.pick,
          center: true,
          child: Text('Only this time', style: _label(t, MockMark.pick)),
        ),
        _Marked(
          mark: MockMark.avoid,
          center: true,
          child: Text('Don’t allow', style: _label(t, MockMark.avoid)),
        ),
      ],
    );
  }
}

class _AccuracyChoice extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool picked;

  const _AccuracyChoice({required this.icon, required this.label, required this.picked});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.surface,
            border: Border.all(color: picked ? t.primary : t.border, width: picked ? 3 : 1),
          ),
          child: Icon(icon, size: 26, color: picked ? t.primary : t.muted),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: HrisType.xs,
            color: t.text,
            fontWeight: picked ? HrisType.semibold : FontWeight.w400,
          ),
        ),
        if (picked)
          Text(
            'Keep this',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: t.primary, fontWeight: HrisType.semibold),
          ),
      ],
    );
    return picked ? body : Opacity(opacity: 0.5, child: body);
  }
}

/// The app's "Location permission" page in Settings — where "Allow all the
/// time" and "Use precise location" actually live on Android 11+.
class LocationPermissionPageMock extends StatelessWidget {
  /// False when "Allow all the time" is already chosen and only the precise
  /// switch needs flipping.
  final bool highlightAlways;

  const LocationPermissionPageMock({super.key, this.highlightAlways = true});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    Widget radio(String label, {bool selected = false, MockMark mark = MockMark.plain}) => _Marked(
      mark: mark,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 16,
            color: selected ? t.primary : t.muted,
          ),
          const SizedBox(width: HrisSpace.s2),
          Expanded(child: Text(label, style: _label(t, mark))),
        ],
      ),
    );
    return _Frame(
      children: [
        Row(
          children: [
            Icon(Icons.arrow_back, size: 16, color: t.muted),
            const SizedBox(width: HrisSpace.s2),
            // Flexible: a large system font size must wrap the title, not
            // overflow the drawing.
            Flexible(
              child: Text(
                'Location permission',
                style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, color: t.text),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Text(
            'HRIS',
            style: TextStyle(fontSize: HrisType.xs, color: t.muted),
          ),
        ),
        const SizedBox(height: 4),
        radio('Allow all the time', selected: true, mark: highlightAlways ? MockMark.pick : MockMark.plain),
        radio('Allow only while using the app'),
        radio('Ask every time'),
        radio('Don’t allow'),
        const SizedBox(height: HrisSpace.s2),
        _Marked(
          mark: MockMark.pick,
          child: Row(
            children: [
              Expanded(child: Text('Use precise location', style: _label(t, MockMark.pick))),
              Icon(Icons.toggle_on, size: 30, color: t.primary),
            ],
          ),
        ),
      ],
    );
  }
}

/// A two-button system dialog (notifications, battery).
class SimpleDialogMock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String allow;
  final String deny;

  const SimpleDialogMock({super.key, required this.icon, required this.title, required this.allow, required this.deny});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return _Frame(
      children: [
        Icon(icon, size: 22, color: t.primary),
        const SizedBox(height: 6),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: HrisType.sm, fontWeight: HrisType.semibold, color: t.text),
        ),
        const SizedBox(height: 6),
        _Marked(
          mark: MockMark.pick,
          center: true,
          child: Text(allow, style: _label(t, MockMark.pick)),
        ),
        _Marked(
          mark: MockMark.avoid,
          center: true,
          child: Text(deny, style: _label(t, MockMark.avoid)),
        ),
      ],
    );
  }
}
