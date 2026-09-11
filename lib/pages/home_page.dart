import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/global.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/budget.dart';
import '../services/llm_service.dart';
import '../services/recurring_service.dart';
import 'bill_edit_page.dart';
import 'search_page.dart';
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

  // AI 周度预警：本周支出 / 近四周平均，> 平均 1.5 倍时提示
  bool _weekAlert = false;
  double _weekSpend = 0, _weekAvg = 0;
  String _weekKey = '';

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
    // 长时间驻留后台后回到 App，也补记到期的周期账单
    await RecurringService.runDueBills();
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
    _checkWeeklyAlert();
  }

  /// AI 周度预警：本周支出超过近四周平均的 1.5 倍时提示
  Future<void> _checkWeeklyAlert() async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final thisWeek = await db.sumBetween(weekStart, now);
    if (thisWeek <= 0) return;

    var prevSum = 0.0;
    var prevWeeks = 0;
    for (var i = 1; i <= 4; i++) {
      final s = weekStart.subtract(Duration(days: 7 * i));
      final e = s.add(const Duration(days: 6));
      // 未来周（月初安装等情况）不计入平均
      if (e.isAfter(today)) continue;
      final v = await db.sumBetween(s, e);
      prevSum += v;
      prevWeeks++;
    }
    if (prevWeeks == 0) return;
    final avg = prevSum / prevWeeks;
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getString('alert_dismissed_week') == _weekKeyOf(weekStart);
    setState(() {
      _weekSpend = thisWeek;
      _weekAvg = avg;
      _weekKey = _weekKeyOf(weekStart);
      _weekAlert = avg > 0 && thisWeek > avg * 1.5 && !dismissed;
    });
  }

  static String _weekKeyOf(DateTime weekStart) =>
      '${weekStart.year}-${_p(weekStart.month)}-${_p(weekStart.day)}';

  /// 弹出 AI 对本周消费的简评（每周只请求一次，结果缓存）
  Future<void> _showWeeklyAiComment() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('alert_comment_$_weekKey');
    if (cached != null) {
      if (mounted) _showCommentDialog(cached);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('AI 正在分析本周消费…'), behavior: SnackBarBehavior.floating));
    try {
      final weekStart = DateTime.tryParse(_weekKey)!;
      final bills = (await DatabaseHelper.instance
              .queryBills(month: monthStr(DateTime.now())))
          .where((b) {
        final d = DateTime.tryParse(b.createTime);
        return d != null && !d.isBefore(weekStart) && b.isExpense;
      }).toList();
      final lines = [
        for (final b in bills.take(100))
          '${b.createTime.substring(5, 10)} ${b.category} ${b.money.toStringAsFixed(2)}元 ${b.remark}',
      ];
      final reply = await LlmService.chat(
        '用户本周（周${'一二三四五六日'[DateTime.now().weekday - 1]}）已支出 '
        '${_weekSpend.toStringAsFixed(2)} 元，此前四周平均每周 ${_weekAvg.toStringAsFixed(2)} 元，'
        '消费速度偏快。本周账单：\n${lines.join('\n')}\n'
        '请用不超过 100 字指出本周消费的主要问题，并给 1-2 条立刻可执行的建议。',
        system: '你是记账 App 的消费提醒助手，回答简洁、口语化、给出具体可执行建议。',
        temperature: 0.4,
      );
      await prefs.setString('alert_comment_$_weekKey', reply);
      if (mounted) _showCommentDialog(reply);
    } on LlmException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('分析失败：$e'), behavior: SnackBarBehavior.floating));
      }
    }
  }

  void _showCommentDialog(String text) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.insights, color: Color(0xFFEF6C00)),
          SizedBox(width: 8),
          Text('本周消费简评'),
        ]),
        content: SelectableText(text, style: const TextStyle(height: 1.6)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('知道了')),
        ],
      ),
    );
  }

  Future<void> _dismissAlert() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alert_dismissed_week', _weekKey);
    setState(() => _weekAlert = false);
  }

  /// AI 周度预警横幅
  Widget _weeklyAlertBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFB74D)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFEF6C00), size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '本周已支出 ¥${_weekSpend.toStringAsFixed(2)}，'
                  '超过近四周平均（¥${_weekAvg.toStringAsFixed(2)}）的 50%',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFE65100)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFEF6C00),
                    visualDensity: VisualDensity.compact),
                onPressed: _showWeeklyAiComment,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('AI 分析一下', style: TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 4),
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: Colors.grey,
                    visualDensity: VisualDensity.compact),
                onPressed: _dismissAlert,
                child: const Text('知道了', style: TextStyle(fontSize: 13)),
              ),
            ]),
          ],
        ),
      );

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
      backgroundColor: context.bg,
      appBar: AppBar(
        title: const Text('一语记',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索账单',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchPage())),
          ),
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
                  if (_weekAlert) ...[
                    _weeklyAlertBanner(),
                    const SizedBox(height: 12),
                  ],
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
        color: context.card,
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
