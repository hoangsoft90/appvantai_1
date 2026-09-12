import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/safe_nav.dart';
import '../../../../shared/services/api_exception.dart';
import '../../data/trip_repository.dart';
import '../../domain/trip_models.dart';

/// Form tạo chuyến (Phase 3 — "Tôi đang chạy").
/// plan2_final §5.1: user KHÔNG nhập lat/lng thủ công — chỉ search địa chỉ,
/// chọn kết quả geocode (backend Nominatim/mock + cache), preview tọa độ ẩn.
class TripFormScreen extends ConsumerStatefulWidget {
  const TripFormScreen({super.key});

  @override
  ConsumerState<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends ConsumerState<TripFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fromAddr = TextEditingController();
  final _toAddr = TextEditingController();
  GeocodeResult? _fromPoint;
  GeocodeResult? _toPoint;
  // plan3 Mục 4/5 — empty state gợi ý khai chiều về: selector ở ngay form.
  String _tripType = 'one_way';
  bool _searchingFrom = false;
  bool _searchingTo = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // plan4_final §4.2: text đổi sau khi đã geocode → tọa độ cũ hết hợp lệ
    // (không cho xảy ra case "địa chỉ A + tọa độ B") — phải tìm lại trước submit.
    _fromAddr.addListener(_invalidateFromPoint);
    _toAddr.addListener(_invalidateToPoint);
  }

  void _invalidateFromPoint() {
    if (_fromPoint != null) setState(() => _fromPoint = null);
  }

  void _invalidateToPoint() {
    if (_toPoint != null) setState(() => _toPoint = null);
  }

  @override
  void dispose() {
    _fromAddr.removeListener(_invalidateFromPoint);
    _toAddr.removeListener(_invalidateToPoint);
    _fromAddr.dispose();
    _toAddr.dispose();
    super.dispose();
  }

  Future<void> _searchAddress(bool isFrom) async {
    final query = (isFrom ? _fromAddr.text : _toAddr.text).trim();
    if (query.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nhập địa chỉ ít nhất 3 ký tự')),
      );
      return;
    }
    setState(() {
      if (isFrom) {
        _searchingFrom = true;
      } else {
        _searchingTo = true;
      }
    });
    try {
      final result = await ref.read(tripRepositoryProvider).geocode(query);
      if (!mounted) return;
      setState(() {
        if (isFrom) {
          _fromPoint = result;
        } else {
          _toPoint = result;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          if (isFrom) {
            _searchingFrom = false;
          } else {
            _searchingTo = false;
          }
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // plan2_final §5.1 + plan4_final §4.2: tọa độ phải khớp địa chỉ text
    // hiện tại — chưa chọn / đã bị vô hiệu do sửa text → chặn submit.
    if (_fromPoint == null || _toPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Vui lòng tìm và chọn điểm đi + điểm đến (địa chỉ vừa sửa cần tìm lại)')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final draft = TripDraft(
        fromLat: _fromPoint!.lat,
        fromLng: _fromPoint!.lng,
        fromAddress: _fromAddr.text.trim(),
        toLat: _toPoint!.lat,
        toLng: _toPoint!.lng,
        toAddress: _toAddr.text.trim(),
        tripType: _tripType,
      );
      final trip = await ref.read(tripRepositoryProvider).createTrip(draft);
      if (!mounted) return;
      // Quét radar ngay sau khi tạo chuyến (plan §4.1: 1 chạm bắt đầu).
      // pushReplacement: thay form bằng màn radar — back từ radar về /home,
      // không quay lại form đã submit (tránh tạo trùng chuyến).
      context.pushReplacement('/trips/${trip.id}/matches');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const SafeBackButton(fallback: '/home'),
        title: const Text('Tạo chuyến đi'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'one_way', label: Text('Đi 1 chiều')),
                ButtonSegment(value: 'return', label: Text('Có chiều về')),
              ],
              selected: {_tripType},
              onSelectionChanged: (s) => setState(() => _tripType = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _tripType == 'return'
                  ? 'Xe rỗng lúc đi — hệ thống ưu tiên tìm hàng cho chặng về.'
                  : 'Chỉ tìm mối hàng trên tuyến đi.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            Text('Điểm đi', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _addressField(
              controller: _fromAddr,
              label: 'Địa chỉ điểm đi (vd: Hà Nội)',
              searching: _searchingFrom,
              onSearch: () => _searchAddress(true),
            ),
            _pointPreview(_fromPoint, theme),
            const SizedBox(height: 24),
            Text('Điểm đến', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _addressField(
              controller: _toAddr,
              label: 'Địa chỉ điểm đến (vd: Hải Phòng)',
              searching: _searchingTo,
              onSearch: () => _searchAddress(false),
            ),
            _pointPreview(_toPoint, theme),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar),
              label: Text(_submitting ? 'Đang tạo...' : 'Tạo chuyến & quét radar'),
            ),
          ],
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
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
            // Hiện lỗi ngay khi user gõ và tự MẤT khi nhập đủ 3 ký tự.
            autovalidateMode: AutovalidateMode.onUserInteraction,
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

  /// Preview điểm đã chọn — KHÔNG hiện lat/lng thô cho user (§14 release UX).
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
              p.label.isEmpty ? 'Đã chọn điểm trên bản đồ' : p.label,
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
