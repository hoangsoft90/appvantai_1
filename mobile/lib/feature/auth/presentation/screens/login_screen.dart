import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/services/api_exception.dart';
import '../../../../shared/services/logger.dart';
import '../../application/auth_controller.dart';

/// Màn hình đăng nhập bằng số điện thoại.
/// Dev: OTP qua /auth/request-otp (backend trả mã khi APP_ENV=dev).
/// Production (phase7 §7.1): Firebase SMS — không có dev_otp.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (_submitting) return;
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final phone = PhoneValidator.normalize(_phoneController.text)!;
    setState(() => _submitting = true);
    try {
      final devOtp = await ref.read(authControllerProvider.notifier).startLogin(phone);
      if (!mounted) return;
      if (devOtp.isNotEmpty) {
        AppLogger.info('Dev OTP cho $phone: $devOtp');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mã OTP (dev): $devOtp')),
        );
      }
      context.push('/otp', extra: phone);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.local_shipping, size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    AppConfig.appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Radar tìm mối hàng tiện đường',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    maxLength: 15,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại',
                      hintText: 'VD: 0912345678',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    validator: PhoneValidator.validate,
                    onFieldSubmitted: (_) => _sendOtp(),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _submitting ? null : _sendOtp,
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Gửi mã OTP'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Ứng dụng chỉ đóng vai trò trung gian kết nối thông tin. Mọi giao dịch '
                    'và trách nhiệm pháp lý do hai bên tự thỏa thuận.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 4),
                  // Phase 7 §7.5 — đọc được điều khoản NGAY ở màn login.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => context.push('/legal/terms'),
                        child: const Text('Điều khoản sử dụng'),
                      ),
                      TextButton(
                        onPressed: () => context.push('/legal/privacy'),
                        child: const Text('Chính sách riêng tư'),
                      ),
                    ],
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