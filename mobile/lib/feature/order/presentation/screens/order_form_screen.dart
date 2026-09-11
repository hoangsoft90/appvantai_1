import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../shared/services/api_exception.dart';
import '../../../identity/domain/vehicle_types.dart';
import '../../../trip/data/trip_repository.dart';
import '../../application/order_list_controller.dart';
import '../../data/order_repository.dart';
import '../../domain/order_models.dart';

/// Form tạo đơn hàng (plan §4.3 — form ngắn, không phải ERP).
/// plan3 Mục 5: KHÔNG bắt nhập lat/lng thủ công — search địa chỉ qua geocode
/// (backend /maps/geocode + cache), preview địa chỉ đọc được, tọa độ ẩn.
class OrderFormScreen extends ConsumerStatefulWidget {
  const OrderFormScreen({super.key});

  @override
  ConsumerState<OrderFormScreen> createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends ConsumerState<OrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickupAddress = TextEditingController();
  final _deliveryAddress = TextEditingController();
  final _weight = TextEditingController();
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _price = TextEditingController();
  final _notes = TextEditingController();

  GeocodeResult? _pickupPoint;
  GeocodeResult? _deliveryPoint;
  bool _searchingPickup = false;
  bool _searchingDelivery = false;

  String _cargoType = 'general';
  String _vehicleRequirement = 'any';
  late DateTime _pickupFrom;
  late DateTime _pickupTo;
  bool _legalConsent = false;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pickupFrom = DateTime.now().add(const Duration(hours: 1));
    _pickupTo = DateTime.now().add(const Duration(hours: 8));
    // plan4_final §4.2: text đổi sau khi đã geocode → tọa độ cũ hết hợp lệ
    // (không cho xảy ra case "địa chỉ A + tọa độ B") — phải tìm lại trước submit.
    _pickupAddress.addListener(_invalidatePickupPoint);
    _deliveryAddress.addListener(_invalidateDeliveryPoint);
  }

  void _invalidatePickupPoint() {
    if (_pickupPoint != null) setState(() => _pickupPoint = null);
  }

  void _invalidateDeliveryPoint() {
    if (_deliveryPoint != null) setState(() => _deliveryPoint = null);
  }

  @override
  void dispose() {
    _pickupAddress.removeListener(_invalidatePickupPoint);
    _deliveryAddress.removeListener(_invalidateDeliveryPoint);
    for (final c in [
      _pickupAddress, _deliveryAddress,
      _weight, _length, _width, _height, _price, _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _searchAddress(bool isPickup) async {
    final query = (isPickup ? _pickupAddress : _deliveryAddress).text.trim();
    if (query.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập địa chỉ ít nhất 3 ký tự')),
      );
      return;
    }
    setState(() {
      if (isPickup) {
        _searchingPickup = true;
      } else {
        _searchingDelivery = true;
      }
    });
    try {
      final result = await ref.read(tripRepositoryProvider).geocode(query);
      if (!mounted) return;
      setState(() {
        if (isPickup) {
          _pickupPoint = result;
        } else {
          _deliveryPoint = result;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          if (isPickup) {
            _searchingPickup = false;
          } else {
            _searchingDelivery = false;
          }
        });
      }
    }
  }

  Future<void> _pickTime(bool isFrom) async {
    final initial = isFrom ? _pickupFrom : _pickupTo;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isFrom) {
        _pickupFrom = dt;
        if (_pickupTo.isBefore(_pickupFrom)) _pickupTo = _pickupFrom.add(const Duration(hours: 4));
      } else {
        _pickupTo = dt;
      }
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // plan3 Mục 5 + plan4_final §4.2: tọa độ đến từ geocode và phải khớp
    // địa chỉ text hiện tại — chưa chọn / đã bị vô hiệu do sửa text → chặn.
    if (_pickupPoint == null || _deliveryPoint == null) {
      setState(() => _errorMessage =
          'Vui lòng tìm và chọn điểm lấy + điểm giao (địa chỉ vừa sửa cần tìm lại)');
      return;
    }
    final weightKg = int.tryParse(_weight.text.trim());
    if (weightKg == null || weightKg <= 0) {
      setState(() => _errorMessage = 'Khối lượng phải là số nguyên > 0');
      return;
    }
    final price = int.tryParse(_price.text.trim());
    if (price == null || price < 0) {
      setState(() => _errorMessage = 'Giá không hợp lệ');
      return;
    }

    final draft = OrderDraft(
      pickupLat: _pickupPoint!.lat,
      pickupLng: _pickupPoint!.lng,
      pickupAddress: _pickupAddress.text.trim(),
      deliveryLat: _deliveryPoint!.lat,
      deliveryLng: _deliveryPoint!.lng,
      deliveryAddress: _deliveryAddress.text.trim(),
      cargoType: _cargoType,
      weightKg: weightKg,
      lengthCm: int.tryParse(_length.text.trim()) ?? 0,
      widthCm: int.tryParse(_width.text.trim()) ?? 0,
      heightCm: int.tryParse(_height.text.trim()) ?? 0,
      vehicleRequirement: _vehicleRequirement,
      pickupFrom: _pickupFrom,
      pickupTo: _pickupTo,
      price: price,
      notes: _notes.text.trim(),
    );

    if (!_legalConsent) {
      setState(() => _errorMessage = 'Vui lòng tick xác nhận điều khoản để đăng hàng');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(orderRepositoryProvider).createOrder(draft);
      ref.invalidate(orderListControllerProvider);
      if (!mounted) return;
      context.go('/orders');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _dec(String label, [String? hint]) => InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Tạo đơn hàng')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Điểm lấy hàng',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _addressField(
                  controller: _pickupAddress,
                  label: 'Địa chỉ điểm lấy (vd: KCN Thăng Long, Hà Nội)',
                  searching: _searchingPickup,
                  onSearch: () => _searchAddress(true),
                ),
                _pointPreview(_pickupPoint, theme),
                const SizedBox(height: 20),
                Text('Điểm giao hàng', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _addressField(
                  controller: _deliveryAddress,
                  label: 'Địa chỉ điểm giao (vd: Cảng Hải Phòng)',
                  searching: _searchingDelivery,
                  onSearch: () => _searchAddress(false),
                ),
                _pointPreview(_deliveryPoint, theme),
                const SizedBox(height: 20),
                Text('Hàng hóa', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _cargoType,
                  decoration: _dec('Loại hàng'),
                  items: cargoTypeLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _cargoType = v ?? 'general'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _weight,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _dec('Khối lượng (kg)', 'VD: 800'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _length,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _dec('Dài (cm)', '0'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _width,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _dec('Rộng (cm)', '0'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _height,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _dec('Cao (cm)', '0'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _vehicleRequirement,
                  decoration: _dec('Yêu cầu xe'),
                  items: [
                    const DropdownMenuItem(value: 'any', child: Text('Xe bất kỳ')),
                    ...vehicleTypeLabels.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                  ],
                  onChanged: (v) => setState(() => _vehicleRequirement = v ?? 'any'),
                ),
                const SizedBox(height: 20),
                Text('Thời gian & giá', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(true),
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text('Từ: ${formatDateTime(_pickupFrom)}'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(false),
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text('Đến: ${formatDateTime(_pickupTo)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _dec('Giá (đ)', 'VD: 2500000'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  maxLength: 500,
                  decoration: _dec('Ghi chú', 'VD: giao trong ngày'),
                ),
                const SizedBox(height: 16),
                // Legal disclaimer (§18) — bắt buộc tick trước khi đăng hàng
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
                        child: Text(
                          'Tôi xác nhận ứng dụng chỉ là trung gian kết nối. Mọi giao dịch, '
                          'chất lượng hàng hóa, thanh toán và trách nhiệm pháp lý do hai bên '
                          'tự thỏa thuận và chịu trách nhiệm.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Đăng đơn hàng'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _addressField({
    required TextEditingController controller,
    required String label,
    required bool searching,
    required VoidCallback onSearch,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            textInputAction: TextInputAction.search,
            decoration: _dec(label, 'Nhập rồi bấm tìm'),
            validator: (v) {
              if ((v ?? '').trim().length < 3) return 'Nhập địa chỉ ít nhất 3 ký tự';
              return null;
            },
            onFieldSubmitted: (_) => onSearch(),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IconButton.filled(
            onPressed: searching ? null : onSearch,
            icon: searching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            tooltip: 'Tìm địa chỉ',
          ),
        ),
      ],
    );
  }

  /// Preview điểm đã chọn — hiện địa chỉ đọc được, KHÔNG hiện tọa độ thô
  /// (plan3 Mục 5 + plan2_final §14).
  Widget _pointPreview(GeocodeResult? p, ThemeData theme) {
    if (p == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Icon(Icons.location_on, size: 16),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              p.label.isEmpty ? 'Đã chọn điểm' : p.label,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
