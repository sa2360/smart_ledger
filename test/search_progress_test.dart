import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ledger/db/database_helper.dart';
import 'package:smart_ledger/models/bill.dart';
import 'package:smart_ledger/models/bill_search.dart';
import 'package:smart_ledger/models/recurring.dart';
import 'package:smart_ledger/pages/search_page.dart';
import 'package:smart_ledger/services/recurring_service.dart';

import 'test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final db = DatabaseHelper.instance;
  const bill = Bill(
    money: 10,
    type: 0,
    category: '购物',
    remark: '折扣 50%_券\\码',
    createTime: '2026-09-30 23:59',
  );
  setUp(() async => directory = await setUpDatabase());
  tearDown(() async => tearDownDatabase(directory));

  test('关键词按字面匹配百分号、下划线和反斜杠', () async {
    await db.insertBills([bill, bill.copyWith(remark: '无折扣')]);
    for (final keyword in ['%', '_', '\\', '50%_券\\码']) {
      expect(await db.searchBills(keyword: keyword), hasLength(1));
      expect(
        (await db.searchBillPage(BillSearchQuery(keyword: keyword))).count,
        1,
      );
    }
  });

  test('超过 500 条仍可完整翻页，全量统计与日期收支过滤一致', () async {
    await db.insertBills(
      List.generate(505, (i) => bill.copyWith(remark: '账单$i')),
    );
    await db.insertBills([
      bill.copyWith(type: 1, money: 25),
      bill.copyWith(createTime: '2026-10-01 00:00', money: 999),
      bill.copyWith(createTime: '2026-09-29 23:59', money: 999),
    ]);
    final query = BillSearchQuery(
      startDate: DateTime(2026, 9, 30),
      endDate: DateTime(2026, 9, 30),
    );
    final first = await db.searchBillPage(query);
    expect(first.count, 506);
    expect(first.expense, 5050);
    expect(first.income, 25);
    final ids = <int>{};
    for (var offset = 0; offset < first.count; offset += 100) {
      final page = await db.searchBillPage(query, offset: offset);
      ids.addAll(page.bills.map((b) => b.id!));
      expect(page.count, first.count);
    }
    expect(ids, hasLength(506));
    final income = await db.searchBillPage(
      BillSearchQuery(type: 1, category: '购物', minMoney: 20, maxMoney: 30),
    );
    expect(income.count, 1);
    expect(income.expense, 0);
    expect(income.income, 25);
    await expectLater(db.searchBillPage(query, limit: 0), throwsArgumentError);
  });

  test('当天执行后修改周期不重复记账，按新星期计算下一期', () async {
    final now = DateTime.now();
    await db.insertRecurring(
      const Recurring(
        money: 10,
        type: 0,
        category: '居住',
        remark: '固定消费',
        cycle: 'daily',
        day: 0,
      ),
    );
    expect(await RecurringService.runDueBills(now: now), 1);
    final current = (await db.queryRecurrings()).single;
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    await db.updateRecurring(
      current.copyWith(cycle: 'weekly', day: nextDay.weekday),
    );
    expect(await RecurringService.runDueBills(now: now), 0);
    expect(await RecurringService.runDueBills(now: nextDay), 1);
    expect(await db.queryBills(), hasLength(2));
  });

  test('月周期执行标记与目标日不同，仍执行当月尚未过去的目标日', () async {
    await db.insertRecurring(
      const Recurring(
        money: 10,
        type: 0,
        category: '居住',
        remark: '房租',
        cycle: 'monthly',
        day: 28,
        lastRun: '2026-09-10',
      ),
    );
    expect(await RecurringService.runDueBills(now: DateTime(2026, 9, 28)), 1);
    expect((await db.queryBills()).single.createTime, '2026-09-28 08:00');
    expect(await RecurringService.runDueBills(now: DateTime(2026, 9, 28)), 0);
  });

  testWidgets('搜索显示全量合计，翻页继续使用已提交的关键词', (tester) async {
    await tester.runAsync(
      () => db.insertBills(
        List.generate(101, (i) => bill.copyWith(remark: '目标$i')),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.enterText(find.byType(TextField).first, '目标');
    await tester.tap(find.widgetWithText(FilledButton, '搜索'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('找到 101 条'), findsOneWidget);
    expect(find.textContaining('支出 ¥1010.00'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '尚未提交');
    await tester.scrollUntilVisible(
      find.textContaining('加载更多'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('加载更多'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('找到 101 条'), findsOneWidget);
    expect(find.textContaining('加载更多'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小屏幕弹出键盘时搜索表单可滚动且不溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 650);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.enterText(find.byType(TextField).first, '午饭');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '搜索'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
