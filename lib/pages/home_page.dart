import 'package:flutter/material.dart';

import '../common/global.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/budget.dart';
import 'bill_edit_page.dart';
import 'widgets/common.dart';

/// 首页：本月/今日收支统计 + 预算进度 + 账单列表（按日分组）
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _range = 1; // 0 今日 / 1 本月 / 2 全部
  bool _loading = true;
  double _monthExpense = 0, _monthIncome = 0, _todayExpense = 0;
  Budget? _budget;
  final List<Bill> _bills = [];

  static String _p(int n) => n.toString().padLeft(2, '0');
  static String monthStr(DateTime d) => '${d.year}-${_p(d.month)}';
  static String dayStr(DateTime d) =>
      '${d.year}-${_p(d.month)}-${_p(d.day)}';

  @override
  void initState() {
    super.initState();
    refreshSignal.addListener(_onSignal);
    _load();
  }

  @override
  void dispose() {
    refreshSignal.removeListener(_onSignal);
    super.dispose();
  }

  void _onSignal() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final db = DatabaseHelper.instance;
    final results = await Future.wait([
      db.sumOfMonth(0, monthStr(now)),
      db.sumOfMonth(1, monthStr(now)),
      db.sumOfMonth(0, dayStr(now)),
      db.getBudget(monthStr(now)),
      db.queryBills(
          month: _range == 0 ? monthStr(now) : null, day: _range == 0 ? dayStr(now) : null),
    ]);
    if (!mounted) return;
    setState(() {
      _monthExpense = results[0] as double;
      _monthIncome = results[1] as double;
      _todayExpense = results[2] as double;
      _budget = results[3] as Budget?;
      _bills
        ..clear()
        ..addAll(results[4] as List<Bill>);
      _loading = false;
    });
  }

  /// 按日期分组，返回 (日期, 当日支出小计, 该日账单) 列表
  List<(String, double, List<Bill>)> get _groups {
    final map = <String, List<Bill>>{};
    for (final b in _bills) {
      map.putIfAbsent(b.createTime.substring(0, 10), () => []).add(b);
    }
    final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final k in keys)
        (
          k,
          map[k]!.where((b) => b.isExpense).fold<double>(0, (s, b) => s + b.money),
          map[k]!
        )
    ];
  }

  String _rangeLabel(String day) {
    final today = dayStr(DateTime.now());
    if (day == today) return '今天';
    return '${day.substring(5, 7)}月${day.substring(8)}日';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('一语记',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
        actions: [
          SegmentedButton<int>(
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 0, label: Text('今日')),
              ButtonSegment(value: 1, label: Text('本月')),
              ButtonSegment(value: 2, label: Text('全部')),
            ],
            selected: {_range},
            onSelectionChanged: (s) {
              _range = s.first;
              _load();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF42A5F5), Color(0xFF1E88E5)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('本月支出',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: .85))),
                        Text('¥${_monthExpense.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const SizedBox(height: 10),
                        Row(children: [
                          _darkStat('本月收入', _monthIncome),
                          const SizedBox(width: 12),
                          _darkStat('今日支出', _todayExpense),
                        ]),
                        if (_budget != null &&
                            _budget!.totalBudget > 0) ...[
                          const SizedBox(height: 12),
                          _budgetBar(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_bills.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(children: [
                        Icon(Icons.receipt_long,
                            size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text('暂无账单，去记一笔吧',
                            style: TextStyle(color: Colors.grey.shade500)),
                      ]),
                    )
                  else
                    ..._groups.map(_dayCard),
                ],
              ),
            ),
    );
  }

  Widget _darkStat(String label, double v) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: .8))),
              Text('¥${v.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ],
          ),
        ),
      );

  Widget _budgetBar() {
    final total = _budget!.totalBudget;
    final ratio = (total <= 0) ? 1.0 : (_monthExpense / total).clamp(0.0, 1.0);
    final over = _monthExpense > total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('月度预算',
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withValues(alpha: .8))),
            Text(
              over
                  ? '已超支 ¥${(_monthExpense - total).toStringAsFixed(2)}'
                  : '剩余 ¥${(total - _monthExpense).toStringAsFixed(2)} / ¥${total.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: .25),
            valueColor: AlwaysStoppedAnimation(
                over ? const Color(0xFFFF5252) : const Color(0xFF69F0AE)),
          ),
        ),
      ],
    );
  }

  Widget _dayCard((String, double, List<Bill>) g) {
    final (day, daySum, list) = g;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_rangeLabel(day),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text('支出 ¥${daySum.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...list.map((b) => BillTile(
                bill: b,
                onTap: () async {
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => BillEditPage(bill: b)));
                  _load();
                },
              )),
        ],
      ),
    );
  }
}
