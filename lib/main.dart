import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api.dart';
import 'core/config.dart';
import 'core/session.dart';
import 'screens/auth/login_screen.dart';
import 'screens/shell.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  await Api.I.init();
  Api.I.stepUpHandler = _stepUp;
  Api.I.onUnauthorized = Session.I.expire;
  runApp(ChangeNotifierProvider.value(value: Session.I, child: const AdminApp()));
}

/// Sensitive actions (refund approve / retry / resolve…) need a fresh password
/// confirmation. Same flow as the web StepUpBridge.
Future<bool> _stepUp() async {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return false;
  final pwd = await prompt(ctx, 'Confirm it’s you', label: 'Password or 6-digit 2FA code', required: true, ok: 'Confirm', obscure: true);
  if (pwd == null) return false;
  final looksLikeTotp = RegExp(r'^\d{6}$').hasMatch(pwd);
  final res = await api.post('/admin/security/step-up', looksLikeTotp ? {'totpCode': pwd} : {'password': pwd});
  if (!res.ok) toast(res.message.isEmpty ? 'Verification failed' : res.message, error: true);
  return res.ok;
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eFixMate Admin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: const _Root(),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  @override
  void initState() {
    super.initState();
    Session.I.restore();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    if (!s.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return s.signedIn ? const Shell() : const LoginScreen();
  }
}
