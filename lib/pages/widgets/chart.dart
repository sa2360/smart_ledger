import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'common.dart';

/// 分类支出占比饼图（fl_chart）
class CategoryPieChart extends StatelessWidget {
  final Map<String, double> data;

  const CategoryPieChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: Text('暂无数据')),
      );
    }
    final total = entries.fold<double>(0, (s, e) => s + e.value);
    final shown = entries.take(6).toList();
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 34,
                    sections: [
                      for (final e in shown)
                        PieChartSectionData(
                          value: e.value,
                          title:
                              '${(e.value / total * 100).toStringAsFixed(0)}%',
                          titleStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                          color: colorOf(e.key),
                          radius: 34,
                        ),
                      if (entries.length > 6)
                        PieChartSectionData(
                          value: entries.skip(6).fold<double>(0, (s, e) => s + e.value),
                          title: '其他',
                          titleStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                          color: Colors.grey.shade400,
                          radius: 34,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in shown)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                                color: colorOf(e.key),
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(e.key,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis),
                          ),
                          Text('${e.value.toStringAsFixed(0)}元',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600)),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
