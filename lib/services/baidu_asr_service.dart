import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 语音识别服务（双模式）
///  - 中转模式（推荐）：ASR_RELAY_URL 指向自建中转服务，Key 保存在服务端，APK 不含任何 Key
///  - 直连模式：构建时注入 BAIDU_API_KEY / BAIDU_SECRET_KEY，App 直接调百度
class BaiduAsrService {
  BaiduAsrService._();

  /// 中转服务地址（如 https://xxx.domcloud.co），非空时走中转
  static const String relayUrl =
      String.fromEnvironment('ASR_RELAY_URL', defaultValue: '');

  static const String apiKey =
      String.fromEnvironment('BAIDU_API_KEY', defaultValue: '');
  static const String secretKey =
      String.fromEnvironment('BAIDU_SECRET_KEY', defaultValue: '');

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
  static Future<String> _recognizeViaRelay(String path, int len) async {
    final audio = await File(path).readAsBytes();
    final cuid = await _cuid();
    final resp = await http
        .post(
          Uri.parse('$relayUrl/asr'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'speech': base64Encode(audio),
            'len': len,
            'cuid': cuid,
          }),
        )
        .timeout(const Duration(seconds: 40));
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final errNo = data['err_no'];
    if (errNo != 0) {
      if (errNo is int && errNo < 0 && data['err_msg'] == null) {
        // 中转层自身的错误（限流/配置缺失）
        throw AsrException('${data['error'] ?? '中转服务异常（$errNo）'}');
      }
      throw AsrException(_errText((errNo ?? -1) as int, '${data['err_msg'] ?? ''}'));
    }
    final result = data['result'];
    if (result is! List || result.isEmpty) return '';
    return (result.first as String).replaceAll(RegExp(r'[，,]+\s*$'), '').trim();
  }

  /// 获取 access_token（有效期约 30 天，缓存到本地）
  static Future<String> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('baidu_asr_token');
    final fetchedAt = prefs.getInt('baidu_asr_token_at') ?? 0;
    final ageSec =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - fetchedAt;
    if (cached != null && cached.isNotEmpty && ageSec < 29 * 86400) {
      return cached;
    }
    final uri = Uri.parse(
        'https://aip.baidubce.com/oauth/2.0/token'
        '?grant_type=client_credentials&client_id=$apiKey&client_secret=$secretKey');
    final resp =
        jsonDecode(utf8.decode(await http.readBytes(uri).timeout(const Duration(seconds: 20))));
    final token = resp['access_token'];
    if (token is! String || token.isEmpty) {
      throw AsrException('获取百度语音凭证失败，请检查 API Key 配置');
    }
    await prefs.setString('baidu_asr_token', token);
    await prefs.setInt('baidu_asr_token_at',
        DateTime.now().millisecondsSinceEpoch ~/ 1000);
    return token;
  }

  /// 识别一段 PCM 录音，返回文字（失败抛 AsrException）
  static Future<String> recognizePcmFile(String path) async {
    final audio = await File(path).readAsBytes();
    if (audio.isEmpty) throw AsrException('录音为空，请重试');
    if (audio.length > 10 * 1024 * 1024) {
      throw AsrException('录音过长，请控制在 60 秒以内');
    }

    // 中转模式：Key 在服务端
    if (useRelay) {
      return _recognizeViaRelay(path, audio.length);
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
        .post(Uri.parse('https://vop.baidu.com/server_api'),
            headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 30));
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final errNo = data['err_no'];
    if (errNo != 0) {
      throw AsrException(_errText((errNo ?? -1) as int, '${data['err_msg'] ?? ''}'));
    }
    final result = data['result'];
    if (result is! List || result.isEmpty) return '';
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
