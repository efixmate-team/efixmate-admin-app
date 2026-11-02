import 'package:flutter/material.dart';

class C {
  static const primary = Color(0xFF2563EB);
  static const primarySoft = Color(0xFFEFF6FF);
  static const ink = Color(0xFF0F172A);
  static const body = Color(0xFF475569);
  static const muted = Color(0xFF94A3B8);
  static const line = Color(0xFFE2E8F0);
  static const bg = Color(0xFFF8FAFC);
  static const green = Color(0xFF16A34A);
  static const greenSoft = Color(0xFFDCFCE7);
  static const red = Color(0xFFDC2626);
  static const redSoft = Color(0xFFFEE2E2);
  static const amber = Color(0xFFD97706);
  static const amberSoft = Color(0xFFFEF3C7);
  static const violet = Color(0xFF7C3AED);
  static const violetSoft = Color(0xFFEDE9FE);
  static const sky = Color(0xFF0284C7);
  static const skySoft = Color(0xFFE0F2FE);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.primary, primary: C.primary, surface: Colors.white),
    scaffoldBackgroundColor: C.bg,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: C.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(color: C.ink, fontSize: 18, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: C.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: C.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: const BorderSide(color: C.line),
    ),
    dividerTheme: const DividerThemeData(color: C.line, space: 1),
  );
}

/// Badge colours by status keyword (booking, dispute, refund, payout…).
(Color, Color) statusColors(String s) {
  final u = s.toUpperCase();
  if (RegExp(r'(COMPLET|RESOLV|APPROV|SUCCESS|PAID|ACTIVE|ACCEPT|DELIVER|REFUNDED|CAPTURED|ON_TRACK|^D$)').hasMatch(u)) {
    return (C.greenSoft, C.green);
  }
  if (RegExp(r'(CANCEL|REJECT|FAIL|BREACH|INACTIVE|SUSPEND|EXPIRED|DISABLED)').hasMatch(u)) return (C.redSoft, C.red);
  if (RegExp(r'(PENDING|OPEN|SUBMITTED|AWAIT|UNPAID|AT_RISK|NEW|DRAFT|UNASSIGNED)').hasMatch(u)) return (C.amberSoft, C.amber);
  if (RegExp(r'(PROGRESS|STARTED|REVIEW|ARRIV|WAY|PROCESS)').hasMatch(u)) return (C.skySoft, C.sky);
  if (RegExp(r'(ASSIGN|SCHEDULED|WAITING|ESCALAT)').hasMatch(u)) return (C.violetSoft, C.violet);
  return (const Color(0xFFF1F5F9), C.body);
}
