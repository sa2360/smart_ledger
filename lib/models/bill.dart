/// 账单实体类，对应 SQLite 中的 bill_table
class Bill {
  final int? id;
  final double money;
  final int type; // 0 支出 / 1 收入
  final String category; // 餐饮/交通/购物/娱乐/学习/工资 等
  final String remark; // 备注（AI 自动生成或手动填写）
  final String createTime; // 记账时间 yyyy-MM-dd HH:mm

  const Bill({
    this.id,
    required this.money,
    required this.type,
    required this.category,
    required this.remark,
    required this.createTime,
  });

  bool get isExpense => type == 0;

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'money': money,
        'type': type,
        'category': category,
        'remark': remark,
        'create_time': createTime,
      };

  factory Bill.fromMap(Map<String, Object?> m) => Bill(
        id: m['id'] as int?,
        money: (m['money'] as num).toDouble(),
        type: m['type'] as int,
        category: (m['category'] ?? '其他') as String,
        remark: (m['remark'] ?? '') as String,
        createTime: (m['create_time'] ?? '') as String,
      );

  Bill copyWith({
    int? id,
    double? money,
    int? type,
    String? category,
    String? remark,
    String? createTime,
  }) =>
      Bill(
        id: id ?? this.id,
        money: money ?? this.money,
        type: type ?? this.type,
        category: category ?? this.category,
        remark: remark ?? this.remark,
        createTime: createTime ?? this.createTime,
      );
}
