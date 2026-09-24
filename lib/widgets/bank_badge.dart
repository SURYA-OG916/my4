import 'package:flutter/material.dart';

class BankInfo {
  final String key;
  final String code;
  final Color color;

  const BankInfo(this.key, this.code, this.color);
}

class _BankRule {
  final List<String> keywords;
  final BankInfo info;

  const _BankRule(this.keywords, this.info);
}

const List<_BankRule> _rules = [
  _BankRule(['state bank', 'sbi'], BankInfo('sbi', 'SBI', Color(0xFF1E88E5))),
  _BankRule(['hdfc'], BankInfo('hdfc', 'HDFC', Color(0xFF1A4F8B))),
  _BankRule(['icici'], BankInfo('icici', 'ICICI', Color(0xFFE65100))),
  _BankRule(['axis'], BankInfo('axis', 'AXIS', Color(0xFF9C1B4A))),
  _BankRule(['kotak'], BankInfo('kotak', 'KOTAK', Color(0xFFD32F2F))),
  _BankRule(['punjab national', 'pnb'], BankInfo('pnb', 'PNB', Color(0xFF8E24AA))),
  _BankRule(['baroda'], BankInfo('bob', 'BOB', Color(0xFFEF6C00))),
  _BankRule(['canara'], BankInfo('canara', 'CAN', Color(0xFF0288D1))),
  _BankRule(['union bank'], BankInfo('union', 'UBI', Color(0xFFC62828))),
  _BankRule(['idfc'], BankInfo('idfc', 'IDFC', Color(0xFF7B1FA2))),
  _BankRule(['yes bank'], BankInfo('yes', 'YES', Color(0xFF1565C0))),
  _BankRule(['indusind'], BankInfo('indusind', 'IND', Color(0xFF6D4C41))),
  _BankRule(['slice'], BankInfo('slice', 'SLICE', Color(0xFF5E35B1))),
  _BankRule(['paytm'], BankInfo('paytm', 'PAYTM', Color(0xFF0277BD))),
];

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final p = parts.first;
    return p.substring(0, p.length >= 2 ? 2 : 1).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

BankInfo bankInfoFor(String bankName) {
  final lower = bankName.toLowerCase();
  for (final rule in _rules) {
    for (final k in rule.keywords) {
      if (lower.contains(k)) return rule.info;
    }
  }
  return BankInfo('other', _initials(bankName), Colors.blueGrey);
}

/// Round badge for a bank. If you add your own logo at
/// assets/banks/<key>.png (e.g. assets/banks/sbi.png) it is used
/// automatically; otherwise a coloured monogram is shown.
///
/// Day 32: logos are shown in full (BoxFit.contain) on a white circle with a
/// little padding, so wide or non-square logos are no longer cropped.
class BankBadge extends StatelessWidget {
  final String bankName;
  final double size;

  const BankBadge({super.key, required this.bankName, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final info = bankInfoFor(bankName);
    final monogram = _Monogram(info: info, size: size);
    if (info.key == 'other') return monogram;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          'assets/banks/${info.key}.png',
          fit: BoxFit.contain,
          // Only wraps the logo when the PNG loads; if the file is missing,
          // errorBuilder's monogram is used directly (no white padding).
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            return Container(
              color: Colors.white,
              padding: EdgeInsets.all(size * 0.12),
              child: child,
            );
          },
          errorBuilder: (_, __, ___) => monogram,
        ),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  final BankInfo info;
  final double size;

  const _Monogram({required this.info, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: info.color, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(size * 0.12),
        child: FittedBox(
          child: Text(
            info.code,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}