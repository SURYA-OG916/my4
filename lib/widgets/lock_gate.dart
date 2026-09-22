import 'package:flutter/material.dart';

import '../utils/app_lock.dart';

/// Covers the whole app with a lock screen until the user authenticates.
/// Use it from MaterialApp's `builder:` so it also covers pushed screens.
class LockGate extends StatefulWidget {
  final Widget child;

  const LockGate({super.key, required this.child});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  /// Re-lock if the app was in the background longer than this.
  static const Duration _relockAfter = Duration(seconds: 30);

  bool _checking = true;
  bool _unlocked = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _unlock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (!AppLock.instance.isPrompting) {
        _pausedAt = DateTime.now();
        AppLock.instance.hideBalances();
      }
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt != null &&
          _unlocked &&
          DateTime.now().difference(pausedAt) > _relockAfter) {
        setState(() => _unlocked = false);
        _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    final supported = await AppLock.instance.isSupported();
    if (!supported) {
      // No fingerprint or screen lock on this phone: nothing to check against.
      if (mounted) {
        setState(() {
          _checking = false;
          _unlocked = true;
        });
      }
      return;
    }
    if (mounted) setState(() => _checking = false);
    final ok = await AppLock.instance.authenticate('Unlock MY4');
    if (mounted && ok) setState(() => _unlocked = true);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_unlocked)
          Positioned.fill(
            child: Scaffold(
              body: Center(
                child: _checking
                    ? const CircularProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline, size: 64),
                          const SizedBox(height: 16),
                          const Text(
                            'MY4 is locked',
                            style: TextStyle(fontSize: 20),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _unlock,
                            icon: const Icon(Icons.fingerprint),
                            label: const Text('Unlock'),
                          ),
                        ],
                      ),
              ),
            ),
          ),
      ],
    );
  }
}