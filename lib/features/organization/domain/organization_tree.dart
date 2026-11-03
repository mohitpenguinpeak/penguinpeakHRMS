/// A forest of the visible, approved directory. Missing managers stay separate;
/// cyclic links are flagged and omitted from rendering, never rewritten in data.
class OrganizationTree {
  OrganizationTree(List<Map<String, dynamic>> profiles) {
    for (final profile in profiles) {
      final id = profile['id']?.toString() ?? '';
      if (id.isNotEmpty && profile['approval_status'] == 'approved') {
        people[id] = profile;
      }
    }
    for (final id in people.keys) {
      final path = <String>[];
      String? current = id;
      while (current != null && people.containsKey(current)) {
        final index = path.indexOf(current);
        if (index >= 0) {
          cycles.addAll(path.sublist(index));
          break;
        }
        path.add(current);
        current = manager(current);
      }
    }
    for (final id in people.keys) {
      final parent = manager(id);
      if (parent == null ||
          !people.containsKey(parent) ||
          cycles.contains(id)) {
        roots.add(id);
      } else {
        (children[parent] ??= []).add(id);
      }
    }
    int compare(String a, String b) =>
        name(a).toLowerCase().compareTo(name(b).toLowerCase());
    roots.sort(compare);
    for (final reports in children.values) {
      reports.sort(compare);
    }
  }
  final people = <String, Map<String, dynamic>>{};
  final roots = <String>[];
  final children = <String, List<String>>{};
  final cycles = <String>{};
  String name(String id) => text(people[id]?['full_name'], 'Unnamed employee');
  String? manager(String id) {
    final value = people[id]?['manager_id']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? note(String id) {
    if (cycles.contains(id)) return 'Reporting cycle · needs review';
    final parent = manager(id);
    if (parent != null && !people.containsKey(parent)) {
      return 'Manager not in this directory';
    }
    if (parent == null) return 'No reporting manager assigned';
    return null;
  }

  Set<String> visible(String search, String? department) {
    final query = search.trim().toLowerCase();
    final matches = people.keys.where((id) {
      final person = people[id]!;
      return (department == null ||
              '${person['department'] ?? ''}'.trim() == department) &&
          [
            person['full_name'],
            person['department'],
            person['designation'],
          ].join(' ').toLowerCase().contains(query);
    });
    final result = <String>{};
    for (final id in matches) {
      String? current = id;
      while (current != null &&
          people.containsKey(current) &&
          result.add(current)) {
        if (cycles.contains(current)) break;
        current = manager(current);
      }
    }
    return result;
  }

  static String text(dynamic value, String fallback) =>
      value == null || '$value'.trim().isEmpty ? fallback : '$value'.trim();
}
