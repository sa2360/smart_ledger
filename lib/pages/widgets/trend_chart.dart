import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// 近 N 个月收支趋势折线图
class TrendLineChart extends StatelessWidget {
  final List<(String, double, double)> data; // (月份, 支出, 收入)

  const TrendLineChart({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(height: 160, child: Center(child: Text('暂无数据')));
    }
    final spotsE = [
      for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i].$2),
    ];
    final spotsI = [
      for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i].$3),
    ];
    final maxY = [
      ...data.map((d) => d.$2),
      ...data.map((d) => d.$3),
    ].fold<double>(0, (m, v) => v > m ? v : m);

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY <= 0 ? 100 : maxY * 1.15,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY <= 0 ? 20 : maxY / 4,
                getDrawingHorizontalLine: (v) => FlLine(
                    color: const Color(0xFFEEEEEE), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (v, meta) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= data.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('${data[idx].$1.substring(5)}月',
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600)),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${data[s.x.toInt()].$1.substring(5)}月\n'
                        '${s.barIndex == 0 ? "支出" : "收入"} '
                        '¥${s.y.toStringAsFixed(2)}',
                        TextStyle(
                          fontSize: 11,
                          color: s.barIndex == 0
                              ? const Color(0xFFEF5350)
                              : const Color(0xFF26A69A),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spotsE,
                  isCurved: true,
                  barWidth: 2.5,
                  color: const Color(0xFFEF5350),
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: const Color(0xFFEF5350).withValues(alpha: .08),
                  ),
                ),
                LineChartBarData(
                  spots: spotsI,
                  isCurved: true,
                  barWidth: 2.5,
                  color: const Color(0xFF26A69A),
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend('支出', const Color(0xFFEF5350)),
            const SizedBox(width: 16),
            _legend('收入', const Color(0xFF26A69A)),
          ],
        ),
      ],
    );
  }

  Widget _legend(String label, Color color) => Row(children: [
        Container(
            width: 18,
            height: 3,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ]);
}
