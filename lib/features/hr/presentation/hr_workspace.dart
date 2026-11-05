import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/hr_repository.dart';
import '../domain/hr_module.dart';
import '../../../shared/widgets/adaptive_layout.dart';

class HrWorkspace extends StatefulWidget {
  const HrWorkspace({
    super.key,
    required this.module,
    required this.role,
    this.repository,
    this.initialRecordId,
    this.onTargetConsumed,
  });
  final HrModule module;
  final String role;
  final HrRepository? repository;
  final String? initialRecordId;
  final VoidCallback? onTargetConsumed;
  @override
  State<HrWorkspace> createState() => _HrWorkspaceState();
}

class _HrWorkspaceState extends State<HrWorkspace> {
  late final HrRepository repo =
      widget.repository ?? SupabaseHrRepository(Supabase.instance.client);
  List<Map<String, dynamic>> rows = [], employees = [];
  String? error;
  bool loading = true;
  bool _initialTargetOpened = false;
  String search = '', status = 'all';
  bool get hr => ['hr', 'admin', 'super_admin'].contains(widget.role);
  String name(dynamic id) =>
      employees
          .where((e) => e['id'] == id)
          .firstOrNull?['full_name']
          ?.toString() ??
      id?.toString() ??
      'Employee';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        repo.records(widget.module.id),
        repo.employees(),
      ]);
      if (!mounted) return;
      setState(() {
        rows = results[0];
        employees = results[1];
        loading = false;
      });
      if (!_initialTargetOpened && widget.initialRecordId != null) {
        _initialTargetOpened = true;
        widget.onTargetConsumed?.call();
        final target = await repo.record(
          widget.module.id,
          widget.initialRecordId!,
        );
        if (!mounted) return;
        if (target == null) {
          setState(
            () => error = 'This record is no longer available to your account.',
          );
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) open(target);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> create() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateRecord(
        module: widget.module,
        repo: repo,
        employees: employees,
        hr: hr,
      ),
    );
    if (created == true && mounted) await load();
  }

  Future<void> open(Map<String, dynamic> row) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _RecordDetail(
        module: widget.module,
        record: row,
        repo: repo,
        hr: hr,
        employeeName: name(row['employee_id']),
        employeeNameFor: name,
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    final filtered = rows
        .where(
          (r) =>
              (status == 'all' || r['status'] == status) &&
              '${r['title']} ${name(r['employee_id'])} ${r['description']}'
                  .toLowerCase()
                  .contains(search.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceHeading(
          title: module.label,
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: loading ? null : load,
                icon: const Icon(Icons.refresh),
              ),
              if (!module.hrCreates || hr)
                FilledButton.icon(
                  onPressed: loading ? null : create,
                  icon: const Icon(Icons.add),
                  label: const Text('New record'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(module.description),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: box.maxWidth < 600 ? box.maxWidth : 320,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Search records',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => search = v),
                ),
              ),
              SizedBox(
                width: box.maxWidth < 600 ? box.maxWidth : 220,
                child: DropdownButtonFormField<String>(
                  initialValue: status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All statuses'),
                    ),
                    for (final s in module.states)
                      DropdownMenuItem(value: s, child: Text(humanize(s))),
                  ],
                  onChanged: (v) => setState(() => status = v ?? 'all'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (error != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Could not load this module.'),
                  SelectableText(error!),
                  TextButton(onPressed: load, child: const Text('Retry')),
                ],
              ),
            ),
          )
        else if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No records found.'),
          )
        else ...[
          Text('${filtered.length} records · latest 200 visible records'),
          const SizedBox(height: 8),
          AdaptiveCards(
            minWidth: 320,
            children: [
              for (final row in filtered)
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => open(row),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row['title'].toString(),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            row['company_wide'] == true
                                ? 'Company policy'
                                : name(row['employee_id']),
                          ),
                          const SizedBox(height: 8),
                          Chip(label: Text(humanize(row['status'].toString()))),
                          if (row['description'] != '')
                            Text(
                              row['description'].toString(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          TextButton(
                            onPressed: () => open(row),
                            child: const Text('View details'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CreateRecord extends StatefulWidget {
  const _CreateRecord({
    required this.module,
    required this.repo,
    required this.employees,
    required this.hr,
  });
  final HrModule module;
  final HrRepository repo;
  final List<Map<String, dynamic>> employees;
  final bool hr;
  @override
  State<_CreateRecord> createState() => _CreateRecordState();
}

class _CreateRecordState extends State<_CreateRecord> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(), description = TextEditingController();
  late final controllers = {
    for (final f in widget.module.fields) f.key: TextEditingController(),
  };
  late String employee = widget.repo.userId;
  bool busy = false, company = false;
  String? error;
  @override
  void dispose() {
    title.dispose();
    description.dispose();
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repo.create(
        widget.module.id,
        employee,
        title.text.trim(),
        description.text.trim(),
        {for (final e in controllers.entries) e.key: e.value.text.trim()},
        company,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text('New ${widget.module.label} record'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.hr) ...[
                  DropdownButtonFormField<String>(
                    initialValue: employee,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Employee'),
                    items: [
                      for (final e in widget.employees)
                        DropdownMenuItem(
                          value: e['id'].toString(),
                          child: Text(
                            e['full_name']?.toString() ?? 'Employee',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            employee = v!;
                          }),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: title,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a title' : null,
                ),
                const SizedBox(height: 12),
                for (final field in widget.module.fields) ...[
                  TextFormField(
                    controller: controllers[field.key],
                    keyboardType: field.number
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.text,
                    minLines: 1,
                    maxLines: 1,
                    decoration: InputDecoration(
                      labelText: field.label,
                      hintText: field.date ? 'YYYY-MM-DD' : null,
                      suffixIcon: field.date
                          ? IconButton(
                              tooltip: 'Choose date',
                              icon: const Icon(Icons.calendar_today),
                              onPressed: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (date != null) {
                                  controllers[field.key]!.text = date
                                      .toIso8601String()
                                      .substring(0, 10);
                                }
                              },
                            )
                          : null,
                    ),
                    validator: (v) => validateHrField(field, v),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: description,
                  maxLength: 8000,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Details / notes',
                  ),
                ),
                if (widget.module.id == 'document' && widget.hr)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Visible to all approved employees'),
                    value: company,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => company = v!),
                  ),
                if (widget.module.attachment)
                  const Text(
                    'Save the record, then attach PDFs or images from its details.',
                  ),
                if (error != null)
                  SelectableText(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );
}

class _RecordDetail extends StatefulWidget {
  const _RecordDetail({
    required this.module,
    required this.record,
    required this.repo,
    required this.hr,
    required this.employeeName,
    required this.employeeNameFor,
  });
  final HrModule module;
  final Map<String, dynamic> record;
  final HrRepository repo;
  final bool hr;
  final String employeeName;
  final String Function(dynamic) employeeNameFor;
  @override
  State<_RecordDetail> createState() => _RecordDetailState();
}

class _RecordDetailState extends State<_RecordDetail> {
  late Map<String, dynamic> row = Map.from(widget.record);
  late Map<String, dynamic> data = Map.from(row['data'] as Map);
  final note = TextEditingController();
  late List<bool> checks = List<bool>.generate(
    widget.module.checklist.length,
    (i) => (data['checklist'] as List?)?.elementAtOrNull(i) == true,
  );
  List<Map<String, dynamic>> files = [], events = [], acks = [];
  bool busy = false, loading = true;
  String? error;
  bool get owner => row['employee_id'] == widget.repo.userId;
  String get status => row['status'].toString();
  bool get canProgress =>
      widget.module.id == 'onboarding' &&
      status == 'active' &&
      (owner || widget.hr);
  bool get canAttach => switch (widget.module.id) {
    'payslip' || 'document' => widget.hr && status == 'draft',
    'onboarding' => (owner || widget.hr) && status == 'active',
    'ticket' =>
      (owner || widget.hr) && ['open', 'in_progress'].contains(status),
    _ => false,
  };
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final results = await Future.wait([
        widget.repo.attachments(row['id'].toString()),
        widget.repo.history(row['id'].toString()),
        widget.repo.acknowledgements(row['id'].toString()),
      ]);
      if (mounted) {
        setState(() {
          files = results[0];
          events = results[1];
          acks = results[2];
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> run(Future<void> Function() work) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> update(String action) => run(() async {
    final patch = action == 'save'
        ? <String, dynamic>{if (canProgress) 'checklist': checks}
        : <String, dynamic>{};
    await widget.repo.update(row, action, note.text.trim(), patch);
    if (!mounted) return;
    // Reload authoritative revision and assignment after every mutation.
    final records = await widget.repo.records(widget.module.id);
    final fresh = records.where((e) => e['id'] == row['id']).firstOrNull;
    if (!mounted) return;
    if (fresh == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      row = fresh;
      data = Map.from(row['data'] as Map);
      note.clear();
    });
    await refresh();
  });
  Future<void> upload() => run(() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (file == null) return;
    final size = await file.xFile.length();
    if (size > 10 * 1024 * 1024) {
      throw const FormatException('File must be under 10 MB.');
    }
    await widget.repo.upload(
      row['id'].toString(),
      file.name,
      await file.readAsBytes(),
    );
    await refresh();
  });
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(row['title'].toString()),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.employeeName),
              Chip(label: Text(humanize(status))),
              SelectableText('Record ID: ${row['id']}'),
              if (row['description'] != '')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(row['description'].toString()),
                ),
              for (final f in widget.module.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SelectableText('${f.label}: ${data[f.key] ?? '—'}'),
                ),
              if (widget.module.id == 'payslip') ...[
                const SizedBox(height: 8),
                Text(
                  'Net salary: INR ${((double.tryParse(data['basic'].toString()) ?? 0) + (double.tryParse(data['allowances'].toString()) ?? 0) - (double.tryParse(data['deductions'].toString()) ?? 0)).toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(
                          'Payslip Summary • ${data['period'] ?? 'Period'}',
                        ),
                        content: SizedBox(
                          width: 425,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Employee: ${widget.employeeName}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Divider(height: 20),
                              _keyVal(
                                'Basic Salary',
                                'INR ${data['basic'] ?? '0'}',
                              ),
                              _keyVal(
                                'Allowances',
                                'INR ${data['allowances'] ?? '0'}',
                              ),
                              _keyVal(
                                'Deductions',
                                'INR ${data['deductions'] ?? '0'}',
                              ),
                              const Divider(height: 20),
                              _keyVal(
                                'Net Salary',
                                'INR ${((double.tryParse(data['basic'].toString()) ?? 0) + (double.tryParse(data['allowances'].toString()) ?? 0) - (double.tryParse(data['deductions'].toString()) ?? 0)).toStringAsFixed(2)}',
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '📄 Payslip PDF generated & downloaded successfully!',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                            icon: const Icon(Icons.download, size: 16),
                            label: const Text('Download PDF'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.picture_as_pdf, size: 16),
                  label: const Text('Download / Generate Payslip PDF'),
                ),
              ],
              for (var i = 0; i < checks.length; i++)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(widget.module.checklist[i]),
                  value: checks[i],
                  onChanged: canProgress && !busy
                      ? (v) => setState(() => checks[i] = v!)
                      : null,
                ),
              if (canProgress)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: busy ? null : () => update('save'),
                    child: const Text('Save progress'),
                  ),
                ),
              const Divider(),
              Text(
                'Attachments',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (loading) const LinearProgressIndicator(),
              for (final file in files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file),
                  title: Text(file['name'].toString()),
                  trailing: IconButton(
                    tooltip: 'Open / download',
                    icon: const Icon(Icons.download),
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            final url = await widget.repo.downloadUrl(
                              file['path'].toString(),
                            );
                            if (!await launchUrl(
                              Uri.parse(url),
                              mode: LaunchMode.externalApplication,
                            )) {
                              throw const FormatException(
                                'Unable to open document.',
                              );
                            }
                          }),
                  ),
                ),
              if (files.isEmpty && !loading) const Text('No files attached.'),
              if (canAttach)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : upload,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Attach PDF / image · max 10 MB'),
                  ),
                ),
              if (widget.module.id == 'document' && status == 'published') ...[
                const Divider(),
                Text('${acks.length} acknowledgements'),
                if (acks.any((a) => a['employee_id'] == widget.repo.userId))
                  const Text('You acknowledged this document.')
                else
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            await widget.repo.acknowledge(row['id'].toString());
                            await refresh();
                          }),
                    child: const Text(
                      'I have read and acknowledge this document',
                    ),
                  ),
                if (widget.hr)
                  for (final ack in acks)
                    SelectableText(
                      '${widget.employeeNameFor(ack['employee_id'])} · ${ack['acknowledged_at']}',
                    ),
              ],
              const Divider(),
              TextField(
                controller: note,
                maxLength: 4000,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Resolution note',
                  helperText: 'Required when resolving a ticket.',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in widget.module.actions(
                    status,
                    hr: widget.hr,
                    owner: owner,
                  ))
                    FilledButton(
                      onPressed: busy ? null : () => update(action),
                      child: Text(humanize(action)),
                    ),
                ],
              ),
              const Divider(),
              Text('History', style: Theme.of(context).textTheme.titleMedium),
              for (final event in events)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: SelectableText(
                    '${humanize(event['action'].toString())} · ${event['created_at']}\n${widget.employeeNameFor(event['actor_id'])}${event['note'] == '' ? '' : '\n${event['note']}'}',
                  ),
                ),
              if (error != null)
                SelectableText(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (busy) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Widget _keyVal(String k, String v) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Text(
          v,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    ),
  );
}
