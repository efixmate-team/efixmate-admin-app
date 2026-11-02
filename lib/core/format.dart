import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _inr2 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

double toNum(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);

int? toInt(dynamic v) => v == null ? null : (v is int ? v : int.tryParse(v.toString()));

String inr(dynamic v, {bool paise = false}) => (paise ? _inr2 : _inr).format(toNum(v));

DateTime? parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

String fmtDate(dynamic v, {String fallback = '—'}) {
  final d = parseDate(v);
  return d == null ? fallback : DateFormat('d MMM yyyy').format(d);
}

String fmtDateTime(dynamic v, {String fallback = '—'}) {
  final d = parseDate(v);
  return d == null ? fallback : DateFormat('d MMM yyyy, h:mm a').format(d);
}

String fmtTime(dynamic v) {
  if (v == null) return '';
  final s = v.toString();
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(s);
  if (m == null) return s;
  final h = int.parse(m.group(1)!);
  final mm = m.group(2)!;
  final ampm = h >= 12 ? 'PM' : 'AM';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$mm $ampm';
}

/// "3:45 PM" for a timestamp (today) or "12 Oct, 3:45 PM" otherwise.
String fmtClock(dynamic v) {
  final d = parseDate(v);
  if (d == null) return '';
  final now = DateTime.now();
  final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
  return DateFormat(sameDay ? 'h:mm a' : 'd MMM, h:mm a').format(d);
}

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String ago(dynamic v) {
  final d = parseDate(v);
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return fmtDate(d);
}

/// "PAYMENT_PENDING" → "Payment pending"
String humanize(dynamic v) {
  final s = (v ?? '').toString().replaceAll('_', ' ').trim();
  if (s.isEmpty) return '—';
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

String str(dynamic v, [String fallback = '—']) {
  if (v == null) return fallback;
  final s = v.toString().trim();
  return s.isEmpty || s == 'null' ? fallback : s;
}

String fullName(Map m, {String first = 'first_name', String last = 'last_name'}) {
  final n = '${m[first] ?? ''} ${m[last] ?? ''}'.trim();
  return n.isEmpty ? str(m['name'] ?? m['full_name']) : n;
}

bool truthy(dynamic v) => v == true || v == 1 || v == '1' || v == 'true' || v == 'Y' || v == 'A';
