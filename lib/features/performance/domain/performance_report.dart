enum PerformancePeriod {
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly'),
  quarterly('Quarterly'),
  annually('Annually');

  const PerformancePeriod(this.label);
  final String label;
}

class PerformanceEmployee {
  PerformanceEmployee(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get name => data['full_name'] as String? ?? 'Employee';
  String get department => data['department'] as String? ?? 'Not assigned';
  double? value(String key) => (data[key] as num?)?.toDouble();
  double? get score => value('score');
  String get rating {
    final score = this.score;
    if (score == null) return 'No data';
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'On track';
    if (score >= 60) return 'Developing';
    return 'Needs attention';
  }
}

class PerformanceReport {
  PerformanceReport.fromJson(Map<String, dynamic> json)
    : start = DateTime.parse(json['start'] as String),
      end = DateTime.parse(json['end'] as String),
      today = DateTime.parse(json['today'] as String),
      timezone = json['timezone'] as String,
      provisional = json['provisional'] as bool,
      employees = (json['employees'] as List)
          .map(
            (row) => PerformanceEmployee(Map<String, dynamic>.from(row as Map)),
          )
          .toList();

  final DateTime start;
  final DateTime end;
  final DateTime today;
  final String timezone;
  final bool provisional;
  final List<PerformanceEmployee> employees;
}

String performanceDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
