import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../common/global.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../services/llm_service.dart';
import '../services/settings_service.dart';
import 'widgets/common.dart';

/// 记账页：三种模式
///   1. 手动记账（表单）
///   2. AI 自然语言记账（口语化文本 -> LLM 解析）
///   3. 拍照小票记账（OCR -> LLM 解析）
class AddBillPage extends StatefulWidget {
  const AddBillPage({super.key});

  @override
  State<AddBillPage> createState() => _AddBillPageState();
}

class _AddBillPageState extends State<AddBillPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  // 手动记账
  bool _expense = true;
  final _moneyCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();
  String _category = '餐饮';
  DateTime _time = DateTime.now();

  // AI 记账
  final _nlCtrl = TextEditingController();
  bool _nlLoading = false;

  // 小票记账
  bool _ocrLoading = false;
  String? _ocrText;

  static const _expenseCates = ['餐饮', '交通', '购物', '娱乐', '学习', '医疗', '居住', '其他'];
  static const _incomeCates = ['工资', '兼职', '理财', '红包', '其他'];

  static String _p(int n) => n.toString().padLeft(2, '0');

  @override
  void dispose() {
    _tab.dispose();
    _moneyCtrl.dispose();
    _remarkCtrl.dispose();
    _nlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('记一笔', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tab,
          labelColor: const Color(0xFF1E88E5),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF1E88E5),
          tabs: const [
            Tab(icon: Icon(Icons.edit_note), text: '手动'),
            Tab(icon: Icon(Icons.auto_awesome), text: 'AI 文本'),
            Tab(icon: Icon(Icons.document_scanner), text: '小票拍照'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_manualTab(), _aiTab(), _receiptTab()],
      ),
    );
  }

  // ---------------- 手动记账 ----------------

  Widget _manualTab() => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _card(Column(children: [
            Row(children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('支出')),
                    ButtonSegment(value: false, label: Text('收入')),
                  ],
                  selected: {_expense},
                  onSelectionChanged: (s) => setState(() {
                    _expense = s.first;
                    _category = _expense ? _expenseCates.first : _incomeCates.first;
                  }),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _moneyCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: '¥ ',
                prefixStyle: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold),
                hintText: '0.00',
                filled: true,
                fillColor: const Color(0xFFF8F9FB),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (_expense ? _expenseCates : _incomeCates)
                  .map((c) => ChoiceChip(
                        label: Text(c),
                        selected: _category == c,
                        selectedColor:
                            colorOf(c).withValues(alpha: .25),
                        labelStyle: TextStyle(
                            color: _category == c
                                ? Colors.black87
                                : Colors.grey.shade700,
                            fontWeight: _category == c
                                ? FontWeight.bold
                                : FontWeight.normal),
                        onSelected: (_) => setState(() => _category = c),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _remarkCtrl,
              decoration: InputDecoration(
                hintText: '备注（选填）',
                filled: true,
                fillColor: const Color(0xFFF8F9FB),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  const Icon(Icons.access_time,
                      size: 18, color: Color(0xFF1E88E5)),
                  const SizedBox(width: 6),
                  Text(
                    '${_time.year}-${_p(_time.month)}-${_p(_time.day)} '
                    '${_p(_time.hour)}:${_p(_time.minute)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ]),
              ),
            ),
          ])),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E88E5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            onPressed: _saveManual,
            child: const Text('保存', style: TextStyle(fontSize: 16)),
          ),
        ],
      );

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    setState(() {
      _time = DateTime(date.year, date.month, date.day,
          time?.hour ?? 12, time?.minute ?? 0);
    });
  }

  Future<void> _saveManual() async {
    final money = double.tryParse(_moneyCtrl.text.trim());
    if (money == null || money <= 0) {
      _toast('请输入正确的金额');
      return;
    }
    final t = _time;
    await DatabaseHelper.instance.insertBill(Bill(
      money: money,
      type: _expense ? 0 : 1,
      category: _category,
      remark: _remarkCtrl.text.trim(),
      createTime:
          '${t.year}-${_p(t.month)}-${_p(t.day)} ${_p(t.hour)}:${_p(t.minute)}',
    ));
    notifyDataChanged();
    if (mounted) {
      _toast('记账成功');
      Navigator.pop(context);
    }
  }

  // ---------------- AI 自然语言记账 ----------------

  Widget _aiTab() => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.auto_awesome,
                    color: Color(0xFF1E88E5), size: 18),
                const SizedBox(width: 6),
                const Text('AI 智能记账',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                Text('智能解析',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade500)),
              ]),
              const SizedBox(height: 10),
              const Text('直接用一句话描述你的消费，AI 会自动拆分账单、识别金额、智能分类：',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 12),
              TextField(
                controller: _nlCtrl,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: '例如：今天午饭花了25，打车回来12，还买了杯奶茶15',
                  filled: true,
                  fillColor: const Color(0xFFF8F9FB),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: ['午饭30 奶茶15', '打车12 地铁4元', '发工资8000', '电影票45 爆米花20']
                    .map((s) => ActionChip(
                          label: Text(s,
                              style: const TextStyle(fontSize: 12)),
                          onPressed: () => _nlCtrl.text = s,
                        ))
                    .toList(),
              ),
            ],
          )),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E88E5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            onPressed: _nlLoading ? null : _aiParse,
            icon: _nlLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome),
            label: Text(_nlLoading ? 'AI 解析中…' : 'AI 解析并记账',
                style: const TextStyle(fontSize: 16)),
          ),
        ],
      );

  Future<void> _aiParse() async {
    final input = _nlCtrl.text.trim();
    if (input.isEmpty) {
      _toast('请先输入消费描述');
      return;
    }
    if (!SettingsService.apiKey.isNotEmpty) {
      _askApiKey();
      return;
    }
    setState(() => _nlLoading = true);
    try {
      final bills = await NlBillParser.parse(input);
      await DatabaseHelper.instance.insertBills(bills);
      notifyDataChanged();
      if (mounted) {
        _showParsedPreview(bills, '已为你记下 ${bills.length} 笔账单');
      }
    } on LlmException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('解析失败：$e');
    } finally {
      if (mounted) setState(() => _nlLoading = false);
    }
  }

  // ---------------- 小票拍照记账 ----------------

  Widget _receiptTab() => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.document_scanner,
                    color: Color(0xFF1E88E5), size: 18),
                const SizedBox(width: 6),
                const Text('拍照小票记账',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const Spacer(),
                Text('OCR + AI',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
              const SizedBox(height: 10),
              const Text('拍摄或选择购物小票照片，自动识别文字并提取消费条目：',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _ocrLoading ? null : () => _doReceipt(true),
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('拍照'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _ocrLoading ? null : () => _doReceipt(false),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('相册'),
                  ),
                ),
              ]),
              if (_ocrLoading) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('正在识别小票并交给 AI 解析…',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ],
              if (_ocrText != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_ocrText!,
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black45, height: 1.4)),
                ),
              ],
            ],
          )),
        ],
      );

  Future<void> _doReceipt(bool fromCamera) async {
    if (!SettingsService.apiKey.isNotEmpty) {
      _askApiKey();
      return;
    }
    final picker = ImagePicker();
    final x = await picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600);
    if (x == null) return;
    setState(() {
      _ocrLoading = true;
      _ocrText = null;
    });
    try {
      // 第一步：端上 OCR（google_mlkit_text_recognition，离线免费）
      final inputImage = InputImage.fromFilePath(x.path);
      final recognized =
          await TextRecognizer(script: TextRecognitionScript.chinese)
              .processImage(inputImage);
      final text = recognized.text.trim();
      if (text.isEmpty) {
        _toast('未能识别出小票文字，请换个光线好的角度重试');
        return;
      }
      _ocrText = text;
      if (mounted) setState(() {});

      // 第二步：小票全文交给 LLM 提取消费条目
      final bills = await ReceiptParser.parse(text);
      await DatabaseHelper.instance.insertBills(bills);
      notifyDataChanged();
      if (mounted) {
        _showParsedPreview(bills, '已从小票提取 ${bills.length} 笔消费');
      }
    } on LlmException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('识别失败：$e');
    } finally {
      if (mounted) setState(() => _ocrLoading = false);
    }
  }

  // ---------------- 公共 ----------------

  void _showParsedPreview(List<Bill> bills, String title) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
            const Divider(height: 20),
            ...bills.map((b) => BillTile(bill: b)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E88E5)),
                  onPressed: () {
                    Navigator.of(context)
                      ..pop()
                      ..pop();
                  },
                  child: const Text('完成'),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _askApiKey() {
    _toast('AI 服务未就绪，请到「我的」页开启内置模型或配置自定义模型');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}
