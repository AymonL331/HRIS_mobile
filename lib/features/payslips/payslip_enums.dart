import '../../shared/widgets/status_badge.dart';

/// Display labels + badge tones for the payslip ENUMs — the Dart twin of the
/// web's `constants/payslipEnums.js`. The values mirror `database/schema.sql`
/// exactly (they are not invented data); the tone is a UI-only mapping, and it
/// is the same mapping the website uses so a Released payslip is green in both
/// places.

/// `payslips.status` ENUM('draft','generated','released','void')
const payslipStatusLabels = <String, String>{
  'draft': 'Draft',
  'generated': 'Generated',
  'released': 'Released',
  'void': 'Void',
};

StatusTone payslipStatusTone(String? status) => switch (status) {
      'draft' => StatusTone.neutral,
      'generated' => StatusTone.info,
      'released' => StatusTone.success,
      'void' => StatusTone.danger,
      _ => StatusTone.neutral,
    };

String payslipStatusLabel(String? status) =>
    payslipStatusLabels[status] ?? (status == null || status.isEmpty ? '—' : status);

/// `payslip_items.category` ENUM('earning','deduction','allowance','contribution','tax')
const payslipItemCategoryLabels = <String, String>{
  'earning': 'Earnings',
  'allowance': 'Allowances',
  'deduction': 'Deductions',
  'contribution': 'Contributions',
  'tax': 'Tax',
};

/// Render order for grouped line items (earnings first, tax last).
const payslipItemCategoryOrder = <String>['earning', 'allowance', 'contribution', 'deduction', 'tax'];

/// `payroll_runs.type` ENUM('normal','thirteenth_month') — the web's
/// RUN_TYPE_LABELS, used only to build a run's fallback display name.
const payrollRunTypeLabels = <String, String>{
  'normal': 'Normal',
  'thirteenth_month': '13th Month',
};
