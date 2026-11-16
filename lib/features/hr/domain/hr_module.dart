import 'package:flutter/material.dart';

class HrField {
  const HrField(
    this.key,
    this.label, {
    this.required = true,
    this.number = false,
    this.date = false,
  });
  final String key, label;
  final bool required, number, date;
}

class HrModule {
  const HrModule(
    this.id,
    this.label,
    this.icon,
    this.description,
    this.fields, {
    this.hrCreates = false,
    this.attachment = false,
    this.checklist = const [],
  });
  final String id, label, description;
  final IconData icon;
  final List<HrField> fields;
  final bool hrCreates, attachment;
  final List<String> checklist;

  static const all = [
    HrModule(
      'payslip',
      'Payslips & Salary',
      Icons.receipt_long,
      'Private salary structures and monthly payslip downloads.',
      [
        HrField('period', 'Salary month (YYYY-MM)'),
        HrField('basic', 'Basic salary', number: true),
        HrField('allowances', 'Allowances', number: true),
        HrField('deductions', 'Deductions', number: true),
      ],
      hrCreates: true,
      attachment: true,
    ),
  ];

  List<String> get states => switch (id) {
    'onboarding' => ['active', 'completed'],
    'payslip' || 'document' => ['draft', 'published'],
    'ticket' => ['open', 'in_progress', 'resolved', 'closed'],
    _ => const [],
  };

  List<String> actions(
    String status, {
    required bool hr,
    required bool owner,
  }) => switch (id) {
    'onboarding' => status == 'active' && (owner || hr) ? ['completed'] : [],
    'payslip' || 'document' => status == 'draft' && hr ? ['published'] : [],
    'ticket' => [
      if (hr && status == 'open') 'in_progress',
      if (hr && ['open', 'in_progress'].contains(status)) 'resolved',
      if ((hr || owner) && status == 'resolved') 'closed',
      if (owner && status == 'resolved') 'open',
    ],
    _ => const [],
  };
}

String humanize(String value) => value.replaceAll('_', ' ');

String? validateHrField(HrField field, String? input) {
  final value = input?.trim() ?? '';
  if (value.isEmpty) {
    return field.required ? '${field.label} is required' : null;
  }
  if (value.length > 4000) return 'Use 4,000 characters or fewer';
  if (field.number) {
    final amount = double.tryParse(value);
    if (amount == null ||
        !amount.isFinite ||
        amount < 0 ||
        amount > 100000000) {
      return 'Enter a valid non-negative amount';
    }
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
      return 'Use up to two decimal places';
    }
  }
  if (field.date) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      return 'Use a valid YYYY-MM-DD date';
    }
  }
  if (field.key == 'period' &&
      field.label.startsWith('Salary') &&
      !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(value)) {
    return 'Use YYYY-MM';
  }
  return null;
}
