---
name: gh-debug-apk
description: Build debug APK for THIS project on GitHub Actions (never build APK locally). Use when asked to "build apk", "build debug apk", "tải apk test", "thấy lỗi trên máy thật", "push code lên gh actions" for appvantai.
---

# Build debug APK qua GitHub Actions (appvantai)

## Quy tắc bất di bất dịch

1. **TUYỆT ĐỐI KHÔNG build APK local** (`flutter build apk`, `./gradlew assembleDebug`,
   `flutter build appbundle`) — user cấm vì tốn disk/network. Android SDK đã bị XÓA khỏi
   máy local (2026-09-11): `/usr/lib/android-sdk`, `~/.gradle`, `~/Android/Sdk`, `~/.android`.
   KHÔNG cài lại local SDK. `flutter pub get / analyze / test` vẫn chạy local bình thường.
2. Build APK **chỉ trên GitHub Actions** bằng **gradle trực tiếp** (`./gradlew assembleDebug`,
   KHÔNG EAS, KHÔNG cần token EAS, KHÔNG keystore — debug signing).
3. **Không đợi build xong** khi user chỉ yêu cầu đẩy code lên CI — push xong là báo link run.

## Thông số cố định

- Repo: `https://github.com/hoangsoft90/appvantai_1` (branch chính: `master`)
- Workflow: `.github/workflows/android-debug-apk.yml` — trigger tự động trên push vào
  `master`/`main` khi `mobile/**` hoặc workflow đổi; hoặc chạy tay bằng `workflow_dispatch`.
- Toolchain pinned trong repo (KHÔNG đổi lung tung):
  - Flutter **3.47.2** stable (subosito/flutter-action@v2)
  - JDK **17** temurin (khớp sourceCompatibility 17 trong build.gradle.kts)
  - AGP **9.1.0** + Kotlin **2.4.0** (`mobile/android/settings.gradle.kts`), Gradle wrapper **9.3.1**
  - compileSdk/targetSdk **36** (pin cứng — Play yêu cầu API 36 từ 31/08/2026)
- Artifact: tên `appvantai-debug-apk`, file `appvantai-debug.apk`, giữ 14 ngày.
  Tải tại: repo → **Actions** → run mới nhất → **Artifacts**.

## Token GitHub (QUAN TRỌNG)

- **KHÔNG lưu token vào repo/skill này** (bất kỳ file nào được commit). Token PAT
  KHÔNG được commit — GitHub tự động thu hồi token lộ trong code.
- Nguồn token khi cần push (theo thứ tự):
  1. Đọc file local **`.secrets/gh_token`** (gitignored, ở project root) nếu tồn tại.
  2. Nếu file chưa có hoặc token bị 401 → hỏi user xin token mới (scope `repo`) **một lần**,
     rồi **LƯU NGAY vào `.secrets/gh_token`** (`mkdir -p .secrets && printf '%s' '<TOKEN>' > .secrets/gh_token`)
     để các phiên sau không phải hỏi lại.
- Kiểm tra token trước khi push: `curl -s -o /dev/null -w '%{http_code}' -H "Authorization: token $(cat .secrets/gh_token)" https://api.github.com/user` → phải ra `200`.
- Nếu 401 → báo user cấp token mới (github.com/settings/tokens), đừng thử lại vô ích.
- Lệnh push luôn dạng `https://hoangsoft90:<TOKEN>@github.com/...` (user:token).

## Quy trình build APK

```bash
# 0) (một lần) xác thực token: curl -s -H "Authorization: token <TOKEN>" https://api.github.com/user → 200
# 1) đảm bảo mọi thay đổi đã commit; kiểm tra không commit file cấm:
git status --porcelain
git diff --cached --name-only | grep -E "^\.plan/|\.dev\.vars|local\.properties|key\.properties$|\.jks$|\.keystore$"   # phải RỖNG
# 2) push branch chính (điền TOKEN do user cung cấp):
git push -u https://hoangsoft90:<TOKEN>@github.com/hoangsoft90/appvantai_1.git master
# 3) báo link run (KHÔNG đợi): https://github.com/hoangsoft90/appvantai_1/actions
# 4) lấy link artifact sau khi build xong (nếu user hỏi):
curl -s -H "Authorization: token <TOKEN>" \
  "https://api.github.com/repos/hoangsoft90/appvantai_1/actions/runs?per_page=1" | jq '.workflow_runs[0].id, .workflow_runs[0].html_url'
```

## Bài học build (đã xử lý sẵn trong repo — đừng phá)

- **`mobile/android/app/build.gradle.kts` là Kotlin DSL — CẤM cú pháp Groovy** (`def`,
  map literal `[(k): v]`, `new X()`, `it.decodeBase64()`). Bản trước trộn Groovy vào .kts
  → `ScriptCompilationException` 11 errors ở bước cấu hình (run 34582723799). Đã viết
  lại bằng Kotlin thuần (`val`, `Base64.getDecoder()`, `GradleException`). Lỗi kiểu này
  không bắt được bằng flutter analyze — chỉ lộ khi gradle compile script (CI).
- `plugins {}` của app PHẢI có `id("org.jetbrains.kotlin.android")` vì gradle.properties
  đặt `android.builtInKotlin=false` (template Flutter — external KGP 2.4.0 trong
  settings.gradle.kts). Thiếu → `kotlin {}` block chết.
- **CI PHẢI chạy `dart run build_runner build --delete-conflicting-outputs` sau `pub get`**:
  `*.g.dart` (riverpod providers) bị gitignore (`*.g.dart` trong root .gitignore) —
  checkout sạch không có → `kernel_snapshot` fail `Type '_$X' not found` hàng loạt
  (run 34584116987). `flutter test` local vẫn pass vì .g.dart tồn tại trên đĩa local —
  đừng nhầm là code OK trên CI.
- **Guard fail-fast release PHẢI hook `gradle.taskGraph.whenReady`, KHÔNG throw trong
  `buildTypes.release {}`** — block đó được evaluate eagerly lúc cấu hình cho MỌI build
  (kể cả assembleDebug) → guard cũ từ fix_p7_1 từng kill cả debug build (run
  34583778615). `whenReady` chỉ chặn khi có task chứa "Release" trong graph.

- **Push lần đầu lên repo MỚI + workflow có `paths:` filter = KHÔNG trigger** (workflow
  chưa kịp đăng ký và/hoặc push không chạm file khớp filter). Fix đã kiểm chứng
  (2026-09-11): commit **chạm chính file workflow** rồi push → run khởi động ngay.
  Push rỗng (--allow-empty) thì KHÔNG ăn — paths filter bỏ qua vì 0 file đổi.
- Token dạng URL phải `https://USER:TOKEN@github.com/...` (chỉ token không đủ —
  git sẽ hỏi password và chết trên shell non-interactive).
- Kiểm tra run đã lên chưa: GET `/actions/runs` — nếu `total_count=0` sau push có
  chạm file workflow → kiểm tra `enabled` qua `/actions/permissions` và private/public.

- `mobile/android/gradle/wrapper/gradle-wrapper.jar` + `gradlew` bị Flutter template
  gitignore nhưng **CI bắt buộc phải có** → đã `git add -f`. Nếu thiếu, CI báo
  `Error: Could not find or load main class org.gradle.wrapper.GradleWrapperMain`.
- **AGP tạo SẴN signing config `debug`** — muốn trỏ keystore riêng phải
  `getByName("debug") { ... }` để OVERRIDE, KHÔNG được `create("debug")`
  (trùng tên → `InvalidUserDataException: Cannot add a SigningConfig with name
  'debug'` — run 34610101578).
- dart-defines cho gradle: **comma-separated base64 của từng cặp KEY=VALUE**, truyền qua
  `-Pdart-defines=...` (đúng như Flutter tool làm). Workflow hiện nhúng
  `APP_ENV=dev` + `API_BASE_URL=https://appvantai-api.testhoangweb.workers.dev`
  (backend production — APK cài máy thật test được ngay, không cần adb reverse)
  + `SENTRY_DSN` (debug app vẫn init Sentry để test error reporting).
  Muốn test worker local: thay cặp API_BASE_URL bằng base64 của
  `API_BASE_URL=http://localhost:8787` (python3: `import base64;
  base64.b64encode(b'API_BASE_URL=http://localhost:8787').decode()`).
- **Firebase Phone Auth đã bật trên APK CI** (2026-09-11): workflow tự sinh
  dart-defines `FIREBASE_*` + `USE_FIREBASE_AUTH=true` từ
  `mobile/android/app/google-services.json` (commit trong repo). Cùng cặp với:
  - `mobile/android/app/debug.keystore` commit cố ý (negation trong
    `mobile/android/.gitignore`) — SHA cố định đăng ký trên Firebase console;
    đổi keystore = SMS hỏng ngay
  - Mobile gửi SMS dạng E.164 (`FirebaseAuthStrategy.toE164`: 0xxx → +84xxx);
    Worker chuẩn hoá ngược +84xxx → 0xxx để khớp identity/seed
- Release build thiếu `--dart-define=APP_ENV=production|staging` → fail-fast ở Gradle
  (cố ý — fix_p7_1). **Debug build không bị chặn.**
- `worker/.wrangler/` đã thêm vào root `.gitignore` — đừng commit local D1/KV state.
- Workflow có Gradle cache (`gradle/actions/setup-gradle@v4`) — cold build ~10-15 phút,
  warm ~5-8 phút. Báo user tải APK ở tab Artifacts.

## Sau khi build xong (trên máy thật)

- Debug APK mặc định trỏ **API production** `https://appvantai-api.testhoangweb.workers.dev`
  (Cloudflare Workers, D1 có seed pilot corridor HN→HP — đơn `notes='pilot'`).
- Muốn test worker local: sửa dart-define `API_BASE_URL` trong workflow về
  `http://localhost:8787` + `adb reverse tcp:8787 tcp:8787`.
- Manifest đã bật `usesCleartextTraffic=true` → HTTP mọi domain chạy được trên máy thật.
