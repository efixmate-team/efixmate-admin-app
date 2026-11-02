import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/format.dart';
import 'theme.dart';

// ─── Feedback ────────────────────────────────────────────────────────────────

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final navigatorKey = GlobalKey<NavigatorState>();

void toast(String msg, {bool error = false}) {
  scaffoldMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? C.red : C.ink,
    ));
}

/// Toast the API result; returns res.ok.
bool toastRes(ApiRes res, {String? success}) {
  if (res.ok) {
    toast(success ?? (res.message.isNotEmpty ? res.message : 'Done'));
  } else {
    toast(res.message.isNotEmpty ? res.message : 'Something went wrong', error: true);
  }
  return res.ok;
}

Future<bool> confirm(BuildContext context, String title, {String? message, String ok = 'Confirm', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: C.red) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

/// Single text prompt. Returns null on cancel.
Future<String?> prompt(BuildContext context, String title,
    {String? label, String? initial, String? hint, bool required = false, int lines = 1, String ok = 'Save', TextInputType? keyboard, bool obscure = false}) async {
  final ctl = TextEditingController(text: initial ?? '');
  final r = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: obscure ? 1 : lines,
          minLines: 1,
          obscureText: obscure,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onChanged: (_) => set(() {}),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            onPressed: required && ctl.text.trim().isEmpty ? null : () => Navigator.pop(c, ctl.text.trim()),
            child: Text(ok),
          ),
        ],
      );
    }),
  );
  return r;
}

/// Pick one of [options] (value → label) in a bottom sheet.
Future<T?> pickOne<T>(BuildContext context, String title, Map<T, String> options, {T? selected}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * .7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)))),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final e in options.entries)
                ListTile(
                  title: Text(e.value),
                  trailing: e.key == selected ? const Icon(Icons.check, color: C.primary) : null,
                  onTap: () => Navigator.pop(c, e.key),
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
}

/// Run an API call with a blocking progress overlay, toast the outcome.
Future<ApiRes> busy(BuildContext context, Future<ApiRes> Function() call, {String? success, bool toastIt = true}) async {
  showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
  ApiRes res;
  try {
    res = await call();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
  if (toastIt) toastRes(res, success: success);
  return res;
}

Future<void> openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) toast('Could not open $url', error: true);
}

void callPhone(dynamic phone) {
  final p = str(phone, '');
  if (p.isEmpty) return toast('No phone number', error: true);
  openUrl('tel:$p');
}

void whatsapp(dynamic phone) {
  var p = str(phone, '').replaceAll(RegExp(r'\D'), '');
  if (p.isEmpty) return toast('No phone number', error: true);
  if (p.length == 10) p = '91$p';
  openUrl('https://wa.me/$p');
}

// ─── Building blocks ─────────────────────────────────────────────────────────

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.label});
  final dynamic status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final s = str(status, '');
    if (s.isEmpty) return const SizedBox.shrink();
    final (bg, fg) = statusColors(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label ?? humanize(s), style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.trailing, required this.children, this.padding = const EdgeInsets.all(14)});
  final String? title;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Expanded(child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: C.ink))),
                ?trailing,
              ]),
            ),
          ...children,
        ]),
      ),
    );
  }
}

class KV extends StatelessWidget {
  const KV(this.k, this.v, {super.key, this.bold = false, this.color});
  final String k;
  final dynamic v;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 4, child: Text(k, style: const TextStyle(color: C.body, fontSize: 13))),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: v is Widget
              ? Align(alignment: Alignment.centerRight, child: v)
              : SelectableText(str(v), textAlign: TextAlign.right, style: TextStyle(fontSize: 13.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color ?? C.ink)),
        ),
      ]),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon, this.color = C.primary, this.sub, this.onTap});
  final String label;
  final String value;
  final IconData? icon;
  final Color color;
  final String? sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.body, fontSize: 12.5))),
            ]),
            const SizedBox(height: 8),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: C.ink))),
            if (sub != null) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 11.5)),
          ]),
        ),
      ),
    );
  }
}

/// Two-column grid of stat tiles.
class StatGrid extends StatelessWidget {
  const StatGrid(this.tiles, {super.key});
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (c, box) {
      final cols = box.maxWidth > 700 ? 4 : 2;
      final w = (box.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.message, {super.key, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: C.muted),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: C.body)),
        ]),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 44, color: C.red),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[const SizedBox(height: 12), OutlinedButton(onPressed: onRetry, child: const Text('Try again'))],
        ]),
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, this.url, required this.name, this.size = 40});
  final dynamic url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = AppConfig.fileUrl(url);
    final initials = name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).take(2).map((e) => e[0].toUpperCase()).join();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: C.primarySoft,
      foregroundImage: u.isEmpty ? null : NetworkImage(u),
      child: Text(initials, style: TextStyle(color: C.primary, fontWeight: FontWeight.w700, fontSize: size * .36)),
    );
  }
}

/// Horizontal scrollable filter chips.
class FilterChips<T> extends StatelessWidget {
  const FilterChips({super.key, required this.options, required this.value, required this.onChanged});
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(e.value),
                selected: e.key == value,
                onSelected: (_) => onChanged(e.key),
                showCheckmark: false,
                labelStyle: TextStyle(fontSize: 12.5, color: e.key == value ? Colors.white : C.ink, fontWeight: FontWeight.w600),
                selectedColor: C.primary,
                backgroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

/// Image thumbnail that opens full-screen on tap.
class NetImage extends StatelessWidget {
  const NetImage(this.path, {super.key, this.size = 72, this.label});
  final dynamic path;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final url = AppConfig.fileUrl(path);
    if (url.isEmpty) {
      return Container(width: size, height: size, decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: C.line)), child: const Icon(Icons.image_not_supported_outlined, color: C.muted));
    }
    final isPdf = url.toLowerCase().contains('.pdf');
    return GestureDetector(
      onTap: () => isPdf ? openUrl(url) : Navigator.push(context, MaterialPageRoute(builder: (_) => ImageViewer(url: url, title: label))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: isPdf
            ? Container(width: size, height: size, color: C.redSoft, child: const Icon(Icons.picture_as_pdf, color: C.red))
            : Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(width: size, height: size, color: C.bg, child: const Icon(Icons.broken_image_outlined, color: C.muted))),
      ),
    );
  }
}

class ImageViewer extends StatelessWidget {
  const ImageViewer({super.key, required this.url, this.title});
  final String url;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title ?? '', style: const TextStyle(color: Colors.white)),
        actions: [IconButton(onPressed: () => openUrl(url), icon: const Icon(Icons.open_in_new))],
      ),
      body: InteractiveViewer(maxScale: 5, child: Center(child: Image.network(url))),
    );
  }
}

/// FutureBuilder wrapper for a single ApiRes with loading/error/refresh handling.
class ApiLoader extends StatefulWidget {
  const ApiLoader({super.key, required this.load, required this.builder});
  final Future<ApiRes> Function() load;
  final Widget Function(BuildContext context, ApiRes res, Future<void> Function() reload) builder;

  @override
  State<ApiLoader> createState() => ApiLoaderState();
}

class ApiLoaderState extends State<ApiLoader> {
  ApiRes? _res;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (_res == null) setState(() => _loading = true);
    final r = await widget.load();
    if (!mounted) return;
    setState(() {
      _res = r;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _res == null) return const Center(child: CircularProgressIndicator());
    final r = _res!;
    if (!r.ok) return ErrorView(r.message.isEmpty ? 'Could not load' : r.message, onRetry: reload);
    return RefreshIndicator(onRefresh: reload, child: widget.builder(context, r, reload));
  }
}

class Gap extends StatelessWidget {
  const Gap([this.size = 12, Key? key]) : super(key: key);
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}

/// Tile used for list rows across modules.
class RowTile extends StatelessWidget {
  const RowTile({super.key, required this.title, this.subtitle, this.lines = const [], this.trailing, this.leading, this.onTap, this.badge});
  final String title;
  final String? subtitle;
  final List<String> lines;
  final Widget? trailing;
  final Widget? leading;
  final Widget? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: C.ink, fontSize: 14.5))),
                  if (badge != null) ...[const SizedBox(width: 6), badge!],
                ]),
                if (subtitle != null && subtitle!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: const TextStyle(color: C.body, fontSize: 13))),
                for (final l in lines.where((e) => e.trim().isNotEmpty))
                  Padding(padding: const EdgeInsets.only(top: 2), child: Text(l, style: const TextStyle(color: C.muted, fontSize: 12.5))),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ]),
        ),
      ),
    );
  }
}
