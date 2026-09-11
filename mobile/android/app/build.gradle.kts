import java.util.Properties
import java.io.FileInputStream

// fix_p7_1.md #2 — dart-define đọc từ Gradle property `dart-defines` (flutter tool
// truyền qua -Pdart-defines=<comma-separated base64 của từng cặp KEY=VALUE>).
// Fallback: dart-define.properties bên android/ (KHÔNG commit — đã gitignore).
def dartDefinesRaw = (project.findProperty("dart-defines") as String? ?: "")
    .split(",").findAll { it.trim() }
    .collectEntries {
        def kv = new String(it.decodeBase64(), "UTF-8").split("=", 2)
        kv.size() == 2 ? [(kv[0]): kv[1]] : [:]
    }
def appEnvDefine = dartDefinesRaw.get("APP_ENV", "")
def propFile = rootProject.file("dart-define.properties")
if (appEnvDefine.isEmpty() && propFile.exists()) {
    def p = new Properties()
    p.load(new FileInputStream(propFile))
    appEnvDefine = p.getProperty("APP_ENV", "")
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "vn.appvantai.appvantai_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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
                throw new GradleException(
                    "Release build phải truyền --dart-define=APP_ENV=production (hoặc staging cho bản test nội bộ). " +
                    "Hiện tại: '" + appEnvDefine + "'."
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
