import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/bill_search.dart';
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
  int? _type;
  DateTimeRange? _dates;
  BillSearchQuery? _activeQuery;
  int _count = 0;
  double _totalExpense = 0, _totalIncome = 0;
  List<Bill> _results = [];
  bool _searched = false;
  bool _searching = false;

  static const _cates = [
    '餐饮',
    '交通',
    '购物',
    '娱乐',
    '学习',
    '医疗',
    '居住',
    '其他',
    '工资',
    '兼职',
    '理财',
    '红包',
  ];

  @override
  void dispose() {
    _kwCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _search({bool more = false, bool refresh = false}) async {
    if (!mounted || _searching) return;
    final minText = _minCtrl.text.trim();
    final maxText = _maxCtrl.text.trim();
    final min = minText.isEmpty ? null : double.tryParse(minText);
    final max = maxText.isEmpty ? null : double.tryParse(maxText);
    if (!more &&
        !refresh &&
        ((minText.isNotEmpty && (min == null || !min.isFinite || min < 0)) ||
            (maxText.isNotEmpty && (max == null || !max.isFinite || max < 0)) ||
            (min != null && max != null && min > max))) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入有效金额范围，最低金额不能大于最高金额')));
      return;
    }
    setState(() => _searching = true);
    FocusScope.of(context).unfocus();
    try {
      final query = (more || refresh) && _activeQuery != null
          ? _activeQuery!
          : BillSearchQuery(
              keyword: _kwCtrl.text.trim(),
              category: _category,
              type: _type,
              minMoney: min,
              maxMoney: max,
              startDate: _dates?.start,
              endDate: _dates?.end,
            );
      final results = await DatabaseHelper.instance.searchBillPage(
        query,
        offset: more ? _results.length : 0,
      );
      if (!mounted) return;
      setState(() {
        _activeQuery = query;
        _results = more ? [..._results, ...results.bills] : results.bills;
        _count = results.count;
        _totalExpense = results.expense;
        _totalIncome = results.income;
        _searched = true;
        _searching = false;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('查询失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pickDates() async {
    final dates = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: _dates,
    );
    if (mounted && dates != null) setState(() => _dates = dates);
  }

  String _dateLabel(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: const Text(
          '搜索账单',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .7,
              ),
              child: SingleChildScrollView(
                child: Container(
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
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              decoration: const InputDecoration(
                                labelText: '收支类型',
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: null,
                                  child: Text('全部收支'),
                                ),
                                DropdownMenuItem(value: 0, child: Text('支出')),
                                DropdownMenuItem(value: 1, child: Text('收入')),
                              ],
                              onChanged: (v) => setState(() => _type = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: _pickDates,
                              icon: const Icon(Icons.date_range),
                              label: Text(
                                _dates == null
                                    ? '全部日期'
                                    : '${_dateLabel(_dates!.start)} 至 ${_dateLabel(_dates!.end)}',
                              ),
                            ),
                          ),
                          if (_dates != null)
                            IconButton(
                              tooltip: '清除日期',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() => _dates = null),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _category,
                              isDense: true,
                              decoration: const InputDecoration(
                                labelText: '分类',
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('全部'),
                                ),
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '最低金额',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _maxCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: '最高金额',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1E88E5),
                          ),
                          onPressed: _searching ? null : _search,
                          child: const Text('搜索'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_searched)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      '找到 $_count 条',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.onSurface,
                      ),
                    ),
                    Text(
                      '支出 ¥${_totalExpense.toStringAsFixed(2)} · '
                      '收入 ¥${_totalIncome.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 12, color: context.subtext),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: !_searched
                  ? Center(
                      child: Text(
                        '输入条件后点击搜索',
                        style: TextStyle(color: context.subtext),
                      ),
                    )
                  : _results.isEmpty
                  ? Center(
                      child: Text(
                        '没有符合条件的账单',
                        style: TextStyle(color: context.subtext),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount:
                          _results.length + (_results.length < _count ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _results.length) {
                          return TextButton(
                            onPressed: _searching
                                ? null
                                : () => _search(more: true),
                            child: Text(
                              _searching
                                  ? '加载中…'
                                  : '加载更多（已显示 ${_results.length}/$_count）',
                            ),
                          );
                        }
                        final b = _results[index];
                        return ColoredBox(
                          color: context.card,
                          child: BillTile(
                            bill: b,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BillEditPage(bill: b),
                                ),
                              );
                              if (mounted) _search(refresh: true);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
