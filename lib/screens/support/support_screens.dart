import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/paged_list.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

const _chat = '/admin/chat';

// ─── Support chat ────────────────────────────────────────────────────────────

/// Support queue — polls like the web panel (queue 6s, open thread 4s).
class ChatQueueScreen extends StatefulWidget {
  const ChatQueueScreen({super.key});
  @override
  State<ChatQueueScreen> createState() => _ChatQueueScreenState();
}

class _ChatQueueScreenState extends State<ChatQueueScreen> {
  String _type = 'ALL';
  String _status = 'OPEN';
  bool _mine = false;
  List<Map<String, dynamic>>? _rows;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await api.get('$_chat/conversations', {'type': _type == 'ALL' ? null : _type, 'mine': _mine ? 'true' : null, 'status': _status});
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _rows = r.list;
        _error = null;
      } else {
        _error = r.message;
        _rows ??= [];
      }
    });
  }

  void _set(VoidCallback f) {
    setState(() {
      f();
      _rows = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Column(children: [
      FilterChips<String>(options: const {'ALL': 'All', 'USER_SUPPORT': 'Customers', 'TECHNICIAN_SUPPORT': 'Technicians'}, value: _type, onChanged: (v) => _set(() => _type = v)),
      Row(children: [
        Expanded(child: FilterChips<String>(options: const {'OPEN': 'Open', 'CLOSED': 'Closed'}, value: _status, onChanged: (v) => _set(() => _status = v))),
        FilterChip(label: const Text('Mine'), selected: _mine, onSelected: (v) => _set(() => _mine = v)),
        const Gap(12),
      ]),
      if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: C.red))),
      Expanded(
        child: rows == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: rows.isEmpty
                    ? ListView(children: const [EmptyView('No conversations here', icon: Icons.forum_outlined)])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Gap(8),
                        itemBuilder: (c, i) {
                          final cv = rows[i];
                          final isTech = cv['type'] == 'TECHNICIAN_SUPPORT';
                          final name = str(isTech ? cv['technician_name'] : cv['customer_name']);
                          final unread = toInt(cv['unread_count']) ?? 0;
                          return RowTile(
                            leading: Avatar(url: isTech ? cv['technician_avatar'] : cv['customer_avatar'], name: name),
                            title: name,
                            badge: unread > 0 ? Badge(label: Text('$unread')) : StatusChip(isTech ? 'ASSIGNED' : 'PROCESS', label: isTech ? 'Technician' : 'Customer'),
                            subtitle: str(cv['last_message_preview'], 'No messages yet'),
                            lines: ['${ago(cv['last_message_at'])}${cv['admin_id'] == null ? ' · unclaimed' : ''}${cv['status'] == 'CLOSED' ? ' · closed' : ''}'],
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatThreadScreen(conversation: cv)));
                              _load();
                            },
                          );
                        },
                      ),
              ),
      ),
    ]);
  }
}

class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({super.key, required this.conversation});
  final Map<String, dynamic> conversation;
  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _msgs = [];
  late Map<String, dynamic> _cv = widget.conversation;
  Timer? _timer;
  bool _sending = false;
  bool _loaded = false;

  int get _id => toInt(_cv['conversation_id'])!;
  bool get _closed => _cv['status'] == 'CLOSED';
  bool get _isTech => _cv['type'] == 'TECHNICIAN_SUPPORT';

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await api.get('$_chat/conversations/$_id/messages');
    if (!mounted || !r.ok) return;
    final msgs = ApiRes.asList(r.map['messages']);
    final grew = msgs.length != _msgs.length;
    setState(() {
      _msgs = msgs;
      _loaded = true;
      if (r.map['conversation'] is Map) _cv = {..._cv, ...ApiRes.asMap(r.map['conversation'])};
    });
    if (grew) {
      api.post('$_chat/conversations/$_id/read');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    final r = await api.post('$_chat/conversations/$_id/messages', {'content': t});
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.ok) {
      _text.clear();
      _load();
    } else {
      toastRes(r);
    }
  }

  Future<void> _attach() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (x == null || !mounted) return;
    setState(() => _sending = true);
    final up = await api.upload('$_chat/upload', files: {'file': x.path});
    if (!up.ok) {
      setState(() => _sending = false);
      {
      toastRes(up);
      return;
    }
    }
    final r = await api.post('$_chat/conversations/$_id/messages', {'media_url': up.map['url'], 'message_type': up.map['message_type']});
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.ok) _load();
    toastRes(r, success: 'Attachment sent');
  }

  Future<void> _claim() async {
    final r = await busy(context, () => api.post('$_chat/conversations/$_id/claim'), success: 'Conversation assigned to you');
    if (r.ok) setState(() => _cv = {..._cv, 'admin_id': Session.I.profile?['admin_id']});
  }

  Future<void> _close() async {
    if (!await confirm(context, 'Close this conversation?', ok: 'Close')) return;
    if (!mounted) return;
    final r = await busy(context, () => api.post('$_chat/conversations/$_id/close'), success: 'Conversation closed');
    if (r.ok) setState(() => _cv = {..._cv, 'status': 'CLOSED'});
  }

  @override
  Widget build(BuildContext context) {
    final phone = _isTech ? _cv['technician_mobile'] : _cv['customer_mobile'];
    final canEdit = Session.I.canOn(_chat, 'EDIT') || Session.I.can('SUPPORT_EDIT');
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(str(_isTech ? _cv['technician_name'] : _cv['customer_name']), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text('${_isTech ? 'Technician' : 'Customer'}${_cv['admin_name'] != null ? ' · ${_cv['admin_name']}' : ''}${_closed ? ' · closed' : ''}', style: const TextStyle(fontSize: 12, color: C.muted)),
        ]),
        actions: [
          IconButton(onPressed: () => callPhone(phone), icon: const Icon(Icons.call)),
          IconButton(onPressed: () => whatsapp(phone), icon: const Icon(Icons.chat_outlined)),
          if (canEdit && !_closed)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'claim' ? _claim() : _close(),
              itemBuilder: (_) => [if (_cv['admin_id'] == null) const PopupMenuItem(value: 'claim', child: Text('Assign to me')), const PopupMenuItem(value: 'close', child: Text('Close conversation'))],
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : _msgs.isEmpty
                  ? const EmptyView('No messages yet')
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _msgs.length,
                      itemBuilder: (c, i) {
                        final m = _msgs[i];
                        final mine = m['sender_type'] == 'ADMIN';
                        final media = m['media_url'];
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(c).size.width * .78),
                            decoration: BoxDecoration(color: mine ? C.primary : Colors.white, borderRadius: BorderRadius.circular(12), border: mine ? null : Border.all(color: C.line)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (!mine) Text(str(m['sender_name'], humanize(m['sender_type'])), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.body)),
                              if (media != null) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: NetImage(media, size: 180)),
                              if (str(m['content'], '').isNotEmpty) Text(str(m['content']), style: TextStyle(color: mine ? Colors.white : C.ink)),
                              const Gap(2),
                              Text('${fmtClock(m['created_at'])}${mine && truthy(m['is_read']) ? ' · read' : ''}',
                                  style: TextStyle(fontSize: 10.5, color: mine ? Colors.white70 : C.muted)),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: _closed
                ? const Padding(padding: EdgeInsets.all(10), child: Text('This conversation is closed.', style: TextStyle(color: C.muted)))
                : Row(children: [
                    IconButton(onPressed: _sending ? null : _attach, icon: const Icon(Icons.attach_file)),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(hintText: 'Type a reply…'),
                      ),
                    ),
                    IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send)),
                  ]),
          ),
        ),
      ]),
    );
  }
}

// ─── Contact inquiries ───────────────────────────────────────────────────────

const _inqStatus = {'': 'All', 'new': 'New', 'in_progress': 'In progress', 'resolved': 'Resolved', 'closed': 'Closed'};

class InquiriesScreen extends StatefulWidget {
  const InquiriesScreen({super.key});
  @override
  State<InquiriesScreen> createState() => _InquiriesScreenState();
}

class _InquiriesScreenState extends State<InquiriesScreen> {
  final _list = GlobalKey<PagedListState>();
  String _status = '';
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final r = await api.get('/admin/contact-inquiries/stats');
    if (mounted && r.ok) setState(() => _stats = r.map);
  }

  @override
  Widget build(BuildContext context) {
    return PagedList(
      key: _list,
      searchHint: 'Search name, email, subject…',
      fetch: (p, l, s) => api.get('/admin/contact-inquiries', {'page': '$p', 'limit': '$l', 'status': _status, 'search': s}),
      header: FilterChips<String>(
        options: {for (final e in _inqStatus.entries) e.key: e.key.isEmpty ? 'All (${_stats['total'] ?? '-'})' : '${e.value} (${_stats[e.key] ?? 0})'},
        value: _status,
        onChanged: (v) {
          setState(() => _status = v);
          _list.currentState?.reload();
        },
      ),
      empty: 'Inbox is empty.',
      itemBuilder: (c, r, i) => RowTile(
        title: str(r['subject'], 'No subject'),
        badge: StatusChip(r['status'] == 'new' ? 'NEW' : r['status']),
        subtitle: '${str(r['name'])} · ${str(r['email'], '')}',
        lines: [ago(r['created_at'])],
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => InquiryDetailScreen(id: r['inquiry_id'])));
          _list.currentState?.reload();
          _loadStats();
        },
      ),
    );
  }
}

class InquiryDetailScreen extends StatefulWidget {
  const InquiryDetailScreen({super.key, required this.id});
  final dynamic id;
  @override
  State<InquiryDetailScreen> createState() => _InquiryDetailScreenState();
}

class _InquiryDetailScreenState extends State<InquiryDetailScreen> {
  final _notes = TextEditingController();
  String? _status;

  @override
  Widget build(BuildContext context) {
    final canEdit = Session.I.canOn('/admin/contact-inquiries', 'EDIT');
    return Scaffold(
      appBar: AppBar(title: const Text('Inquiry')),
      body: ApiLoader(
        load: () async {
          final r = await api.get('/admin/contact-inquiries/${widget.id}');
          if (r.ok) {
            _status ??= str(r.map['status'], 'new');
            if (_notes.text.isEmpty) _notes.text = str(r.map['admin_notes'], '');
          }
          return r;
        },
        builder: (c, res, reload) {
          final d = res.map;
          return ListView(padding: const EdgeInsets.all(12), children: [
            SectionCard(title: str(d['subject'], 'No subject'), trailing: StatusChip(d['status']), children: [
              Text(str(d['message']), style: const TextStyle(height: 1.4)),
            ]),
            const Gap(),
            SectionCard(title: 'Contact details', children: [
              KV('Name', d['name']),
              KV('Email', d['email']),
              KV('Phone', d['phone']),
              Row(children: [
                if (d['phone'] != null) TextButton.icon(onPressed: () => callPhone(d['phone']), icon: const Icon(Icons.call, size: 18), label: const Text('Call')),
                if (d['email'] != null) TextButton.icon(onPressed: () => openUrl('mailto:${d['email']}?subject=Re: ${Uri.encodeComponent(str(d['subject'], ''))}'), icon: const Icon(Icons.mail_outline, size: 18), label: const Text('Email')),
              ]),
            ]),
            const Gap(),
            SectionCard(title: 'Meta', children: [
              KV('Source', d['source']),
              KV('IP address', d['ip_address']),
              KV('Received', fmtDateTime(d['created_at'])),
              if (d['resolved_at'] != null) KV('Resolved', fmtDateTime(d['resolved_at'])),
            ]),
            if (canEdit) ...[
              const Gap(),
              StatefulBuilder(builder: (c, set) {
                return SectionCard(title: 'Update status', children: [
                  Wrap(spacing: 6, children: [
                    for (final e in _inqStatus.entries.where((e) => e.key.isNotEmpty)) ChoiceChip(label: Text(e.value), selected: _status == e.key, onSelected: (_) => set(() => _status = e.key)),
                  ]),
                  const Gap(8),
                  TextField(controller: _notes, maxLines: 4, minLines: 2, decoration: const InputDecoration(labelText: 'Admin notes')),
                  const Gap(8),
                  FilledButton(
                    onPressed: () async {
                      final r = await busy(context, () => api.patch('/admin/contact-inquiries/${widget.id}', {'status': _status, 'admin_notes': _notes.text}), success: 'Inquiry updated');
                      if (r.ok) reload();
                    },
                    child: const Text('Save'),
                  ),
                ]);
              }),
            ],
          ]);
        },
      ),
    );
  }
}
