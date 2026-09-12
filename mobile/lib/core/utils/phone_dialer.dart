import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Mở app điện thoại (dialer) với số của đối tác.
///
/// Tách riêng khỏi UI để **test được** URI sinh ra: một `tel:` sai định dạng sẽ
/// im lặng không làm gì trên máy thật (đúng loại lỗi khó thấy khi review).

/// Chuẩn hoá số người dùng/đối tác về URI `tel:` cho dialer.
/// Giữ lại chỉ chữ số và `+` (bỏ space/gạch/chấm/ngoặc mà API có thể trả).
Uri telUri(String rawPhone) {
  final cleaned = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
  return Uri(scheme: 'tel', path: cleaned);
}

/// Mở dialer với [phone]. Không bao giờ ném ra ngoài và không chặn UI:
/// máy không có app gọi điện / lỗi platform → SnackBar kèm số để user tự bấm.
Future<void> dialPhone(BuildContext context, String phone) async {
  final uri = telUri(phone);
  if (uri.path.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (await launchUrl(uri)) return;
  } catch (_) {
    // rơi xuống thông báo bên dưới
  }
  messenger.showSnackBar(
    SnackBar(content: Text('Không mở được ứng dụng gọi điện — số: $phone')),
  );
}
