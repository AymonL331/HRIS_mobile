import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/http/api_exception.dart';
import '../../shared/tokens.dart';
import '../../shared/widgets/kit.dart';
import '../../shared/widgets/status_badge.dart';
import '../my_profile/section_tabs.dart';
import '../my_profile/web_format.dart';
import 'accountabilities_api.dart';
import 'accountabilities_models.dart';

/// MY ACCOUNTABILITIES (server migration 103) — the web page
/// (pages/employee/MyAccountabilitiesPage.jsx + AccountabilityList) on the
/// phone: what the company issued me — devices, accounts, system logins — with
/// their details and photos, still with me (With me) or already returned
/// (Returned). Read-only; passwords are never shown here (HR keeps them).
class AccountabilitiesScreen extends StatefulWidget {
  final AccountabilitiesApi api;

  /// Whether this page is the one showing — the list loads each time it is opened.
  final bool active;

  const AccountabilitiesScreen({super.key, required this.api, this.active = true});

  @override
  State<AccountabilitiesScreen> createState() => _AccountabilitiesScreenState();
}

class _AccountabilitiesScreenState extends State<AccountabilitiesScreen> {
  MyAccountabilities? _data;
  bool _loading = false;
  String? _error;
  String _tab = 'onboarding';
  final _open = <int>{};

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(AccountabilitiesScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.api.listMine();
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _data = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Please try again.';
          _data = null;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final data = _data;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(HrisSpace.s4, HrisSpace.s2, HrisSpace.s4, HrisSpace.s6),
        children: [
          Text(
            'What the company issued you — devices, accounts and system logins — and what you have already returned. '
            'Contact HR if something here is not right.',
            style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.muted),
          ),
          const SizedBox(height: HrisSpace.s4),
          if (_loading && data == null)
            const LoadingBlock(semanticsLabel: 'Loading your accountabilities')
          else if (_error != null)
            StatePanel(
              error: true,
              title: "Couldn't load your accountabilities",
              message: _error,
              action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
            )
          else if (data != null) ...[
            SectionTabs(
              tabs: [
                SectionTab('onboarding', 'With me (${data.onboarding})'),
                SectionTab('offboarding', 'Returned (${data.offboarding})'),
              ],
              activeKey: _tab,
              onChange: (k) => setState(() => _tab = k),
              label: 'With me or returned',
            ),
            const SizedBox(height: HrisSpace.s4),
            ..._list(data),
          ],
        ],
      ),
    );
  }

  List<Widget> _list(MyAccountabilities data) {
    final t = HrisTokens.of(context);
    final items = data.items.where((i) => i.status == _tab).toList();
    final groups = [
      for (final s in data.sections)
        (s, items.where((i) => i.sectionId == s.id).toList()),
    ].where((g) => g.$2.isNotEmpty).toList();
    if (groups.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(HrisSpace.s4),
          child: Text(
            _tab == 'onboarding' ? 'Nothing is recorded as issued to you.' : 'Nothing returned yet.',
            style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.muted),
          ),
        ),
      ];
    }
    return [
      for (final (section, list) in groups)
        Padding(
          padding: const EdgeInsets.only(bottom: HrisSpace.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: HrisSpace.s2),
                child: Text(
                  '${section.name}${section.status == 'hidden' ? ' (hidden)' : ''}'.toUpperCase(),
                  style: TextStyle(fontFamily: HrisFont.mono, fontSize: 11, height: 16 / 11, letterSpacing: 0.9, color: t.muted),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(HrisRadius.panel),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) Divider(height: 1, thickness: 1, color: t.border),
                      _ItemRow(
                        section: section,
                        item: list[i],
                        open: _open.contains(list[i].id),
                        api: widget.api,
                        onToggle: () => setState(() {
                          if (!_open.remove(list[i].id)) _open.add(list[i].id);
                        }),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

/// Under the name: the return line, else the first filled date field, else
/// "With the employee".
String subLine(AccSection section, AccItem item) {
  if (item.status == 'offboarding') {
    final cond = returnConditionLabels[item.returnCondition] ?? '';
    final when = item.returnedAt == null || item.returnedAt!.isEmpty ? '—' : WebFormat.dateOnly(item.returnedAt);
    return 'Returned $when${cond.isNotEmpty ? ' · $cond' : ''}';
  }
  for (final f in effectiveFields(section, item.layout)) {
    final v = item.details[f.key];
    if (!f.na && f.type == 'date' && v != null && '$v'.isNotEmpty) return '${f.label}: ${WebFormat.dateOnly(v)}';
  }
  return 'With the employee';
}

class _ItemRow extends StatelessWidget {
  final AccSection section;
  final AccItem item;
  final bool open;
  final VoidCallback onToggle;
  final AccountabilitiesApi api;

  const _ItemRow({required this.section, required this.item, required this.open, required this.onToggle, required this.api});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: InkWell(
            key: Key('acc_item_${item.id}'),
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: HrisSize.touch),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s4, vertical: HrisSpace.s3),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: open ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(Icons.chevron_right, size: 18, color: t.muted),
                    ),
                    const SizedBox(width: HrisSpace.s2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: TextStyle(fontSize: HrisType.sm, height: 20 / 14, fontWeight: HrisType.semibold, color: t.text)),
                          Text(subLine(section, item), style: TextStyle(fontSize: HrisType.xs, height: 16 / 12, color: t.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (open) _ItemDetails(section: section, item: item, api: api),
      ],
    );
  }
}

class _ItemDetails extends StatelessWidget {
  final AccSection section;
  final AccItem item;
  final AccountabilitiesApi api;

  const _ItemDetails({required this.section, required this.item, required this.api});

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final shown = effectiveFields(section, item.layout).where((f) {
      if (f.na) return true;
      if (f.type == 'password') return item.secretKeys.contains(f.key);
      if (f.type == 'photo') return item.photoKeys.contains(f.key);
      final v = item.details[f.key];
      return v != null && '$v'.isNotEmpty;
    }).toList();
    final muted = TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.muted);
    final body = TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.text);

    Widget pair(String label, Widget value) => Padding(
          padding: const EdgeInsets.only(bottom: HrisSpace.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 128, child: Text(label, style: muted)),
              const SizedBox(width: HrisSpace.s4),
              Expanded(child: value),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(HrisSpace.s4 + 24, 0, HrisSpace.s4, HrisSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (shown.isEmpty) pair('Details', Text('None entered.', style: muted)),
          for (final f in shown)
            pair(
              f.label,
              f.na
                  ? Text('Not applicable', style: muted)
                  : f.type == 'password'
                      ? Text('●●●●●●●●', style: body.copyWith(fontFamily: HrisFont.mono))
                      : f.type == 'photo'
                          ? _Photo(api: api, item: item, field: f)
                          : f.type == 'date'
                              ? Text(WebFormat.dateOnly(item.details[f.key]), style: body)
                              : Text('${item.details[f.key]}', style: body),
            ),
          if (item.status == 'offboarding')
            Container(
              margin: const EdgeInsets.only(top: HrisSpace.s1),
              padding: const EdgeInsets.symmetric(horizontal: HrisSpace.s3, vertical: HrisSpace.s2),
              decoration: BoxDecoration(color: t.surfaceSunken, borderRadius: BorderRadius.circular(HrisRadius.control)),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: HrisSpace.s1,
                runSpacing: HrisSpace.s1,
                children: [
                  Text.rich(TextSpan(style: body, children: [
                    const TextSpan(text: 'Returned / access removed: ', style: TextStyle(fontWeight: HrisType.semibold)),
                    TextSpan(text: item.returnedAt == null || item.returnedAt!.isEmpty ? '—' : WebFormat.dateOnly(item.returnedAt)),
                  ])),
                  if (item.returnCondition != null && item.returnCondition!.isNotEmpty)
                    StatusBadge(
                      returnConditionLabels[item.returnCondition] ?? item.returnCondition!,
                      tone: returnConditionTone(item.returnCondition),
                    ),
                  if ((item.returnedByUsername ?? '').isNotEmpty) Text('· recorded by ${item.returnedByUsername}', style: body),
                  if ((item.returnNotes ?? '').isNotEmpty) Text('· ${item.returnNotes}', style: body),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A private photo: loaded through the API (bearer), "Loading…" until then,
/// "Could not load the photo." on failure; a tap shows it large.
class _Photo extends StatefulWidget {
  final AccountabilitiesApi api;
  final AccItem item;
  final AccField field;

  const _Photo({required this.api, required this.item, required this.field});

  @override
  State<_Photo> createState() => _PhotoState();
}

class _PhotoState extends State<_Photo> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(_Photo old) {
    super.didUpdateWidget(old);
    // A new upload changes updated_at, which reloads the picture.
    if (old.item.id != widget.item.id || old.item.updatedAt != widget.item.updatedAt || old.field.key != widget.field.key) {
      _bytes = null;
      _failed = false;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    try {
      final b = await widget.api.photo(widget.item.id, widget.field.key);
      if (mounted) setState(() => _bytes = b);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HrisTokens.of(context);
    final muted = TextStyle(fontSize: HrisType.sm, height: 20 / 14, color: t.muted);
    if (_failed) return Text('Could not load the photo.', style: muted);
    final b = _bytes;
    if (b == null) return Text('Loading…', style: muted);
    final title = '${widget.item.name} — ${widget.field.label}';
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        key: Key('acc_photo_${widget.item.id}_${widget.field.key}'),
        onTap: () => showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Image.memory(b, fit: BoxFit.contain),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
          ),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220, maxHeight: 160),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(HrisRadius.control),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(b, fit: BoxFit.contain, semanticLabel: title),
        ),
      ),
    );
  }
}
