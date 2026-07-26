import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _pinCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length != 4) {
      setState(() => _error = 'A PIN pontosan 4 számjegy.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider).signInWithPin(pin);
    } catch (e) {
      setState(() => _error = e is PinLoginException ? e.message : 'A bejelentkezés sikertelen.');
      _pinCtrl.clear();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.mail_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 20),
                  Text('TaskMail', style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 6),
                  Text(
                    'Jelentkezz be a ServeOS PIN-kódoddal',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _pinCtrl,
                    autofocus: true,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 12),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(counterText: '', labelText: 'PIN kód'),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.priorityUrgent),
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Bejelentkezés'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
