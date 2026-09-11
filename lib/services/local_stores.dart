import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 常用记账模板：一键填入手动记账表单
class TemplateStore {
  TemplateStore._();

  static const _key = 'bill_templates';

  static Future<List<Map<String, dynamic>>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(Map<String, dynamic> tpl) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await list();
    // 相同备注+分类+金额视为同一条，替换旧值
    items.removeWhere((e) =>
        e['remark'] == tpl['remark'] &&
        e['category'] == tpl['category'] &&
        e['money'] == tpl['money']);
    items.insert(0, tpl);
    if (items.length > 12) items.removeRange(12, items.length);
    await prefs.setString(_key, jsonEncode(items));
  }

  static Future<void> removeAt(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await list();
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    await prefs.setString(_key, jsonEncode(items));
  }
}

/// 分类纠错学习：用户修改 AI 归错的分类后记录「备注关键词 → 正确分类」，
/// 下次自然语言解析时作为 few-shot 参考传给模型，越用越准
class CorrectionStore {
  CorrectionStore._();

  static const _key = 'category_corrections';
  static const _max = 20;

  static Future<List<Map<String, dynamic>>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(String keyword, String category) async {
    if (keyword.trim().isEmpty || category.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final items = await list();
    items.removeWhere((e) => e['keyword'] == keyword);
    items.insert(0, {'keyword': keyword.trim(), 'category': category.trim()});
    if (items.length > _max) items.removeRange(_max, items.length);
    await prefs.setString(_key, jsonEncode(items));
  }

  /// 生成给模型的纠正提示；无记录时返回空串
  static Future<String> hints() async {
    final items = await list();
    if (items.isEmpty) return '';
    return '\n用户过往的分类纠正记录（备注关键词→正确分类）：'
        '${items.map((e) => "${e["keyword"]}→${e["category"]}").join("、")}。'
        '备注包含这些关键词的条目，请优先使用纠正后的分类。';
  }
}
