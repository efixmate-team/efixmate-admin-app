import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';

bool _canEditSettings() => Session.I.canOn('/admin/settings', 'EDIT') || Session.I.can('SYSTEM_SETTINGS');

// ─── General: customer greeting + upload policy ──────────────────────────────

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});
  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  final _greeting = TextEditingController();
  Map<String, dynamic> _policy = {};
  bool _loading = true;
  final _ctl = <String, TextEditingController>{};

  static const _defaults = {
    'images': {'enabled': true, 'maxUploadMb': 10, 'targetMb': 1, 'outputFormat': 'webp', 'acceptedFormats': ['jpg', 'jpeg', 'png', 'webp', 'gif', 'avif', 'heic', 'heif', 'bmp', 'tiff']},
    'documents': {'enabled': true, 'maxUploadMb': 10, 'targetMb': 1, 'acceptedFormats': ['pdf', 'jpg', 'jpeg', 'png', 'webp']},
    'videos': {'maxUploadMb': 10, 'acceptedFormats': ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v']},
  };
  static const _formats = {
    'images': ['jpg', 'jpeg', 'png', 'webp', 'gif', 'avif', 'heic', 'heif', 'bmp', 'tiff'],
    'documents': ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'jpg', 'jpeg', 'png', 'webp'],
    'videos': ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'],
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Future.wait([api.get('/admin/settings/customer-app'), api.get('/admin/upload-settings')]);
    if (!mounted) return;
    setState(() {
      _greeting.text = str(r[0].map['greeting'], '');
      final raw = r[1].ok ? r[1].map : {};
      _policy = {
        for (final k in _defaults.keys) k: {...Map<String, dynamic>.from(_defaults[k]!), ...ApiRes.asMap(raw[k])},
      };
      _loading = false;
    });
  }

  TextEditingController _c(String sec, String key) =>
      _ctl.putIfAbsent('$sec.$key', () => TextEditingController(text: '${ApiRes.asMap(_policy[sec])[key] ?? ''}'));

  Future<void> _saveGreeting() async {
    await busy(context, () => api.post('/admin/settings/customer-app', {'greeting': _greeting.text.trim()}), success: 'Greeting saved.');
  }

  Future<void> _savePolicy() async {
    final out = <String, dynamic>{};
    for (final sec in _policy.keys) {
      final m = Map<String, dynamic>.from(_policy[sec]);
      for (final k in const ['maxUploadMb', 'targetMb']) {
        if (_ctl.containsKey('$sec.$k')) m[k] = num.tryParse(_ctl['$sec.$k']!.text) ?? m[k];
      }
      out[sec] = m;
    }
    await busy(context, () => api.post('/admin/upload-settings', {'policy': out}), success: 'Upload settings saved.');
  }

  @override
  Widget build(BuildContext context) {
    final can = _canEditSettings();
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(12), children: [
      SectionCard(title: 'Customer app home greeting', children: [
        const Text('Heading on the app’s home screen. The customer’s first name is added in front automatically.', style: TextStyle(color: C.body, fontSize: 12.5)),
        const Gap(8),
        TextField(controller: _greeting, enabled: can, maxLength: 80, decoration: const InputDecoration(labelText: 'Greeting text')),
        if (can) FilledButton(onPressed: _saveGreeting, child: const Text('Save greeting')),
      ]),
      const Gap(),
      for (final sec in const ['images', 'documents', 'videos']) ...[
        SectionCard(title: humanize(sec), children: [
          if (sec != 'videos')
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(sec == 'images' ? 'Convert & compress (WebP)' : 'Compress documents'),
              value: truthy(ApiRes.asMap(_policy[sec])['enabled']),
              onChanged: can ? (v) => setState(() => (_policy[sec] as Map)['enabled'] = v) : null,
            ),
          Row(children: [
            Expanded(child: TextField(controller: _c(sec, 'maxUploadMb'), enabled: can, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max upload size (MB)'))),
            if (sec != 'videos') ...[
              const Gap(8),
              Expanded(child: TextField(controller: _c(sec, 'targetMb'), enabled: can, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Compress target (MB)'))),
            ],
          ]),
          const Gap(8),
          const Text('Accepted formats', style: TextStyle(fontWeight: FontWeight.w600)),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final f in _formats[sec]!)
              FilterChip(
                label: Text(f),
                visualDensity: VisualDensity.compact,
                selected: (ApiRes.asMap(_policy[sec])['acceptedFormats'] as List? ?? const []).contains(f),
                onSelected: !can
                    ? null
                    : (on) => setState(() {
                          final l = List<String>.from((_policy[sec] as Map)['acceptedFormats'] ?? const []);
                          on ? l.add(f) : l.remove(f);
                          (_policy[sec] as Map)['acceptedFormats'] = l;
                        }),
              ),
          ]),
        ]),
        const Gap(),
      ],
      if (can) FilledButton(onPressed: _savePolicy, child: const Text('Save upload settings')),
      const Gap(40),
    ]);
  }
}

// ─── Notification channels ───────────────────────────────────────────────────

const _notifTypes = {
  'otp': ('OTP / Verification', 'One-time passwords for login and identity verification'),
  'bookingConfirmation': ('Booking Confirmation', 'Sent when a booking is created or updated'),
  'paymentConfirmation': ('Payment Confirmation', 'Sent after a successful or failed payment'),
  'technicianAssignment': ('Technician Assignment', 'Notify customer when a technician is assigned'),
  'reminders': ('Reminders', 'Service reminders and follow-up messages'),
};

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  Map<String, Map<String, bool>>? _s;

  @override
  void initState() {
    super.initState();
    api.get('/admin/settings/notifications').then((r) {
      if (!mounted) return;
      final raw = r.ok ? r.map : <String, dynamic>{};
      setState(() => _s = {
            for (final k in _notifTypes.keys)
              k: {for (final ch in const ['whatsapp', 'sms', 'email']) ch: truthy(ApiRes.asMap(raw[k])[ch] ?? (k == 'otp' ? ch == 'sms' : true))},
          });
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final can = _canEditSettings();
    if (s == null) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Text('Choose which channels to use for each notification type.', style: TextStyle(color: C.body)),
      const Gap(8),
      for (final e in _notifTypes.entries) ...[
        SectionCard(title: e.value.$1, children: [
          Text(e.value.$2, style: const TextStyle(fontSize: 12.5, color: C.muted)),
          Wrap(spacing: 8, children: [
            for (final ch in const {'whatsapp': 'WhatsApp', 'sms': 'SMS', 'email': 'Email'}.entries)
              FilterChip(label: Text(ch.value), selected: s[e.key]![ch.key]!, onSelected: can ? (v) => setState(() => s[e.key]![ch.key] = v) : null),
          ]),
        ]),
        const Gap(8),
      ],
      if (can) FilledButton(onPressed: () => busy(context, () => api.post('/admin/settings/notifications', {'settings': s}), success: 'Notification settings saved.'), child: const Text('Save')),
    ]);
  }
}

// ─── Payment gateways ────────────────────────────────────────────────────────

const _gateways = {'razorpay': 'Razorpay', 'cashfree': 'Cashfree', 'stripe': 'Stripe', 'phonepe': 'PhonePe'};

class PaymentSettingsScreen extends StatefulWidget {
  const PaymentSettingsScreen({super.key});
  @override
  State<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends State<PaymentSettingsScreen> {
  Map<String, Map<String, Map<String, bool>>>? _s;
  Map<String, dynamic> _configured = {};

  @override
  void initState() {
    super.initState();
    api.get('/admin/settings/payment-gateway').then((r) {
      if (!mounted) return;
      final raw = r.ok ? r.map : <String, dynamic>{};
      _configured = ApiRes.asMap(r['gatewayStatus']);
      setState(() => _s = {
            for (final sec in const ['accept', 'refund'])
              sec: {
                for (final g in _gateways.keys)
                  g: {
                    'enabled': truthy(ApiRes.asMap(ApiRes.asMap(raw[sec])[g])['enabled'] ?? g == 'razorpay'),
                    'isDefault': truthy(ApiRes.asMap(ApiRes.asMap(raw[sec])[g])['isDefault'] ?? g == 'razorpay'),
                  },
              },
          });
    });
  }

  void _toggle(String sec, String g) {
    setState(() {
      final m = _s![sec]!;
      m[g]!['enabled'] = !m[g]!['enabled']!;
      if (!m[g]!['enabled']!) m[g]!['isDefault'] = false;
      if (!m.values.any((v) => v['isDefault']! && v['enabled']!)) {
        final first = m.keys.where((k) => m[k]!['enabled']!).firstOrNull;
        if (first != null) m[first]!['isDefault'] = true;
      }
    });
  }

  void _default(String sec, String g) => setState(() {
        for (final k in _s![sec]!.keys) {
          _s![sec]![k]!['isDefault'] = k == g;
        }
      });

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final can = _canEditSettings();
    if (s == null) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(12), children: [
      for (final sec in const [('accept', 'Accept Payments', 'Enable gateways used for collecting payments from customers.'), ('refund', 'Process Refunds', 'Choose which gateways can initiate refunds back to customers.')]) ...[
        SectionCard(title: sec.$2, children: [
          Text(sec.$3, style: const TextStyle(color: C.body, fontSize: 12.5)),
          for (final g in _gateways.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(g.value),
              subtitle: Text(truthy(ApiRes.asMap(_configured[g.key])['configured']) ? 'Credentials configured' : 'Credentials not configured on server', style: const TextStyle(fontSize: 11.5)),
              leading: Radio<bool>(value: true, groupValue: s[sec.$1]![g.key]!['isDefault'], onChanged: can && s[sec.$1]![g.key]!['enabled']! ? (_) => _default(sec.$1, g.key) : null),
              trailing: Switch(value: s[sec.$1]![g.key]!['enabled']!, onChanged: can ? (_) => _toggle(sec.$1, g.key) : null),
            ),
          const Text('Radio = default gateway', style: TextStyle(fontSize: 11, color: C.muted)),
        ]),
        const Gap(),
      ],
      if (can) FilledButton(onPressed: () => busy(context, () => api.post('/admin/settings/payment-gateway', {'settings': s}), success: 'Payment settings saved.'), child: const Text('Save')),
    ]);
  }
}

// ─── Referral rewards ────────────────────────────────────────────────────────

class ReferralSettingsScreen extends StatefulWidget {
  const ReferralSettingsScreen({super.key});
  @override
  State<ReferralSettingsScreen> createState() => _ReferralSettingsScreenState();
}

class _ReferralSettingsScreenState extends State<ReferralSettingsScreen> {
  Map<String, dynamic>? _c;
  final _ctl = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    api.get('/admin/settings/referral').then((r) {
      if (!mounted) return;
      setState(() {
        _c = {
          'user_enabled': true, 'tech_enabled': true, 'user_referrer_reward': 200, 'user_referred_reward': 100,
          'tech_referrer_reward': 500, 'tech_referred_reward': 0, 'trigger': 'FIRST_BOOKING_COMPLETED',
          ...(r.ok ? r.map : {}),
        };
        for (final k in const ['user_referrer_reward', 'user_referred_reward', 'tech_referrer_reward', 'tech_referred_reward']) {
          _ctl[k] = TextEditingController(text: '${_c![k] ?? 0}');
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final can = _canEditSettings();
    if (c == null) return const Center(child: CircularProgressIndicator());
    Widget section(String title, String desc, String p) => SectionCard(title: title, children: [
          Text(desc, style: const TextStyle(color: C.body, fontSize: 12.5)),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Enabled'), value: truthy(c['${p}_enabled']), onChanged: can ? (v) => setState(() => c['${p}_enabled'] = v) : null),
          TextField(controller: _ctl['${p}_referrer_reward'], enabled: can && truthy(c['${p}_enabled']), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Referrer reward (₹)', helperText: 'Paid to the person who shared their code.')),
          const Gap(8),
          TextField(controller: _ctl['${p}_referred_reward'], enabled: can && truthy(c['${p}_enabled']), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Referred reward (₹)', helperText: 'Paid to the new person who used the code.')),
        ]);
    return ListView(padding: const EdgeInsets.all(12), children: [
      section('Customer Referrals', 'Reward customers for inviting new customers.', 'user'),
      const Gap(),
      section('Technician Referrals', 'Reward technicians for inviting new technicians.', 'tech'),
      const Gap(8),
      const Text('Rewards are paid when the referred person completes their first booking/job.', style: TextStyle(fontSize: 12, color: C.muted)),
      const Gap(),
      if (can)
        FilledButton(
          onPressed: () {
            final body = {...c, for (final e in _ctl.entries) e.key: num.tryParse(e.value.text) ?? 0};
            busy(context, () => api.post('/admin/settings/referral', body), success: 'Referral settings saved.');
          },
          child: const Text('Save'),
        ),
    ]);
  }
}

// ─── My profile, password, 2FA, language ─────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _mobile = TextEditingController();
  String? _image;
  bool _twoFa = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Session.I.restore();
    final p = Session.I.profile ?? {};
    final tf = await api.get('/admin/security/2fa');
    if (!mounted) return;
    setState(() {
      _first.text = str(p['first_name'], '');
      _last.text = str(p['last_name'], '');
      _mobile.text = str(p['mobile_number'], '');
      _image = p['profile_image']?.toString();
      _twoFa = truthy(tf.map['totp_enabled']);
      _loaded = true;
    });
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 75);
    if (x == null) return;
    final bytes = await File(x.path).readAsBytes();
    setState(() => _image = 'data:image/jpeg;base64,${base64Encode(bytes)}');
  }

  Future<void> _save() async {
    final p = Session.I.profile ?? {};
    final r = await busy(context, () => api.post('/admin/update', {
          'adminId': p['admin_id'],
          'firstName': _first.text.trim(),
          'lastName': _last.text.trim(),
          'mobileNumber': _mobile.text.trim(),
          'email': p['email'],
          'profileImage': _image,
        }), success: 'Profile updated successfully!');
    if (r.ok) Session.I.restore();
  }

  Future<void> _changePassword() async {
    final cur = TextEditingController(), nw = TextEditingController(), cf = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Change password'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: cur, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
          const Gap(8),
          TextField(controller: nw, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
          const Gap(8),
          TextField(controller: cf, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Update'))],
      ),
    );
    if (ok != true || !mounted) return;
    if (nw.text != cf.text) return toast('New passwords do not match', error: true);
    await busy(context, () => api.post('/admin/change-password', {'currentPassword': cur.text, 'newPassword': nw.text}), success: 'Password changed');
  }

  Future<void> _twoFactor() async {
    if (_twoFa) {
      final pwd = await prompt(context, 'Turn off two-factor authentication', label: 'Your password', required: true, obscure: true, ok: 'Turn off');
      if (pwd == null || !mounted) return;
      final r = await busy(context, () => api.post('/admin/security/2fa/disable', {'password': pwd}), success: '2FA turned off');
      if (r.ok) setState(() => _twoFa = false);
      return;
    }
    final setup = await busy(context, () => api.post('/admin/security/2fa/setup', {}), toastIt: false);
    if (!setup.ok) {
      toastRes(setup);
      return;
    }
    if (!mounted) return;
    final secret = str(setup.map['secret'], '');
    final url = str(setup.map['otpauthUrl'], '');
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Set up two-factor authentication'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Add this key to Google Authenticator / Authy, then enter the 6-digit code.'),
            const Gap(8),
            SelectableText(secret, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
            Row(children: [
              TextButton.icon(onPressed: () {
                Clipboard.setData(ClipboardData(text: secret));
                toast('Key copied');
              }, icon: const Icon(Icons.copy, size: 16), label: const Text('Copy key')),
              if (url.isNotEmpty) TextButton.icon(onPressed: () => openUrl(url), icon: const Icon(Icons.open_in_new, size: 16), label: const Text('Open app')),
            ]),
            TextField(controller: code, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Authentication code')),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Enable'))],
      ),
    );
    if (ok != true || !mounted) return;
    final r = await busy(context, () => api.post('/admin/security/2fa/enable', {'code': code.text.trim()}), success: '2FA enabled');
    if (r.ok) setState(() => _twoFa = true);
  }

  Future<void> _language() async {
    final cur = str(Session.I.profile?['preferred_language'], 'en');
    final v = await pickOne<String>(context, 'Panel language', const {'en': 'English', 'hi': 'हिन्दी (Hindi)'}, selected: cur);
    if (v == null || !mounted) return;
    final r = await busy(context, () => api.put('/admin/profile/language', {'language': v}), success: 'Language saved');
    if (r.ok) Session.I.restore();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final p = Session.I.profile ?? {};
    return ListView(padding: const EdgeInsets.all(12), children: [
      SectionCard(title: 'Personal information', children: [
        Center(
          child: GestureDetector(
            onTap: _pickImage,
            child: Stack(children: [
              _image != null && _image!.startsWith('data:')
                  ? CircleAvatar(radius: 40, backgroundImage: MemoryImage(base64Decode(_image!.split(',').last)))
                  : Avatar(url: _image, name: Session.I.displayName, size: 80),
              const Positioned(right: 0, bottom: 0, child: CircleAvatar(radius: 13, child: Icon(Icons.camera_alt, size: 14))),
            ]),
          ),
        ),
        const Gap(),
        TextField(controller: _first, decoration: const InputDecoration(labelText: 'First name')),
        const Gap(8),
        TextField(controller: _last, decoration: const InputDecoration(labelText: 'Last name')),
        const Gap(8),
        TextField(controller: _mobile, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number')),
        const Gap(8),
        TextField(controller: TextEditingController(text: str(p['email'], '')), enabled: false, decoration: const InputDecoration(labelText: 'Email address', helperText: 'Email address cannot be changed for security reasons.')),
        const Gap(),
        FilledButton(onPressed: _save, child: const Text('Save profile')),
      ]),
      const Gap(),
      SectionCard(title: 'Security', children: [
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.password), title: const Text('Change password'), trailing: const Icon(Icons.chevron_right), onTap: _changePassword),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.verified_user_outlined),
          title: const Text('Two-factor authentication'),
          subtitle: Text(_twoFa ? 'On' : 'Off'),
          trailing: Switch(value: _twoFa, onChanged: (_) => _twoFactor()),
        ),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.translate), title: const Text('Panel language'), subtitle: Text(str(p['preferred_language'], 'en') == 'hi' ? 'हिन्दी' : 'English'), onTap: _language),
      ]),
      const Gap(),
      SectionCard(title: 'App', children: [
        KV('Server', AppConfig.baseUrl),
        KV('Signed in as', p['email']),
        KV('Role', Session.I.isSuperAdmin ? 'Super Admin' : str(p['role_name'], 'Administrator')),
      ]),
    ]);
  }
}
