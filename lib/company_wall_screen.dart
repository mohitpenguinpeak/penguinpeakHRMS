import 'shared/widgets/app_toast.dart';

import 'package:flutter/material.dart';

import 'shared/widgets/adaptive_layout.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

class CompanyWallScreen extends StatefulWidget {
  final String role;
  const CompanyWallScreen({
    super.key,
    required this.role,
    this.initialPostId,
    this.onTargetConsumed,
  });
  final String? initialPostId;
  final VoidCallback? onTargetConsumed;

  @override
  State<CompanyWallScreen> createState() => _CompanyWallScreenState();
}

class _CompanyWallScreenState extends State<CompanyWallScreen> {
  final SupabaseClient _db = Supabase.instance.client;
  bool _loading = true;
  bool _targetConsumed = false;
  String? _error;
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _profiles = [];

  String? get _uid => _db.auth.currentUser?.id;
  bool get _canPin =>
      ['admin', 'super_admin', 'hr', 'management'].contains(widget.role);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profilesRes = await _db
          .from('profiles')
          .select('id, full_name, department, role')
          .eq('approval_status', 'approved')
          .order('full_name');
      _profiles = List<Map<String, dynamic>>.from(profilesRes);

      final postsRes = await _db
          .from('company_wall_posts')
          .select('*, company_wall_comments(*), company_wall_reactions(*)')
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false);
      _posts = List<Map<String, dynamic>>.from(postsRes);

      if (!mounted) return;
      if (widget.initialPostId != null) {
        _posts.sort(
          (a, b) => a['id'] == widget.initialPostId
              ? -1
              : b['id'] == widget.initialPostId
              ? 1
              : 0,
        );
        if (!_targetConsumed) {
          _targetConsumed = true;
          widget.onTargetConsumed?.call();
        }
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _employeeName(dynamic id) {
    final key = id?.toString();
    for (final p in _profiles) {
      if (p['id']?.toString() == key)
        return (p['full_name'] ?? 'Employee').toString();
    }
    return 'Employee';
  }

  Future<void> _createPost() async {
    String postType = 'general';
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    bool isPinned = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Company Wall Post'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: postType,
                    decoration: const InputDecoration(labelText: 'Post Type'),
                    items: const [
                      DropdownMenuItem(
                        value: 'announcement',
                        child: Text('Company Announcement'),
                      ),
                      DropdownMenuItem(
                        value: 'hr_update',
                        child: Text('HR Update'),
                      ),
                      DropdownMenuItem(
                        value: 'birthday',
                        child: Text('Birthday Card'),
                      ),
                      DropdownMenuItem(
                        value: 'anniversary',
                        child: Text('Work Anniversary'),
                      ),
                      DropdownMenuItem(
                        value: 'appreciation',
                        child: Text('Employee Appreciation'),
                      ),
                      DropdownMenuItem(
                        value: 'general',
                        child: Text('General Post'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => postType = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Post Title *',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'What would you like to share? *',
                    ),
                  ),
                  if (_canPin) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Pin Post to Top'),
                      value: isPinned,
                      onChanged: (v) => setDialogState(() => isPinned = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (titleController.text.trim().isEmpty ||
                    contentController.text.trim().isEmpty) {
                  AppToast.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Title and content are required.'),
                    ),
                  );
                  return;
                }
                try {
                  await _db.from('company_wall_posts').insert({
                    'author_id': _uid,
                    'post_type': postType,
                    'title': titleController.text.trim(),
                    'content': contentController.text.trim(),
                    'is_pinned': isPinned,
                  });
                  if (!mounted) return;
                  Navigator.pop(dialogContext);
                  _loadData();
                  AppToast.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Post published to Company Wall!'),
                    ),
                  );
                } catch (e) {
                  AppToast.of(context)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _react(Map<String, dynamic> post, String reactionType) async {
    try {
      final uid = _uid;
      if (uid == null) return;
      final reactions = (post['company_wall_reactions'] as List?) ?? [];
      final existing = reactions.firstWhere(
        (r) => r['user_id']?.toString() == uid,
        orElse: () => {},
      );

      if (existing.isNotEmpty) {
        if (existing['reaction_type'] == reactionType) {
          // Remove reaction
          await _db
              .from('company_wall_reactions')
              .delete()
              .eq('id', existing['id']);
        } else {
          // Update reaction
          await _db
              .from('company_wall_reactions')
              .update({'reaction_type': reactionType})
              .eq('id', existing['id']);
        }
      } else {
        await _db.from('company_wall_reactions').insert({
          'post_id': post['id'],
          'user_id': uid,
          'reaction_type': reactionType,
        });
      }
      _loadData();
    } catch (e) {
      AppToast.of(context)
          .showSnackBar(SnackBar(content: Text('Error reacting: $e')));
    }
  }

  Future<void> _addComment(
    Map<String, dynamic> post,
    String commentText,
  ) async {
    if (commentText.trim().isEmpty) return;
    try {
      await _db.from('company_wall_comments').insert({
        'post_id': post['id'],
        'author_id': _uid,
        'comment_text': commentText.trim(),
      });
      _loadData();
    } catch (e) {
      AppToast.of(context)
          .showSnackBar(SnackBar(content: Text('Error adding comment: $e')));
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'announcement':
        return Colors.red;
      case 'hr_update':
        return Colors.blue;
      case 'birthday':
        return Colors.pink;
      case 'anniversary':
        return Colors.purple;
      case 'appreciation':
        return Colors.amber;
      default:
        return Colors.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceHeading(
          title: 'Company Wall',
          action: FilledButton.icon(
            onPressed: _createPost,
            icon: const Icon(Icons.campaign),
            label: const Text('Create Post'),
          ),
        ),
        const SizedBox(height: 16),
        _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text('Error: $_error'))
            : _posts.isEmpty
            ? const Center(child: Text('No company wall posts yet.'))
            : ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _posts.length,
                itemBuilder: (context, index) {
                  final post = _posts[index];
                  final isPinned = post['is_pinned'] == true;
                  final type = post['post_type'] ?? 'general';
                  final comments =
                      (post['company_wall_comments'] as List?) ?? [];
                  final reactions =
                      (post['company_wall_reactions'] as List?) ?? [];
                  final likes = reactions
                      .where((r) => r['reaction_type'] == 'like')
                      .length;
                  final celebrates = reactions
                      .where((r) => r['reaction_type'] == 'celebrate')
                      .length;
                  final myReaction = reactions.firstWhere(
                    (r) => r['user_id']?.toString() == _uid,
                    orElse: () => {},
                  )['reaction_type'];

                  final commentController = TextEditingController();

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: isPinned
                          ? const BorderSide(color: Colors.amber, width: 2)
                          : BorderSide.none,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (isPinned) ...[
                                const Icon(
                                  Icons.push_pin,
                                  color: Colors.amber,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Chip(
                                label: Text(
                                  type.toUpperCase(),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: _typeColor(type)
                                    .withOpacity(0.2),
                              ),
                              Text(
                                _employeeName(post['author_id']),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            post['title'] ?? '',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(post['content'] ?? ''),
                          const Divider(height: 24),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: () => _react(post, 'like'),
                                icon: Icon(
                                  Icons.thumb_up,
                                  size: 18,
                                  color: myReaction == 'like'
                                      ? Colors.blue
                                      : Colors.grey,
                                ),
                                label: Text('Like ($likes)'),
                              ),
                              const SizedBox(width: 12),
                              TextButton.icon(
                                onPressed: () => _react(post, 'celebrate'),
                                icon: Icon(
                                  Icons.celebration,
                                  size: 18,
                                  color: myReaction == 'celebrate'
                                      ? Colors.purple
                                      : Colors.grey,
                                ),
                                label: Text('Celebrate ($celebrates)'),
                              ),
                              Text(
                                '${comments.length} comments',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          ...comments.map(
                            (c) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_employeeName(c['author_id'])}: ',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      c['comment_text'] ?? '',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: commentController,
                                  decoration: const InputDecoration(
                                    hintText: 'Write a comment...',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (v) {
                                    _addComment(post, v);
                                    commentController.clear();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.send),
                                onPressed: () {
                                  _addComment(post, commentController.text);
                                  commentController.clear();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ],
    );
  }
}
