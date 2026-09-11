import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// fix_p7_1.md #2 — dart-define đọc từ Gradle property `dart-defines` (flutter tool
// truyền qua -Pdart-defines=<comma-separated base64 của từng cặp KEY=VALUE>).
// Fallback: dart-define.properties bên android/ (KHÔNG commit — đã gitignore).
//
// ⚠️ BÀI HỌC (run GH Actions 34582723799): file này là Kotlin DSL (.kts) — CẤM cú
// pháp Groovy (`def`, map literal `[(k): v]`, `new X()`). Bản trước dùng `def` →
// ScriptCompilationException ngay khi cấu hình. Chỉ viết Kotlin chuẩn.
val dartDefinesRaw: Map<String, String> =
    (project.findProperty("dart-defines") as String? ?: "")
        .split(",")
        .filter { it.isNotBlank() }
        .mapNotNull { token ->
            val decoded = runCatching {
                String(Base64.getDecoder().decode(token), Charsets.UTF_8)
            }.getOrNull() ?: return@mapNotNull null
            val parts = decoded.split("=", limit = 2)
            if (parts.size == 2) parts[0] to parts[1] else null
        }
        .toMap()

var appEnvDefine = dartDefinesRaw["APP_ENV"] ?: ""
val propFile = rootProject.file("dart-define.properties")
if (appEnvDefine.isEmpty() && propFile.exists()) {
    val props = Properties()
    props.load(FileInputStream(propFile))
    appEnvDefine = props.getProperty("APP_ENV", "")
}

// Phase 7 §7.3 — release signing qua key.properties (KHÔNG commit file thật,
// đã nằm trong android/.gitignore). Template: mobile/android/key.properties.example.
// Không có file → fallback debug signing (flutter run --release vẫn chạy được).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "vn.appvantai.appvantai_mobile"
    // 2026-09: Google Play yêu cầu target API 36 từ 31/08/2026 — pin cứng 36 thay
    // vì theo flutter.compileSdk/targetSdkVersion (Flutter default có thể tụt hậu).
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "vn.appvantai.appvantai_mobile"
        minSdk = flutter.minSdkVersion
        // Play policy: targetSdkVersion >= 36 bắt buộc từ 31/08/2026.
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // fix_p7_1.md #4 — release build KHÔNG truyền APP_ENV=production → FAIL ngay
            // lúc build (không dựa vào operator nhớ dart-define). Dev local vượt qua bằng
            // cách chạy debug build; bản release test nội bộ dùng --dart-define=APP_ENV=staging.
            if (appEnvDefine != "production" && appEnvDefine != "staging") {
                throw GradleException(
                    "Release build phải truyền --dart-define=APP_ENV=production (hoặc staging cho bản test nội bộ). " +
                        "Hiện tại: '" + appEnvDefine + "'.",
                )
            }
            // Có key.properties → sign bằng keystore release; không → debug keys
            // (chỉ để test nội bộ — KHÔNG upload lên Play Store, phase 8 bắt buộc keystore thật).
            signingConfig = signingConfigs.getByName(
                if (hasReleaseKeystore) "release" else "debug",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
