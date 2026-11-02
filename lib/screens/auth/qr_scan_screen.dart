import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../ui/theme.dart';

/// What the web panel's profile QR carries
/// (`efixmate-admin://login?api=…&uid=…&email=…`). No secret is inside.
class LoginQr {
  LoginQr({required this.uid, this.api, this.email});
  final String uid;
  final String? api;
  final String? email;

  /// Accepts the app QR, or a plain login link `…/login/<uid>` as a fallback.
  static LoginQr? parse(String raw) {
    final s = raw.trim();
    final uri = Uri.tryParse(s);
    if (uri != null && uri.scheme == 'efixmate-admin') {
      final uid = uri.queryParameters['uid'];
      if (uid == null || uid.isEmpty) return null;
      return LoginQr(uid: uid, api: uri.queryParameters['api'], email: uri.queryParameters['email']);
    }
    final m = RegExp(r'/login/([^/?#\s]+)').firstMatch(s);
    if (m != null) return LoginQr(uid: Uri.decodeComponent(m.group(1)!));
    return null;
  }
}

/// Full-screen camera scanner; pops with a [LoginQr] once a valid code is seen.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _ctl = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final qr = LoginQr.parse(b.rawValue ?? '');
      if (qr != null) {
        _done = true;
        Navigator.pop(context, qr);
        return;
      }
    }
    setState(() => _hint = 'That isn’t an eFixMate admin login QR');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan login QR', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(onPressed: _ctl.toggleTorch, icon: const Icon(Icons.flash_on)),
          IconButton(onPressed: _ctl.switchCamera, icon: const Icon(Icons.cameraswitch_outlined)),
        ],
      ),
      body: Stack(alignment: Alignment.center, children: [
        MobileScanner(
          controller: _ctl,
          onDetect: _onDetect,
          errorBuilder: (c, e) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Camera unavailable: ${e.errorCode.name}. Allow camera access in settings.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
        Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(18)),
        ),
        Positioned(
          bottom: 48,
          left: 24,
          right: 24,
          child: Text(
            _hint ?? 'Open the web admin panel → Profile → “Sign in on the mobile app”, then point the camera at the QR code.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _hint == null ? Colors.white : C.amber, fontSize: 14),
          ),
        ),
      ]),
    );
  }
}
