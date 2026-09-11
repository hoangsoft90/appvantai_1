import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/services/api_exception.dart';
import '../../../../shared/services/logger.dart';
import '../../application/auth_controller.dart';

/// Nhập mã OTP 6 số gửi tới số điện thoại (OTP dev hoặc mã SMS Firebase).
/// Verify thành công → AuthController cập nhật state → router đưa về /home.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone});

  final String phone;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _otpController = TextEditingController();
  bool _submitting = false;
  bool _resending = false;
  String? _errorMessage;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_submitting) return;
    final code = _otpController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _errorMessage = 'Vui lòng nhập đủ 6 chữ số');
      return;
    }
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).verifyOtp(widget.phone, code);
      if (!mounted) return;
      // Xác thực xong → về /home (context.go thay thế toàn bộ stack)
      context.go('/home');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resend() async {
    if (_resending) return;
    setState(() {
      _resending = true;
      _errorMessage = null;
    });
    try {
      final devOtp = await ref.read(authControllerProvider.notifier).startLogin(widget.phone);
      if (!mounted) return;
      if (devOtp.isNotEmpty) {
        AppLogger.info('Dev OTP (resend) cho ${widget.phone}: $devOtp');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mã OTP (dev): $devOtp')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi lại mã OTP')),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Xác thực OTP')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Nhập mã OTP 6 số đã gửi tới\n${widget.phone}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
                decoration: const InputDecoration(
                  hintText: '••••••',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onSubmitted: (_) => _verify(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _verify,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Xác nhận'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _resending ? null : _resend,
                child: _resending ? const Text('Đang gửi lại...') : const Text('Gửi lại mã'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}