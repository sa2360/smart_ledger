import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/bill.dart';
import '../models/budget.dart';

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
      version: 1,
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
      },
    );
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
}
