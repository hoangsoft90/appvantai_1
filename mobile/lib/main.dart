import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app/app.dart';
import 'core/config/app_auth_mode.dart';
import 'core/config/app_config.dart';

/// DSN Sentry truyền qua dart-define:
///   --dart-define=SENTRY_DSN=https://xxx@oxxx.ingest.us.sentry.io/xxxx
/// Không truyền → dsn rỗng → Sentry tự vô hiệu hoá (dev không gửi sự kiện).
const String _kSentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // plan2_final §7.3: release build fail-fast nếu dev config lọt vào production.
  AppConfig.assertReleaseConfig();
  // phase7 §7.1: fail-fast nếu bật Firebase mà thiếu config dart-define.
  AppAuthMode.assertFirebaseConfigIfEnabled();

  await SentryFlutter.init(
    (options) {
      options.dsn = _kSentryDsn;
      options.environment = AppConfig.appEnv;
      options.release = 'appvantai_mobile@${const String.fromEnvironment(
        'APP_VERSION',
        defaultValue: 'dev',
      )}';
    },
    // Wrap runApp — lỗi Flutter framework + zone chưa bắt đều về Sentry.
    appRunner: () async {
      if (AppAuthMode.isFirebase) {
        // Options từ dart-define (không cần firebase_options.dart sinh code).
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: AppAuthMode.firebaseApiKey,
            appId: AppAuthMode.firebaseAppId,
            messagingSenderId: AppAuthMode.firebaseSenderId,
            projectId: AppAuthMode.firebaseProjectId,
          ),
        );
      }
      runApp(const ProviderScope(child: App()));
    },
  );
}
