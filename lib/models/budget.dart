import 'dart:convert';

/// 预算配置实体类，对应 SQLite 中的 budget_table
/// cate_budget 以 JSON 字符串存储各分类预算，如 {"餐饮":800,"交通":200}
class Budget {
  final int? id;
  final double totalBudget; // 月度总预算
  final Map<String, double> cateBudget; // 各分类预算
  final String month; // 所属月份 yyyy-MM

  const Budget({
    this.id,
    required this.totalBudget,
    required this.cateBudget,
    required this.month,
  });

  String get cateBudgetJson => jsonEncode(cateBudget);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'total_budget': totalBudget,
        'cate_budget': cateBudgetJson,
        'month': month,
      };

  factory Budget.fromMap(Map<String, Object?> m) => Budget(
        id: m['id'] as int?,
        totalBudget: (m['total_budget'] as num?)?.toDouble() ?? 0,
        cateBudget: _decodeCate(m['cate_budget'] as String?),
        month: (m['month'] ?? '') as String,
      );

  static Map<String, double> _decodeCate(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }
}
