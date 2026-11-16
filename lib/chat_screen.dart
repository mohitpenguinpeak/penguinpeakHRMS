import 'shared/widgets/app_toast.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatScreen extends StatefulWidget {
  final String role;
  const ChatScreen({
    super.key,
    required this.role,
    this.initialConversationId,
    this.onTargetConsumed,
  });
  final String? initialConversationId;
  final VoidCallback? onTargetConsumed;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final SupabaseClient _db = Supabase.instance.client;
  RealtimeChannel? _realtimeChannel;

  bool _loading = true;
  bool _initialConversationOpened = false;
  String? _error;
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _profiles = [];
  Map<String, dynamic>? _activeConversation;
  List<Map<String, dynamic>> _messages = [];
  final TextEditingController _messageController = TextEditingController();

  // Attachment & Urgent Priority State
  bool _isUrgent = false;
  String? _dismissedUrgentMessageId;
  String? _attachmentUrl;
  String _attachmentType = 'none'; // 'none', 'image', 'video', 'file'

  String? get _uid => _db.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _messageController.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    try {
      _realtimeChannel =
          _db
              .channel('public:messages')
              .onPostgresChanges(
                event: PostgresChangeEvent.insert,
                schema: 'public',
                table: 'messages',
                callback: (payload) {
                  final newRecord = payload.newRecord;
                  final senderId = newRecord['sender_id']?.toString();
                  final convId = newRecord['conversation_id']?.toString();
                  final msgText = newRecord['message']?.toString() ?? '';

                  // Live update active chat messages
                  if (_activeConversation != null &&
                      _activeConversation!['id'] == convId) {
                    if (!_messages.any((m) => m['id'] == newRecord['id'])) {
                      if (mounted) {
                        setState(() {
                          _messages.add(newRecord);
                        });
                      }
                    }
                  }

                  // Show an in-app banner; this does not deliver an OS push notification.
                  if (senderId != _uid && mounted) {
                    final isUrgentMsg = msgText.contains('🚨 [URGENT]');
                    final cleanMsg = msgText
                        .replaceAll('🚨 [URGENT]', '')
                        .replaceAll(
                          RegExp(r'\[ATTACHMENT:.*\]'),
                          '[Attachment]',
                        )
                        .trim();
                    final senderName = _employeeName(senderId);

                    AppToast.of(context).hideCurrentSnackBar();
                    AppToast.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: isUrgentMsg
                            ? const Color(0xFF881337)
                            : const Color(0xFF1E293B),
                        duration: const Duration(seconds: 4),
                        margin: const EdgeInsets.all(12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isUrgentMsg
                                ? Colors.red
                                : Colors.amber.shade700,
                          ),
                        ),
                        content: Row(
                          children: [
                            Icon(
                              isUrgentMsg
                                  ? Icons.notification_important
                                  : Icons.mark_chat_unread_outlined,
                              color: isUrgentMsg
                                  ? Colors.redAccent
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isUrgentMsg
                                        ? '🚨 URGENT MESSAGE from $senderName'
                                        : '📩 New Message from $senderName',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    cleanMsg.isEmpty
                                        ? 'Sent a message'
                                        : cleanMsg,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  _loadData();
                },
              )
            ..subscribe();
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _uid;
      if (uid == null) throw Exception('User not authenticated');

      final profilesRes = await _db
          .from('profiles')
          .select('id, full_name, department, role')
          .eq('approval_status', 'approved')
          .order('full_name');
      _profiles = List<Map<String, dynamic>>.from(profilesRes);

      final partRes = await _db
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', uid);

      final convIds = partRes.map((p) => p['conversation_id']).toList();

      if (convIds.isNotEmpty) {
        final convRes = await _db
            .from('conversations')
            .select('*, conversation_participants(user_id), messages(*)')
            .inFilter('id', convIds)
            .order('created_at', ascending: false);
        _conversations = List<Map<String, dynamic>>.from(convRes);
      } else {
        _conversations = [];
      }

      if (!mounted) return;
      setState(() => _loading = false);
      if (!_initialConversationOpened && widget.initialConversationId != null) {
        _initialConversationOpened = true;
        widget.onTargetConsumed?.call();
        final conversation = _conversations
            .where((c) => c['id'] == widget.initialConversationId)
            .firstOrNull;
        if (conversation != null) {
          await _loadMessages(conversation);
        } else {
          AppToast.of(context).showSnackBar(
            const SnackBar(
              content: Text('This conversation is no longer available.'),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMessages(Map<String, dynamic> conversation) async {
    setState(() {
      _activeConversation = conversation;
    });
    try {
      final res = await _db
          .from('messages')
          .select('*')
          .eq('conversation_id', conversation['id'])
          .order('created_at', ascending: true);
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      AppToast.of(context)
          .showSnackBar(SnackBar(content: Text('Error loading messages: $e')));
    }
  }

  Future<void> _startOneToOneChat(String peerId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      for (final c in _conversations) {
        if (c['is_group'] == false) {
          final parts = (c['conversation_participants'] as List?) ?? [];
          final participantIds = parts
              .map((p) => p['user_id'].toString())
              .toSet();
          if (participantIds.contains(uid) &&
              participantIds.contains(peerId) &&
              participantIds.length == 2) {
            _loadMessages(c);
            return;
          }
        }
      }

      final convId = await _db.rpc(
        'create_direct_conversation',
        params: {'p_peer_id': peerId},
      );

      await _loadData();
      final created = _conversations.firstWhere((c) => c['id'] == convId);
      _loadMessages(created);
    } catch (e) {
      AppToast.of(context)
          .showSnackBar(SnackBar(content: Text('Error starting chat: $e')));
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _attachmentUrl == null) return;
    if (_activeConversation == null || _uid == null) return;

    try {
      String fullMessage = text;
      if (_attachmentUrl != null && _attachmentUrl!.isNotEmpty) {
        fullMessage =
            '[ATTACHMENT:${_attachmentType.toUpperCase()}:$_attachmentUrl] $text';
      }
      if (_isUrgent) {
        fullMessage = '🚨 [URGENT] $fullMessage';
      }

      await _db.from('messages').insert({
        'conversation_id': _activeConversation!['id'],
        'sender_id': _uid,
        'message': fullMessage,
      });

      if (_isUrgent && mounted) {
        AppToast.of(context).showSnackBar(
          const SnackBar(
            content: Text('Urgent message sent.'),
            backgroundColor: Colors.red,
          ),
        );
      }

      _messageController.clear();
      setState(() {
        _attachmentUrl = null;
        _attachmentType = 'none';
        _isUrgent = false;
      });

      _loadMessages(_activeConversation!);
      _loadData();
    } catch (e) {
      AppToast.of(context)
          .showSnackBar(SnackBar(content: Text('Error sending message: $e')));
    }
  }

  void _showAttachmentDialog() {
    String selectedType = 'image';
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Share Attachment / Media'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'image',
                    label: Text('Photo'),
                    icon: Icon(Icons.image),
                  ),
                  ButtonSegment(
                    value: 'video',
                    label: Text('Video'),
                    icon: Icon(Icons.videocam),
                  ),
                  ButtonSegment(
                    value: 'file',
                    label: Text('File'),
                    icon: Icon(Icons.attach_file),
                  ),
                ],
                selected: {selectedType},
                onSelectionChanged: (set) =>
                    setDialogState(() => selectedType = set.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: 'Enter ${selectedType.toUpperCase()} URL / Link',
                  hintText: 'https://example.com/media.png',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final url = urlController.text.trim();
                if (url.isNotEmpty) {
                  setState(() {
                    _attachmentUrl = url;
                    _attachmentType = selectedType;
                  });
                }
                Navigator.pop(c);
              },
              child: const Text('Attach'),
            ),
          ],
        ),
      ),
    );
  }

  String _employeeName(dynamic id) {
    final key = id?.toString();
    for (final p in _profiles) {
      if (p['id']?.toString() == key) {
        return (p['full_name'] ?? 'Employee').toString();
      }
    }
    return 'Employee';
  }

  String _getConversationTitle(Map<String, dynamic> c) {
    if (c['is_group'] == true && c['title'] != null) {
      return c['title'];
    }
    final uid = _uid;
    final parts = (c['conversation_participants'] as List?) ?? [];
    for (final p in parts) {
      final pid = p['user_id']?.toString();
      if (pid != uid && pid != null) {
        return _employeeName(pid);
      }
    }
    return 'Chat';
  }

  void _showNewChatDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start Conversation'),
        content: SizedBox(
          width: 400,
          height: 400,
          child: ListView.builder(
            itemCount: _profiles
                .where((p) => p['id']?.toString() != _uid)
                .length,
            itemBuilder: (context, index) {
              final otherProfiles = _profiles
                  .where((p) => p['id']?.toString() != _uid)
                  .toList();
              final p = otherProfiles[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text((p['full_name'] ?? 'U')[0].toUpperCase()),
                ),
                title: Text(p['full_name'] ?? ''),
                subtitle: Text(
                  '${p['department'] ?? 'General'} • ${p['role']}',
                ),
                onTap: () {
                  Navigator.pop(dialogContext);
                  _startOneToOneChat(p['id'].toString());
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> m, bool isMe) {
    String text = m['message'] ?? '';
    bool isUrgentMsg = text.contains('🚨 [URGENT]');
    text = text.replaceAll('🚨 [URGENT]', '').trim();

    String? attachUrl;
    String attachType = 'none';

    final match = RegExp(r'\[ATTACHMENT:(IMAGE|VIDEO|FILE):(.*?)\]')
        .firstMatch(text);
    if (match != null) {
      attachType = match.group(1)!.toLowerCase();
      attachUrl = match.group(2);
      text = text.replaceAll(match.group(0)!, '').trim();
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUrgentMsg
              ? Colors.red.withOpacity(0.15)
              : isMe
              ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUrgentMsg ? Colors.red : Theme.of(context).dividerColor,
            width: isUrgentMsg ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isUrgentMsg) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.warning, color: Colors.red, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'URGENT ESCALATION',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            if (!isMe)
              Text(
                _employeeName(m['sender_id']),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: Colors.amber,
                ),
              ),
            if (attachUrl != null && attachUrl.isNotEmpty) ...[
              const SizedBox(height: 6),
              if (attachType == 'image')
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    attachUrl,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.black26,
                      child: Row(
                        children: const [
                          Icon(Icons.broken_image, color: Colors.grey),
                          SizedBox(width: 8),
                          Text('Photo attachment'),
                        ],
                      ),
                    ),
                  ),
                )
              else if (attachType == 'video')
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        Icons.play_circle_fill,
                        color: Colors.redAccent,
                        size: 28,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Video Attachment',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        Icons.insert_drive_file,
                        color: Colors.blueAccent,
                        size: 28,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'File Attachment',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
            ],
            if (text.isNotEmpty) Text(text),
            const SizedBox(height: 4),
            Text(
              m['created_at']?.toString().split('T')[1].substring(0, 5) ?? '',
              style: const TextStyle(fontSize: 9, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationsList() {
    return Card(
      child: ListView.builder(
        itemCount: _conversations.length,
        itemBuilder: (context, index) {
          final c = _conversations[index];
          final title = _getConversationTitle(c);
          final messages = (c['messages'] as List?) ?? [];
          messages.sort(
            (a, b) => (b['created_at'] ?? '').compareTo(a['created_at'] ?? ''),
          );
          final lastMsg = messages.isNotEmpty
              ? messages.first['message']
              : 'No messages yet';
          final isActive = _activeConversation?['id'] == c['id'];

          return ListTile(
            selected: isActive,
            leading: CircleAvatar(
              child: Text(title.isNotEmpty ? title[0].toUpperCase() : 'C'),
            ),
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              lastMsg,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _loadMessages(c),
          );
        },
      ),
    );
  }

  Widget _buildActiveChatWindow(bool isMobile) {
    if (_activeConversation == null) {
      return const Card(
        child: Center(child: Text('Select a conversation to start messaging')),
      );
    }

    Map<String, dynamic>? latestUrgentMsg;
    if (_messages.isNotEmpty) {
      for (final m in _messages.reversed) {
        if (m['message']?.contains('🚨 [URGENT]') == true) {
          latestUrgentMsg = m;
          break;
        }
      }
    }

    return Card(
      child: Column(
        children: [
          // Chat Header with Back Button on Mobile
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                if (isMobile)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() => _activeConversation = null),
                  ),
                Expanded(
                  child: Text(
                    _getConversationTitle(_activeConversation!),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Urgent Message Alert Banner
          if (latestUrgentMsg != null &&
              _dismissedUrgentMessageId != latestUrgentMsg['id']?.toString())
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Colors.red.withOpacity(0.2),
              child: Row(
                children: [
                  const Icon(
                    Icons.notification_important,
                    color: Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '🚨 URGENT: ${_employeeName(latestUrgentMsg['sender_id'])} sent a high-priority message!',
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red, size: 16),
                    tooltip: 'Dismiss urgent alert',
                    onPressed: () {
                      setState(() {
                        _dismissedUrgentMessageId = latestUrgentMsg?['id']
                            ?.toString();
                      });
                    },
                  ),
                ],
              ),
            ),
          // Attachment Preview Badge
          if (_attachmentUrl != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.blue.withOpacity(0.15),
              child: Row(
                children: [
                  Icon(
                    _attachmentType == 'image'
                        ? Icons.image
                        : _attachmentType == 'video'
                        ? Icons.videocam
                        : Icons.attach_file,
                    color: Colors.blue,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Attached ${_attachmentType.toUpperCase()}: $_attachmentUrl',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() {
                      _attachmentUrl = null;
                      _attachmentType = 'none';
                    }),
                  ),
                ],
              ),
            ),
          // Messages List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                final isMe = m['sender_id']?.toString() == _uid;
                return _buildMessageBubble(m, isMe);
              },
            ),
          ),
          // Input Bar
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.attach_file,
                    color: Colors.grey,
                    size: 20,
                  ),
                  onPressed: _showAttachmentDialog,
                  tooltip: 'Attach Media/File',
                ),
                IconButton(
                  icon: Icon(
                    Icons.warning_amber_rounded,
                    color: _isUrgent ? Colors.red : Colors.grey,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _isUrgent = !_isUrgent),
                  tooltip: _isUrgent
                      ? 'Urgent Priority Active'
                      : 'Set Delivery Priority: Urgent',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: _isUrgent
                          ? '🚨 Type URGENT message...'
                          : 'Type a message...',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: _isUrgent ? Colors.red : null,
                  ),
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = MediaQuery.sizeOf(context).height;
        final isMobile = screenWidth < 720;

        // Dynamically stretch to fill full bottom height of screen
        final fillHeight = (screenHeight - (isMobile ? 120 : 150)).clamp(
          480.0,
          1400.0,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Secure Messaging',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: isMobile ? 20 : 28,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _showNewChatDialog,
                  icon: const Icon(Icons.message_outlined, size: 18),
                  label: Text(isMobile ? 'New' : 'New Chat'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: fillHeight,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text('Error: $_error'))
                  : isMobile
                  ? (_activeConversation == null
                        ? _buildConversationsList()
                        : _buildActiveChatWindow(true))
                  : Row(
                      children: [
                        SizedBox(width: 300, child: _buildConversationsList()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildActiveChatWindow(false)),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
