import 'package:flutter/material.dart';

import '../../shared/tokens.dart';

/// The web DetailSection (EmployeeDetail.module.css `.section`): a bordered
/// panel, 16px semibold title, a secondary description, then the label/value
/// fields — one column on a phone (the web's ≤640px rule).
class DetailSection extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget> children;

  const DetailSection({super.key, required this.title, this.description, required this.children});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: HrisSpace.s3),
      padding: const EdgeInsets.fromLTRB(HrisSpace.s4, 14, HrisSpace.s4, HrisSpace.s4),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(HrisRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: TextStyle(fontSize: HrisType.md, height: 24 / 16, fontWeight: HrisType.semibold, color: t.text)),
          if (description != null)
            Text(description!, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text2)),
          const SizedBox(height: HrisSpace.s3),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: HrisSpace.s3),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// The web DetailField: a 12px secondary label over the value; an empty value
/// is an em dash so the layout stays even. [value] is text or a widget (a badge).
class DetailField extends StatelessWidget {
  final String label;
  final Object? value;

  const DetailField(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final v = value;
    final empty = v == null || (v is String && v.isEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: HrisType.xs, height: 16 / 12, color: t.text2)),
        const SizedBox(height: 2),
        if (v is Widget)
          v
        else
          Text(empty ? '—' : '$v', style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text)),
      ],
    );
  }
}

/// The web's `.mutedValue`: muted italic ("Not enrolled").
class MutedValue extends StatelessWidget {
  final String text;

  const MutedValue(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: HrisTokens.of(context).muted, fontStyle: FontStyle.italic),
      );
}

/// One column of [DetailRowsTable].
class RowsColumn {
  final String label;
  final String Function(Map<String, dynamic> row) value;

  /// Long free text (an address) gets a wider cell that wraps.
  final bool long;

  const RowsColumn(this.label, this.value, {this.long = false});
}

/// The web DetailRowsTable: a bordered compact table that scrolls sideways on
/// a phone, sunken header row with the app's mono caps labels; an empty value
/// is an em dash; no rows → the muted empty line.
class DetailRowsTable extends StatelessWidget {
  final List<RowsColumn> columns;
  final List<Map<String, dynamic>> rows;
  final String emptyMessage;

  const DetailRowsTable({super.key, required this.columns, required this.rows, required this.emptyMessage});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    if (rows.isEmpty) {
      return Text(emptyMessage, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.muted));
    }
    final head = TextStyle(
      fontFamily: HrisFont.mono,
      fontSize: 11,
      height: 16 / 11,
      fontWeight: HrisType.medium,
      letterSpacing: 1.1,
      color: t.text2,
    );
    final cell = TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text);
    Widget box(Widget child, {required bool long, bool header = false, bool last = false}) => Container(
          constraints: BoxConstraints(minWidth: long ? 224 : 112, maxWidth: long ? 384 : 260),
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: header ? 8 : 6),
          decoration: BoxDecoration(
            color: header ? t.surfaceSunken : null,
            border: last ? null : Border(bottom: BorderSide(color: t.border)),
          ),
          child: child,
        );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(HrisRadius.control),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(children: [
              for (final c in columns) box(Text(c.label.toUpperCase(), style: head), long: c.long, header: true),
            ]),
            for (var i = 0; i < rows.length; i++)
              TableRow(children: [
                for (final c in columns)
                  box(
                    Text(_orDash(c.value(rows[i])), style: cell),
                    long: c.long,
                    last: i == rows.length - 1,
                  ),
              ]),
          ],
        ),
      ),
    );
  }

  static String _orDash(String s) => s.isEmpty ? '—' : s;
}
