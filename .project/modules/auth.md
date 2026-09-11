# modules/auth.md — Đăng nhập OTP + phiên

## Làm gì

Đăng nhập bằng SĐT + OTP (dev mode: mã hiện SnackBar, không cần SMS). JWT 30 ngày.
Onboarding chọn vai trò (customer/driver) sau login đầu tiên.

## API endpoints

| Endpoint | Dùng |
|---|---|
| `POST /auth/request-otp` | `{phone}` → `{ok, dev_otp?}` (dev_otp chỉ khi APP_ENV=dev && ALLOW_DEV_OTP=true) |
| `POST /auth/verify-otp` | `{phone, otp}` → `{token, user}` |
| `POST /auth/logout` | parity (client tự xóa token) |
| `GET /me` | bootstrap: user + driver_profile + legal_consent_at |
| `PATCH /me` | name/role (role đổi khi còn đơn active → 409 `ROLE_LOCKED`) |
| `POST /me/legal-consent` | tick disclaimer (bắt buộc trước tạo đơn/nhận đơn) |

## Local storage

`TokenStorage` (shared_preferences, interface để swap secure storage): lưu JWT.
Bootstrap đọc token → gọi /me → quyết định landing.

## Files

`feature/auth/{data/auth_repository.dart,domain/auth_models.dart,
presentation/screens/login_screen.dart}` · `shared/services/token_storage.dart` ·
router redirect `app/app.dart` (`_landing()`).

## Lỗi đáng nhớ

- OTP sai/hết hạn → 400 `INVALID_OTP`; request 6 lần/15 phút → 429 (retry chỉ
  re-verify, không re-request).
- User bị ban với token còn hạn → 401 `USER_NOT_FOUND` (role/status đọc DB mỗi request).

## Spec

`openspec/specs/auth-otp/spec.md` · `user-identity-vehicle/spec.md`
