import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/format.dart';
import 'theme.dart';
import 'widgets.dart';

enum F { text, multiline, number, decimal, email, phone, password, toggle, select, multiSelect, date, dateTime, time, color, image }

typedef OptionsLoader = Future<Map<String, String>> Function(Map<String, dynamic> values);

/// One field in a generated form. [key] is the payload key sent to the API.
class Field {
  Field(this.key, this.label, {
    this.type = F.text,
    this.required = false,
    this.options,
    this.loader,
    this.hint,
    this.help,
    this.visibleIf,
    this.dependsOn = const [],
    this.initial,
  });

  final String key;
  final String label;
  final F type;
  final bool required;

  /// Static options (value → label) for select / multiSelect.
  final Map<String, String>? options;

  /// Dynamic options; re-run when any key in [dependsOn] changes.
  final OptionsLoader? loader;
  final List<String> dependsOn;
  final String? hint;
  final String? help;
  final dynamic initial;

  /// Hide the field unless this returns true for the current values.
  final bool Function(Map<String, dynamic> values)? visibleIf;
}

/// Opens a full-screen form; [onSubmit] receives the values and returns the
/// API result. Closes and returns true when the save succeeded.
Future<bool> openForm(
  BuildContext context, {
  required String title,
  required List<Field> fields,
  Map<String, dynamic>? initial,
  required Future<ApiRes> Function(Map<String, dynamic> values) onSubmit,
  String submitLabel = 'Save',
}) async {
  final r = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => FormPage(title: title, fields: fields, initial: initial ?? {}, onSubmit: onSubmit, submitLabel: submitLabel)),
  );
  return r == true;
}

class FormPage extends StatefulWidget {
  const FormPage({super.key, required this.title, required this.fields, required this.initial, required this.onSubmit, this.submitLabel = 'Save'});
  final String title;
  final List<Field> fields;
  final Map<String, dynamic> initial;
  final Future<ApiRes> Function(Map<String, dynamic> values) onSubmit;
  final String submitLabel;

  @override
  State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  late final Map<String, dynamic> v;
  final _ctl = <String, TextEditingController>{};
  final _opts = <String, Map<String, String>>{};
  final _loadingOpts = <String>{};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    v = {};
    for (final f in widget.fields) {
      v[f.key] = widget.initial.containsKey(f.key) ? widget.initial[f.key] : f.initial;
      if (_isText(f.type)) _ctl[f.key] = TextEditingController(text: v[f.key] == null ? '' : v[f.key].toString());
    }
    for (final f in widget.fields) {
      if (f.loader != null) _load(f);
    }
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isText(F t) => const [F.text, F.multiline, F.number, F.decimal, F.email, F.phone, F.password, F.color].contains(t);

  Future<void> _load(Field f) async {
    setState(() => _loadingOpts.add(f.key));
    try {
      final o = await f.loader!(v);
      if (mounted) setState(() => _opts[f.key] = o);
    } finally {
      if (mounted) setState(() => _loadingOpts.remove(f.key));
    }
  }

  void _set(String key, dynamic value) {
    setState(() => v[key] = value);
    for (final f in widget.fields) {
      if (f.dependsOn.contains(key) && f.loader != null) {
        v[f.key] = f.type == F.multiSelect ? <String>[] : null;
        _load(f);
      }
    }
  }

  Map<String, String> _optionsFor(Field f) => f.options ?? _opts[f.key] ?? const {};

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final out = <String, dynamic>{};
    for (final f in widget.fields) {
      if (f.visibleIf != null && !f.visibleIf!(v)) continue;
      dynamic val = v[f.key];
      if (_isText(f.type)) {
        final t = _ctl[f.key]!.text.trim();
        val = switch (f.type) {
          F.number => t.isEmpty ? null : int.tryParse(t),
          F.decimal => t.isEmpty ? null : double.tryParse(t),
          _ => t.isEmpty ? null : t,
        };
      }
      final empty = val == null || (val is String && val.isEmpty) || (val is List && val.isEmpty);
      if (f.required && empty && f.type != F.toggle) {
        setState(() => _error = '${f.label} is required');
        return;
      }
      out[f.key] = f.type == F.toggle ? (val == true) : val;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await widget.onSubmit(out);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      toast(res.message.isNotEmpty ? res.message : 'Saved');
      Navigator.pop(context, true);
    } else {
      setState(() => _error = res.message.isNotEmpty ? res.message : 'Unable to save');
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.fields.where((f) => f.visibleIf == null || f.visibleIf!(v)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final f in visible) Padding(padding: const EdgeInsets.only(bottom: 14), child: _field(f)),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.redSoft, borderRadius: BorderRadius.circular(10)),
              child: Text(_error!, style: const TextStyle(color: C.red)),
            ),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(widget.submitLabel),
          ),
        ),
      ),
    );
  }

  Widget _label(Field f) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('${f.label}${f.required ? ' *' : ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: C.ink)),
      );

  Widget _help(Field f) => f.help == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 4), child: Text(f.help!, style: const TextStyle(fontSize: 12, color: C.muted)));

  Widget _field(Field f) {
    switch (f.type) {
      case F.toggle:
        return Card(
          child: SwitchListTile(
            title: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: f.help == null ? null : Text(f.help!, style: const TextStyle(fontSize: 12)),
            value: truthy(v[f.key]),
            onChanged: (x) => _set(f.key, x),
          ),
        );
      case F.select:
        final opts = _optionsFor(f);
        final cur = v[f.key]?.toString();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(f),
          InkWell(
            onTap: () async {
              if (opts.isEmpty) return;
              final picked = await pickOne<String>(context, f.label, opts, selected: cur);
              if (picked != null) _set(f.key, picked);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                hintText: _loadingOpts.contains(f.key) ? 'Loading…' : (f.hint ?? 'Select'),
                suffixIcon: const Icon(Icons.expand_more),
              ),
              isEmpty: cur == null || !opts.containsKey(cur),
              child: Text(cur != null ? (opts[cur] ?? cur) : ''),
            ),
          ),
          _help(f),
        ]);
      case F.multiSelect:
        final opts = _optionsFor(f);
        final sel = List<String>.from((v[f.key] as List?)?.map((e) => e.toString()) ?? const []);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(f),
          if (_loadingOpts.contains(f.key)) const LinearProgressIndicator(),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in opts.entries)
              FilterChip(
                label: Text(e.value, style: const TextStyle(fontSize: 12.5)),
                selected: sel.contains(e.key),
                onSelected: (on) {
                  final next = [...sel];
                  on ? next.add(e.key) : next.remove(e.key);
                  _set(f.key, next);
                },
              ),
          ]),
          _help(f),
        ]);
      case F.date:
      case F.dateTime:
        final d = parseDate(v[f.key]);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(f),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(context: context, initialDate: d ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (picked == null) return;
              if (f.type == F.date) return _set(f.key, ymd(picked));
              if (!mounted) return;
              final t = await showTimePicker(context: context, initialTime: d != null ? TimeOfDay.fromDateTime(d) : TimeOfDay.now());
              final full = DateTime(picked.year, picked.month, picked.day, t?.hour ?? 0, t?.minute ?? 0);
              _set(f.key, full.toIso8601String());
            },
            child: InputDecorator(
              decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today, size: 18)),
              isEmpty: d == null,
              child: Text(d == null ? '' : (f.type == F.date ? fmtDate(d) : fmtDateTime(d))),
            ),
          ),
          _help(f),
        ]);
      case F.time:
        final cur = v[f.key]?.toString();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(f),
          InkWell(
            onTap: () async {
              final parts = (cur ?? '09:00').split(':');
              final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0));
              if (t != null) _set(f.key, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
            },
            child: InputDecorator(decoration: const InputDecoration(suffixIcon: Icon(Icons.schedule, size: 18)), isEmpty: cur == null, child: Text(fmtTime(cur))),
          ),
        ]);
      case F.image:
        final cur = v[f.key];
        final isLocal = cur is XFile;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(f),
          Row(children: [
            if (cur != null && !isLocal) NetImage(cur, size: 72),
            if (isLocal) const Icon(Icons.check_circle, color: C.green),
            if (isLocal) Expanded(child: Padding(padding: const EdgeInsets.only(left: 6), child: Text(cur.name, overflow: TextOverflow.ellipsis))),
            if (!isLocal) const Spacer(),
            OutlinedButton.icon(
              icon: const Icon(Icons.upload, size: 18),
              label: Text(cur == null ? 'Choose image' : 'Replace'),
              onPressed: () async {
                final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
                if (x != null) _set(f.key, x);
              },
            ),
          ]),
          _help(f),
        ]);
      default:
        final kb = switch (f.type) {
          F.number => TextInputType.number,
          F.decimal => const TextInputType.numberWithOptions(decimal: true),
          F.email => TextInputType.emailAddress,
          F.phone => TextInputType.phone,
          F.multiline => TextInputType.multiline,
          _ => TextInputType.text,
        };
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label(f),
          TextField(
            controller: _ctl[f.key],
            keyboardType: kb,
            obscureText: f.type == F.password,
            maxLines: f.type == F.multiline ? 5 : 1,
            minLines: f.type == F.multiline ? 3 : 1,
            decoration: InputDecoration(
              hintText: f.hint,
              prefixIcon: f.type == F.color
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Container(width: 18, height: 18, decoration: BoxDecoration(color: _parseColor(_ctl[f.key]!.text), borderRadius: BorderRadius.circular(4), border: Border.all(color: C.line))),
                    )
                  : null,
            ),
            onChanged: f.type == F.color ? (_) => setState(() {}) : null,
          ),
          _help(f),
        ]);
    }
  }
}

Color _parseColor(String s) {
  final h = s.replaceAll('#', '').trim();
  if (h.length != 6) return Colors.transparent;
  final n = int.tryParse(h, radix: 16);
  return n == null ? Colors.transparent : Color(0xFF000000 | n);
}

/// True when a form value is a freshly picked image that must be uploaded.
bool isPickedFile(dynamic v) => v is XFile;

/// Absolute URL helper re-exported for screens that only import form.dart.
String fileUrl(dynamic p) => AppConfig.fileUrl(p);
