import 'package:flutter/material.dart';

import '../greeting_check.dart';

class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({required this.checkGreeting, super.key});

  final GreetingCheck? checkGreeting;

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  bool _checking = false;
  String? _message;
  bool _failed = false;

  Future<void> _checkConnection() async {
    final check = widget.checkGreeting;
    if (check == null || _checking) return;
    setState(() {
      _checking = true;
      _message = null;
      _failed = false;
    });
    try {
      final greeting = await check('Balmatchum');
      if (!mounted) return;
      setState(() => _message = greeting.message);
    } on Exception {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Balmatchum',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const ValueKey('bootstrap_check_connection'),
                    onPressed: widget.checkGreeting == null || _checking
                        ? null
                        : _checkConnection,
                    child: Text(_checking ? 'Checking…' : 'Check connection'),
                  ),
                  const SizedBox(height: 16),
                  if (widget.checkGreeting == null)
                    const Text('Set SERVER_URL to enable connection checks.'),
                  if (_message != null)
                    Text(
                      _message!,
                      key: const ValueKey('bootstrap_connection_success'),
                      textAlign: TextAlign.center,
                    ),
                  if (_failed)
                    const Text(
                      'Connection failed. Check the server URL and try again.',
                      key: ValueKey('bootstrap_connection_error'),
                      textAlign: TextAlign.center,
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
