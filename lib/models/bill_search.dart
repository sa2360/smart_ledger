/// 一次已提交的搜索条件；翻页时不读取尚未提交的表单改动。
class BillSearchQuery {
  final String keyword;
  final String? category;
  final int? type;
  final double? minMoney;
  final double? maxMoney;
  final DateTime? startDate;
  final DateTime? endDate;

  const BillSearchQuery({
    this.keyword = '',
    this.category,
    this.type,
    this.minMoney,
    this.maxMoney,
    this.startDate,
    this.endDate,
  });

  (String?, List<Object>) get sqlFilter {
    final where = <String>[];
    final args = <Object>[];
    if (keyword.trim().isNotEmpty) {
      where.add("(remark LIKE ? ESCAPE '\\' OR category LIKE ? ESCAPE '\\')");
      final escaped = keyword
          .trim()
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      args.addAll(['%$escaped%', '%$escaped%']);
    }
    if (category != null && category!.isNotEmpty) {
      where.add('category = ?');
      args.add(category!);
    }
    if (type != null) {
      where.add('type = ?');
      args.add(type!);
    }
    if (minMoney != null) {
      where.add('money >= ?');
      args.add(minMoney!);
    }
    if (maxMoney != null) {
      where.add('money <= ?');
      args.add(maxMoney!);
    }
    String date(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (startDate != null) {
      where.add('create_time >= ?');
      args.add(date(startDate!));
    }
    if (endDate != null) {
      where.add('create_time < ?');
      args.add(date(DateTime(endDate!.year, endDate!.month, endDate!.day + 1)));
    }
    return (where.isEmpty ? null : where.join(' AND '), args);
  }
}
