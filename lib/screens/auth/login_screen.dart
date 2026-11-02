import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/session.dart';
import '../../ui/theme.dart';
import '../../ui/widgets.dart';
import 'qr_scan_screen.dart';

/// Admins sign in with their personal login link (…/login/<admin id>) — the
/// server requires the admin id alongside email + password. Paste the link or
/// just the id; it's remembered on this device.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _uid = TextEditingController();
  final _email = TextEditingController();
  final _pwd = TextEditingController();
  final _code = TextEditingController();
  final _pwdFocus = FocusNode();
  bool _hide = true;
  bool _loading = false;
  String? _error;
  String? _pendingToken;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      _uid.text = p.getString('efm_admin_uid') ?? '';
      _email.text = p.getString('efm_admin_email') ?? '';
      setState(() {});
    });
  }

  /// Fill server, login ID and email from the web profile QR; only the
  /// password is left to type.
  Future<void> _scan() async {
    final qr = await Navigator.push<LoginQr>(context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (qr == null || !mounted) return;
    if (qr.api != null && qr.api!.isNotEmpty) {
      await AppConfig.useScannedServer(qr.api!);
      Api.I.rebuild();
    }
    setState(() {
      _uid.text = qr.uid;
      if (qr.email != null && qr.email!.isNotEmpty) _email.text = qr.email!;
      _error = null;
    });
    toast('QR scanned — enter your password');
    _pwdFocus.requestFocus();
  }

  String _parseUid(String raw) {
    final s = raw.trim();
    final m = RegExp(r'/login/([^/?#\s]+)').firstMatch(s);
    return Uri.decodeComponent(m?.group(1) ?? s);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_pendingToken != null) {
        final r = await Session.I.verify2fa(_pendingToken!, _code.text.trim());
        if (!r.ok) return setState(() => _error = r.message.isEmpty ? 'Invalid code' : r.message);
        return _finish();
      }
      final uid = _parseUid(_uid.text);
      if (uid.isEmpty || _email.text.trim().isEmpty || _pwd.text.isEmpty) {
        return setState(() => _error = 'Enter your login link / admin ID, email and password.');
      }
      final check = await api.post('/check-uid', {'uid': uid});
      if (check['exists'] != true) {
        return setState(() => _error = check.ok || check['exists'] == false ? 'This login link is invalid or no longer available.' : check.message);
      }
      if (check['belongsTo'] != null && check['belongsTo'] != 'ADMIN') {
        return setState(() => _error = 'This link is not an admin login link.');
      }
      final r = await Session.I.login(uid: uid, email: _email.text.trim(), password: _pwd.text);
      if (!r.ok) {
        final wait = r['retry_after'];
        return setState(() => _error = wait != null ? 'Too many attempts. Try again in ${wait}s.' : (r.message.isEmpty ? 'Login failed' : r.message));
      }
      final p = await SharedPreferences.getInstance();
      await p.setString('efm_admin_uid', uid);
      await p.setString('efm_admin_email', _email.text.trim());
      if (r['requires2fa'] == true && r['pendingToken'] != null) {
        return setState(() => _pendingToken = r['pendingToken'].toString());
      }
      await _finish();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _finish() async {
    final ok = await Session.I.restore();
    if (!ok && mounted) setState(() => _error = 'Login succeeded, but the session could not be loaded.');
  }

  Future<void> _serverPicker() async {
    final picked = await pickOne<ServerEnv>(context, 'Server', {
      ServerEnv.live: 'Live  (api.efixmate.com)',
      ServerEnv.dev: 'Dev  (dev.api.efixmate.com)',
      ServerEnv.local: 'Local  (${AppConfig.localHost})',
      if (AppConfig.customUrl.isNotEmpty) ServerEnv.custom: 'From QR  (${AppConfig.customUrl})',
    }, selected: AppConfig.env);
    if (picked == null || !mounted) return;
    String? local;
    if (picked == ServerEnv.local) {
      local = await prompt(context, 'Local server URL', initial: AppConfig.localHost, hint: 'http://192.168.1.10:5000');
      if (local == null) return;
    }
    await AppConfig.save(picked, local: local);
    Api.I.rebuild();
    setState(() {});
    toast('Server: ${AppConfig.baseUrl}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                GestureDetector(
                  onLongPress: _serverPicker,
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: C.primarySoft, borderRadius: BorderRadius.circular(18)),
                    child: const Icon(Icons.admin_panel_settings, color: C.primary, size: 34),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('eFixMate Admin', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: C.ink)),
                const SizedBox(height: 4),
                Text(_pendingToken == null ? 'Sign in to manage your operations' : 'Enter the 6-digit code from your authenticator app',
                    style: const TextStyle(color: C.body)),
                const SizedBox(height: 28),
                if (_pendingToken == null) ...[
                  TextField(
                    controller: _uid,
                    decoration: const InputDecoration(labelText: 'Login link or admin ID', prefixIcon: Icon(Icons.link)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pwd,
                    focusNode: _pwdFocus,
                    obscureText: _hide,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _hide = !_hide)),
                    ),
                  ),
                ] else
                  TextField(
                    controller: _code,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: 'Authentication code', prefixIcon: Icon(Icons.verified_user_outlined)),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: C.redSoft, borderRadius: BorderRadius.circular(10)),
                    child: Text(_error!, style: const TextStyle(color: C.red)),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_pendingToken == null ? 'Sign in' : 'Verify'),
                ),
                if (_pendingToken != null)
                  TextButton(onPressed: () => setState(() => _pendingToken = null), child: const Text('Back')),
                if (_pendingToken == null) ...[
                  const SizedBox(height: 16),
                  const Row(children: [
                    Expanded(child: Divider()),
                    Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('or', style: TextStyle(color: C.muted))),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan QR from web admin panel'),
                  ),
                ],
                const SizedBox(height: 24),
                Center(
                  child: Text('Server: ${AppConfig.baseUrl}', style: const TextStyle(color: C.muted, fontSize: 11.5)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
