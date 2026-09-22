import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_ledger/common/global.dart';
import 'package:smart_ledger/db/database_helper.dart';
import 'package:smart_ledger/models/bill.dart';
import 'package:smart_ledger/models/budget.dart';
import 'package:smart_ledger/models/recurring.dart';
import 'package:smart_ledger/services/backup_service.dart';
import 'package:smart_ledger/services/recurring_service.dart';
import 'package:smart_ledger/services/settings_service.dart';
import 'test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final db = DatabaseHelper.instance;
  const bill = Bill(
    money: 12,
    type: 0,
    category: '餐饮',
    remark: '午饭',
    createTime: '2026-09-19 12:00',
  );
  Recurring recurring({
    String cycle = 'daily',
    int day = 0,
    String last = '',
  }) => Recurring(
    money: 10,
    type: 0,
    category: '居住',
    remark: '固定消费',
    cycle: cycle,
    day: day,
    lastRun: last,
  );
  setUp(() async {
    directory = await setUpDatabase();
  });
  tearDown(() async {
    await tearDownDatabase(directory);
  });

  test('每日首次只入一笔，刷新和并发调用不重复', () async {
    await db.insertRecurring(recurring());
    final now = DateTime(2026, 9, 19);
    var notifications = 0;
    void listener() {
      notifications++;
      RecurringService.runDueBills(now: now);
    }

    refreshSignal.addListener(listener);
    try {
      await Future.wait(
        List.generate(5, (_) => RecurringService.runDueBills(now: now)),
      );
      expect(await db.queryBills(), hasLength(1));
      expect(await RecurringService.runDueBills(now: now), 0);
      expect(notifications, 1);
      expect(await RecurringService.runDueBills(now: DateTime(2026, 9, 22)), 3);
      expect((await db.queryBills()).map((b) => b.createTime), [
        '2026-09-22 08:00',
        '2026-09-21 08:00',
        '2026-09-20 08:00',
        '2026-09-19 08:00',
      ]);
    } finally {
      refreshSignal.removeListener(listener);
    }
  });

  test('周期补记跨年，停用项不执行', () async {
    await db.insertRecurring(
      recurring(cycle: 'weekly', day: 1, last: '2025-12-29'),
    );
    await db.insertRecurring(
      recurring(cycle: 'monthly', day: 28, last: '2025-12-28'),
    );
    await db.insertRecurring(recurring().copyWith(enabled: 0));
    expect(await RecurringService.runDueBills(now: DateTime(2026, 2, 28)), 10);
    expect(await RecurringService.runDueBills(now: DateTime(2026, 2, 28)), 0);
  });

  test('周期执行日期更新失败时，账单插入一起回滚', () async {
    await db.insertRecurring(recurring());
    final sql = await db.db;
    await sql.execute(
      "CREATE TRIGGER reject_run BEFORE UPDATE ON recurring_table BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await expectLater(
      RecurringService.runDueBills(now: DateTime(2026, 9, 19)),
      throwsA(anything),
    );
    expect(await db.queryBills(), isEmpty);
    expect((await db.queryRecurrings()).single.lastRun, '');
  });

  test('备份恢复业务、模板、纠错和外观，但不导出密钥', () async {
    await db.insertBill(bill);
    await db.saveBudget(
      const Budget(totalBudget: 100, cateBudget: {'餐饮': 80}, month: '2026-09'),
    );
    await db.insertRecurring(recurring(last: '2026-09-19'));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'bill_templates',
      jsonEncode([
        {'money': 12, 'category': '餐饮', 'remark': '午饭', 'is_income': 0},
      ]),
    );
    await prefs.setString(
      'category_corrections',
      jsonEncode([
        {'keyword': '午饭', 'category': '餐饮'},
      ]),
    );
    await prefs.setString('theme_mode', 'dark');
    await prefs.setString('custom_api_key', 'private-test-key');
    final snapshot = await BackupService.snapshot();
    expect(jsonEncode(snapshot), isNot(contains('private-test-key')));
    await db.insertBill(bill);
    await prefs.setString('theme_mode', 'light');
    expect(await BackupService.restore(jsonEncode(snapshot)), 1);
    await SettingsService.init();
    expect(await db.queryBills(), hasLength(1));
    expect((await db.getBudget('2026-09'))!.totalBudget, 100);
    expect((await db.queryRecurrings()).single.lastRun, '2026-09-19');
    expect(prefs.getString('theme_mode'), 'dark');
    expect(prefs.getString('bill_templates'), contains('午饭'));
    expect(prefs.getString('category_corrections'), contains('午饭'));
    expect(SettingsService.customApiKey, isEmpty);
    expect(await (await db.db).query('restore_preferences'), isEmpty);
  });

  test('损坏备份、无效日期、重复 ID 均在清空前拒绝', () async {
    await db.insertBill(bill);
    for (final mutate in <void Function(Map<String, Object?>)>[
      (m) => m.remove('bills'),
      (m) => (m['bills'] as List).first['create_time'] = '2026-02-30 12:00',
      (m) => (m['bills'] as List).add((m['bills'] as List).first),
      (m) => m['version'] = 999,
      (m) => (m['preferences'] as Map)['bill_templates'] = '[{}]',
    ]) {
      final snapshot = Map<String, Object?>.from(
        jsonDecode(jsonEncode(await BackupService.snapshot())) as Map,
      );
      mutate(snapshot);
      await expectLater(
        BackupService.restore(jsonEncode(snapshot)),
        throwsFormatException,
      );
      expect((await db.queryBills()).single.remark, '午饭');
    }
  });

  test('恢复途中数据库写入失败，旧三表和设置完整保留', () async {
    await db.insertBill(bill);
    await db.saveBudget(
      const Budget(totalBudget: 100, cateBudget: {}, month: '2026-09'),
    );
    await db.insertRecurring(recurring());
    final snapshot = await BackupService.snapshot();
    final sql = await db.db;
    await sql.execute(
      "CREATE TRIGGER reject_restore BEFORE INSERT ON budget_table BEGIN SELECT RAISE(ABORT, 'test failure'); END",
    );
    await expectLater(
      BackupService.restore(jsonEncode(snapshot)),
      throwsA(anything),
    );
    expect(await db.queryBills(), hasLength(1));
    expect(await db.getBudget('2026-09'), isNotNull);
    expect(await db.queryRecurrings(), hasLength(1));
    expect(await sql.query('restore_preferences'), isEmpty);
  });

  test('兼容旧版备份并保留本机设置', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', 'dark');
    final old = {
      'app': 'yiyuji_ledger',
      'version': 1,
      'bills': [bill.toMap()],
      'budgets': [],
      'recurrings': [],
    };
    expect(await BackupService.restore(jsonEncode(old)), 1);
    expect(prefs.getString('theme_mode'), 'dark');
  });

  test('恢复提交后中断，下次初始化继续恢复偏好', () async {
    final sql = await db.db;
    await sql.insert('restore_preferences', {
      'id': 1,
      'payload': jsonEncode({
        for (final key in BackupService.preferenceKeys)
          key: key == 'theme_mode' ? 'dark' : null,
      }),
    });
    await SettingsService.init();
    expect(SettingsService.themeMode.name, 'dark');
    expect(await sql.query('restore_preferences'), isEmpty);
  });

  test('批量入账任一失败时整体回滚', () async {
    await expectLater(
      db.insertBills([bill.copyWith(id: 1), bill.copyWith(id: 1)]),
      throwsA(anything),
    );
    expect(await db.queryBills(), isEmpty);
  });
  test('数据库 v2 升级保留原有账单并建立恢复任务表', () async {
    await db.insertBill(bill);
    final sql = await db.db;
    await sql.execute('DROP TABLE restore_preferences');
    await sql.execute('PRAGMA user_version = 2');
    await db.close();
    final upgraded = await db.db;
    expect(
      (await upgraded.rawQuery('PRAGMA user_version')).single['user_version'],
      3,
    );
    expect((await db.queryBills()).single.remark, '午饭');
    expect(await upgraded.query('restore_preferences'), isEmpty);
  });
}
