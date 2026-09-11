import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/services/api_exception.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/auth_models.dart';
import '../../domain/vehicle_types.dart';

/// Form khai báo xe (Phase 1).
/// Vehicle lấy trực tiếp từ AuthController (single source of truth):
/// - chưa khai (driver mới) → form rỗng, sau khi lưu về /home
/// - đã có xe (vào từ /profile) → form prefill, sau khi lưu quay lại /profile
class VehicleFormScreen extends ConsumerStatefulWidget {
  const VehicleFormScreen({super.key});

  @override
  ConsumerState<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends ConsumerState<VehicleFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _plate;
  late final TextEditingController _capacity;
  late final TextEditingController _length;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _area;
  late String _vehicleType;
  bool _submitting = false;
  String? _errorMessage;

  /// Chốt tại lúc MỞ màn hình: onboarding (chưa có xe) → save xong về /home;
  /// sửa (đã có xe từ trước) → save xong pop về /profile.
  /// KHÔNG tính lại lúc lưu vì applyUser đã set vehicle → nhầm nhánh.
  late final bool _isEdit;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider).value;
    _isEdit = auth is AuthAuthenticated && auth.user.vehicle != null;
    final v = auth is AuthAuthenticated ? auth.user.vehicle : null;
    _vehicleType = v?.vehicleType ?? 'truck';
    _plate = TextEditingController(text: v?.licensePlate ?? '');
    _capacity = TextEditingController(text: v?.capacityKg.toString() ?? '');
    _length = TextEditingController(text: v?.lengthCm.toString() ?? '');
    _width = TextEditingController(text: v?.widthCm.toString() ?? '');
    _height = TextEditingController(text: v?.heightCm.toString() ?? '');
    _area = TextEditingController(text: v?.operatingArea ?? '');
  }

  @override
  void dispose() {
    _plate.dispose();
    _capacity.dispose();
    _length.dispose();
    _width.dispose();
    _height.dispose();
    _area.dispose();
    super.dispose();
  }

  int _intOf(String raw, {required String label, bool required = true}) {
    final n = int.tryParse(raw.trim());
    if (n == null || n < 0) {
      throw '$label không hợp lệ';
    }
    if (required && n == 0) {
      throw 'Vui lòng nhập ${label.toLowerCase()}';
    }
    return n;
  }

  Future<void> _save() async {
    if (_submitting) return;
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final int capacityKg;
    final int lengthCm;
    final int widthCm;
    final int heightCm;
    try {
      capacityKg = _intOf(_capacity.text, label: 'Tải trọng (kg)');
      lengthCm = _intOf(_length.text, label: 'Dài (cm)', required: false);
      widthCm = _intOf(_width.text, label: 'Rộng (cm)', required: false);
      heightCm = _intOf(_height.text, label: 'Cao (cm)', required: false);
    } on String catch (msg) {
      setState(() => _errorMessage = msg);
      return;
    }

    setState(() => _submitting = true);
    try {
      final vehicle = VehicleProfile(
        vehicleType: _vehicleType,
        licensePlate: _plate.text.trim().toUpperCase(),
        capacityKg: capacityKg,
        lengthCm: lengthCm,
        widthCm: widthCm,
        heightCm: heightCm,
        operatingArea: _area.text.trim(),
      );
      await ref.read(authRepositoryProvider).saveVehicle(vehicle);

      final current = ref.read(authControllerProvider).value;
      if (current is AuthAuthenticated) {
        ref
            .read(authControllerProvider.notifier)
            .applyUser(current.user.copyWith(vehicle: vehicle));
      }
      if (!mounted) return;
      if (_isEdit) {
        context.pop(); // từ /profile → quay lại hồ sơ
      } else {
        context.go('/home'); // từ onboarding → vào home
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _dec(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Sửa thông tin xe' : 'Thông tin xe')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Thông tin xe giúp hệ thống chỉ đề xuất mối hàng phù hợp tải trọng '
                  'và loại xe của bạn (plan §3.1).',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _vehicleType,
                  decoration: _dec('Loại xe', ''),
                  items: vehicleTypeLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _vehicleType = v ?? 'truck'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 12,
                  decoration: _dec('Biển số xe', 'VD: 29C-123.45'),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (!RegExp(r'^[A-Za-z0-9.\- ]{4,12}$').hasMatch(t)) {
                      return 'Biển số không hợp lệ (4-12 ký tự)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _capacity,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _dec('Tải trọng (kg)', 'VD: 5000'),
                  validator: (v) => (int.tryParse(v ?? '') ?? 0) > 0
                      ? null
                      : 'Vui lòng nhập tải trọng > 0',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _length,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _dec('Dài (cm)', '620'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _width,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _dec('Rộng (cm)', '220'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _height,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _dec('Cao (cm)', '220'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _area,
                  maxLength: 200,
                  decoration: _dec('Khu vực hoạt động', 'VD: Hà Nội – Hải Phòng'),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _save,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEdit ? 'Lưu thay đổi' : 'Hoàn tất'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}