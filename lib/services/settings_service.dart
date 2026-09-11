import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI 服务配置（双模式）：
///   builtin —— 开箱即用：构建时通过 --dart-define 注入内置服务，用户无需任何配置
///   custom  —— 用户自定义：兼容 OpenAI 接口格式，自行填写接口地址、模型名称、API Key
/// API Key 仅保存在本机 shared_preferences，不上传任何服务器。
class SettingsService {
  SettingsService._();

  static late SharedPreferences _prefs;

  // -------- 构建期注入的内置 AI 配置（对用户不可见） --------
  static const String builtinBaseUrl = String.fromEnvironment(
      'LLM_BASE_URL',
      defaultValue: 'https://apihub.agnes-ai.cn/v1');
  static const String builtinModel =
      String.fromEnvironment('LLM_MODEL', defaultValue: 'agnes-2.5-flash');
  static const String builtinApiKey =
      String.fromEnvironment('LLM_API_KEY', defaultValue: '');

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // 兼容旧版本：之前单独保存的 Key 迁移为自定义模式
    final legacy = _prefs.getString('llm_api_key');
    if (legacy != null && legacy.isNotEmpty) {
      await _prefs.setString('custom_api_key', legacy);
      await _prefs.setString('ai_mode', 'custom');
      await _prefs.remove('llm_api_key');
    }
  }

  // -------- 模式与自定义配置 --------

  static String get mode => _prefs.getString('ai_mode') ?? 'builtin';

  static set mode(String v) {
    _prefs.setString('ai_mode', v);
    _version.value++;
  }

  static String get customBaseUrl => _prefs.getString('custom_base_url') ?? '';

  static set customBaseUrl(String v) {
    _prefs.setString('custom_base_url', v);
    _version.value++;
  }

  static String get customModel => _prefs.getString('custom_model') ?? '';

  static set customModel(String v) {
    _prefs.setString('custom_model', v);
    _version.value++;
  }

  static String get customApiKey => _prefs.getString('custom_api_key') ?? '';

  static set customApiKey(String v) {
    _prefs.setString('custom_api_key', v);
    _version.value++;
  }

  // -------- 生效配置 --------

  static bool get useCustom => mode == 'custom';

  static String get baseUrl =>
      useCustom && customBaseUrl.isNotEmpty ? customBaseUrl : builtinBaseUrl;

  static String get model =>
      useCustom && customModel.isNotEmpty ? customModel : builtinModel;

  static String get apiKey =>
      useCustom ? customApiKey : builtinApiKey;

  static bool get isReady => apiKey.isNotEmpty;

  /// 配置变化信号（模式切换 / 自定义保存后通知各页面刷新状态）
  static final ValueNotifier<int> _version = ValueNotifier(0);
  static ValueListenable<int> get configListenable => _version;

  // -------- 外观（深色模式） --------

  static ThemeMode get themeMode => switch (_prefs.getString('theme_mode')) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static set themeMode(ThemeMode v) {
    _prefs.setString('theme_mode', v.name);
    _themeModeNotifier.value = v;
  }

  static final ValueNotifier<ThemeMode> _themeModeNotifier =
      ValueNotifier(themeMode);
  static ValueListenable<ThemeMode> get themeModeListenable =>
      _themeModeNotifier;
}
