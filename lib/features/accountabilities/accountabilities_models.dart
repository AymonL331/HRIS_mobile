import '../../core/format/money.dart';
import '../../shared/widgets/status_badge.dart';
import '../my_profile/web_format.dart';

List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? v.map(asJsonMap).whereType<Map<String, dynamic>>().toList() : const [];

/// GET /api/me/accountabilities → { sections, items, counts }.
class MyAccountabilities {
  final List<AccSection> sections;
  final List<AccItem> items;
  final int onboarding;
  final int offboarding;

  const MyAccountabilities({required this.sections, required this.items, required this.onboarding, required this.offboarding});

  factory MyAccountabilities.fromJson(Map<String, dynamic> j) {
    final counts = asJsonMap(j['counts']) ?? const {};
    return MyAccountabilities(
      sections: _maps(j['sections']).map(AccSection.fromJson).toList(),
      items: _maps(j['items']).map(AccItem.fromJson).toList(),
      onboarding: Money.asNum(counts['onboarding']).toInt(),
      offboarding: Money.asNum(counts['offboarding']).toInt(),
    );
  }
}

/// One field a section asks for: { key, label, type: text|date|note|password|photo, required }.
class AccField {
  final String key;
  final String label;
  final String type;

  /// "Not applicable" for this one item (its layout's `na`).
  final bool na;

  const AccField({required this.key, required this.label, required this.type, this.na = false});

  factory AccField.fromJson(Map<String, dynamic> j) =>
      AccField(key: '${j['key'] ?? ''}', label: '${j['label'] ?? ''}', type: '${j['type'] ?? 'text'}');

  AccField copyWith({String? label, bool? na}) => AccField(key: key, label: label ?? this.label, type: type, na: na ?? this.na);
}

class AccSection {
  final int id;
  final String name;
  final String status;
  final List<AccField> fields;

  const AccSection({required this.id, required this.name, required this.status, required this.fields});

  factory AccSection.fromJson(Map<String, dynamic> j) => AccSection(
        id: Money.asNum(j['id']).toInt(),
        name: '${j['name'] ?? ''}',
        status: '${j['status'] ?? 'active'}',
        fields: _maps(j['fields']).map(AccField.fromJson).toList(),
      );
}

class AccItem {
  final int id;
  final int sectionId;
  final String name;
  final String status; // onboarding | offboarding
  final Map<String, dynamic> details;
  final Map<String, dynamic>? layout;
  final String? returnedAt;
  final String? returnCondition;
  final String? returnNotes;
  final String? returnedByUsername;
  final String? updatedAt;
  final List<String> secretKeys;
  final List<String> photoKeys;

  const AccItem({
    required this.id,
    required this.sectionId,
    required this.name,
    required this.status,
    required this.details,
    this.layout,
    this.returnedAt,
    this.returnCondition,
    this.returnNotes,
    this.returnedByUsername,
    this.updatedAt,
    this.secretKeys = const [],
    this.photoKeys = const [],
  });

  factory AccItem.fromJson(Map<String, dynamic> j) => AccItem(
        id: Money.asNum(j['id']).toInt(),
        sectionId: Money.asNum(j['section_id']).toInt(),
        name: '${j['name'] ?? ''}',
        status: '${j['status'] ?? ''}',
        details: asJsonMap(j['details']) ?? const {},
        layout: asJsonMap(j['layout']),
        returnedAt: j['returned_at']?.toString(),
        returnCondition: j['return_condition'] as String?,
        returnNotes: j['return_notes'] as String?,
        returnedByUsername: j['returned_by_username'] as String?,
        updatedAt: j['updated_at']?.toString(),
        secretKeys: ((j['secret_keys'] as List?) ?? const []).map((e) => '$e').toList(),
        photoKeys: ((j['photo_keys'] as List?) ?? const []).map((e) => '$e').toList(),
      );
}

/// The web's utils/accountabilities#effectiveFields: the section's fields
/// (relabelled for this item, flagged N/A), then the item's own extras.
List<AccField> effectiveFields(AccSection? section, Map<String, dynamic>? layout) {
  final l = layout ?? const {};
  final labels = asJsonMap(l['labels']) ?? const {};
  final na = ((l['na'] as List?) ?? const []).map((e) => '$e').toSet();
  return [
    for (final f in section?.fields ?? const <AccField>[])
      f.copyWith(label: labels[f.key] is String && (labels[f.key] as String).isNotEmpty ? labels[f.key] as String : f.label, na: na.contains(f.key)),
    for (final e in _maps(l['extra'])) AccField.fromJson(e),
  ];
}

const returnConditionLabels = {
  'good': 'Good',
  'damaged': 'Damaged',
  'lost': 'Lost',
  'not_returned': 'Not returned',
};

StatusTone returnConditionTone(String? v) => switch (v) {
      'good' => StatusTone.success,
      'damaged' => StatusTone.warning,
      'lost' || 'not_returned' => StatusTone.danger,
      _ => StatusTone.neutral,
    };
