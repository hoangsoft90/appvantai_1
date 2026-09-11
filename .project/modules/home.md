# modules/home.md — App shell + Home role-aware

## Làm gì

Bootstrap gate (splash đọc token + /me), điều hướng theo vai trò, hub truy cập
các tính năng.

## Luồng

`SplashScreen` → bootstrap: có token → `GET /me` → landing theo role/onboarding
(driver thiếu xe → `/vehicle`); không token → `/login`. Home driver: nút tạo
chuyến + danh sách chuyến + vào radar; Home customer: nút tạo đơn + danh sách đơn.

## Files

`feature/home/presentation/screens/home_screen.dart` ·
`shared/widgets/splash_screen.dart` · `app/app.dart` + `app/router/app_router.dart`.

## Lỗi đáng nhớ

- go_router 16: `GoRouter.refresh()` xóa push stack → chỉ refresh khi landing đổi.
- Controller phải watch-in-build (nếu không → "Ref disposed").

## Spec

`openspec/specs/app-shell-navigation/spec.md`
