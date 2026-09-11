import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/bill.dart';
import 'bill_edit_page.dart';
import 'widgets/common.dart';

/// 账单搜索页：关键词 + 分类 + 金额区间筛选
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _kwCtrl = TextEditingController();
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  String? _category;
  List<Bill> _results = [];
  bool _searched = false;
  bool _searching = false;

  static const _cates = [
    '餐饮', '交通', '购物', '娱乐', '学习', '医疗', '居住', '其他',
    '工资', '兼职', '理财', '红包',
  ];

  @override
  void dispose() {
    _kwCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    final results = await DatabaseHelper.instance.searchBills(
      keyword: _kwCtrl.text,
      category: _category,
      minMoney: double.tryParse(_minCtrl.text.trim()),
      maxMoney: double.tryParse(_maxCtrl.text.trim()),
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _searched = true;
      _searching = false;
    });
  }

  double get _totalExpense =>
      _results.where((b) => b.isExpense).fold(0, (s, b) => s + b.money);
  double get _totalIncome =>
      _results.where((b) => !b.isExpense).fold(0, (s, b) => s + b.money);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(title: const Text('搜索账单',
          style: TextStyle(fontWeight: FontWeight.bold))),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            color: context.card,
            child: Column(
              children: [
                TextField(
                  controller: _kwCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: '搜索备注或分类，如「奶茶」',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    filled: true,
                    fillColor: context.bg,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _category,
                      isDense: true,
                      decoration: const InputDecoration(
                          labelText: '分类', isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('全部')),
                        for (final c in _cates)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => setState(() => _category = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _minCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration:
                          const InputDecoration(labelText: '最低金额', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _maxCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration:
                          const InputDecoration(labelText: '最高金额', isDense: true),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1E88E5)),
                    onPressed: _searching ? null : _search,
                    child: const Text('搜索'),
                  ),
                ),
              ],
            ),
          ),
          if (_searched)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(children: [
                Text('找到 ${_results.length} 条',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.onSurface)),
                const Spacer(),
                Text('支出 ¥${_totalExpense.toStringAsFixed(2)} · '
                    '收入 ¥${_totalIncome.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 12, color: context.subtext)),
              ]),
            ),
          Expanded(
            child: !_searched
                ? Center(
                    child: Text('输入条件后点击搜索',
                        style: TextStyle(color: context.subtext)))
                : _results.isEmpty
                    ? Center(
                        child: Text('没有符合条件的账单',
                            style: TextStyle(color: context.subtext)))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: context.card,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                for (final b in _results) ...[
                                  BillTile(
                                    bill: b,
                                    onTap: () async {
                                      await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  BillEditPage(bill: b)));
                                      _search();
                                    },
                                  ),
                                  if (b != _results.last)
                                    Divider(height: 1, color: context.divider),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
