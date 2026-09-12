import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/services/api_exception.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/domain/auth_models.dart';

/// Onboarding (Phase 1 — Identity): nhập tên + chọn vai trò.
/// Lưu xong → AuthController.applyUser → router tự chuyển:
///  - driver → /vehicle (bắt buộc khai xe)
///  - customer → /home
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _role = 'customer';
  bool _legalConsent = false;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_legalConsent) {
      setState(() => _errorMessage = 'Vui lòng tick xác nhận điều khoản để tiếp tục');
      return;
    }

    setState(() => _submitting = true);
    try {
      // Tài khoản quản trị (seed sẵn ở D1) KHÔNG gửi role trong onboarding —
      // PATCH /me chấp nhận đổi sang driver|customer nên sẽ tự giáng quyền admin.
      final current = ref.read(authControllerProvider).value;
      final isAdmin = current is AuthAuthenticated && current.user.isAdmin;
      var user = await ref.read(authRepositoryProvider).updateMe(
            name: _nameController.text.trim(),
            role: isAdmin ? null : _role,
          );
      // Legal disclaimer (§18): ghi nhận thời gian tick + IP (audit ở backend)
      if (!user.hasLegalConsent) {
        user = await ref.read(authRepositoryProvider).giveLegalConsent();
      }
      // Router sẽ redirect theo needsOnboarding/isDriver/hasVehicle
      ref.read(authControllerProvider.notifier).applyUser(user);
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
      appBar: AppBar(title: const Text('Hoàn tất hồ sơ')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Bạn tham gia với vai trò nào?',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.done,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Họ và tên',
                    prefixIcon: Icon(Icons.person_outline),
                    counterText: '',
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.length < 2) return 'Vui lòng nhập họ tên (tối thiểu 2 ký tự)';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'customer',
                      label: Text('Chủ hàng'),
                      icon: Icon(Icons.inventory_2_outlined),
                    ),
                    ButtonSegment(
                      value: 'driver',
                      label: Text('Tài xế'),
                      icon: Icon(Icons.local_shipping_outlined),
                    ),
                  ],
                  selected: {_role},
                  onSelectionChanged: (s) => setState(() => _role = s.first),
                ),
                const SizedBox(height: 8),
                Text(
                  _role == 'driver'
                      ? 'Bạn sẽ khai thông tin xe ở bước tiếp theo.'
                      : 'Bạn sẽ đăng hàng cần vận chuyển.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 20),
                // Legal disclaimer (§18) — bắt buộc tick, backend lưu audit kèm IP.
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _legalConsent,
                        onChanged: (v) => setState(() => _legalConsent = v ?? false),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => context.push('/legal/terms'),
                          child: Text.rich(
                            TextSpan(
                              text: 'Tôi xác nhận ứng dụng chỉ đóng vai trò trung gian kết nối thông tin. '
                                  'Mọi giao dịch, chất lượng hàng hóa, thanh toán và trách nhiệm pháp lý '
                                  'phát sinh do hai bên tự thỏa thuận và chịu trách nhiệm. '
                                  'Ứng dụng không tham gia vào quá trình vận chuyển. ',
                              children: [
                                TextSpan(
                                  text: 'Xem Điều khoản sử dụng.',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Tiếp tục'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}