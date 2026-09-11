import 'llm_service.dart';

/// 账单问答服务：AI 记账助手
/// 把用户最近两个月的账单明细作为上下文，支持多轮对话查询与分析
class BillQaService {
  BillQaService._();

  /// 回答一条用户提问
  /// [history] 为最近的对话记录（不含本次提问），用于多轮上下文
  static Future<String> answer({
    required String question,
    required List<({String role, String content})> history,
    required List<String> billLines,
  }) async {
    final billText = billLines.isEmpty ? '（暂无账单记录）' : billLines.join('\n');
    final system = '你是记账 App「一语记」的 AI 记账助手。'
        '以下是用户最近两个月的账单明细，格式为「时间 | 类型 | 分类 | 金额 | 备注」：\n'
        '$billText\n'
        '请根据这些真实数据回答用户的问题，要求：\n'
        '1. 只基于账单数据回答，不要编造数据；账单中没有的信息要如实说明\n'
        '2. 金额保留两位小数，统计要准确\n'
        '3. 回答简洁，一般不超过 150 字，可以用简短的数字列表\n'
        '4. 用中文回答，语气友好自然';

    // 构造多轮消息：系统提示 + 最近对话 + 本次提问
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': system},
      for (final m in history)
        {'role': m.role, 'content': m.content},
      {'role': 'user', 'content': question},
    ];
    return LlmService.chatMessages(messages, temperature: 0.4);
  }
}
