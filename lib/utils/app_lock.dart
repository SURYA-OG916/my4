import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Central place for app-lock and balance-visibility state.
class AppLock {
  AppLock._();
  static final AppLock instance = AppLock._();

  /// How long balances stay revealed after a successful unlock.
  static const Duration balanceRevealDuration = Duration(seconds: 60);

  final LocalAuthentication _auth = LocalAuthentication();

  /// true while balances are revealed.
  final ValueNotifier<bool> balancesVisible = ValueNotifier<bool>(false);

  Timer? _hideTimer;
  bool _prompting = false;

  bool get isPrompting => _prompting;

  /// True if the phone has a fingerprint/face or a screen lock we can use.
  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// Shows the system prompt (fingerprint, with PIN/pattern/password fallback).
  Future<bool> authenticate(String reason) async {
    if (_prompting) return false;
    _prompting = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    } finally {
      _prompting = false;
    }
  }

  /// Asks for authentication, then reveals balances for a short time.
  /// If the phone has no screen lock at all, there is nothing to check
  /// against, so balances are revealed without a prompt.
  Future<bool> revealBalances() async {
    if (balancesVisible.value) return true;
    final supported = await isSupported();
    final ok = supported ? await authenticate('Unlock to view balances') : true;
    if (ok) {
      balancesVisible.value = true;
      _hideTimer?.cancel();
      _hideTimer = Timer(balanceRevealDuration, hideBalances);
    }
    return ok;
  }

  void hideBalances() {
    _hideTimer?.cancel();
    balancesVisible.value = false;
  }
}