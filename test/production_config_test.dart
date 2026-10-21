import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ledger/services/baidu_asr_service.dart';
import 'package:smart_ledger/services/settings_service.dart';

import 'test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const verifyProduction = bool.fromEnvironment('VERIFY_PRODUCTION');
  late Directory directory;

  setUp(() async {
    directory = await setUpDatabase();
  });
  tearDown(() async => tearDownDatabase(directory));

  test(
    '生产配置使新安装的内置 AI 和语音服务可用',
    () {
      expect(SettingsService.mode, 'builtin');
      expect(SettingsService.relayUrl, 'https://8.163.98.62/v1');
      expect(SettingsService.baseUrl, 'https://8.163.98.62/v1');
      expect(SettingsService.model, 'agnes-2.5-flash');
      expect(SettingsService.isReady, isTrue);
      expect(SettingsService.builtinApiKey, isEmpty);
      expect(SettingsService.apiKey, isEmpty);

      expect(BaiduAsrService.relayUrl, 'https://8.163.98.62');
      expect(BaiduAsrService.useRelay, isTrue);
      expect(BaiduAsrService.isConfigured, isTrue);
      expect(BaiduAsrService.apiKey, isEmpty);
      expect(BaiduAsrService.secretKey, isEmpty);
    },
    skip: verifyProduction
        ? false
        : '需同时传入 --dart-define=VERIFY_PRODUCTION=true 和 '
              '--dart-define-from-file=config/production.json',
  );
}
