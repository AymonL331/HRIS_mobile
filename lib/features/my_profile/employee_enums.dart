import '../../shared/widgets/status_badge.dart';

/// The web's constants/employeeEnums.js — labels + badge tones for the
/// employees ENUM columns, mirroring database/schema.sql exactly.

const statusLabels = {'active': 'Active', 'inactive': 'Inactive'};

StatusTone statusTone(String? v) => switch (v) {
      'active' => StatusTone.success,
      _ => StatusTone.neutral,
    };

const employmentStatusLabels = {
  'probationary': 'Probationary',
  'regular': 'Regular',
  'project_based': 'Project Based',
  'seasonal': 'Seasonal',
  'contractual': 'Contractual',
  'casual': 'Casual',
  'intern_ojt': 'Intern / OJT',
  'trainee': 'Trainee',
  'consultant': 'Consultant',
};

StatusTone employmentStatusTone(String? v) => switch (v) {
      'probationary' => StatusTone.warning,
      'regular' => StatusTone.success,
      'project_based' || 'seasonal' || 'contractual' || 'consultant' => StatusTone.info,
      _ => StatusTone.neutral,
    };

const employmentTypeLabels = {
  'full_time': 'Full Time',
  'part_time': 'Part Time',
  'freelancer': 'Freelancer',
  'apprentice': 'Apprentice',
  'remote': 'Remote',
  'field_based': 'Field Based',
};

const workArrangementLabels = {'office': 'Office', 'field': 'Field', 'hybrid': 'Hybrid'};

const salaryTypeLabels = {'monthly': 'Monthly', 'daily': 'Daily', 'hourly': 'Hourly'};

const civilStatusLabels = {
  'single': 'Single',
  'married': 'Married',
  'annulled': 'Annulled',
  'separated': 'Separated',
  'widowed': 'Widowed',
  'others': 'Others',
};

const genderLabels = {'male': 'Male', 'female': 'Female', 'other': 'Other'};

const educationLevelLabels = {
  'elementary': 'Elementary',
  'high_school': 'High School',
  'college': 'College',
  'graduate_special': 'Graduate / Special Studies',
  'post_graduate_others': 'Post Graduate / Others',
};

const familyRelationLabels = {
  'father': 'Father',
  'mother': 'Mother',
  'spouse': 'Spouse',
  'sibling': 'Sibling',
  'child': 'Child',
};

/// data_access_level ENUM('all','branch','department','self').
const dataAccessLabels = {
  'all': 'Full access',
  'branch': 'Branch',
  'department': 'Department',
  'self': 'Self-service',
};

/// labelFor: '' for no value, the label when known, else the raw value.
String labelFor(Map<String, String> map, Object? value) {
  final v = value?.toString() ?? '';
  if (v.isEmpty) return '';
  return map[v] ?? v;
}
