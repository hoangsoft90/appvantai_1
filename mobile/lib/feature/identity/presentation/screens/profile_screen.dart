import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../shared/services/api_exception.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/auth_models.dart';
import '../../domain/vehicle_types.dart';

/// Hồ sơ cá nhân: thông tin user + xe (nếu tài xế).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final auth = ref.read(authControllerProvider).value;
    if (auth is! AuthAuthenticated) return;
    final controller = TextEditingController(text: auth.user.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa tên'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Họ và tên'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || !context.mounted) return;
    try {
      final user = await ref.read(authRepositoryProvider).updateMe(name: newName);
      ref.read(authControllerProvider.notifier).applyUser(user);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider).value;
    if (auth is! AuthAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = auth.user;
    final vehicle = user.vehicle;

    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ của tôi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(user.name.isEmpty ? 'Chưa có tên' : user.name),
              subtitle: Text(user.phone),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Sửa tên',
                onPressed: () => _editName(context, ref),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(
                user.isDriver ? Icons.local_shipping : Icons.inventory_2_outlined,
              ),
              title: Text(user.isDriver ? 'Tài xế' : 'Chủ hàng'),
            ),
          ),
          // Phase 8 §8.3 — version app + legal docs xem được mọi lúc từ Hồ sơ.
          const _VersionTile(),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Điều khoản sử dụng'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/legal/terms'),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Chính sách riêng tư'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/legal/privacy'),
                ),
              ],
            ),
          ),
          if (user.isDriver) ...[
            const SizedBox(height: 16),
            Text('Thông tin xe', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: vehicle == null || vehicle.isEmpty
                    ? const Text('Chưa khai báo xe')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _row('Loại xe', vehicleTypeLabel(vehicle.vehicleType)),
                          _row('Biển số', vehicle.licensePlate),
                          _row('Tải trọng', '${vehicle.capacityKg} kg'),
                          _row('Kích thước',
                              '${vehicle.lengthCm} × ${vehicle.widthCm} × ${vehicle.heightCm} cm'),
                          _row('Khu vực', vehicle.operatingArea.isEmpty ? '—' : vehicle.operatingArea),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.push('/vehicle'),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Cập nhật thông tin xe'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(label, style: TextStyle(color: Colors.grey.shade600))),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

/// Phase 8 §8.3 — hiển thị version từ pubspec (1.0.0+1) trong Hồ sơ.
/// Stateful để fetch PackageInfo đúng 1 lần; test/ môi trường thiếu plugin → '—'.
class _VersionTile extends StatefulWidget {
  const _VersionTile();

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  String _version = '…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {
      if (mounted) setState(() => _version = '—');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('Phiên bản'),
        trailing: Text(_version),
      ),
    );
  }
}