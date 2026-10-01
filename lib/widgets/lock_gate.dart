import 'package:flutter/material.dart';

import '../utils/app_lock.dart';

// Day 38: same navy palette as the rest of the app.
const Color _navy = Color(0xFF1F2A44);
const Color _navySoft = Color(0xFF3B4A6B);

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
  bool _authenticating = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Day 38: start the fingerprint prompt after the first frame is drawn.
    // Asking for it straight from initState could reach Android while the
    // activity was still saving state ("Called after onSaveInstanceState()").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _unlock();
    });
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
        // Day 38: give Android a moment to finish restoring the activity
        // before asking for the fingerprint prompt.
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && !_unlocked) _unlock();
        });
      }
    }
  }

  Future<void> _unlock() async {
    // Day 38: never start a second prompt while one is already showing
    // (start-up, resume and the Unlock button could all trigger this).
    if (_authenticating) return;
    _authenticating = true;
    try {
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
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_unlocked)
          Positioned.fill(
            child: Scaffold(
              body: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_navy, _navySoft],
                  ),
                ),
                child: Center(
                  child: _checking
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.lock_outline,
                                size: 46,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'MY4 is locked',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Use your fingerprint or screen lock to continue',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 28),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: _navy,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 14,
                                ),
                              ),
                              onPressed: _unlock,
                              icon: const Icon(Icons.fingerprint),
                              label: const Text('Unlock'),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}