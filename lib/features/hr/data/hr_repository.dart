import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

abstract class HrRepository {
  String get userId;
  Future<List<Map<String, dynamic>>> records(String module);
  Future<Map<String, dynamic>?> record(String module, String id) async =>
      (await records(module)).where((row) => row['id'] == id).firstOrNull;

  Future<List<Map<String, dynamic>>> employees();
  Future<String> create(
    String module,
    String employee,
    String title,
    String description,
    Map<String, dynamic> data,
    bool companyWide,
  );
  Future<void> update(
    Map<String, dynamic> record,
    String action,
    String note,
    Map<String, dynamic> patch,
  );
  Future<List<Map<String, dynamic>>> history(String id);
  Future<List<Map<String, dynamic>>> attachments(String id);
  Future<List<Map<String, dynamic>>> acknowledgements(String id);
  Future<void> acknowledge(String id);
  Future<void> upload(String id, String name, Uint8List bytes);
  Future<String> downloadUrl(String path);
}

class SupabaseHrRepository implements HrRepository {
  SupabaseHrRepository(this.client);
  final SupabaseClient client;
  @override
  String get userId => client.auth.currentUser!.id;
  @override
  Future<List<Map<String, dynamic>>> records(String module) async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('hr_records')
            .select()
            .eq('module', module)
            .order('created_at', ascending: false)
            .limit(200),
      );
  @override
  Future<Map<String, dynamic>?> record(String module, String id) => client
      .from('hr_records')
      .select()
      .eq('module', module)
      .eq('id', id)
      .maybeSingle();
  @override
  Future<List<Map<String, dynamic>>> employees() async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('profiles')
            .select('id, full_name')
            .eq('approval_status', 'approved')
            .order('full_name'),
      );
  @override
  Future<String> create(
    String module,
    String employee,
    String title,
    String description,
    Map<String, dynamic> data,
    bool companyWide,
  ) async => (await client.rpc(
    'hr_create_record',
    params: {
      'p_module': module,
      'p_employee': employee,
      'p_title': title,
      'p_description': description,
      'p_data': data,
      'p_company_wide': companyWide,
    },
  )).toString();
  @override
  Future<void> update(
    Map<String, dynamic> record,
    String action,
    String note,
    Map<String, dynamic> patch,
  ) async {
    await client.rpc(
      'hr_update_record',
      params: {
        'p_id': record['id'],
        'p_revision': record['revision'],
        'p_action': action,
        'p_note': note,
        'p_patch': patch,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> history(String id) async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('hr_record_history')
            .select()
            .eq('record_id', id)
            .order('created_at'),
      );
  @override
  Future<List<Map<String, dynamic>>> attachments(String id) async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('hr_attachments')
            .select()
            .eq('record_id', id)
            .order('created_at'),
      );
  @override
  Future<List<Map<String, dynamic>>> acknowledgements(String id) async =>
      List<Map<String, dynamic>>.from(
        await client.from('hr_acknowledgements').select().eq('record_id', id),
      );
  @override
  Future<void> acknowledge(String id) async {
    await client.rpc('hr_acknowledge', params: {'p_id': id});
  }

  @override
  Future<void> upload(String id, String name, Uint8List bytes) async {
    final ext = name.split('.').last.toLowerCase();
    if (!['pdf', 'png', 'jpg', 'jpeg'].contains(ext) ||
        bytes.isEmpty ||
        bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('Choose a PDF, PNG or JPG file under 10 MB.');
    }
    final path = '$id/$userId/${DateTime.now().microsecondsSinceEpoch}.$ext';
    final bucket = client.storage.from('hr-private');
    await bucket.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        contentType: ext == 'pdf'
            ? 'application/pdf'
            : ext == 'png'
            ? 'image/png'
            : 'image/jpeg',
      ),
    );
    try {
      await client.rpc(
        'hr_register_attachment',
        params: {'p_id': id, 'p_name': name, 'p_path': path},
      );
    } catch (_) {
      try {
        await bucket.remove([path]);
      } catch (_) {
        /* Keep the original registration error. */
      }
      rethrow;
    }
  }

  @override
  Future<String> downloadUrl(String path) =>
      client.storage.from('hr-private').createSignedUrl(path, 60);
}
