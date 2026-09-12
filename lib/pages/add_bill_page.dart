import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../common/global.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../services/baidu_asr_service.dart';
import '../services/llm_service.dart';
import '../services/local_stores.dart';
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

  // 语音记账：录音 -> 百度短语音识别
  final _recorder = AudioRecorder();
  bool _listening = false; // 正在录音
  bool _recognizing = false; // 正在识别
  String? _pendingVoicePath;
  Timer? _autoStopTimer;

  // 常用模板
  List<Map<String, dynamic>> _templates = [];

  // 小票记账
  bool _ocrLoading = false;
  String? _ocrText;

  static const _expenseCates = ['餐饮', '交通', '购物', '娱乐', '学习', '医疗', '居住', '其他'];
  static const _incomeCates = ['工资', '兼职', '理财', '红包', '其他'];

  static String _p(int n) => n.toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final list = await TemplateStore.list();
    if (mounted) setState(() => _templates = list);
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _tab.dispose();
    _moneyCtrl.dispose();
    _remarkCtrl.dispose();
    _nlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
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
          if (_templates.isNotEmpty) _templateRow(),
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
          Row(children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                onPressed: _saveManual,
                child: const Text('保存', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _saveTemplate,
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('存为模板'),
            ),
          ]),
        ],
      );

  /// 常用模板横排：点击填入表单，长按删除
  Widget _templateRow() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SizedBox(
          height: 36,
          child: Row(children: [
            Icon(Icons.bookmark, size: 16, color: Colors.amber.shade700),
            const SizedBox(width: 6),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _templates.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final t = _templates[i];
                  return InkWell(
                    onTap: () => _applyTemplate(t),
                    onLongPress: () => _deleteTemplate(i),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${t["is_income"] == 1 ? "+" : "-"}¥${t["money"]} ${t["remark"] ?? t["category"]}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      );

  void _applyTemplate(Map<String, dynamic> t) {
    setState(() {
      _expense = t['is_income'] != 1;
      _moneyCtrl.text = '${t['money']}';
      _remarkCtrl.text = '${t['remark'] ?? ''}';
      _category = '${t['category'] ?? '其他'}';
      _time = DateTime.now();
    });
  }

  Future<void> _deleteTemplate(int i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除模板'),
        content: const Text('确定删除这个常用模板吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await TemplateStore.removeAt(i);
      _loadTemplates();
    }
  }

  Future<void> _saveTemplate() async {
    final money = double.tryParse(_moneyCtrl.text.trim());
    if (money == null || money <= 0) {
      _toast('先填写金额，再保存为模板');
      return;
    }
    await TemplateStore.add({
      'money': money,
      'is_income': _expense ? 0 : 1,
      'category': _category,
      'remark': _remarkCtrl.text.trim(),
    });
    _loadTemplates();
    _toast('已保存为常用模板');
  }

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
              Text('直接用一句话描述你的消费，AI 会自动拆分账单、识别金额、智能分类：',
                  style: TextStyle(fontSize: 13, color: context.subtext)),
              const SizedBox(height: 12),
              TextField(
                controller: _nlCtrl,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: '例如：今天午饭花了25，打车回来12，还买了杯奶茶15',
                  filled: true,
                  fillColor: const Color(0xFFF8F9FB),
                  suffixIcon: _micButton(),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
              if (_listening || _recognizing) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _recognizing ? '识别中，请稍候…' : '正在录音，说完再点一下麦克风停止',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                ]),
              ],
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

  /// 语音输入按钮：说话转文字后填入输入框，再由用户点击 AI 解析
  Widget _micButton() => IconButton(
        icon: _recognizing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(
                _listening ? Icons.mic : Icons.mic_none,
                color: _listening ? Colors.red : Colors.grey,
              ),
        tooltip: '语音输入',
        onPressed: (_listening || _recognizing) && !_listening ? null : _toggleVoice,
      );

  /// 语音记账：点一下开始录音，再点一下停止并识别；最长 55 秒自动停止
  Future<void> _toggleVoice() async {
    if (_listening) {
      await _stopAndRecognize();
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        _toast('需要麦克风权限才能语音记账，请在系统设置中允许');
        return;
      }
      if (!BaiduAsrService.isConfigured) {
        _toast('语音服务未配置，请使用最新版安装包');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.pcm';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      setState(() {
        _listening = true;
        _pendingVoicePath = path;
      });
      // 最长 55 秒自动停止识别（百度上限 60 秒）
      _autoStopTimer = Timer(const Duration(seconds: 55), () {
        if (_listening && mounted) _stopAndRecognize();
      });
    } catch (e) {
      if (mounted) _toast('无法启动录音：请检查麦克风权限（$e）');
    }
  }

  Future<void> _stopAndRecognize() async {
    _autoStopTimer?.cancel();
    final path = _pendingVoicePath;
    setState(() {
      _listening = false;
      _recognizing = true;
    });
    try {
      await _recorder.stop();
      final text = await BaiduAsrService.recognizePcmFile(path!);
      if (mounted) {
        setState(() => _recognizing = false);
        if (text.isEmpty) {
          _toast('没听清，请靠近麦克风再说一次');
        } else {
          _nlCtrl.text = text;
        }
      }
    } on AsrException catch (e) {
      if (mounted) {
        setState(() => _recognizing = false);
        _toast(e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _recognizing = false);
        _toast('识别失败：$e');
      }
    }
  }

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
              Text('拍摄或选择购物小票照片，自动识别文字并提取消费条目：',
                  style: TextStyle(fontSize: 13, color: context.subtext)),
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
                Text('正在识别小票并交给 AI 解析…',
                    style: TextStyle(fontSize: 12, color: context.subtext)),
              ],
              if (_ocrText != null) ...[
                SizedBox(height: 12),
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
                      style: TextStyle(
                          fontSize: 12, color: context.subtext, height: 1.4)),
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
          color: context.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}
