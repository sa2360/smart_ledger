/// 周期记账实体类，对应 SQLite 中的 recurring_table
/// 房租、订阅等固定收支，到期自动入账
class Recurring {
  final int? id;
  final double money;
  final int type; // 0 支出 / 1 收入
  final String category;
  final String remark;
  final String cycle; // daily / weekly / monthly
  final int day; // monthly: 1-28；weekly: 1-7（周一=1）；daily 无意义，存 0
  final String lastRun; // 上次执行的日期 yyyy-MM-dd，空串表示尚未执行过
  final int enabled; // 1 启用 / 0 停用

  const Recurring({
    this.id,
    required this.money,
    required this.type,
    required this.category,
    required this.remark,
    required this.cycle,
    required this.day,
    this.lastRun = '',
    this.enabled = 1,
  });

  bool get isExpense => type == 0;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'money': money,
        'type': type,
        'category': category,
        'remark': remark,
        'cycle': cycle,
        'day': day,
        'last_run': lastRun,
        'enabled': enabled,
      };

  factory Recurring.fromMap(Map<String, Object?> m) => Recurring(
        id: m['id'] as int?,
        money: (m['money'] as num).toDouble(),
        type: m['type'] as int,
        category: (m['category'] ?? '其他') as String,
        remark: (m['remark'] ?? '') as String,
        cycle: (m['cycle'] ?? 'monthly') as String,
        day: (m['day'] ?? 1) as int,
        lastRun: (m['last_run'] ?? '') as String,
        enabled: (m['enabled'] ?? 1) as int,
      );

  Recurring copyWith({
    int? id,
    double? money,
    int? type,
    String? category,
    String? remark,
    String? cycle,
    int? day,
    String? lastRun,
    int? enabled,
  }) =>
      Recurring(
        id: id ?? this.id,
        money: money ?? this.money,
        type: type ?? this.type,
        category: category ?? this.category,
        remark: remark ?? this.remark,
        cycle: cycle ?? this.cycle,
        day: day ?? this.day,
        lastRun: lastRun ?? this.lastRun,
        enabled: enabled ?? this.enabled,
      );

  String get cycleLabel => switch (cycle) {
        'daily' => '每天',
        'weekly' => '每周${'一二三四五六日'[day - 1]}',
        _ => '每月$day日',
      };
}
