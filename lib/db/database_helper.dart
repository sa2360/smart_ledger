import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/bill.dart';
import '../models/budget.dart';
import '../models/recurring.dart';

/// 本地 SQLite 数据库单例
/// 表结构与《软件设计说明书》第四章一致：
///   bill_table   账单记录表
///   budget_table 预算配置表
class DatabaseHelper {
  DatabaseHelper._();

  static final DatabaseHelper instance = DatabaseHelper._();
  static Database? _db;

  Future<Database> get db async {
    _db ??= await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'smart_ledger.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE bill_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            money FLOAT,
            type INTEGER,
            category TEXT,
            remark TEXT,
            create_time TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE budget_table (
            id INTEGER PRIMARY KEY,
            total_budget FLOAT,
            cate_budget TEXT,
            month TEXT
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_bill_create_time ON bill_table(create_time)');
        await _createRecurringTable(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await _createRecurringTable(db);
        }
      },
    );
  }

  static Future<void> _createRecurringTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        money FLOAT,
        type INTEGER,
        category TEXT,
        remark TEXT,
        cycle TEXT,
        day INTEGER,
        last_run TEXT,
        enabled INTEGER DEFAULT 1
      )
    ''');
  }

  // ---------------- 账单 CRUD ----------------

  Future<int> insertBill(Bill bill) async {
    final d = await db;
    return d.insert('bill_table', bill.toMap());
  }

  Future<List<int>> insertBills(List<Bill> bills) async {
    final d = await db;
    final batch = d.batch();
    for (final b in bills) {
      batch.insert('bill_table', b.toMap());
    }
    final res = await batch.commit(continueOnError: true);
    return res.map((e) => e as int).toList();
  }

  /// 按条件查询：month(yyyy-MM)、type(0/1)、category
  Future<List<Bill>> queryBills({
    String? month,
    int? type,
    String? category,
    String? day, // yyyy-MM-dd
  }) async {
    final d = await db;
    final where = <String>[];
    final args = <Object>[];
    if (month != null) {
      where.add('create_time LIKE ?');
      args.add('$month%');
    }
    if (day != null) {
      where.add('create_time LIKE ?');
      args.add('$day%');
    }
    if (type != null) {
      where.add('type = ?');
      args.add(type);
    }
    if (category != null) {
      where.add('category = ?');
      args.add(category);
    }
    final res = await d.query('bill_table',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'create_time DESC, id DESC');
    return res.map(Bill.fromMap).toList();
  }

  Future<int> updateBill(Bill bill) async {
    final d = await db;
    return d.update('bill_table', bill.toMap(),
        where: 'id = ?', whereArgs: [bill.id]);
  }

  Future<int> deleteBill(int id) async {
    final d = await db;
    return d.delete('bill_table', where: 'id = ?', whereArgs: [id]);
  }

  /// 统计某月某类型的总金额
  Future<double> sumOfMonth(int type, String month) async {
    final d = await db;
    final res = await d.rawQuery(
      'SELECT SUM(money) AS s FROM bill_table WHERE type = ? AND create_time LIKE ?',
      [type, '$month%'],
    );
    return (res.first['s'] as num?)?.toDouble() ?? 0;
  }

  /// 统计 [start, end] 日期区间（含端点）内某类型总金额
  Future<double> sumBetween(DateTime start, DateTime end, {int type = 0}) async {
    final d = await db;
    String fmt(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final res = await d.rawQuery(
      "SELECT SUM(money) AS s FROM bill_table WHERE type = ? "
      "AND substr(create_time, 1, 10) >= ? AND substr(create_time, 1, 10) <= ?",
      [type, fmt(start), fmt(end)],
    );
    return (res.first['s'] as num?)?.toDouble() ?? 0;
  }

  /// 搜索账单：备注/分类关键词 + 分类过滤 + 金额区间
  Future<List<Bill>> searchBills({
    String? keyword,
    String? category,
    double? minMoney,
    double? maxMoney,
  }) async {
    final d = await db;
    final where = <String>[];
    final args = <Object>[];
    if (keyword != null && keyword.trim().isNotEmpty) {
      where.add('(remark LIKE ? OR category LIKE ?)');
      final kw = '%${keyword.trim()}%';
      args..add(kw)..add(kw);
    }
    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    if (minMoney != null) {
      where.add('money >= ?');
      args.add(minMoney);
    }
    if (maxMoney != null) {
      where.add('money <= ?');
      args.add(maxMoney);
    }
    final res = await d.query('bill_table',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'create_time DESC, id DESC',
        limit: 500);
    return res.map(Bill.fromMap).toList();
  }

  /// 统计某月各分类支出总额，按金额降序
  Future<Map<String, double>> categorySpendOfMonth(String month) async {
    final d = await db;
    final res = await d.rawQuery(
      'SELECT category, SUM(money) AS s FROM bill_table '
      'WHERE type = 0 AND create_time LIKE ? GROUP BY category ORDER BY s DESC',
      ['$month%'],
    );
    return {
      for (final row in res)
        (row['category'] ?? '其他') as String:
            (row['s'] as num?)?.toDouble() ?? 0,
    };
  }

  // ---------------- 预算 CRUD ----------------

  Future<Budget?> getBudget(String month) async {
    final d = await db;
    final res = await d
        .query('budget_table', where: 'month = ?', whereArgs: [month], limit: 1);
    if (res.isEmpty) return null;
    return Budget.fromMap(res.first);
  }

  /// 保存预算（同一月份只保留一条）
  Future<void> saveBudget(Budget budget) async {
    final d = await db;
    await d.delete('budget_table', where: 'month = ?', whereArgs: [budget.month]);
    await d.insert('budget_table', budget.toMap());
  }

  // ---------------- 周期记账 CRUD ----------------

  Future<List<Recurring>> queryRecurrings({bool enabledOnly = false}) async {
    final d = await db;
    final res = await d.query('recurring_table',
        where: enabledOnly ? 'enabled = 1' : null,
        orderBy: 'id DESC');
    return res.map(Recurring.fromMap).toList();
  }

  Future<int> insertRecurring(Recurring r) async {
    final d = await db;
    return d.insert('recurring_table', r.toMap());
  }

  Future<int> updateRecurring(Recurring r) async {
    final d = await db;
    return d.update('recurring_table', r.toMap(),
        where: 'id = ?', whereArgs: [r.id]);
  }

  Future<int> deleteRecurring(int id) async {
    final d = await db;
    return d.delete('recurring_table', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- 备份 / 恢复 ----------------

  /// 读取整表原始数据（备份用）
  Future<List<Map<String, Object?>>> rawTable(String table) async {
    final d = await db;
    return d.query(table);
  }

  /// 恢复备份前清空全部业务数据
  Future<void> clearAllForRestore() async {
    final d = await db;
    await d.delete('bill_table');
    await d.delete('budget_table');
    await d.delete('recurring_table');
  }

  // ---------------- 统计扩展 ----------------

  /// 近 count 个月的月度收支汇总，按月份升序
  /// 返回 (月份, 支出, 收入) 列表
  Future<List<(String, double, double)>> monthlySummaries(int count) async {
    final d = await db;
    final now = DateTime.now();
    final months = <String>[
      for (var i = count - 1; i >= 0; i--)
        (now.month - i <= 0)
            ? '${now.year - 1}-${(now.month - i + 12).toString().padLeft(2, '0')}'
            : '${now.year}-${(now.month - i).toString().padLeft(2, '0')}'
    ];
    final res = await d.rawQuery(
      'SELECT substr(create_time, 1, 7) AS m, type, SUM(money) AS s '
      'FROM bill_table GROUP BY m, type',
    );
    final map = <String, List<double>>{}; // month -> [expense, income]
    for (final row in res) {
      final m = row['m'] as String;
      final type = row['type'] as int;
      final s = (row['s'] as num?)?.toDouble() ?? 0;
      final pair = map.putIfAbsent(m, () => [0, 0]);
      if (type == 0) {
        pair[0] = s;
      } else {
        pair[1] = s;
      }
    }
    return [
      for (final m in months) (m, map[m]?[0] ?? 0, map[m]?[1] ?? 0),
    ];
  }
}
