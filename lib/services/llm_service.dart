import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/bill.dart';
import '../models/budget.dart';
import 'local_stores.dart';
import 'settings_service.dart';

/// LLM 服务封装
/// 默认使用构建时内置的智能模型服务（用户免配置），
/// 也支持用户在「我的」页自定义 OpenAI 兼容接口（接口地址 / 模型名称 / API Key）。
class LlmService {
  LlmService._();

  // 生效配置统一从 SettingsService 读取（内置或用户自定义）
  static String get baseUrl => SettingsService.baseUrl;
  static String get apiKey => SettingsService.apiKey;
  static String get model => SettingsService.model;

  static bool get isConfigured => apiKey.isNotEmpty;

  /// 通用对话请求，返回模型回复文本
  static Future<String> chat(String userContent,
      {String? system, double temperature = 0.3}) async {
    return chatMessages([
      if (system != null) {'role': 'system', 'content': system},
      {'role': 'user', 'content': userContent},
    ], temperature: temperature);
  }

  /// 多轮对话请求：messages 为完整的 OpenAI 格式消息列表
  static Future<String> chatMessages(List<Map<String, String>> messages,
      {double temperature = 0.3}) async {
    if (!isConfigured) {
      throw LlmException('AI 服务未就绪，请到「我的」页开启内置模型或配置自定义模型');
    }
    final uri = Uri.parse('$baseUrl/chat/completions');
    try {
      final resp = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'temperature': temperature,
              'messages': messages,
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (resp.statusCode != 200) {
        throw LlmException('接口返回 ${resp.statusCode}：${_brief(resp.body)}');
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final content = data['choices']?[0]?['message']?['content'];
      if (content is! String || content.isEmpty) {
        throw LlmException('模型未返回内容');
      }
      return content;
    } on LlmException {
      rethrow;
    } catch (e) {
      throw LlmException('网络请求失败，请检查网络后重试（$e）');
    }
  }

  /// 从模型回复中提取 JSON（容忍 ```json 包裹及前后多余文字）
  static dynamic extractJson(String text) {
    var t = text.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(t);
    if (fence != null) t = fence.group(1)!.trim();
    // 直接尝试解析
    try {
      return jsonDecode(t);
    } catch (_) {}
    // 截取首个 { 或 [ 到最后一个 } 或 ]
    final start = t.indexOf(RegExp(r'[\[{]'));
    if (start >= 0) {
      final end = max(t.lastIndexOf('}'), t.lastIndexOf(']'));
      if (end > start) {
        return jsonDecode(t.substring(start, end + 1));
      }
    }
    throw LlmException('AI 返回内容无法解析为 JSON');
  }

  static int max(int a, int b) => a > b ? a : b;

  static String _brief(String s) =>
      s.length > 200 ? '${s.substring(0, 200)}...' : s;
}

class LlmException implements Exception {
  final String message;
  LlmException(this.message);
  @override
  String toString() => message;
}

/// 自然语言记账解析
class NlBillParser {
  /// 输入口语化文本（可含多条消费），返回结构化账单列表
  static Future<List<Bill>> parse(String input) async {
    final now = DateTime.now();
    // 用户过往的分类纠正记录作为 few-shot 参考，越用越准
    final correctionHints = await CorrectionStore.hints();
    final system = '你是记账助手。用户会给出口语化的收支描述，'
        '你需要拆分出每一条收支记录。'
        '今天日期：${now.year}-${_p(now.month)}-${_p(now.day)} '
        '${_p(now.hour)}:${_p(now.minute)}。'
        '分类只能从以下选择：餐饮、交通、购物、娱乐、学习、医疗、居住、其他、工资、兼职、理财、红包。'
        'type 字段：0 表示支出，1 表示收入。'
        '必须只输出 JSON 数组，不要输出任何其他文字。每个元素格式：'
        '{"money":金额数字,"type":0,"category":"分类","remark":"不超过12字的备注"}。'
        '示例：输入"晚饭32，奶茶15"输出'
        '[{"money":32,"type":0,"category":"餐饮","remark":"晚饭"},'
        '{"money":15,"type":0,"category":"餐饮","remark":"奶茶"}]'
        '$correctionHints';

    final text = await LlmService.chat(input, system: system);
    final json = LlmService.extractJson(text);
    final list = json is List ? json : [json];

    final defaultTime =
        '${now.year}-${_p(now.month)}-${_p(now.day)} ${_p(now.hour)}:${_p(now.minute)}';
    final bills = <Bill>[];
    for (final item in list) {
      if (item is! Map) continue;
      final money = num.tryParse('${item['money']}')?.toDouble();
      if (money == null || money <= 0) continue;
      final isIncome = item['type'] == 1 || item['type'] == '1';
      bills.add(Bill(
        money: money,
        type: isIncome ? 1 : 0,
        category: '${item['category'] ?? '其他'}',
        remark: '${item['remark'] ?? ''}',
        createTime: defaultTime,
      ));
    }
    if (bills.isEmpty) {
      throw LlmException('未能从文本中识别出有效账单，请描述得更具体一些');
    }
    return bills;
  }

  static String _p(int n) => n.toString().padLeft(2, '0');
}

/// 小票 OCR 文本解析
class ReceiptParser {
  /// 输入 OCR 识别出的小票全文，返回账单列表
  static Future<List<Bill>> parse(String ocrText) async {
    final now = DateTime.now();
    final system = '你是小票解析助手。用户提供的是购物小票的 OCR 识别文本，'
        '可能包含噪点或乱码，请提取其中的商品/服务消费条目。'
        '今天日期：${now.year}-${_p(now.month)}-${_p(now.day)} '
        '${_p(now.hour)}:${_p(now.minute)}。'
        '分类只能从以下选择：餐饮、交通、购物、娱乐、学习、医疗、居住、其他。'
        '全部为支出（type=0）。金额取商品实付单价，忽略条码、编号等数字。'
        '必须只输出 JSON 数组，不要输出任何其他文字。每个元素格式：'
        '{"money":金额数字,"category":"分类","remark":"商品名，不超过12字"}。';

    final text = await LlmService.chat(ocrText, system: system);
    final json = LlmService.extractJson(text);
    final list = json is List ? json : [json];

    final defaultTime =
        '${now.year}-${_p(now.month)}-${_p(now.day)} ${_p(now.hour)}:${_p(now.minute)}';
    final bills = <Bill>[];
    for (final item in list) {
      if (item is! Map) continue;
      final money = num.tryParse('${item['money']}')?.toDouble();
      if (money == null || money <= 0) continue;
      bills.add(Bill(
        money: money,
        type: 0,
        category: '${item['category'] ?? '购物'}',
        remark: '${item['remark'] ?? '小票消费'}',
        createTime: defaultTime,
      ));
    }
    if (bills.isEmpty) {
      throw LlmException('未能从该小票中识别出消费条目');
    }
    return bills;
  }

  static String _p(int n) => n.toString().padLeft(2, '0');
}

/// AI 账单分析：消费总结 + 省钱建议 + 预算规划（支持月度 / 年度）
class MonthlyAnalyzer {
  /// 返回 (总结报告 Markdown 文本, AI 建议的分类预算)
  /// [yearly] 为 true 时生成年度报告（不输出下月预算 JSON）
  static Future<(String, Map<String, double>)> analyze({
    required String month,
    required List<Bill> bills,
    required double monthExpense,
    required double monthIncome,
    required Map<String, double> categorySpend,
    required Budget? currentBudget,
    bool yearly = false,
  }) async {
    final periodLabel = yearly ? '年度' : '月度';
    // 把整期账单明细拼成文本（核心 Token 消耗点）
    final lines = <String>[];
    for (final b in bills) {
      final t = b.isExpense ? '支出' : '收入';
      lines.add('${b.createTime} | $t | ${b.category} | ${b.money.toStringAsFixed(2)}元 | ${b.remark}');
    }
    final cateLine = categorySpend.entries
        .map((e) => '${e.key}:${e.value.toStringAsFixed(2)}元')
        .join('，');
    final budgetLine = currentBudget == null
        ? '本月未设置预算'
        : '总预算${currentBudget.totalBudget}元，分类预算${currentBudget.cateBudget}';

    final planInstruction = yearly
        ? '''第二部分以「# 明年消费展望」为标题，基于全年消费趋势给出明年整体消费建议（2-3句）。'''
        : '''第二部分以「# 下月预算规划」为标题，说明规划思路（1-2句）。
第三部分只输出一个 JSON 代码块（不要有其他文字），内容为下月各分类建议预算，格式：
{"餐饮":数字,"交通":数字,"购物":数字,"娱乐":数字,"其他":数字}
金额必须参考本月实际消费，合理收紧。''';

    final prompt = '''
以下是用户 $month 的全部账单明细（时间 | 类型 | 分类 | 金额 | 备注）：
${lines.join('\n')}

统计信息：$periodLabel总支出 $monthExpense 元，总收入 $monthIncome 元。
分类支出汇总：$cateLine。
用户设置的预算：$budgetLine。

请你作为个人理财分析师完成以下部分，并严格按格式输出：
第一部分以「# $periodLabel消费报告」为标题，用 Markdown 写：
1. 本$periodLabel整体收支评价（2-3句）
2. 消费结构分析：哪些分类占比最高、是否有单笔大额或不合理消费（列出具体例子）
3. 3-5 条个性化省钱建议，要引用上面账单里的真实数据
$planInstruction''';

    final text = await LlmService.chat(prompt, temperature: 0.5);
    var report = text;
    var plan = <String, double>{};

    if (!yearly) {
      // 从回复里拆出 JSON 预算部分
      final jsonMatch =
          RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```').firstMatch(text);
      if (jsonMatch != null) {
        try {
          final m = jsonDecode(jsonMatch.group(1)!) as Map<String, dynamic>;
          plan = m.map((k, v) => MapEntry(k, (v as num).toDouble()));
          // 从报告中移除 JSON 块，避免正文出现裸 JSON
          report = text.replaceRange(jsonMatch.start, jsonMatch.end, '').trim();
        } catch (_) {}
      }
    }
    return (report, plan);
  }
}
