import 'package:flutter/material.dart';

import '../common/global.dart';
import '../db/database_helper.dart';
import '../models/budget.dart';
import 'widgets/common.dart';

/// 预算管理页：设置月度总预算与分类预算，超支提醒
class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  static const _cates = ['餐饮', '交通', '购物', '娱乐', '其他'];

  Budget? _budget;
  double _monthExpense = 0;
  Map<String, double> _cateSpend = {};
  bool _loading = true;
  late String _month;

  static String _p(int n) => n.toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = '${now.year}-${_p(now.month)}';
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
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final month = '${now.year}-${_p(now.month)}';
    final results = await Future.wait([
      db.getBudget(month),
      db.sumOfMonth(0, month),
      db.categorySpendOfMonth(month),
    ]);
    if (!mounted) return;
    setState(() {
      _budget = results[0] as Budget?;
      _monthExpense = results[1] as double;
      _cateSpend = results[2] as Map<String, double>;
      _loading = false;
    });
    _checkOverrun();
  }

  /// 超支提醒（设计书 5.4：超出阈值提示）
  void _checkOverrun() {
    if (_budget == null || _budget!.totalBudget <= 0) return;
    final total = _budget!.totalBudget;
    if (_monthExpense > total) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade400,
          content: Text(
              '⚠️ 本月已超支 ¥${(_monthExpense - total).toStringAsFixed(2)}，'
              '建议控制非必要消费'),
        ));
      });
    }
  }

  Future<void> _edit() async {
    final ctrlTotal = TextEditingController(
        text: _budget == null || _budget!.totalBudget <= 0
            ? ''
            : _budget!.totalBudget.toStringAsFixed(0));
    final ctrls = {
      for (final c in _cates)
        c: TextEditingController(
            text: _budget?.cateBudget[c] == null
                ? ''
                : _budget!.cateBudget[c]!.toStringAsFixed(0)),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('设置 $_month 预算'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrlTotal,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '月度总预算（元）', prefixText: '¥ '),
              ),
              const SizedBox(height: 10),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text('分类预算（选填）：',
                      style: TextStyle(fontSize: 13, color: context.subtext))),
              for (final c in _cates)
                TextField(
                  controller: ctrls[c],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      InputDecoration(labelText: c, prefixText: '¥ '),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final total = double.tryParse(ctrlTotal.text.trim()) ?? 0;
    final cate = <String, double>{};
    for (final e in ctrls.entries) {
      final v = double.tryParse(e.value.text.trim());
      if (v != null && v > 0) cate[e.key] = v;
    }
    if (total <= 0 && cate.isEmpty) return;
    await DatabaseHelper.instance.saveBudget(Budget(
      totalBudget: total,
      cateBudget: cate,
      month: _month,
    ));
    notifyDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final hasBudget = _budget != null && _budget!.totalBudget > 0;
    final total = hasBudget ? _budget!.totalBudget : 0.0;
    final ratio = total <= 0 ? 0.0 : (_monthExpense / total).clamp(0.0, 1.0);
    final over = _monthExpense > total && total > 0;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Text('预算管理（$_month）',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.edit), onPressed: _edit),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: over
                      ? [const Color(0xFFEF5350), const Color(0xFFE53935)]
                      : [const Color(0xFF26A69A), const Color(0xFF00897B)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hasBudget ? '月度总预算' : '尚未设置月度预算',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: .85))),
                if (hasBudget) ...[
                  Text('¥${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 12,
                      backgroundColor: Colors.white.withValues(alpha: .25),
                      valueColor: AlwaysStoppedAnimation(
                          over ? const Color(0xFFFFEBEE) : const Color(0xFFB2DFDB)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    over
                        ? '已超支 ¥${(_monthExpense - total).toStringAsFixed(2)}'
                        : '已使用 ¥${_monthExpense.toStringAsFixed(2)}，'
                            '剩余 ¥${(total - _monthExpense).toStringAsFixed(2)}'
                            '（${(ratio * 100).toStringAsFixed(0)}%）',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ] else ...[
                  const SizedBox(height: 4),
                  const Text('设置预算后可实时监控超支情况',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _edit,
                    child: const Text('去设置预算'),
                  ),
                ],
              ],
            ),
          ),
          if (hasBudget && _budget!.cateBudget.isNotEmpty) ...[
            const SizedBox(height: 14),
            _card(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('分类预算使用情况',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 6),
                ..._budget!.cateBudget.entries.map(_cateRow),
              ],
            )),
          ],
          const SizedBox(height: 14),
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('本月实际分类支出',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 6),
              if (_cateSpend.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('暂无支出记录',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade500)),
                )
              else
                ..._cateSpend.entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Icon(iconOf(e.key), size: 18, color: colorOf(e.key)),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: 42,
                            child: Text(e.key,
                                style: const TextStyle(fontSize: 13))),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: total > 0
                                  ? (e.value / total).clamp(0.0, 1.0)
                                  : 0,
                              minHeight: 8,
                              backgroundColor: const Color(0xFFEEEEEE),
                              valueColor: AlwaysStoppedAnimation(
                                  colorOf(e.key)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('¥${e.value.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                      ]),
                    )),
            ],
          )),
        ],
      ),
    );
  }

  Widget _cateRow(MapEntry<String, double> e) {
    final spent = _cateSpend[e.key] ?? 0;
    final ratio = (e.value <= 0) ? 0.0 : (spent / e.value).clamp(0.0, 1.0);
    final over = spent > e.value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(iconOf(e.key), size: 16, color: colorOf(e.key)),
            const SizedBox(width: 6),
            Text(e.key, style: const TextStyle(fontSize: 13)),
            const Spacer(),
            Text(
              '¥${spent.toStringAsFixed(2)} / ¥${e.value.toStringAsFixed(0)}'
              '${over ? "（超支）" : ""}',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: over ? Colors.red : Colors.black87),
            ),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: const Color(0xFFEEEEEE),
              valueColor: AlwaysStoppedAnimation(
                  over ? Colors.red : colorOf(e.key)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}
