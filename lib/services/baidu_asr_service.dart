import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_service.dart';

/// 语音识别服务（双模式）
///  - 中转模式（推荐）：ASR_RELAY_URL 指向自建中转服务，Key 保存在服务端，APK 不含任何 Key
///  - 直连模式：构建时注入 BAIDU_API_KEY / BAIDU_SECRET_KEY，App 直接调百度
class BaiduAsrService {
  BaiduAsrService._();

  /// 中转服务地址（如 https://xxx.domcloud.co），非空时走中转
  static const String relayUrl = String.fromEnvironment(
    'ASR_RELAY_URL',
    defaultValue: '',
  );

  static const String apiKey = String.fromEnvironment(
    'BAIDU_API_KEY',
    defaultValue: '',
  );
  static const String secretKey = String.fromEnvironment(
    'BAIDU_SECRET_KEY',
    defaultValue: '',
  );

  static bool get useRelay => relayUrl.isNotEmpty;

  static bool get isConfigured =>
      useRelay || (apiKey.isNotEmpty && secretKey.isNotEmpty);

  /// 设备标识（中转服务用于限流）
  static Future<String> _cuid() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('baidu_cuid');
    if (existing != null && existing.isNotEmpty) return existing;
    final cuid = 'yiyuji_${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString('baidu_cuid', cuid);
    return cuid;
  }

  /// 通过中转服务识别（服务端持有百度 Key）
  static Future<String> _recognizeViaRelay(List<int> audio) async {
    final base = relayUrl.replaceFirst(RegExp(r'/+$'), '');
    if (!SettingsService.validServiceUrl(base)) {
      throw const AsrException('语音接口必须使用有效的 HTTPS 地址');
    }
    final cuid = await _cuid();
    final resp = await http
        .post(
          Uri.parse('$base/asr'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'speech': base64Encode(audio),
            'len': audio.length,
            'cuid': cuid,
          }),
        )
        .timeout(const Duration(seconds: 40));
    return parseResponse(resp);
  }

  /// 获取 access_token（有效期约 30 天，缓存到本地）
  static Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('baidu_asr_token');
    final fetchedAt = prefs.getInt('baidu_asr_token_at') ?? 0;
    final ageSec = DateTime.now().millisecondsSinceEpoch ~/ 1000 - fetchedAt;
    if (cached != null &&
        cached.isNotEmpty &&
        ageSec >= 0 &&
        ageSec < 29 * 86400) {
      return cached;
    }
    final uri = Uri.https('aip.baidubce.com', '/oauth/2.0/token', {
      'grant_type': 'client_credentials',
      'client_id': apiKey,
      'client_secret': secretKey,
    });
    final resp = jsonDecode(
      utf8.decode(
        await http.readBytes(uri).timeout(const Duration(seconds: 20)),
      ),
    );
    final token = resp['access_token'];
    if (token is! String || token.isEmpty) {
      throw AsrException('获取百度语音凭证失败，请检查 API Key 配置');
    }
    await prefs.setString('baidu_asr_token', token);
    await prefs.setInt(
      'baidu_asr_token_at',
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    return token;
  }

  /// 识别一段 PCM 录音，返回文字（失败抛 AsrException）
  static Future<String> recognizePcmFile(String path) async {
    final audio = await File(path).readAsBytes();
    if (audio.isEmpty) throw AsrException('录音为空，请重试');
    if (audio.length > 16000 * 2 * 60) {
      throw AsrException('录音过长，请控制在 60 秒以内');
    }

    // 中转模式：Key 在服务端
    if (useRelay) {
      return _recognizeViaRelay(audio);
    }

    // 直连模式
    final token = await _token();
    final prefs = await SharedPreferences.getInstance();
    final cuid = prefs.getString('baidu_cuid') ?? _newCuid(prefs);

    final body = jsonEncode({
      'format': 'pcm',
      'rate': 16000,
      'channel': 1,
      'cuid': cuid,
      'token': token,
      'len': audio.length,
      'speech': base64Encode(audio),
    });
    final resp = await http
        .post(
          Uri.parse('https://vop.baidu.com/server_api'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 30));
    return parseResponse(resp);
  }

  static String parseResponse(http.Response resp) {
    if (resp.statusCode != 200) {
      throw AsrException(
        resp.statusCode == 429
            ? '今日语音请求次数已达上限'
            : '语音服务暂不可用（HTTP ${resp.statusCode}）',
      );
    }
    final dynamic data;
    try {
      data = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      throw const AsrException('语音服务返回了无效数据，请稍后重试');
    }
    if (data is! Map) throw const AsrException('语音服务返回了无效数据');
    final errNo = data['err_no'];
    if (errNo != 0) {
      throw AsrException(
        _errText(
          errNo is int ? errNo : -1,
          '${data['err_msg'] ?? data['error'] ?? ''}',
        ),
      );
    }
    final result = data['result'];
    if (result is! List || result.isEmpty) return '';
    if (result.first is! String) throw const AsrException('语音识别结果格式错误');
    // 百度会在结果末尾补一个「，」，去掉再展示
    return (result.first as String).replaceAll(RegExp(r'[，,]+\s*$'), '').trim();
  }

  static String _newCuid(SharedPreferences prefs) {
    final cuid = 'yiyuji_${DateTime.now().millisecondsSinceEpoch}';
    prefs.setString('baidu_cuid', cuid);
    return cuid;
  }

  static String _errText(int code, String msg) => switch (code) {
    3301 => '没听清，请离麦克风近一点重试',
    3302 => '语音服务鉴权失败，请检查 Key 配置',
    3303 => '语音服务器繁忙，请稍后重试',
    3304 => '请求超过限额',
    3308 => '录音过长，请控制在 60 秒以内',
    3309 => '录音太短，请说一点内容',
    3310 => '音频静音或质量太差，请重试',
    _ => '识别失败（$code $msg）',
  };
}

class AsrException implements Exception {
  final String message;
  const AsrException(this.message);
  @override
  String toString() => message;
}
